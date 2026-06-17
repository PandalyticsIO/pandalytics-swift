import Foundation

/// Sends signal batches to the Pandalytics ingestion endpoint.
///
/// The request is authenticated with the SDK-supplied ingestion key (sent as a
/// Bearer token). No secret beyond that key ever lives in the client.
///
/// Wire format: newline-delimited JSON (NDJSON) body, one signal per line with
/// `app_id` merged in.
struct PandalyticsTransport: SignalTransport {

    private let ingestURL: URL
    private let ingestionKey: String
    private let options: PandalyticsOptions

    /// - Parameters:
    ///   - ingestURL: Full URL of the ingestion endpoint (defaults to production).
    ///   - ingestionKey: Per-app secret the developer copies from the dashboard.
    ///   - options: SDK options; `options.environment` is sent so the dashboard
    ///     can separate production / beta / debug data.
    init(
        ingestURL: URL = PandalyticsConfig.productionIngestURL,
        ingestionKey: String,
        options: PandalyticsOptions
    ) {
        self.ingestURL = ingestURL
        self.ingestionKey = ingestionKey
        self.options = options
    }

    func send(batch: SignalBatch) async -> TransportResult {
        let encoder = JSONEncoder()
        var lines: [Data] = []
        lines.reserveCapacity(batch.signals.count)

        for signal in batch.signals {
            let flat = FlatSignal(appId: batch.appId, signal: signal)
            guard let line = try? encoder.encode(flat) else {
                return .serverError
            }
            lines.append(line)
        }

        let newline = Data([0x0a])
        var body = Data()
        for (i, line) in lines.enumerated() {
            body.append(line)
            if i < lines.count - 1 {
                body.append(newline)
            }
        }

        var request = URLRequest(url: ingestURL)
        request.httpMethod = "POST"
        request.setValue("application/x-ndjson", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(ingestionKey)", forHTTPHeaderField: "Authorization")
        request.setValue(options.environment.rawValue, forHTTPHeaderField: "X-Pandalytics-Environment")
        // Back-compat: servers/binaries that only know the legacy boolean. Only
        // a debug build is "dev"; beta (TestFlight) is real-ish, not dev.
        request.setValue(
            options.environment == .debug ? "true" : "false",
            forHTTPHeaderField: "X-Pandalytics-Dev"
        )
        request.httpBody = body
        request.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .networkError }
            if (200...299).contains(http.statusCode) { return .success }
            if http.statusCode == 429 || http.statusCode == 402 { return .rateLimited }
            // 401 means the ingestion key is wrong — retrying won't help.
            // Treat like rateLimited (drop) so we don't spam the endpoint.
            if http.statusCode == 401 || http.statusCode == 403 { return .rateLimited }
            return .serverError
        } catch {
            return .networkError
        }
    }
}

/// A flattened signal with `app_id` included on every line so the on-the-wire
/// format stays identical regardless of transport.
private struct FlatSignal: Encodable {
    let appId: String
    let signal: Signal

    enum CodingKeys: String, CodingKey {
        case appId = "app_id"
    }

    func encode(to encoder: Encoder) throws {
        try signal.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(appId, forKey: .appId)
    }
}
