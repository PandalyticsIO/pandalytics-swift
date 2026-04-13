import Testing
@testable import Pandalytics

@Suite("SessionManager")
struct SessionManagerTests {

    @Test("Same inputs on same day produce same session hash")
    func sameInputsSameHash() {
        let today = SessionManager.todayString()
        let h1 = SessionManager.generateSessionHash(date: today, osVersion: "18.0", appVersion: "2.0", timezone: "America/New_York")
        let h2 = SessionManager.generateSessionHash(date: today, osVersion: "18.0", appVersion: "2.0", timezone: "America/New_York")
        #expect(h1 == h2)
    }

    @Test("Different OS version produces different session hash")
    func differentOSVersion() {
        let today = SessionManager.todayString()
        let h1 = SessionManager.generateSessionHash(date: today, osVersion: "18.0", appVersion: "2.0", timezone: "America/New_York")
        let h2 = SessionManager.generateSessionHash(date: today, osVersion: "17.0", appVersion: "2.0", timezone: "America/New_York")
        #expect(h1 != h2)
    }

    @Test("Different day produces different session hash")
    func differentDay() {
        let h1 = SessionManager.generateSessionHash(date: "2026-03-23", osVersion: "18.0", appVersion: "2.0", timezone: "America/New_York")
        let h2 = SessionManager.generateSessionHash(date: "2026-03-24", osVersion: "18.0", appVersion: "2.0", timezone: "America/New_York")
        #expect(h1 != h2)
    }

    @Test("Hash is 64-character hex string (SHA-256)")
    func hashFormat() {
        let hash = SessionManager.generateSessionHash(date: "2026-01-01", osVersion: "18.0", appVersion: "1.0", timezone: "UTC")
        #expect(hash.count == 64)
        #expect(hash.allSatisfy { $0.isHexDigit })
    }

    @Test("Installation hash is consistent for same input")
    func installationHashConsistent() {
        let h1 = SessionManager.sha256("test-uuid-123")
        let h2 = SessionManager.sha256("test-uuid-123")
        #expect(h1 == h2)
        #expect(h1.count == 64)
    }

    @Test("Installation hash differs for different input")
    func installationHashDiffers() {
        let h1 = SessionManager.sha256("uuid-aaa")
        let h2 = SessionManager.sha256("uuid-bbb")
        #expect(h1 != h2)
    }
}
