import Foundation

/// A single analytics signal. Contains no personal data.
/// Tracks app installations, not users.
struct Signal: Codable, Sendable {
    let signalType: String
    let timestamp: String
    let screenName: String?
    let appVersion: String
    let buildNumber: String
    let osName: String
    let osVersion: String
    let deviceModel: String
    let deviceType: String              // phone, tablet, desktop, watch, tv, headset, unknown
    let locale: String
    let language: String                // ISO 639-1 e.g. "en", "de"
    let region: String                  // IANA timezone identifier
    let installationHash: String        // SHA-256 of persistent installation UUID
    let metadata: [String: String]?     // color_scheme, accessibility, custom

    enum CodingKeys: String, CodingKey {
        case signalType = "signal_type"
        case timestamp
        case screenName = "screen_name"
        case appVersion = "app_version"
        case buildNumber = "build_number"
        case osName = "os_name"
        case osVersion = "os_version"
        case deviceModel = "device_model"
        case deviceType = "device_type"
        case locale
        case language
        case region
        case installationHash = "installation_hash"
        case metadata
    }
}

/// The batch payload sent to the ingestion server.
struct SignalBatch: Codable, Sendable {
    let appId: String
    let signals: [Signal]

    enum CodingKeys: String, CodingKey {
        case appId = "app_id"
        case signals
    }
}
