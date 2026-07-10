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
        defaults.set(data, forKey: key)
        return defaults.data(forKey: key) == data
    }

    func removeData(forKey key: String) {
        defaults.removeObject(forKey: key)
    }
}
