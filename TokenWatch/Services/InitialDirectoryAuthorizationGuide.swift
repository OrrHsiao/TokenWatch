import Foundation

/// 管理首次未选择任何数据目录时的一次性设置引导。
///
/// 该引导只决定是否提示和记录已展示状态；不会打开目录面板或创建 bookmark。
@MainActor
struct InitialDirectoryAuthorizationGuide {
    static let storageKey = "TokenWatch.didPresentInitialDirectoryAuthorizationGuide"

    private let defaults: UserDefaults
    private let bookmarkKeys: [String]
    private let hasBookmark: (String) -> Bool

    init(
        defaults: UserDefaults = .standard,
        bookmarkKeys: [String] = ProviderRegistry.allProviders.map(\.bookmarkKey),
        hasBookmark: @escaping (String) -> Bool = { key in
            SecurityScopedBookmarkManager.shared.hasBookmark(forKey: key)
        }
    ) {
        self.defaults = defaults
        self.bookmarkKeys = bookmarkKeys
        self.hasBookmark = hasBookmark
    }

    /// 仅当从未展示过引导且所有 provider 都没有保存 bookmark 时返回 `true`。
    func shouldPresent() -> Bool {
        guard !defaults.bool(forKey: Self.storageKey), !bookmarkKeys.isEmpty else {
            return false
        }
        return bookmarkKeys.allSatisfy { !hasBookmark($0) }
    }

    /// 在展示 sheet 前记录状态，确保用户选择“稍后”后也不会重复打扰。
    func markPresented() {
        defaults.set(true, forKey: Self.storageKey)
    }
}
