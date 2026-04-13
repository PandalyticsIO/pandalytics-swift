import Foundation
@testable import Pandalytics

/// Creates a test signal with a given type. Minimal fields, no PII.
func makeTestSignal(type: String = "test", metadata: [String: String]? = nil) -> Signal {
    Signal(
        signalType: type,
        timestamp: ISO8601DateFormatter().string(from: Date()),
        screenName: nil,
        appVersion: "1.0",
        buildNumber: "1",
        osName: "iOS",
        osVersion: "18.0",
        deviceModel: "iPhone15,2",
        deviceType: "phone",
        locale: "en_US",
        language: "en",
        region: "UTC",
        userHash: "test-hash",
        isDev: true,
        metadata: metadata
    )
}

/// Creates a unique temp directory for test persistence. Caller should clean up after test.
func makeTempPersistenceDirectory() -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("PandalyticsTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// Removes a temp directory and all its contents.
func cleanupTempDirectory(_ dir: URL) {
    try? FileManager.default.removeItem(at: dir)
}
