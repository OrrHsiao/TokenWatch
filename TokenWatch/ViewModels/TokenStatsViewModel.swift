import Foundation
import os.log

/// 多 provider 用量统计 ViewModel
///
/// 每个 provider 维护独立 ProviderState(stats / loading / error / 授权状态),
/// 各 Tab 之间互不影响。重 IO + 解析在后台 actor 上执行,保证 UI 不卡顿。
@MainActor
final class TokenStatsViewModel: Sendable {

    /// 单 provider 的 UI 状态
    struct ProviderState: Sendable {
        var stats: AggregatedStats?
        var isLoading = false
        var errorMessage: String?
        var needsAuthorization = true
    }

    /// 当前所有 provider 的状态(只读)
    private(set) var states: [ProviderID: ProviderState] = [:]

    /// observer 注册凭证;移除 observer 时使用
    struct ObservationToken: Hashable, Sendable {
        let id: UUID
    }

    /// 已注册的 observer。key 为 token,value 为 main-actor 隔离的回调
    private var observers: [ObservationToken: @MainActor (ProviderID) -> Void] = [:]

    private let bookmarkManager = SecurityScopedBookmarkManager.shared
    private let aggregator = UsageAggregator()
    private let logger = Logger(subsystem: "com.xiaoao.TokenWatch", category: "TokenStatsViewModel")

    init() {
        for provider in ProviderRegistry.allProviders {
            states[provider.id] = ProviderState()
        }
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
    func loadAllStats() async {
        await withTaskGroup(of: Void.self) { group in
            for provider in ProviderRegistry.allProviders {
                let id = provider.id
                group.addTask {
                    await self.loadStats(for: id)
                }
            }
        }
    }

    /// 加载指定 provider 的统计
    func loadStats(for id: ProviderID) async {
        guard let provider = ProviderRegistry.provider(for: id) else { return }

        states[id]?.isLoading = true
        states[id]?.errorMessage = nil
        notifyStateChange(id)

        // Step 1: 检查 Bookmark
        if !bookmarkManager.hasBookmark(forKey: provider.bookmarkKey) {
            states[id]?.needsAuthorization = true
            states[id]?.isLoading = false
            logger.info("\(provider.displayName) 未授权,需要用户操作")
            notifyStateChange(id)
            return
        }

        // Step 2: 恢复 Bookmark
        guard let rootURL = bookmarkManager.restoreBookmarkAndAccess(forKey: provider.bookmarkKey) else {
            states[id]?.errorMessage = "无法访问 \(provider.defaultDirectoryPath),请重新授权"
            states[id]?.needsAuthorization = true
            states[id]?.isLoading = false
            logger.error("\(provider.displayName) Bookmark 恢复失败")
            notifyStateChange(id)
            return
        }
        defer { bookmarkManager.stopAccessing(forKey: provider.bookmarkKey) }

        // Step 3-5: 后台扫 + 解析 + 聚合
        let aggregator = self.aggregator
        let logger = self.logger
        let providerCopy = provider

        let result: Result<AggregatedStats, Error> = await Task.detached(priority: .userInitiated) {
            do {
                let entries = try providerCopy.loadEntries(from: rootURL)
                logger.info("\(providerCopy.displayName) 解析得 \(entries.count) 条记录")
                let stats = aggregator.aggregate(entries)
                return .success(stats)
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success(let stats):
            states[id]?.stats = stats
            states[id]?.needsAuthorization = false
            states[id]?.errorMessage = nil
        case .failure(let error):
            states[id]?.errorMessage = "数据加载失败: \(error.localizedDescription)"
            logger.error("\(provider.displayName) 加载失败: \(error.localizedDescription)")
        }

        states[id]?.isLoading = false
        notifyStateChange(id)
    }

    /// 触发指定 provider 的授权流程
    func requestAuthorization(for id: ProviderID) async {
        guard let provider = ProviderRegistry.provider(for: id) else { return }
        if let _ = await bookmarkManager.promptUserToSelectDirectory(forProvider: provider) {
            states[id]?.needsAuthorization = false
            logger.info("\(provider.displayName) 用户授权成功")
            await loadStats(for: id)
        } else {
            logger.info("\(provider.displayName) 用户取消授权")
        }
    }
}
