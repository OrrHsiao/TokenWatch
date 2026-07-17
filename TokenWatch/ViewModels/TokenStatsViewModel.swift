import Foundation
import os.log

enum ProviderDirectoryState: Sendable, Equatable {
    case notSelected
    case selected
    case selectedNoData
    case needsReselection

    var needsAuthorization: Bool {
        self == .notSelected || self == .needsReselection
    }
}

/// 多 provider 用量统计 ViewModel
///
/// 每个 provider 维护独立 ProviderState(stats / loading / error / 授权状态),
/// 各 Tab 之间互不影响。重 IO + 解析在后台 actor 上执行,保证 UI 不卡顿。
@MainActor
final class TokenStatsViewModel: Sendable {

    /// 刷新行为。
    enum LoadMode: Sendable, Equatable {
        /// 用户主动触发的刷新:发送 loading 状态通知。
        case interactive
        /// 后台定时刷新:数据未变化时不发送通知。
        case silentIfUnchanged
    }

    /// 单 provider 的 UI 状态
    struct ProviderState: Sendable {
        var stats: AggregatedStats?
        var entries: [ParsedUsageEntry]?
        var isLoading = false
        var errorMessage: String?
        var needsAuthorization = true
        var lastRefreshedAt: Date?
        var directoryState: ProviderDirectoryState = .notSelected
        var directoryAuthorizationErrorMessage: String?
        var isAuthorizing = false
    }

    /// 当前所有 provider 的状态(只读)
    private(set) var states: [ProviderID: ProviderState] = [:]

    /// observer 注册凭证;移除 observer 时使用
    struct ObservationToken: Hashable, Sendable {
        let id: UUID
    }

    /// 已注册的 observer。key 为 token,value 为 main-actor 隔离的回调
    private var observers: [ObservationToken: @MainActor (ProviderID) -> Void] = [:]

    private let providers: [any UsageProvider]
    private let bookmarkManager: any BookmarkAccessManaging
    private let languageSettings: AppLanguageSettings
    private let aggregator: any UsageAggregating
    private let nowProvider: @Sendable () -> Date
    private let logger = Logger(subsystem: "com.xiaoao.TokenWatch", category: "TokenStatsViewModel")
    private var loadGate = ProviderLoadGate()
    private var entryFingerprints: [ProviderID: UsageEntriesFingerprint] = [:]

    init(
        languageSettings: AppLanguageSettings = .shared,
        providers: [any UsageProvider] = ProviderRegistry.allProviders,
        bookmarkManager: any BookmarkAccessManaging = SecurityScopedBookmarkManager.shared,
        aggregator: any UsageAggregating = UsageAggregator(),
        nowProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.languageSettings = languageSettings
        self.providers = providers
        self.bookmarkManager = bookmarkManager
        self.aggregator = aggregator
        self.nowProvider = nowProvider
        for provider in providers {
            states[provider.id] = ProviderState()
        }
    }

    nonisolated static func cannotAccessDataDirectoryMessage(
        providerName: String,
        language: AppLanguage
    ) -> String {
        String(
            format: AppStrings.text(
                .errorCannotAccessProviderDirectoryFormat,
                language: language
            ),
            providerName
        )
    }

    nonisolated static func authorizationFailedMessage(
        providerName: String,
        language: AppLanguage
    ) -> String {
        String(
            format: AppStrings.text(
                .errorProviderDirectoryAuthorizationFailedFormat,
                language: language
            ),
            providerName
        )
    }

    nonisolated static func loadFailedMessage(error: Error, language: AppLanguage) -> String {
        let detail: String
        if let localizedError = error as? any AppLocalizedError {
            detail = localizedError.localizedDescription(language: language)
        } else {
            detail = error.localizedDescription
        }
        return "\(AppStrings.text(.errorLoadFailedPrefix, language: language)): \(detail)"
    }

