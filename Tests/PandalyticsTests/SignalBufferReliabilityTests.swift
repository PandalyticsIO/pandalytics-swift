import Testing
import Foundation
@testable import Pandalytics

@Suite("Signal Buffer Reliability")
struct SignalBufferReliabilityTests {

    // MARK: - Persistence

    @Test("Signals persist to disk on add")
    func signalsPersistToDisk() async {
        let dir = makeTempPersistenceDirectory()
        defer { cleanupTempDirectory(dir) }

        let buffer = SignalBuffer(persistenceDirectory: dir)
        let transport = RecordingTransport()
        await buffer.configure(appId: "test", transport: transport)

        await buffer.add(makeTestSignal(type: "persist_test"))

        let file = dir.appendingPathComponent("signals.json")
        #expect(FileManager.default.fileExists(atPath: file.path))

        let data = try! Data(contentsOf: file)
        let signals = try! JSONDecoder().decode([Signal].self, from: data)
        #expect(signals.count == 1)
        #expect(signals[0].signalType == "persist_test")
    }

    @Test("Persisted signals loaded on configure")
    func persistedSignalsLoadedOnConfigure() async {
        let dir = makeTempPersistenceDirectory()
        defer { cleanupTempDirectory(dir) }

        // First buffer: add signals and let them persist
        let buffer1 = SignalBuffer(persistenceDirectory: dir)
        let transport1 = RecordingTransport()
        await buffer1.configure(appId: "test", transport: transport1)
        await buffer1.add(makeTestSignal(type: "from_previous_session"))
        await buffer1.add(makeTestSignal(type: "from_previous_session"))

        let countBefore = await buffer1.bufferedCount
        #expect(countBefore == 2)

        // Second buffer (simulates new app launch): should load persisted signals
        let buffer2 = SignalBuffer(persistenceDirectory: dir)
        let transport2 = RecordingTransport()
        await buffer2.configure(appId: "test", transport: transport2)

        let countAfter = await buffer2.bufferedCount
        #expect(countAfter == 2)
    }

    @Test("Persisted signals survive across buffer instances (simulates app restart)")
    func persistedSignalsSurviveRestart() async {
        let dir = makeTempPersistenceDirectory()
        defer { cleanupTempDirectory(dir) }

        // Session 1: add signals, network fails, signals stuck in buffer
        let failingTransport = FailingTransport(result: .networkError)
        let buffer1 = SignalBuffer(persistenceDirectory: dir)
        await buffer1.configure(appId: "test", transport: failingTransport)
        await buffer1.add(makeTestSignal(type: "survived"))
        await buffer1.add(makeTestSignal(type: "survived"))
        await buffer1.add(makeTestSignal(type: "survived"))
        await buffer1.flush()
        // Flush failed — signals should still be on disk

        // Session 2: new buffer, working network, should deliver old signals
        let recorder = RecordingTransport()
        let buffer2 = SignalBuffer(persistenceDirectory: dir)
        await buffer2.configure(appId: "test", transport: recorder)
        await buffer2.flush()

        #expect(recorder.totalSignalsSent == 3)
        #expect(recorder.batches[0].signals.allSatisfy { $0.signalType == "survived" })
    }

