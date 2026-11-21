import Testing
import Foundation
@testable import Pandalytics

/// The `config` object on an ingest line (#186) — the wire shape the server
/// reads in `web/lib/ingest/config.ts`: string pairs under `config`, absent on
/// lines that report none.
@Suite("Installation config")
struct InstallationConfigTests {

    private func json(_ signal: Signal) throws -> [String: Any] {
        let data = try JSONEncoder().encode(signal)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("A line carrying config encodes it as a string object under `config`")
    func configOnTheWire() throws {
        var signal = makeTestSignal(type: "config_change")
        signal.config = ["smart_sync": "on", "theme": "dark"]

        let line = try json(signal)
        let config = try #require(line["config"] as? [String: String])
        #expect(config == ["smart_sync": "on", "theme": "dark"])
        #expect(line["installation_hash"] as? String == "test-hash")
    }

    @Test("A line without config has no `config` key at all")
    func noConfigNoKey() throws {
        let line = try json(makeTestSignal(type: "app_open"))
        #expect(line["config"] == nil)
    }

    @Test("An empty value is sent — it clears the key on the server")
    func emptyValueIsSent() throws {
        var signal = makeTestSignal(type: "config_change")
        signal.config = ["theme": ""]
        let config = try #require(try json(signal)["config"] as? [String: String])
        #expect(config == ["theme": ""])
    }

    @Test("Signals persisted before config existed still load")
    func oldPersistedSignalsDecode() throws {
        let old = #"""
        {"signal_type":"app_open","timestamp":"2026-03-23T10:00:00Z","app_version":"1.0",
         "build_number":"1","os_name":"iOS","os_version":"18.0","device_model":"iPhone15,2",
         "device_type":"phone","locale":"en_US","language":"en","region":"UTC",
         "country_code":"US","installation_hash":"h"}
        """#
        let signal = try JSONDecoder().decode(Signal.self, from: Data(old.utf8))
        #expect(signal.config == nil)
    }

    @Test("Config survives the disk buffer and reaches the transport")
    func configSurvivesBuffer() async throws {
        let dir = makeTempPersistenceDirectory()
        defer { cleanupTempDirectory(dir) }

        var signal = makeTestSignal(type: "config_change")
        signal.config = ["smart_sync": "off"]

        // Written to disk before any transport exists…
        let first = SignalBuffer(persistenceDirectory: dir)
        await first.add(signal)

        // …and read back by the next launch, which sends it.
        let transport = RecordingTransport()
        let second = SignalBuffer(persistenceDirectory: dir)
        await second.configure(appId: "app", transport: transport)
        await second.flush()

        let sent = try #require(transport.batches.first?.signals.first)
        #expect(sent.config == ["smart_sync": "off"])
    }
}
