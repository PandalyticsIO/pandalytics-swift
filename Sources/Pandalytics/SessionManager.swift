import Foundation
import CryptoKit

/// Manages two identity layers:
/// 1. installationHash: persistent per-install UUID (stored in UserDefaults), SHA-256 hashed.
///    Deleted when the app is uninstalled. Enables retention tracking.
/// 2. sessionHash: daily-rotating hash from device properties. Groups signals within a day.
actor SessionManager {

    private static let installationIdKey = "com.pandalytics.installationId"

    private var cachedSessionHash: String?
    private var cachedDate: String?

    /// Returns the persistent installation hash (SHA-256 of a random UUID stored in UserDefaults).
    /// The UUID is generated on first call and persists until the app is uninstalled.
    func installationHash() -> String {
        let uuid = Self.getOrCreateInstallationId()
        return Self.sha256(uuid)
    }

    /// Returns the current session hash. Rotates daily.
    func currentSessionHash() -> String {
        let today = Self.todayString()

        if let cached = cachedSessionHash, cachedDate == today {
            return cached
        }

        let hash = Self.generateSessionHash(date: today)
        cachedSessionHash = hash
        cachedDate = today
        return hash
    }

    // MARK: - Installation ID (persistent per install)

    private static func getOrCreateInstallationId() -> String {
        if let existing = UserDefaults.standard.string(forKey: installationIdKey) {
            return existing
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: installationIdKey)
        return newId
    }

    // MARK: - Session hash (daily-rotating)

    static func generateSessionHash(
        date: String? = nil,
        osVersion: String? = nil,
        appVersion: String? = nil,
        timezone: String? = nil
    ) -> String {
        let day = date ?? todayString()
        let os = osVersion ?? ProcessInfo.processInfo.operatingSystemVersionString
        let app = appVersion ?? (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")
        let tz = timezone ?? TimeZone.current.identifier

        let input = "\(day):\(os):\(app):\(tz)"
        return sha256(input)
    }

    static func sha256(_ input: String) -> String {
        let hash = SHA256.hash(data: Data(input.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: Date())
    }
}
