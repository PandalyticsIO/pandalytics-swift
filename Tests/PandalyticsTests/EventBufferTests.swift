import Testing
import Foundation
@testable import Pandalytics

@Suite("SignalBuffer")
struct SignalBufferTests {

    @Test("Signals are buffered before flush")
    func bufferAccumulatesSignals() async {
        let dir = makeTempPersistenceDirectory()
        defer { cleanupTempDirectory(dir) }

        let buffer = SignalBuffer(persistenceDirectory: dir)
        let transport = RecordingTransport()
        await buffer.configure(appId: "test", transport: transport)

        await buffer.add(makeTestSignal())
        await buffer.add(makeTestSignal())
        await buffer.add(makeTestSignal())

        let count = await buffer.bufferedCount
        #expect(count == 3)
    }

    @Test("SignalBatch JSON encoding matches server format")
    func batchEncodingFormat() throws {
        let signal = Signal(
            signalType: "app_open",
            timestamp: "2026-03-23T10:00:00Z",
            screenName: "HomeScreen",
            appVersion: "2.0.0",
            buildNumber: "42",
            osName: "iOS",
            osVersion: "18.1",
            deviceModel: "iPhone15,2",
            deviceType: "phone",
            locale: "en_US",
            language: "en",
            region: "America/New_York",
            installationHash: "abc123",
            metadata: ["color_scheme": "dark"]
        )

        let batch = SignalBatch(appId: "my-app-id", signals: [signal])
        let data = try JSONEncoder().encode(batch)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["app_id"] as? String == "my-app-id")

        let signals = json["signals"] as! [[String: Any]]
        #expect(signals.count == 1)
        #expect(signals[0]["signal_type"] as? String == "app_open")
        #expect(signals[0]["screen_name"] as? String == "HomeScreen")
        #expect(signals[0]["os_name"] as? String == "iOS")
        #expect(signals[0]["device_model"] as? String == "iPhone15,2")
        #expect(signals[0]["device_type"] as? String == "phone")
        #expect(signals[0]["locale"] as? String == "en_US")
        #expect(signals[0]["language"] as? String == "en")
        #expect(signals[0]["installation_hash"] as? String == "abc123")
        #expect(signals[0]["build_number"] as? String == "42")

        let meta = signals[0]["metadata"] as? [String: String]
        #expect(meta?["color_scheme"] == "dark")
    }

    @Test("Signal encodes device_type, language, and installation_hash")
    func newFieldsEncoding() throws {
        let signal = Signal(
            signalType: "test",
            timestamp: "2026-03-23T10:00:00Z",
            screenName: nil,
            appVersion: "1.0",
            buildNumber: "1",
            osName: "iOS",
            osVersion: "18.0",
            deviceModel: "iPhone15,2",
            deviceType: "tablet",
            locale: "de_DE",
            language: "de",
            region: "Europe/Berlin",
            installationHash: "hash",
            metadata: nil
        )

        let data = try JSONEncoder().encode(signal)
        let json = String(data: data, encoding: .utf8)!

        #expect(json.contains("\"device_type\""))
        #expect(json.contains("\"tablet\""))
        #expect(json.contains("\"language\""))
        #expect(json.contains("\"de\""))
        #expect(json.contains("\"installation_hash\""))
        #expect(json.contains("\"hash\""))
    }
}
