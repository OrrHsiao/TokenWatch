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

    @Test("授权面板文案按当前语言生成")
    func openPanelCopyUsesCurrentLanguage() {
        #expect(SecurityScopedBookmarkManager.openPanelCopy(language: .zhHans).message == "TokenWatch 想访问用户目录")
        #expect(SecurityScopedBookmarkManager.openPanelCopy(language: .zhHans).prompt == "授权访问")
        #expect(SecurityScopedBookmarkManager.openPanelCopy(language: .en).message == "TokenWatch wants to access your home folder")
        #expect(SecurityScopedBookmarkManager.openPanelCopy(language: .en).prompt == "Authorize")
    }

    @MainActor
    @Test("无效 bookmark 恢复失败时清除注入 store")
    func invalidBookmarkRemovalUsesInjectedStore() {
        let key = "InvalidBookmark"
        let store = ManagerBookmarkStore(values: [key: Data([0])])
        let manager = SecurityScopedBookmarkManager(bookmarkStore: store)

        #expect(manager.hasBookmark(forKey: key))
        #expect(manager.restoreBookmarkAndAccess(forKey: key) == nil)
        #expect(!manager.hasBookmark(forKey: key))
        #expect(store.removedKeys == [key])
    }
}

private final class ManagerBookmarkStore: BookmarkDataStoring, @unchecked Sendable {
    private var values: [String: Data]
    private(set) var removedKeys: [String] = []

    init(values: [String: Data]) {
        self.values = values
    }

    func data(forKey key: String) -> Data? {
        values[key]
    }

    func save(_ data: Data, forKey key: String) -> Bool {
        values[key] = data
        return values[key] == data
    }

    func removeData(forKey key: String) {
        values[key] = nil
        removedKeys.append(key)
    }
}