    /// 注册状态变更监听
    /// - Parameter handler: 任一 provider 状态变化时被调用
    /// - Returns: 凭证,后续可用于 removeObserver
    @discardableResult
    func observe(_ handler: @escaping @MainActor (ProviderID) -> Void) -> ObservationToken {
        let token = ObservationToken(id: UUID())
        observers[token] = handler
        return token
    }

    /// 取消之前 observe 注册的回调
    func removeObserver(_ token: ObservationToken) {
        observers.removeValue(forKey: token)
    }

    /// 通知所有 observer 指定 provider 状态变更
    private func notifyStateChange(_ id: ProviderID) {
        // 拷贝快照后再遍历:handler 内部若同步 observe/removeObserver,
        // 直接迭代 dict 会触发 UB。同步通知 + 异步使用模式下,这是廉价且必要的防御
        for handler in Array(observers.values) {
            handler(id)
        }
    }

    /// 启动时并发触发所有 provider 的 loadStats
    /// 设计原因:Swift 6 region-based isolation checker 在 `withTaskGroup` 闭包中
    /// 显式标 `@MainActor [weak self]` 时会崩(编译器内部错误);
    /// 改为 `await self.loadStats(...)` 让 main actor 自动 hop,行为等价且 self 由 AppDelegate 持有不会循环引用。
    func loadAllStats(mode: LoadMode = .interactive) async {
        await withTaskGroup(of: Void.self) { group in
            for provider in providers {
                let id = provider.id
                group.addTask {
                    await self.loadStats(for: id, mode: mode)
                }
            }
        }
    }

    private func setDirectoryState(
        _ directoryState: ProviderDirectoryState,
        for id: ProviderID
    ) {
        states[id]?.directoryState = directoryState
        states[id]?.needsAuthorization =
            directoryState.needsAuthorization
    }

    /// 清除仅属于一个 provider 的解析结果。
    /// - Returns: 清理前是否存在需要通知 UI 的数据或刷新时间。
    @discardableResult
    private func clearProviderData(for id: ProviderID) -> Bool {
        let hadData = states[id]?.stats != nil
            || states[id]?.entries != nil
            || entryFingerprints[id] != nil
            || states[id]?.lastRefreshedAt != nil

        states[id]?.stats = nil
        states[id]?.entries = nil
        states[id]?.lastRefreshedAt = nil
        entryFingerprints.removeValue(forKey: id)
        return hadData
    }

    /// 加载指定 provider 的统计。
    /// 授权面板活动时跳过加载；取得 gate 后才允许开始 bookmark 恢复。
    func loadStats(
        for id: ProviderID,
        mode: LoadMode = .interactive
    ) async {
        guard let provider = provider(for: id) else {
            return
        }
        guard states[id]?.isAuthorizing != true else {
            logger.info(
                "\(provider.displayName) 正在选择数据目录,跳过刷新"
            )
            return
        }
        guard loadGate.enter(id) else {
            logger.info(
                "\(provider.displayName) 已在刷新中,跳过重复请求"
            )
            return
        }

        await performLoad(for: provider, mode: mode)
    }

