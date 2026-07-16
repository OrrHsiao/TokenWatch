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
