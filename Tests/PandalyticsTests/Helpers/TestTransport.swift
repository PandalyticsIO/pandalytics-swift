import Foundation
@testable import Pandalytics

/// Records all batches sent — acts as a "dummy database" for test assertions.
final class RecordingTransport: SignalTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _batches: [SignalBatch] = []

    var batches: [SignalBatch] {
        lock.withLock { _batches }
    }

    var totalSignalsSent: Int {
        batches.flatMap(\.signals).count
    }

    func send(batch: SignalBatch) async -> TransportResult {
        lock.withLock { _batches.append(batch) }
        return .success
    }
}

/// Always returns a specific failure — simulates persistent network down, server errors, rate limiting.
final class FailingTransport: SignalTransport, @unchecked Sendable {
    let result: TransportResult
    private let lock = NSLock()
    private var _attemptCount = 0

    var attemptCount: Int {
        lock.withLock { _attemptCount }
    }

    init(result: TransportResult) {
        self.result = result
    }

    func send(batch: SignalBatch) async -> TransportResult {
        lock.withLock { _attemptCount += 1 }
        return result
    }
}

/// Fails N times then succeeds — simulates temporary network outage recovery.
final class TransientFailureTransport: SignalTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _callCount = 0
    private var _batches: [SignalBatch] = []
    let failCount: Int

    var callCount: Int {
        lock.withLock { _callCount }
    }

    var batches: [SignalBatch] {
        lock.withLock { _batches }
    }

    init(failCount: Int) {
        self.failCount = failCount
    }

    func send(batch: SignalBatch) async -> TransportResult {
        let current = lock.withLock {
            _callCount += 1
            return _callCount
        }
        if current <= failCount {
            return .networkError
        }
        lock.withLock { _batches.append(batch) }
        return .success
    }
}

/// Adds a configurable delay before responding — verifies the SDK doesn't block and tests concurrent flush guards.
final class SlowTransport: SignalTransport, @unchecked Sendable {
    let delay: Duration
    private let lock = NSLock()
    private var _batches: [SignalBatch] = []

    var batches: [SignalBatch] {
        lock.withLock { _batches }
    }

    init(delay: Duration) {
        self.delay = delay
    }

    func send(batch: SignalBatch) async -> TransportResult {
        try? await Task.sleep(for: delay)
        lock.withLock { _batches.append(batch) }
        return .success
    }
}