    /// 执行已取得 provider load gate 的完整加载。
    /// 所有 return 路径都由 defer 释放 gate。
    private func performLoad(
        for provider: any UsageProvider,
        mode: LoadMode
    ) async {
        let id = provider.id
        defer { loadGate.leave(id) }

        let sendsLoadingNotifications = mode == .interactive
        if sendsLoadingNotifications {
            states[id]?.isLoading = true
            states[id]?.errorMessage = nil
            notifyStateChange(id)
        }

        guard bookmarkManager.hasBookmark(
            forKey: provider.bookmarkKey
        ) else {
            let previousDirectoryState =
                states[id]?.directoryState
            let previousDirectoryError =
                states[id]?.directoryAuthorizationErrorMessage
            let previousLoadError = states[id]?.errorMessage
            let wasLoading = states[id]?.isLoading == true
            let clearedData = clearProviderData(for: id)

            states[id]?.errorMessage = nil
            states[id]?.isLoading = false

            if previousDirectoryState == .needsReselection {
                // restore 失败已删除 bookmark；静默刷新不能把该状态
                // 和 provider-specific 错误降级为普通未选择。
                setDirectoryState(.needsReselection, for: id)
            } else {
                setDirectoryState(.notSelected, for: id)
                states[id]?.directoryAuthorizationErrorMessage = nil
            }

            logger.info(
                "\(provider.displayName) 尚未选择数据目录"
            )

            let shouldNotify = sendsLoadingNotifications
                || clearedData
                || wasLoading
                || previousLoadError != nil
                || previousDirectoryState
                    != states[id]?.directoryState
                || previousDirectoryError
                    != states[id]?
                        .directoryAuthorizationErrorMessage
            if shouldNotify {
                notifyStateChange(id)
            }
            return
        }

        guard let rootURL =
            bookmarkManager.restoreBookmarkAndAccess(
                forKey: provider.bookmarkKey
            )
        else {
            let message =
                Self.cannotAccessDataDirectoryMessage(
                    providerName: provider.displayName,
                    language: languageSettings.resolvedLanguage
                )
            let previousDirectoryState =
                states[id]?.directoryState
            let previousDirectoryError =
                states[id]?.directoryAuthorizationErrorMessage
            let previousLoadError = states[id]?.errorMessage
            let wasLoading = states[id]?.isLoading == true
            let clearedData = clearProviderData(for: id)

            setDirectoryState(.needsReselection, for: id)
            states[id]?.directoryAuthorizationErrorMessage =
                message
            states[id]?.errorMessage = nil
            states[id]?.isLoading = false

            logger.error(
                "\(provider.displayName) Bookmark 恢复失败"
            )

            let shouldNotify = sendsLoadingNotifications
                || clearedData
                || wasLoading
                || previousLoadError != nil
                || previousDirectoryState
                    != states[id]?.directoryState
                || previousDirectoryError != message
            if shouldNotify {
                notifyStateChange(id)
            }
            return
        }
        defer {
            bookmarkManager.stopAccessing(
                forKey: provider.bookmarkKey
            )
        }

        guard provider.validateDataRoot(rootURL) == .valid else {
            let message = AppStrings.text(
                .settingsDirectoryNoData,
                language: languageSettings.resolvedLanguage
            )
            let previousDirectoryState = states[id]?.directoryState
            let previousDirectoryError =
                states[id]?.directoryAuthorizationErrorMessage
            let previousLoadError = states[id]?.errorMessage
            let wasLoading = states[id]?.isLoading == true
            let clearedData = clearProviderData(for: id)

            // 目录可访问并不代表它属于当前 provider；缺少必要结构时
            // 提示用户重新选择，但不把“结构存在且暂时无记录”误判为选错。
            setDirectoryState(.needsReselection, for: id)
            states[id]?.directoryAuthorizationErrorMessage = message
            states[id]?.errorMessage = nil
            states[id]?.isLoading = false

            logger.error(
                "\(provider.displayName) 目录缺少预期数据结构，需要重新选择"
            )

            let shouldNotify = sendsLoadingNotifications
                || clearedData
                || wasLoading
                || previousLoadError != nil
                || previousDirectoryState != .needsReselection
                || previousDirectoryError != message
            if shouldNotify {
                notifyStateChange(id)
            }
            return
        }

        // bookmark 可恢复即表示目录仍已选择；parser 失败不能把
        // 该状态改回未选择或 needsReselection。
        let restoredDirectoryPresentationChanged =
            states[id]?.directoryState != .selected
            || states[id]?.needsAuthorization != false
            || states[id]?
                .directoryAuthorizationErrorMessage != nil
        setDirectoryState(.selected, for: id)
        states[id]?.directoryAuthorizationErrorMessage = nil

        let aggregator = self.aggregator
        let logger = self.logger
        let providerCopy = provider
        let previousFingerprint = entryFingerprints[id]
        let canReuseExistingStats =
            states[id]?.stats != nil
            && states[id]?.errorMessage == nil

        let result: Result<ProviderLoadResult, Error> =
            await Task.detached(priority: .userInitiated) {
                do {
                    let entries = try providerCopy.loadEntries(
                        from: rootURL
                    )
                    logger.info(
                        "\(providerCopy.displayName) 解析得 \(entries.count) 条记录"
                    )
                    let fingerprint =
                        UsageEntriesFingerprint.make(
                            from: entries
                        )
                    if canReuseExistingStats,
                       previousFingerprint == fingerprint {
                        return .success(
                            .unchanged(
                                entryCount: entries.count
                            )
                        )
                    }

                    let stats = aggregator.aggregate(entries)
                    return .success(
                        .loaded(
                            stats: stats,
                            entries: entries,
                            fingerprint: fingerprint,
                            entryCount: entries.count
                        )
                    )
                } catch {
                    return .failure(error)
                }
            }.value

        switch result {
        case .success(
            .loaded(
                let stats,
                let entries,
                let fingerprint,
                _
            )
        ):
            entryFingerprints[id] = fingerprint
            states[id]?.stats = stats
            states[id]?.entries = entries
            setDirectoryState(
                entries.isEmpty ? .selectedNoData : .selected,
                for: id
            )
            states[id]?.directoryAuthorizationErrorMessage =
                nil
            states[id]?.errorMessage = nil
            states[id]?.lastRefreshedAt = nowProvider()
            states[id]?.isLoading = false
            notifyStateChange(id)

        case .success(.unchanged(let entryCount)):
            let targetDirectoryState:
                ProviderDirectoryState =
                    entryCount == 0
                    ? .selectedNoData
                    : .selected
            let shouldNotify = sendsLoadingNotifications
                || restoredDirectoryPresentationChanged
                || states[id]?.directoryState
                    != targetDirectoryState
                || states[id]?
                    .directoryAuthorizationErrorMessage != nil
                || states[id]?.errorMessage != nil
                || states[id]?.isLoading == true

            setDirectoryState(
                targetDirectoryState,
                for: id
            )
            states[id]?.directoryAuthorizationErrorMessage =
                nil
            states[id]?.errorMessage = nil
            states[id]?.lastRefreshedAt = nowProvider()
            states[id]?.isLoading = false
            if shouldNotify {
                notifyStateChange(id)
            }

        case .failure(let error):
            let message = Self.loadFailedMessage(
                error: error,
                language: languageSettings.resolvedLanguage
            )
            let shouldNotify = sendsLoadingNotifications
                || restoredDirectoryPresentationChanged
                || states[id]?.errorMessage != message
                || states[id]?.isLoading == true

            // stats、entries 与 fingerprint 保留最后一次成功值；
            // bookmark 已成功恢复，所以目录状态保持 selected。
            setDirectoryState(.selected, for: id)
            states[id]?.directoryAuthorizationErrorMessage =
                nil
            states[id]?.errorMessage = message
            states[id]?.lastRefreshedAt = nowProvider()
            states[id]?.isLoading = false
            logger.error(
                "\(provider.displayName) 加载失败: \(error.localizedDescription)"
            )
            if shouldNotify {
                notifyStateChange(id)
            }
        }
    }

