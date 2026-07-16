import Foundation

protocol BookmarkDataCreating: Sendable {
    func createBookmarkData(for url: URL) throws -> Data
}

struct SecurityScopedBookmarkDataCreator: BookmarkDataCreating {
    func createBookmarkData(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }
}

struct ResolvedBookmark: Sendable, Equatable {
    let url: URL
    let isStale: Bool
}

protocol BookmarkDataResolving: Sendable {
    /// 解析 security-scoped bookmark 并返回过期状态。
    /// - Parameter data: 已持久化的 bookmark data。
    /// - Returns: 解析后的 URL 与 stale 标记。
    func resolveBookmarkData(_ data: Data) throws -> ResolvedBookmark
}

struct SecurityScopedBookmarkDataResolver: BookmarkDataResolving {
    func resolveBookmarkData(_ data: Data) throws -> ResolvedBookmark {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return ResolvedBookmark(url: url, isStale: isStale)
    }
}

protocol SecurityScopedResourceAccessing: Sendable {
    /// 开始访问 security-scoped URL。
    func startAccessing(_ url: URL) -> Bool

    /// 停止访问 security-scoped URL。
    func stopAccessing(_ url: URL)
}

struct URLSecurityScopedResourceAccessor: SecurityScopedResourceAccessing {
    func startAccessing(_ url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}

protocol BookmarkDataStoring: Sendable {
    func data(forKey key: String) -> Data?

    /// 保存 bookmark data；返回 `false` 时不得改变调用前的值。
    func save(_ data: Data, forKey key: String) -> Bool
    func removeData(forKey key: String)
}

final class UserDefaultsBookmarkStore: BookmarkDataStoring, @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func data(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    func save(_ data: Data, forKey key: String) -> Bool {
        let previousValue = defaults.object(forKey: key)
        defaults.set(data, forKey: key)
        guard defaults.data(forKey: key) == data else {
            if let previousValue {
                defaults.set(previousValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
            return false
        }
        return true
    }

    func removeData(forKey key: String) {
        defaults.removeObject(forKey: key)
    }
}
