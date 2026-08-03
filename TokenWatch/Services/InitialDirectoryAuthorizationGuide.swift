import Foundation

/// 管理首次未选择任何数据目录时的一次性设置引导。
///
/// 该引导只决定是否提示和记录已展示状态；不会打开目录面板或创建 bookmark。
@MainActor
struct InitialDirectoryAuthorizationGuide {
    static let storageKey = "TokenWatch.didPresentInitialDirectoryAuthorizationGuide"
    static let debugForcePresentationArgument =
        "--force-initial-directory-authorization-guide"
    static let automatedTestingSkipPresentationEnvironmentKey =
        "TOKENWATCH_SKIP_INITIAL_DIRECTORY_AUTHORIZATION_GUIDE"

    private let defaults: UserDefaults
    private let bookmarkKeys: [String]
    private let hasBookmark: (String) -> Bool
    private let isDebugPresentationForced: () -> Bool
    private let isPresentationSuppressedForAutomation: () -> Bool

    init(
        defaults: UserDefaults = .standard,
        bookmarkKeys: [String] = ProviderRegistry.allProviders.map(\.bookmarkKey),
        hasBookmark: @escaping (String) -> Bool = { key in
            SecurityScopedBookmarkManager.shared.hasBookmark(forKey: key)
        },
        isDebugPresentationForced: @escaping () -> Bool = {
#if DEBUG
            CommandLine.arguments.contains(
                InitialDirectoryAuthorizationGuide.debugForcePresentationArgument
            )
#else
            false
#endif
        },
        isPresentationSuppressedForAutomation: @escaping () -> Bool = {
#if DEBUG
            ProcessInfo.processInfo.environment[
                InitialDirectoryAuthorizationGuide.automatedTestingSkipPresentationEnvironmentKey
            ] == "YES"
#else
            false
#endif
        }
    ) {
        self.defaults = defaults
        self.bookmarkKeys = bookmarkKeys
        self.hasBookmark = hasBookmark
        self.isDebugPresentationForced = isDebugPresentationForced
        self.isPresentationSuppressedForAutomation = isPresentationSuppressedForAutomation
    }

    /// 仅当从未展示过引导且所有 provider 都没有保存 bookmark 时返回 `true`。
    /// Debug 强制测试开启时，只要存在 provider 即返回 `true`。
    func shouldPresent() -> Bool {
        guard !bookmarkKeys.isEmpty else { return false }

        // 仅供本地调试和 UI 测试验证提示流程，不会修改真实 bookmark 或发布版行为。
        if isDebugPresentationForced() {
            return true
        }

        // App-hosted 单元测试不能等待用户交互的模态提示。
        // 此显式环境变量仅由 CI 单元测试任务设置。
        guard !isPresentationSuppressedForAutomation() else {
            return false
        }

        guard !defaults.bool(forKey: Self.storageKey) else {
            return false
        }
        return bookmarkKeys.allSatisfy { !hasBookmark($0) }
    }

    /// 在用户响应提示后记录状态，确保用户选择“稍后”后也不会重复打扰。
    /// Debug 强制测试不记录该状态，以便每次启动均可重复验证。
    func markPresented() {
        // 强制测试不污染用户已有的一次性展示记录，因此每次 Debug Run 均可重现。
        guard !isDebugPresentationForced() else { return }
        defaults.set(true, forKey: Self.storageKey)
    }
}