    /// 为指定 provider 显示数据目录选择面板。
    /// - Parameter id: 唯一 provider 标识。
    /// - Returns: bookmark 成功保存时返回 true；取消、保存失败、
    ///   provider 不存在或已有同 provider 目录操作时返回 false。
    @discardableResult
    func requestAuthorization(
        for id: ProviderID
    ) async -> Bool {
        guard let provider = provider(for: id) else {
            return false
        }
        guard !loadGate.isActive(id),
              states[id]?.isAuthorizing != true
        else {
            logger.info(
                "\(provider.displayName) 正在执行目录操作,跳过重复授权"
            )
            return false
        }

        states[id]?.isAuthorizing = true
        notifyStateChange(id)

        let result =
            await bookmarkManager.promptUserToSelectDirectory(
                forProvider: provider
            )

        switch result {
        case .cancelled:
            states[id]?.isAuthorizing = false
            logger.info(
                "\(provider.displayName) 用户取消目录选择"
            )
            notifyStateChange(id)
            return false

        case .failed:
            states[id]?.isAuthorizing = false
            states[id]?.directoryAuthorizationErrorMessage =
                Self.authorizationFailedMessage(
                    providerName: provider.displayName,
                    language: languageSettings.resolvedLanguage
                )
            logger.error(
                "\(provider.displayName) 目录授权保存失败"
            )
            notifyStateChange(id)
            return false

        case .authorized(_):
            states[id]?.isAuthorizing = false
            states[id]?.directoryAuthorizationErrorMessage =
                nil
            setDirectoryState(.selected, for: id)

            // 从 isAuthorizing 切到 load gate 的过程必须保持原子：
            // 此处之前没有 observer 回调，此处也不能插入 await。
            guard loadGate.enter(id) else {
                logger.error(
                    "\(provider.displayName) 授权成功后未能取得加载门禁"
                )
                notifyStateChange(id)
                return true
            }

            logger.info(
                "\(provider.displayName) 用户授权成功"
            )
            await performLoad(
                for: provider,
                mode: .interactive
            )
            return true
        }
    }

