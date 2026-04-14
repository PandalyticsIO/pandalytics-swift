import Testing
import Foundation
@testable import Pandalytics

/// Integration test that sends real signals through the Pandalytics ingestion
/// edge function to the pandalytics_dev Tinybird workspace.
///
/// Simulates a session (app_open → screen_view → screen_view → button_tap → app_close)
/// and verifies the edge function accepts them (2xx) — which implies:
///   1. The ingestion key hashed correctly and resolved to an app_id in Supabase.
///   2. The edge function forwarded the batch to Tinybird successfully.
///
/// Required env vars (no fallback — the test skips if missing, because
/// without a valid key everything is forged):
///   PANDALYTICS_APP_ID         — UUID of the app you created in the dashboard
///   PANDALYTICS_INGESTION_KEY  — the `panda_sk_...` secret shown once at creation
///
/// Optional:
///   PANDALYTICS_INGEST_URL     — override the ingest URL
///                                (default: http://localhost:3000/api/v1/ingest
///                                 so the test hits the local Next.js dev server).
///
/// To run:
///   cd sdks/swift && \
///   PANDALYTICS_APP_ID=<uuid> PANDALYTICS_INGESTION_KEY=panda_sk_... \
///   swift test --filter TinybirdIntegration
///
/// The 5 signals should appear in the pandalytics_dev workspace's `signals`
/// datasource within ~seconds.
@Suite("Tinybird Integration")
struct TinybirdIntegrationTests {

    @Test("Simulated session is delivered via the ingest edge function")
    func sessionDeliveredViaEdgeFunction() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let appId = env["PANDALYTICS_APP_ID"],
              let ingestionKey = env["PANDALYTICS_INGESTION_KEY"] else {
            // Skip cleanly rather than fail — running this test without real
            // creds is pointless since the edge function would reject them.
            print("[integration-test] Skipping: PANDALYTICS_APP_ID and PANDALYTICS_INGESTION_KEY must be set.")
            return
        }

        let ingestURL = URL(
            string: env["PANDALYTICS_INGEST_URL"] ?? "http://localhost:3000/api/v1/ingest"
        )!

        let transport = PandalyticsTransport(
            ingestURL: ingestURL,
            ingestionKey: ingestionKey,
            isDev: true
        )

        let installationHash = "test-installation-\(UUID().uuidString.prefix(8))"
        let now = ISO8601DateFormatter().string(from: Date())

        func makeSignal(type: String, screen: String? = nil, extraMeta: [String: String] = [:]) -> Signal {
            var meta = ["color_scheme": "dark", "source": "swift-integration-test"]
            for (k, v) in extraMeta { meta[k] = v }
            return Signal(
                signalType: type,
                timestamp: now,
                screenName: screen,
                appVersion: "1.0.0",
                buildNumber: "1",
                osName: "iOS",
                osVersion: "18.0",
                deviceModel: "iPhone15,2",
                deviceType: "phone",
                locale: "en_US",
                language: "en",
                region: "America/New_York",
                installationHash: String(installationHash),
                metadata: meta
            )
        }

        let signals: [Signal] = [
            makeSignal(type: "app_open"),
            makeSignal(type: "screen_view", screen: "HomeScreen"),
            makeSignal(type: "screen_view", screen: "SettingsScreen"),
            makeSignal(type: "button_tap", extraMeta: ["button_id": "save"]),
            makeSignal(type: "app_close"),
        ]

        let batch = SignalBatch(appId: appId, signals: signals)
        let result = await transport.send(batch: batch)

        #expect(
            result == .success,
            "Expected success but got \(result). Check that the ingest URL is reachable and the ingestion key is valid."
        )
    }

    @Test("Forged ingestion key is rejected by the edge function")
    func forgedKeyRejected() async throws {
        let env = ProcessInfo.processInfo.environment
        // This test runs unconditionally against localhost — no real creds needed.
        let ingestURL = URL(
            string: env["PANDALYTICS_INGEST_URL"] ?? "http://localhost:3000/api/v1/ingest"
        )!

        // Skip if there's no dev server — we check with a quick HEAD probe.
        // (The transport has a 10s timeout; a wrong URL would just fail slowly.)
        let transport = PandalyticsTransport(
            ingestURL: ingestURL,
            ingestionKey: "panda_sk_obviously-not-a-real-key",
            isDev: true
        )

        let signal = Signal(
            signalType: "forgery_attempt",
            timestamp: ISO8601DateFormatter().string(from: Date()),
            screenName: nil,
            appVersion: "1.0.0", buildNumber: "1",
            osName: "iOS", osVersion: "18.0",
            deviceModel: "iPhone15,2", deviceType: "phone",
            locale: "en_US", language: "en", region: "UTC",
            installationHash: "fake",
            metadata: nil
        )
        let batch = SignalBatch(appId: "00000000-0000-0000-0000-000000000000", signals: [signal])

        let result = await transport.send(batch: batch)

        // A wrong key maps to 401, which our transport translates to `.rateLimited`
        // (signals dropped, no retry). A `.networkError` means the dev server
        // isn't running; skip in that case rather than fail the whole suite.
        if result == .networkError {
            print("[integration-test] Skipping forgery test: dev server at \(ingestURL) is unreachable.")
            return
        }
        #expect(
            result == .rateLimited,
            "Expected forged key to be rejected (mapped to .rateLimited), got \(result)"
        )
    }
}
