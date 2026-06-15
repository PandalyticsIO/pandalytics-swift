import Foundation

/// Static configuration for the Pandalytics SDK.
///
/// No secrets live here. The per-app ingestion key is supplied by the
/// developer at runtime via `Pandalytics.configure(appId:ingestionKey:)` and
/// sent to the ingestion endpoint as a Bearer token.
enum PandalyticsConfig {
    /// Production ingestion endpoint. `push.pandalytics.io` is a stable public
    /// URL contract — treat it as immutable; do not change it.
    static let productionIngestURL = URL(string: "https://push.pandalytics.io")!
}
