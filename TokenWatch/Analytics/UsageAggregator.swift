import Foundation
import os.log

/// Token 用量聚合器
/// 将 ParsedUsageEntry 列表按多维度聚合为 AggregatedStats
/// 参考 ccusage 的 daily/weekly/monthly/session 报告聚合逻辑
final class UsageAggregator: Sendable {

    private let pricingEngine = PricingEngine()
    private let logger = Logger(subsystem: "com.xiaoao.TokenWatch", category: "UsageAggregator")

    /// 主入口：聚合所有条目
    /// - Parameter entries: 解析后的用量条目列表
    /// - Returns: 多维度聚合统计结果
    func aggregate(_ entries: [ParsedUsageEntry]) -> AggregatedStats {
        guard !entries.isEmpty else {
            logger.warning("无可用数据，返回空统计")
            return .zero
        }

        // 计算 unique 数据源数（session + agent 组合）
        let uniqueFiles = Set(entries.map { entry in
            "\(entry.sessionID)\(entry.agentId.map { "_\($0)" } ?? "")"
        })

        logger.info("开始聚合：\(entries.count) 条记录，\(uniqueFiles.count) 个数据源")

        // 性能优化：分组前预先复用一份 Calendar 实例
        // 避免每条 entry 在 keySelector 内重复访问 Calendar.current 的 thread-local 拷贝
        let calendar = Calendar.current

        return AggregatedStats(
            overall: aggregateEntries(entries),
            byDay: groupAndAggregate(entries) { dayKey(from: $0.timestamp, calendar: calendar) },
            byWeek: groupAndAggregate(entries) { weekKey(from: $0.timestamp, calendar: calendar) },
            byMonth: groupAndAggregate(entries) { monthKey(from: $0.timestamp, calendar: calendar) },
            bySession: groupAndAggregate(entries) { $0.sessionID },
            byModel: groupAndAggregate(entries) { $0.model },
            byProject: groupAndAggregate(entries) { $0.cwd ?? "unknown" },
            dataSourceCount: uniqueFiles.count
        )
    }

    // MARK: - Private Aggregation

    /// 聚合一组条目为 UsageSummary，内含按模型细分
    private func aggregateEntries(_ entries: [ParsedUsageEntry]) -> UsageSummary {
        var totalInput = 0, totalOutput = 0, totalCacheRead = 0, totalCacheCreation = 0
        var totalCost = 0.0
        var modelBreakdown: [String: UsageSummary] = [:]

        let byModel = Dictionary(grouping: entries, by: { $0.model })

        for (model, modelEntries) in byModel {
            var mInput = 0, mOutput = 0, mCacheRead = 0, mCacheCreation = 0
            var mCost = 0.0

            for entry in modelEntries {
                mInput += entry.usage.inputTokens
                mOutput += entry.usage.outputTokens
                mCacheRead += entry.usage.cacheReadInputTokens
                // cache_creation_input_tokens 与 ephemeral_5m/1h 是总分关系
                // 由 TokenUsage.totalCacheCreationTokens 统一处理，避免 double-count
                mCacheCreation += entry.usage.totalCacheCreationTokens

                let (cost, _) = pricingEngine.calculateCost(
                    usage: entry.usage,
                    model: entry.model
                )
                mCost += cost
            }

            totalInput += mInput
            totalOutput += mOutput
            totalCacheRead += mCacheRead
            totalCacheCreation += mCacheCreation
            totalCost += mCost

            modelBreakdown[model] = UsageSummary(
                inputTokens: mInput,
                outputTokens: mOutput,
                cacheReadTokens: mCacheRead,
                cacheCreationTokens: mCacheCreation,
                totalTokens: mInput + mOutput + mCacheRead + mCacheCreation,
                cost: mCost,
                entryCount: modelEntries.count,
                modelBreakdown: [:]
            )
        }

        return UsageSummary(
            inputTokens: totalInput,
            outputTokens: totalOutput,
            cacheReadTokens: totalCacheRead,
            cacheCreationTokens: totalCacheCreation,
            totalTokens: totalInput + totalOutput + totalCacheRead + totalCacheCreation,
            cost: totalCost,
            entryCount: entries.count,
            modelBreakdown: modelBreakdown
        )
    }

    /// 按 key 分组后聚合
    private func groupAndAggregate(
        _ entries: [ParsedUsageEntry],
        keySelector: (ParsedUsageEntry) -> String
    ) -> [String: UsageSummary] {
        let grouped = Dictionary(grouping: entries, by: keySelector)
        return grouped.mapValues { aggregateEntries($0) }
    }

    // MARK: - Date Helpers

    /// 生成日 key，格式: "yyyy-MM-dd"（与原 DateFormatter 行为一致）
    /// 设计原因：原实现在每条 entry 上 `new DateFormatter()` 有显著的分配/初始化开销。
    /// 改用 Calendar.dateComponents + String(format:) 拼接，零并发隐患（DateFormatter 非线程安全），
    /// 且 Calendar 默认使用当前 TimeZone（与原 `formatter.timeZone = TimeZone.current` 等价）。
    private func dayKey(from date: Date?, calendar: Calendar) -> String {
        guard let date = date else { return "unknown" }
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return "unknown"
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// 生成月 key，格式: "yyyy-MM"（与原 DateFormatter 行为一致）
    private func monthKey(from date: Date?, calendar: Calendar) -> String {
        guard let date = date else { return "unknown" }
        let components = calendar.dateComponents([.year, .month], from: date)
        guard let year = components.year, let month = components.month else {
            return "unknown"
        }
        return String(format: "%04d-%02d", year, month)
    }

    /// 生成 ISO 8601 周 key，格式: "2026-W24"
    private func weekKey(from date: Date?, calendar: Calendar) -> String {
        guard let date = date else { return "unknown" }
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        guard let year = components.yearForWeekOfYear, let week = components.weekOfYear else {
            return "unknown"
        }
        return String(format: "%d-W%02d", year, week)
    }
}
