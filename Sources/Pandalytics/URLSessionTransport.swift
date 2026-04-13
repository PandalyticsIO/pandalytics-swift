import Foundation

/// Sends signal batches to the Pandalytics ingestion server over HTTP using URLSession.
/// This is the only component that performs real network I/O.
struct URLSessionTransport: SignalTransport {

    private static let productionURL = URL(string: "https://push.pandalytics.io")!
    private static let devURL = URL(string: "https://pushdev.pandalytics.io")!

    private let serverURL: URL

    init(isDev: Bool) {
        self.serverURL = isDev ? Self.devURL : Self.productionURL
    }

    func send(batch: SignalBatch) async -> TransportResult {
        guard let body = try? JSONEncoder().encode(batch) else {
            return .serverError
        }

        var request = URLRequest(url: serverURL.appendingPathComponent("/v1/signals"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .networkError }
            if (200...299).contains(http.statusCode) { return .success }
            if http.statusCode == 429 || http.statusCode == 402 { return .rateLimited }
            return .serverError
        } catch {
            return .networkError
        }
    }
}
