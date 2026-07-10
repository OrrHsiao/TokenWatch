import Foundation
import Testing
@testable import TokenWatch

@MainActor
@Suite("BookmarkPersistence")
struct BookmarkPersistenceTests {
    @Test("bookmark data 创建失败时授权完成结果为 nil")
    func creationFailureReturnsNil() {
        let manager = SecurityScopedBookmarkManager(
            bookmarkDataCreator: ThrowingBookmarkDataCreator(),
            bookmarkStore: InMemoryBookmarkStore()
        )

        let result = manager.persistSelectedDirectory(
            URL(fileURLWithPath: "/Users/example", isDirectory: true),
            forKey: "bookmark"
        )

        #expect(result == nil)
        #expect(!manager.hasBookmark(forKey: "bookmark"))
    }

    @Test("bookmark store 拒绝写入时授权完成结果为 nil")
    func saveFailureReturnsNil() {
        let manager = SecurityScopedBookmarkManager(
            bookmarkDataCreator: FixedBookmarkDataCreator(data: Data([1, 2, 3])),
            bookmarkStore: RejectingBookmarkStore()
        )

        let result = manager.persistSelectedDirectory(
            URL(fileURLWithPath: "/Users/example", isDirectory: true),
            forKey: "bookmark"
        )

        #expect(result == nil)
        #expect(!manager.hasBookmark(forKey: "bookmark"))
    }

    @Test("UserDefaults store 写后回读相同数据才返回成功")
    func userDefaultsStoreVerifiesRoundTrip() throws {
        let suite = "BookmarkPersistenceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsBookmarkStore(defaults: defaults)
        let data = Data([4, 5, 6])

        #expect(store.save(data, forKey: "bookmark"))
        #expect(store.data(forKey: "bookmark") == data)
    }
}

private enum BookmarkFixtureError: Error {
    case creationFailed
}

private struct ThrowingBookmarkDataCreator: BookmarkDataCreating {
    func createBookmarkData(for url: URL) throws -> Data {
        throw BookmarkFixtureError.creationFailed
    }
}

private struct FixedBookmarkDataCreator: BookmarkDataCreating {
    let data: Data

    func createBookmarkData(for url: URL) throws -> Data {
        data
    }
}

private final class InMemoryBookmarkStore: BookmarkDataStoring, @unchecked Sendable {
    private var values: [String: Data] = [:]

    func data(forKey key: String) -> Data? {
        values[key]
    }

    func save(_ data: Data, forKey key: String) -> Bool {
        values[key] = data
        return values[key] == data
    }

    func removeData(forKey key: String) {
        values[key] = nil
    }
}

private struct RejectingBookmarkStore: BookmarkDataStoring {
    func data(forKey key: String) -> Data? { nil }
    func save(_ data: Data, forKey key: String) -> Bool { false }
    func removeData(forKey key: String) {}
}
