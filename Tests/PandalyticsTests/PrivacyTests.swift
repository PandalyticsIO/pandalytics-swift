import Testing
import Foundation
@testable import Pandalytics

@Suite("Privacy")
struct PrivacyTests {

    @Test("Signal payload contains no IP address field")
    func noIPInPayload() throws {
        let signal = Signal(
            signalType: "test",
            timestamp: "2026-03-23T10:00:00Z",
            screenName: "Home",
            appVersion: "1.0",
            buildNumber: "42",
            osName: "iOS",
            osVersion: "18.0",
            deviceModel: "iPhone15,2",
            deviceType: "phone",
            locale: "en_US",
            language: "en",
            region: "America/New_York",
            installationHash: "abc123hash",
            metadata: nil
        )

        let data = try JSONEncoder().encode(signal)
        let json = String(data: data, encoding: .utf8)!

        #expect(!json.contains("\"ip\""))
        #expect(!json.contains("device_id"))
        #expect(!json.contains("idfa"))
        #expect(!json.contains("idfv"))
        #expect(!json.contains("advertising"))
    }

    @Test("Signal batch payload uses correct field names for server")
    func batchEncodingMatchesServer() throws {
        let signal = Signal(
            signalType: "app_open",
            timestamp: "2026-03-23T10:00:00Z",
            screenName: nil,
            appVersion: "2.0",
            buildNumber: "100",
            osName: "macOS",
            osVersion: "15.0",
            deviceModel: "Mac14,2",
            deviceType: "desktop",
            locale: "de_DE",
            language: "de",
            region: "Europe/Berlin",
            installationHash: "hashed_user",
            metadata: ["color_scheme": "dark"]
        )

        let batch = SignalBatch(appId: "test-app", signals: [signal])
        let data = try JSONEncoder().encode(batch)
        let json = String(data: data, encoding: .utf8)!

        // Verify the server-expected field names
        #expect(json.contains("\"app_id\""))
        #expect(json.contains("\"signals\""))
        #expect(json.contains("\"signal_type\""))
        #expect(json.contains("\"installation_hash\""))
        #expect(json.contains("\"build_number\""))
        #expect(json.contains("\"device_model\""))
        #expect(json.contains("\"device_type\""))
        #expect(json.contains("\"locale\""))
        #expect(json.contains("\"language\""))
        #expect(json.contains("\"metadata\""))
        #expect(json.contains("\"color_scheme\""))

        // Verify no PII field names
        #expect(!json.contains("\"ip\""))
        #expect(!json.contains("\"user_agent\""))
        #expect(!json.contains("\"device_id\""))
    }

    @Test("Installation hash does not contain the raw UUID")
    func installationHashOpaqueToUUID() {
        let uuid = "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"
        let hash = SessionManager.sha256(uuid)
        #expect(!hash.contains("E621"))
        #expect(!hash.contains("C36C"))
        #expect(hash.count == 64)
    }

    @Test("Region uses IANA timezone identifier, not IP geolocation")
    func regionIsTimezone() {
        let signal = Signal(
            signalType: "test",
            timestamp: "2026-03-23T10:00:00Z",
            screenName: nil,
            appVersion: "1.0",
            buildNumber: "1",
            osName: "iOS",
            osVersion: "18.0",
            deviceModel: "iPhone15,2",
            deviceType: "phone",
            locale: "en_US",
            language: "en",
            region: TimeZone.current.identifier,
            installationHash: "hash",
            metadata: nil
        )

        #expect(signal.region.contains("/") || signal.region == "UTC" || signal.region == "GMT")
    }
}
