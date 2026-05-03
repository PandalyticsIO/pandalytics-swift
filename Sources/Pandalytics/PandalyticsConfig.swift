import Foundation

/// Static configuration for the Pandalytics SDK.
///
/// No secrets live here. The per-app ingestion key is supplied by the
/// developer at runtime via `Pandalytics.configure(appId:ingestionKey:)` and
/// passed to the ingestion edge function as a Bearer token. The raw Tinybird
/// APPEND tokens that used to be compiled into the SDK are now held by the
/// edge function and never reach the client.
enum PandalyticsConfig {
    /// Production ingestion endpoint. `push.pandalytics.io` is the public URL
    /// contract — see the dashboard repo's AGENTS.md "Public URL contract"
    /// section before changing.
    static let productionIngestURL = URL(string: "https://push.pandalytics.io")!
}
