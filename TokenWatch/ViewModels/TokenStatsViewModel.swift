import Foundation
import os.log

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

    nonisolated static func cannotAccessHomeMessage(language: AppLanguage) -> String {
        AppStrings.text(.errorCannotAccessHome, language: language)
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

    /// 加载指定 provider 的统计
    func loadStats(for id: ProviderID, mode: LoadMode = .interactive) async {
        guard let provider = provider(for: id) else { return }
        guard loadGate.enter(id) else {
            logger.info("\(provider.displayName) 已在刷新中,跳过重复请求")
            return
        }
        defer { loadGate.leave(id) }

        let sendsLoadingNotifications = (mode == .interactive)
        if sendsLoadingNotifications {
            states[id]?.isLoading = true
            states[id]?.errorMessage = nil
            notifyStateChange(id)
        }

        // Step 1: 检查 Bookmark
        if !bookmarkManager.hasBookmark(forKey: provider.bookmarkKey) {
            let shouldNotify = states[id]?.needsAuthorization != true
                || states[id]?.isLoading == true
                || states[id]?.errorMessage != nil
            states[id]?.needsAuthorization = true
            states[id]?.isLoading = false
            states[id]?.errorMessage = nil
            logger.info("\(provider.displayName) 未授权,需要用户操作")
            if sendsLoadingNotifications || shouldNotify {
                notifyStateChange(id)
            }
            return
        }

        // Step 2: 恢复 Bookmark
        guard let rootURL = bookmarkManager.restoreBookmarkAndAccess(forKey: provider.bookmarkKey) else {
            let message = Self.cannotAccessHomeMessage(language: languageSettings.resolvedLanguage)
            let shouldNotify = states[id]?.errorMessage != message
                || states[id]?.needsAuthorization != true
                || states[id]?.isLoading == true
            states[id]?.errorMessage = message
            states[id]?.needsAuthorization = true
            states[id]?.isLoading = false
            logger.error("\(provider.displayName) Bookmark 恢复失败")
            if sendsLoadingNotifications || shouldNotify {
                notifyStateChange(id)
            }
            return
        }
        defer { bookmarkManager.stopAccessing(forKey: provider.bookmarkKey) }
        states[id]?.needsAuthorization = false

        // Step 3-5: 后台扫 + 解析 + 聚合
        let aggregator = self.aggregator
        let logger = self.logger
        let providerCopy = provider
        let previousFingerprint = entryFingerprints[id]
        let canReuseExistingStats = states[id]?.stats != nil && states[id]?.errorMessage == nil

        let result: Result<ProviderLoadResult, Error> = await Task.detached(priority: .userInitiated) {
            do {
                let entries = try providerCopy.loadEntries(from: rootURL)
                logger.info("\(providerCopy.displayName) 解析得 \(entries.count) 条记录")
                let fingerprint = UsageEntriesFingerprint.make(from: entries)
                if canReuseExistingStats, previousFingerprint == fingerprint {
                    return .success(.unchanged(entryCount: entries.count))
                }
                let stats = aggregator.aggregate(entries)
                return .success(.loaded(stats: stats, entries: entries, fingerprint: fingerprint, entryCount: entries.count))
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success(.loaded(let stats, let entries, let fingerprint, _)):
            entryFingerprints[id] = fingerprint
            states[id]?.stats = stats
            states[id]?.entries = entries
            states[id]?.needsAuthorization = false
            states[id]?.errorMessage = nil
            states[id]?.lastRefreshedAt = nowProvider()
            states[id]?.isLoading = false
            notifyStateChange(id)
        case .success(.unchanged):
            states[id]?.lastRefreshedAt = nowProvider()
            if sendsLoadingNotifications {
                states[id]?.isLoading = false
                notifyStateChange(id)
            }
        case .failure(let error):
            let message = Self.loadFailedMessage(
                error: error,
                language: languageSettings.resolvedLanguage
            )
            let shouldNotify = states[id]?.errorMessage != message || states[id]?.isLoading == true
            states[id]?.errorMessage = message
            states[id]?.lastRefreshedAt = nowProvider()
            logger.error("\(provider.displayName) 加载失败: \(error.localizedDescription)")
            states[id]?.isLoading = false
            if sendsLoadingNotifications || shouldNotify {
                notifyStateChange(id)
            }
        }
    }

    /// 将所有共享同一 bookmark key 的 provider 标记为已授权并通知 UI。
    /// 用户目录授权是跨 provider 共享的,所以在任一 Tab 授权成功后其它 Tab 不应继续显示授权按钮。
    func markProvidersAuthorized(sharingBookmarkWith provider: any UsageProvider) {
        for candidate in providers where candidate.bookmarkKey == provider.bookmarkKey {
            states[candidate.id]?.needsAuthorization = false
            states[candidate.id]?.errorMessage = nil
            notifyStateChange(candidate.id)
        }
    }

    /// 触发指定 provider 的授权流程
    /// - Returns: 用户完成授权并保存 bookmark 时返回 true;取消或 provider 不存在时返回 false
    @discardableResult
    func requestAuthorization(for id: ProviderID) async -> Bool {
        guard let provider = provider(for: id) else { return false }
        switch await bookmarkManager.promptUserToSelectDirectory(forProvider: provider) {
        case .authorized:
            markProvidersAuthorized(sharingBookmarkWith: provider)
            logger.info("\(provider.displayName) 用户授权成功")
            await loadAllStats()
            return true
        case .cancelled:
            logger.info("\(provider.displayName) 用户取消授权")
            return false
        case .failed:
            logger.error("\(provider.displayName) 目录授权保存失败")
            return false
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
