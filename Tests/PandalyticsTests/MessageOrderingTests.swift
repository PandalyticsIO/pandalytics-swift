import Testing
import Foundation
@testable import Pandalytics

@Suite("Message Ordering")
struct MessageOrderingTests {

    @Test("Signals added before configure are buffered and sent after configure")
    func signalsBeforeConfigureAreDelivered() async {
        let dir = makeTempPersistenceDirectory()
        defer { cleanupTempDirectory(dir) }

        let buffer = SignalBuffer(persistenceDirectory: dir)

        // Add signals before configure — no transport yet
        await buffer.add(makeTestSignal(type: "early_1"))
        await buffer.add(makeTestSignal(type: "early_2"))
        await buffer.add(makeTestSignal(type: "early_3"))

        let countBefore = await buffer.bufferedCount
        #expect(countBefore == 3)

        // Flush should be a no-op (no transport)
        await buffer.flush()
        let countAfterNoOpFlush = await buffer.bufferedCount
        #expect(countAfterNoOpFlush == 3)

        // Now configure with a recording transport
        let transport = RecordingTransport()
        await buffer.configure(appId: "test", transport: transport)

        // Flush — all 3 early signals should be delivered
        await buffer.flush()

        #expect(transport.totalSignalsSent == 3)
        let types = transport.batches.flatMap(\.signals).map(\.signalType)
        #expect(types.contains("early_1"))
        #expect(types.contains("early_2"))
        #expect(types.contains("early_3"))
    }

    @Test("Signal ordering is preserved through the buffer")
    func signalOrderingPreserved() async {
        let dir = makeTempPersistenceDirectory()
        defer { cleanupTempDirectory(dir) }

        let transport = RecordingTransport()
        let buffer = SignalBuffer(persistenceDirectory: dir)
        await buffer.configure(appId: "test", transport: transport)

        for i in 0..<5 {
            await buffer.add(makeTestSignal(type: "ordered_\(i)"))
        }

        await buffer.flush()

        let types = transport.batches.flatMap(\.signals).map(\.signalType)
        #expect(types == ["ordered_0", "ordered_1", "ordered_2", "ordered_3", "ordered_4"])
    }

    @Test("Signals persist even without configure — survives 'crash before configure'")
    func signalsPersistWithoutConfigure() async {
        let dir = makeTempPersistenceDirectory()
        defer { cleanupTempDirectory(dir) }

        // Session 1: signals added, no configure ever called (simulates crash during init)
        let buffer1 = SignalBuffer(persistenceDirectory: dir)
        await buffer1.add(makeTestSignal(type: "pre_crash"))
        await buffer1.add(makeTestSignal(type: "pre_crash"))

        let file = dir.appendingPathComponent("signals.json")
        #expect(FileManager.default.fileExists(atPath: file.path))

        // Session 2: fresh buffer, configure properly, signals from session 1 should be delivered
        let transport = RecordingTransport()
        let buffer2 = SignalBuffer(persistenceDirectory: dir)
        await buffer2.configure(appId: "test", transport: transport)
        await buffer2.flush()

        #expect(transport.totalSignalsSent == 2)
        #expect(transport.batches[0].signals.allSatisfy { $0.signalType == "pre_crash" })
    }

    @Test("Mixed pre-configure and post-configure signals all delivered in order")
    func mixedPrePostConfigureSignals() async {
        let dir = makeTempPersistenceDirectory()
        defer { cleanupTempDirectory(dir) }

        let buffer = SignalBuffer(persistenceDirectory: dir)

        // Add pre-configure signals
        await buffer.add(makeTestSignal(type: "before_1"))
        await buffer.add(makeTestSignal(type: "before_2"))

        // Configure
        let transport = RecordingTransport()
        await buffer.configure(appId: "test", transport: transport)

        // Add post-configure signals
        await buffer.add(makeTestSignal(type: "after_1"))
        await buffer.add(makeTestSignal(type: "after_2"))

        await buffer.flush()

        let types = transport.batches.flatMap(\.signals).map(\.signalType)
        #expect(types == ["before_1", "before_2", "after_1", "after_2"])
    }

    @Test("Signals from previous session appear before new session signals after configure")
    func persistedSignalsOrderedBeforeNew() async {
        let dir = makeTempPersistenceDirectory()
        defer { cleanupTempDirectory(dir) }

        // Session 1: add signals, don't flush
        let buffer1 = SignalBuffer(persistenceDirectory: dir)
        let transport1 = FailingTransport(result: .networkError)
        await buffer1.configure(appId: "test", transport: transport1)
        await buffer1.add(makeTestSignal(type: "session_1"))

        // Session 2: configure loads persisted, add new, flush
        let transport2 = RecordingTransport()
        let buffer2 = SignalBuffer(persistenceDirectory: dir)
        await buffer2.configure(appId: "test", transport: transport2)
        await buffer2.add(makeTestSignal(type: "session_2"))
        await buffer2.flush()

        let types = transport2.batches.flatMap(\.signals).map(\.signalType)
        #expect(types.count == 2)
        #expect(types[0] == "session_1")
        #expect(types[1] == "session_2")
    }
}
