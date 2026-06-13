import Foundation
import Testing
@testable import Pandalytics

@Suite("Run State Store")
struct RunStateStoreTests {

    @Test("No pending events on a fresh store")
    func freshStoreHasNothingToRecover() {
        let dir = makeTempPersistenceDirectory()
        defer { cleanupTempDirectory(dir) }

        let store = RunStateStore(persistenceDirectory: dir)
        #expect(store.recoverPendingEvents() == nil)
    }

    @Test("Critical signal pending marker is recovered if process exits before buffering")
    func criticalSignalPendingMarkerRecovered() {
        let dir = makeTempPersistenceDirectory()
        defer { cleanupTempDirectory(dir) }

        let store = RunStateStore(persistenceDirectory: dir)
        #expect(store.recoverPendingEvents() == nil)

        let pendingEvent = store.recordCriticalSignalQueued(
            type: "error",
            screenName: nil,
            metadata: ["error_name": "DatabaseError"]
        )

        // A fresh store on the same directory simulates the next launch.
        let recovery = RunStateStore(persistenceDirectory: dir).recoverPendingEvents()
        #expect(recovery?.pendingEvents.first?.id == pendingEvent.id)
        #expect(recovery?.pendingEvents.first?.type == "error")
        #expect(recovery?.pendingEvents.first?.metadata?["error_name"] == "DatabaseError")
        #expect(recovery?.pendingEvents.first?.metadata?["pandalytics_recovered"] == "true")
    }

    @Test("Recovered pending event is cleared after durable buffering")
    func completedPendingEventIsCleared() {
        let dir = makeTempPersistenceDirectory()
        defer { cleanupTempDirectory(dir) }

        let store = RunStateStore(persistenceDirectory: dir)
        let pendingEvent = store.recordCriticalSignalQueued(
            type: "error",
            screenName: nil,
            metadata: nil
        )

        let recovery = RunStateStore(persistenceDirectory: dir).recoverPendingEvents()
        #expect(recovery?.pendingEvents.first?.id == pendingEvent.id)

        // Once the signal is durably buffered the marker is completed, so the
        // next launch has nothing left to recover.
        let recoveringStore = RunStateStore(persistenceDirectory: dir)
        recoveringStore.completePendingEvent(id: pendingEvent.id)

        #expect(RunStateStore(persistenceDirectory: dir).recoverPendingEvents() == nil)
    }
}
