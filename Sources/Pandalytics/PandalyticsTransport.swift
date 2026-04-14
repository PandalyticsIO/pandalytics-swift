import Foundation

/// Sends signal batches to the Pandalytics ingestion edge function.
///
/// The edge function (at `/api/v1/ingest`) authenticates the request using
/// the SDK-supplied ingestion key, rewrites `app_id` on every row from the
/// server-resolved value, and forwards the batch to Tinybird. The raw Tinybird
/// APPEND token never leaves the server — that's the whole point of this
/// transport existing.
///
/// Wire format: NDJSON body, one signal per line with `app_id` merged in.
struct PandalyticsTransport: SignalTransport {

    private let ingestURL: URL
    private let ingestionKey: String
    private let isDev: Bool

    /// - Parameters:
    ///   - ingestURL: Full URL of the ingestion endpoint (defaults to production).
    ///   - ingestionKey: Per-app secret the developer copies from the dashboard.
    ///   - isDev: Routes to the `pandalytics_dev` workspace when true.
    init(
        ingestURL: URL = PandalyticsConfig.productionIngestURL,
        ingestionKey: String,
        isDev: Bool
    ) {
        self.ingestURL = ingestURL
        self.ingestionKey = ingestionKey
        self.isDev = isDev
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
        request.setValue(isDev ? "true" : "false", forHTTPHeaderField: "X-Pandalytics-Dev")
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

/// A flattened signal with app_id included — matches the Tinybird `signals`
/// datasource schema. The edge function will overwrite `app_id` with the
/// server-authenticated value, but we include the SDK-supplied value so the
/// on-the-wire format stays identical regardless of transport.
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