    private func provider(for id: ProviderID) -> (any UsageProvider)? {
        providers.first(where: { $0.id == id })
    }
}

private enum ProviderLoadResult: Sendable {
    case loaded(stats: AggregatedStats, entries: [ParsedUsageEntry], fingerprint: UsageEntriesFingerprint, entryCount: Int)
    case unchanged(entryCount: Int)
}

/// 跟踪正在刷新的 provider,避免定时刷新和手动刷新重叠触发重复全量解析。
struct ProviderLoadGate {
    private var activeProviderIDs: Set<ProviderID> = []

    mutating func enter(_ id: ProviderID) -> Bool {
        activeProviderIDs.insert(id).inserted
    }

    mutating func leave(_ id: ProviderID) {
        activeProviderIDs.remove(id)
    }

    func isActive(_ id: ProviderID) -> Bool {
        activeProviderIDs.contains(id)
    }
}

/// 用于判断 provider 本次解析结果是否与上次一致。
///
/// 指纹只在同一进程内比较,目标是跳过后台刷新中的重复聚合和 UI 通知;
/// 不作为持久化校验和使用。
struct UsageEntriesFingerprint: Equatable, Sendable {
    private let count: Int
    private let sum: Int
    private let xor: Int

    static func make(from entries: [ParsedUsageEntry]) -> UsageEntriesFingerprint {
        var sum = 0
        var xor = 0
        for entry in entries {
            var hasher = Hasher()
            hasher.combine(entry.dedupKey)
            hasher.combine(entry.sessionID)
            hasher.combine(entry.timestamp?.timeIntervalSince1970)
            hasher.combine(entry.model)
            hasher.combine(entry.cwd)
            hasher.combine(entry.agentId)
            hasher.combine(entry.isSubagent)
            hasher.combine(entry.isSidechain)
            hasher.combine(entry.hasSourceMessageID)
            hasher.combine(entry.provider)
            hasher.combine(entry.upstreamProviderID)
            hasher.combine(entry.upstreamCost)
            hasher.combine(entry.usage.inputTokens)
            hasher.combine(entry.usage.outputTokens)
            hasher.combine(entry.usage.cacheReadInputTokens)
            hasher.combine(entry.usage.totalCacheCreationTokens)
            hasher.combine(entry.usage.cacheCreate5mTokens)
            hasher.combine(entry.usage.cacheCreate1hTokens)
            hasher.combine(entry.usage.reasoningTokens)
            hasher.combine(entry.usage.serviceTier)
            hasher.combine(entry.usage.speed)

            let value = hasher.finalize()
            sum &+= value
            xor ^= value
        }
        return UsageEntriesFingerprint(count: entries.count, sum: sum, xor: xor)
    }
}
