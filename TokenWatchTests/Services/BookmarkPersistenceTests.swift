import Foundation
import Testing
@testable import TokenWatch

@MainActor
@Suite("BookmarkPersistence")
struct BookmarkPersistenceTests {
    @Test("重新选择时 bookmark 创建失败会保留旧数据")
    func reselectionCreationFailureKeepsExistingBookmark() {
        let oldData = Data([1, 2, 3])
        let store = InMemoryBookmarkStore(values: ["bookmark": oldData])
        let manager = SecurityScopedBookmarkManager(
            bookmarkDataCreator: ThrowingBookmarkDataCreator(),
            bookmarkStore: store
        )

        #expect(!manager.persistSelectedDirectory(
            URL(fileURLWithPath: "/replacement", isDirectory: true),
            forKey: "bookmark"
        ))
        #expect(store.data(forKey: "bookmark") == oldData)
    }

    @Test("重新选择时 bookmark 保存失败会保留旧数据")
    func reselectionSaveFailureKeepsExistingBookmark() {
        let oldData = Data([4, 5, 6])
        let store = RejectingBookmarkStore(values: ["bookmark": oldData])
        let manager = SecurityScopedBookmarkManager(
            bookmarkDataCreator: FixedBookmarkDataCreator(data: Data([7, 8, 9])),
            bookmarkStore: store
        )

        #expect(!manager.persistSelectedDirectory(
            URL(fileURLWithPath: "/replacement", isDirectory: true),
            forKey: "bookmark"
        ))
        #expect(store.data(forKey: "bookmark") == oldData)
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
    private var values: [String: Data]

    init(values: [String: Data] = [:]) {
        self.values = values
    }

    func data(forKey key: String) -> Data? { values[key] }

    func save(_ data: Data, forKey key: String) -> Bool {
        values[key] = data
        return true
    }

    func removeData(forKey key: String) { values[key] = nil }
}

private final class RejectingBookmarkStore: BookmarkDataStoring, @unchecked Sendable {
    private var values: [String: Data]

    init(values: [String: Data] = [:]) {
        self.values = values
    }

    func data(forKey key: String) -> Data? { values[key] }
    func save(_ data: Data, forKey key: String) -> Bool { false }
    func removeData(forKey key: String) { values[key] = nil }
}
