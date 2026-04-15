import Foundation
import Testing
@testable import Pandalytics

@Suite("Run State Store")
struct RunStateStoreTests {

    @Test("Pending lifecycle signal is recovered on next run")
    func pendingLifecycleSignalRecovered() {
        let dir = makeTempPersistenceDirectory()
        defer { cleanupTempDirectory(dir) }

        let store = RunStateStore(persistenceDirectory: dir)
        #expect(store.startRun() == nil)

        let pendingID = store.recordLifecycleSignalQueued(type: "app_background")
        #expect(pendingID != nil)

        let nextStore = RunStateStore(persistenceDirectory: dir)
        let recovery = nextStore.startRun()

        #expect(recovery?.pendingEvents.count == 1)
        #expect(recovery?.pendingEvents.first?.type == "app_background")
    }

    @Test("Recovered pending event is cleared after durable buffering")
    func completedPendingEventIsCleared() {
        let dir = makeTempPersistenceDirectory()
        defer { cleanupTempDirectory(dir) }

        let store = RunStateStore(persistenceDirectory: dir)
        #expect(store.startRun() == nil)

        let pendingID = store.recordLifecycleSignalQueued(type: "app_close")
        let recovery = RunStateStore(persistenceDirectory: dir).startRun()

        #expect(recovery?.pendingEvents.first?.id == pendingID)

        let recoveringStore = RunStateStore(persistenceDirectory: dir)
        recoveringStore.completePendingEvent(id: pendingID)
        let backgroundID = recoveringStore.recordLifecycleSignalQueued(type: "app_background")
        recoveringStore.completePendingEvent(id: backgroundID)

        let finalRecovery = recoveringStore.startRun()
        #expect(finalRecovery == nil)
    }

    @Test("Foreground run without clean shutdown creates unexpected-run event")
    func foregroundRunWithoutCleanShutdownCreatesUnexpectedEvent() {
        let dir = makeTempPersistenceDirectory()
        defer { cleanupTempDirectory(dir) }

        let store = RunStateStore(persistenceDirectory: dir)
        #expect(store.startRun() == nil)
        let lifecycleID = store.recordLifecycleSignalQueued(type: "app_foreground")
        store.completePendingEvent(id: lifecycleID)

        let recovery = RunStateStore(persistenceDirectory: dir).startRun()
        #expect(recovery?.pendingEvents.count == 1)
        #expect(recovery?.pendingEvents.first?.type == "previous_run_ended_unexpectedly")
        #expect(recovery?.pendingEvents.first?.metadata?["last_lifecycle_signal"] == "app_foreground")
    }

    @Test("Background run without app close is not reported as unexpected")
    func backgroundRunWithoutCleanShutdownIsNotUnexpected() {
        let dir = makeTempPersistenceDirectory()
        defer { cleanupTempDirectory(dir) }

        let store = RunStateStore(persistenceDirectory: dir)
        #expect(store.startRun() == nil)
        let lifecycleID = store.recordLifecycleSignalQueued(type: "app_background")
        store.completePendingEvent(id: lifecycleID)

        let recovery = RunStateStore(persistenceDirectory: dir).startRun()
        #expect(recovery == nil)
    }

    @Test("State-only background marker avoids unexpected-run recovery")
    func stateOnlyBackgroundMarkerAvoidsUnexpectedRecovery() {
        let dir = makeTempPersistenceDirectory()
        defer { cleanupTempDirectory(dir) }

        let store = RunStateStore(persistenceDirectory: dir)
        #expect(store.startRun() == nil)
        store.recordLifecycleState(type: "app_background")

        let recovery = RunStateStore(persistenceDirectory: dir).startRun()
        #expect(recovery == nil)
    }

    @Test("Critical signal pending marker is recovered if process exits before buffering")
    func criticalSignalPendingMarkerRecovered() {
        let dir = makeTempPersistenceDirectory()
        defer { cleanupTempDirectory(dir) }

        let store = RunStateStore(persistenceDirectory: dir)
        #expect(store.startRun() == nil)

        let pendingEvent = store.recordCriticalSignalQueued(
            type: "error",
            screenName: nil,
            metadata: ["error_name": "DatabaseError"]
        )

        let recovery = RunStateStore(persistenceDirectory: dir).startRun()
        #expect(recovery?.pendingEvents.first?.id == pendingEvent.id)
        #expect(recovery?.pendingEvents.first?.type == "error")
        #expect(recovery?.pendingEvents.first?.metadata?["error_name"] == "DatabaseError")
        #expect(recovery?.pendingEvents.first?.metadata?["pandalytics_recovered"] == "true")
    }
}
