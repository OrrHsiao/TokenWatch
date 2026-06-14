import Foundation
import os.log

/// 为 UI 准备统计数据的 ViewModel
/// 协调 Bookmark → 扫描 → 解析 → 聚合 全流程
///
/// 主线程仅负责：状态读写、Bookmark 生命周期、UI 通知
/// 重 IO 与 JSON 解析在后台 actor 上执行，避免卡 UI
@MainActor
final class TokenStatsViewModel: Sendable {

    private(set) var stats: AggregatedStats?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var needsAuthorization = true

    private let bookmarkManager = SecurityScopedBookmarkManager.shared
    private let scanner = JSONLScanner()
    private let parser = JSONLParser()
    private let aggregator = UsageAggregator()
    private let logger = Logger(subsystem: "com.xiaoao.TokenWatch", category: "TokenStatsViewModel")

    /// 尝试加载并计算统计数据
    /// 完整流程：Bookmark 恢复 → 扫描 JSONL → 解析 usage → 聚合统计
    func loadStats() async {
        isLoading = true
        errorMessage = nil

        // Step 1: 检查是否有已存储的 Bookmark
        if !bookmarkManager.hasBookmark {
            needsAuthorization = true
            isLoading = false
            logger.info("未找到已存储的 Bookmark，需要用户授权")
            return
        }

        // Step 2: 恢复 Bookmark 访问
        guard let claudeDir = bookmarkManager.restoreBookmarkAndAccess() else {
            errorMessage = "无法访问 ~/.claude 目录，请重新授权"
            needsAuthorization = true
            isLoading = false
            logger.error("Bookmark 恢复失败")
            return
        }

        defer { bookmarkManager.stopAccessing() }

        // Step 3-5: 重 IO + 解析 + 聚合 → 后台执行
        // scanner / parser / aggregator 均为 Sendable + nonisolated 方法，可安全跨 actor
        let scanner = self.scanner
        let parser = self.parser
        let aggregator = self.aggregator
        let logger = self.logger

        let result: Result<AggregatedStats, Error> = await Task.detached(priority: .userInitiated) {
            do {
                let files = try scanner.scanAllJSONLFiles(in: claudeDir)
                logger.info("扫描到 \(files.count) 个 JSONL 文件")

                let entries = try parser.parseAllFiles(files, claudeDataRoot: claudeDir)
                logger.info("解析得到 \(entries.count) 条用量记录")

                let stats = aggregator.aggregate(entries)
                logger.info("统计聚合完成")
                return .success(stats)
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success(let stats):
            self.stats = stats
            self.needsAuthorization = false
            self.errorMessage = nil
        case .failure(let error):
            self.errorMessage = "数据加载失败: \(error.localizedDescription)"
            logger.error("加载失败: \(error.localizedDescription)")
        }

        isLoading = false
    }

    /// 触发授权流程
    /// 弹出 NSOpenPanel 让用户选择 ~/.claude 目录
    func requestAuthorization() async {
        if let _ = await bookmarkManager.promptUserToSelectClaudeDirectory() {
            needsAuthorization = false
            logger.info("用户授权成功")
            await loadStats()
        } else {
            logger.info("用户取消授权")
        }
    }
}
