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

    /// 状态变更回调,UI 层据此刷新指定 Tab
    var onStateChange: (@MainActor (ProviderID) -> Void)?

    private let bookmarkManager = SecurityScopedBookmarkManager.shared
    private let aggregator = UsageAggregator()
    private let logger = Logger(subsystem: "com.xiaoao.TokenWatch", category: "TokenStatsViewModel")

    init() {
        for provider in ProviderRegistry.allProviders {
            states[provider.id] = ProviderState()
        }
    }

    /// 通知 UI 指定 provider 状态已变更
    private func notifyStateChange(_ id: ProviderID) {
        onStateChange?(id)
    }

    /// 启动时并发触发所有 provider 的 loadStats
    /// 设计原因:Swift 6 region-based isolation checker 在 `withTaskGroup` + `@MainActor` 闭包上有 bug,
    /// 故改用裸 Task 并发触发,各 task 共享主 actor 串行,但 IO/解析重活在 detached task 内执行
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