    @Test("Corrupt persistence file handled gracefully — deleted, no crash")
    func corruptPersistenceFile() async {
        let dir = makeTempPersistenceDirectory()
        defer { cleanupTempDirectory(dir) }

        // Write garbage to the persistence file
        let file = dir.appendingPathComponent("signals.json")
        try! "not valid json {{{".data(using: .utf8)!.write(to: file)

        // Should not crash, should delete the corrupt file
        let buffer = SignalBuffer(persistenceDirectory: dir)
        let transport = RecordingTransport()
        await buffer.configure(appId: "test", transport: transport)

        let count = await buffer.bufferedCount
        #expect(count == 0)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test("Empty persistence file handled gracefully")
    func emptyPersistenceFile() async {
        let dir = makeTempPersistenceDirectory()
        defer { cleanupTempDirectory(dir) }

        let file = dir.appendingPathComponent("signals.json")
        try! Data().write(to: file)

        let buffer = SignalBuffer(persistenceDirectory: dir)
        let transport = RecordingTransport()
        await buffer.configure(appId: "test", transport: transport)

        let count = await buffer.bufferedCount
        #expect(count == 0)
    }

    // MARK: - Capacity

    @Test("Buffer enforces 1000 signal cap")
    func bufferEnforcesCapacity() async {
        let dir = makeTempPersistenceDirectory()
        defer { cleanupTempDirectory(dir) }

        // Don't configure yet — no transport means auto-flush is a no-op
        let buffer = SignalBuffer(persistenceDirectory: dir)

        for i in 0..<1050 {
            await buffer.add(makeTestSignal(type: "signal_\(i)"))
        }

        let count = await buffer.bufferedCount
        #expect(count == 1000)
    }

    @Test("Cap drops oldest signals, keeps newest")
    func capDropsOldest() async {
        let dir = makeTempPersistenceDirectory()
        defer { cleanupTempDirectory(dir) }

        // Don't configure — auto-flush no-op, all signals stay in buffer
        let buffer = SignalBuffer(persistenceDirectory: dir)

        for i in 0..<1010 {
            await buffer.add(makeTestSignal(type: "signal_\(i)"))
        }

        // Now configure and flush to see what's in the buffer
        let transport = RecordingTransport()
        await buffer.configure(appId: "test", transport: transport)
        await buffer.flush()

        let sentSignals = transport.batches.flatMap(\.signals)
        #expect(sentSignals.count == 1000)

        // The first 10 (signal_0 through signal_9) should have been dropped
        let types = sentSignals.map(\.signalType)
        #expect(!types.contains("signal_0"))
        #expect(!types.contains("signal_9"))
        #expect(types.contains("signal_10"))
        #expect(types.contains("signal_1009"))
    }

    // MARK: - Network failure / retry

    @Test("Signals retry on network error — remain in buffer after failed flush")
    func retryOnNetworkError() async {
        let dir = makeTempPersistenceDirectory()
        defer { cleanupTempDirectory(dir) }

        let transport = FailingTransport(result: .networkError)
        let buffer = SignalBuffer(persistenceDirectory: dir)
        await buffer.configure(appId: "test", transport: transport)

        await buffer.add(makeTestSignal())
        await buffer.add(makeTestSignal())
        await buffer.flush()

        // Signals should still be in buffer
        let count = await buffer.bufferedCount
        #expect(count == 2)
        #expect(transport.attemptCount == 1)
    }

    @Test("Signals retry on server error — remain in buffer after failed flush")
    func retryOnServerError() async {
        let dir = makeTempPersistenceDirectory()
        defer { cleanupTempDirectory(dir) }

        let transport = FailingTransport(result: .serverError)
        let buffer = SignalBuffer(persistenceDirectory: dir)
        await buffer.configure(appId: "test", transport: transport)

        await buffer.add(makeTestSignal())
        await buffer.flush()

        let count = await buffer.bufferedCount
        #expect(count == 1)
    }

    @Test("Signals dropped on rate limit (429) — buffer cleared")
    func droppedOnRateLimit() async {
        let dir = makeTempPersistenceDirectory()
        defer { cleanupTempDirectory(dir) }

        let transport = FailingTransport(result: .rateLimited)
        let buffer = SignalBuffer(persistenceDirectory: dir)
        await buffer.configure(appId: "test", transport: transport)

        await buffer.add(makeTestSignal())
        await buffer.add(makeTestSignal())
        await buffer.flush()

        // Rate limited signals should be dropped, not retried
        let count = await buffer.bufferedCount
        #expect(count == 0)
    }

    @Test("Transient failure then recovery delivers all signals")
    func transientFailureRecovery() async {
        let dir = makeTempPersistenceDirectory()
        defer { cleanupTempDirectory(dir) }

        let transport = TransientFailureTransport(failCount: 2)
        let buffer = SignalBuffer(persistenceDirectory: dir)
        await buffer.configure(appId: "test", transport: transport)

        await buffer.add(makeTestSignal(type: "retry_me"))
        await buffer.add(makeTestSignal(type: "retry_me"))

        // First two flushes fail
        await buffer.flush()
        let count1 = await buffer.bufferedCount
        #expect(count1 == 2)

        await buffer.flush()
        let count2 = await buffer.bufferedCount
        #expect(count2 == 2)

        // Third flush succeeds
        await buffer.flush()
        let count3 = await buffer.bufferedCount
        #expect(count3 == 0)

        #expect(transport.callCount == 3)
        #expect(transport.batches.count == 1)
        #expect(transport.batches[0].signals.count == 2)
    }

    @Test("Signals added during an in-flight flush are preserved")
    func signalsAddedDuringFlushArePreserved() async {
        let dir = makeTempPersistenceDirectory()
        defer { cleanupTempDirectory(dir) }

        let transport = BlockingTransport()
        let buffer = SignalBuffer(persistenceDirectory: dir)

        for i in 0..<1000 {
            await buffer.add(makeTestSignal(type: "before_\(i)"))
        }

        await buffer.configure(appId: "test", transport: transport)

        let flushTask = Task {
            await buffer.flush()
        }

        while transport.batches.isEmpty {
            try? await Task.sleep(for: .milliseconds(1))
        }

        for i in 0..<1000 {
            await buffer.add(makeTestSignal(type: "during_\(i)"))
        }

        transport.release()
        await flushTask.value

        let pendingCount = await buffer.bufferedCount
        #expect(pendingCount == 1000)

        await buffer.flush()

        let sentTypes = transport.batches.flatMap(\.signals).map(\.signalType)
        #expect(sentTypes.count == 2000)
        #expect(sentTypes.contains("before_0"))
        #expect(sentTypes.contains("before_999"))
        #expect(sentTypes.contains("during_0"))
        #expect(sentTypes.contains("during_999"))
    }

    // MARK: - Flush behavior

    @Test("Successful flush removes signals from buffer and disk")
    func successfulFlushCleansUp() async {
        let dir = makeTempPersistenceDirectory()
        defer { cleanupTempDirectory(dir) }

        let transport = RecordingTransport()
        let buffer = SignalBuffer(persistenceDirectory: dir)
        await buffer.configure(appId: "test", transport: transport)

        await buffer.add(makeTestSignal())
        await buffer.add(makeTestSignal())

        let file = dir.appendingPathComponent("signals.json")
        #expect(FileManager.default.fileExists(atPath: file.path))

        await buffer.flush()

        let count = await buffer.bufferedCount
        #expect(count == 0)
        #expect(transport.totalSignalsSent == 2)

        // Disk file should be cleaned up
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test("Flush with empty buffer is a no-op")
    func emptyFlushIsNoOp() async {
        let dir = makeTempPersistenceDirectory()
        defer { cleanupTempDirectory(dir) }

        let transport = RecordingTransport()
        let buffer = SignalBuffer(persistenceDirectory: dir)
        await buffer.configure(appId: "test", transport: transport)

        await buffer.flush()

        #expect(transport.totalSignalsSent == 0)
    }

    @Test("Flush before configure is a no-op — signals preserved")
    func flushBeforeConfigurePreservesSignals() async {
        let dir = makeTempPersistenceDirectory()
        defer { cleanupTempDirectory(dir) }

        let buffer = SignalBuffer(persistenceDirectory: dir)

        // Add signals before configure
        await buffer.add(makeTestSignal(type: "early"))
        await buffer.add(makeTestSignal(type: "early"))

        // Flush without transport — should be a no-op
        await buffer.flush()

        let count = await buffer.bufferedCount
        #expect(count == 2)

        // Now configure and flush — signals should be delivered
        let transport = RecordingTransport()
        await buffer.configure(appId: "test", transport: transport)
        await buffer.flush()

        #expect(transport.totalSignalsSent == 2)
        let types = transport.batches.flatMap(\.signals).map(\.signalType)
        #expect(types.allSatisfy { $0 == "early" })
    }
}
