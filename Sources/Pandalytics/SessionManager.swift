import Foundation
import CryptoKit

/// Manages the installation identity:
/// installationHash is a persistent per-install UUID stored in UserDefaults and
/// SHA-256 hashed before it leaves the device. It is deleted when the app is
/// uninstalled and enables installation-level analytics.
actor SessionManager {

    private static let installationIdKey = "com.pandalytics.installationId"

    /// Returns the persistent installation hash (SHA-256 of a random UUID stored in UserDefaults).
    /// The UUID is generated on first call and persists until the app is uninstalled.
    func installationHash() -> String {
        let uuid = Self.getOrCreateInstallationId()
        return Self.sha256(uuid)
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

    static func sha256(_ input: String) -> String {
        let hash = SHA256.hash(data: Data(input.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
