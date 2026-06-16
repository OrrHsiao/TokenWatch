import Foundation
import Testing
@testable import TokenWatch

struct SecurityScopedBookmarkManagerTests {

    @Test("同一 bookmark key 的并发访问需要成对释放")
    func sharedSessionRequiresBalancedStops() {
        var sessions = SecurityScopedAccessSessions()
        let key = "HomeDirectoryBookmark"
        let url = URL(fileURLWithPath: "/Users/example", isDirectory: true)

        sessions.insert(url, forKey: key)
        #expect(sessions.retainExisting(forKey: key) == url)

        #expect(sessions.release(forKey: key) == nil)
        #expect(sessions.retainExisting(forKey: key) == url)

        #expect(sessions.release(forKey: key) == nil)
        #expect(sessions.release(forKey: key) == url)
        #expect(sessions.retainExisting(forKey: key) == nil)
    }
}
