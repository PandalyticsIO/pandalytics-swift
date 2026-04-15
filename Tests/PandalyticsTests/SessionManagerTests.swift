import Testing
@testable import Pandalytics

@Suite("SessionManager")
struct SessionManagerTests {

    @Test("Hash is 64-character hex string (SHA-256)")
    func hashFormat() {
        let hash = SessionManager.sha256("test-uuid-123")
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
