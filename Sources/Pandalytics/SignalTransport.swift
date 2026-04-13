import Foundation

/// Result of attempting to send a signal batch to the ingestion server.
enum TransportResult: Sendable {
    /// Batch was accepted by the server (2xx).
    case success
    /// Server rejected the batch due to rate limiting (429) or quota exceeded (402).
    /// Signals should be dropped — retrying would produce the same result.
    case rateLimited
    /// Server returned an error (5xx or unexpected status). Retry later.
    case serverError
    /// Network is unreachable or the request timed out. Retry later.
    case networkError
}

/// Abstraction over how signal batches are delivered to the ingestion server.
/// The real implementation uses URLSession; test doubles can simulate any failure scenario.
protocol SignalTransport: Sendable {
    func send(batch: SignalBatch) async -> TransportResult
}
