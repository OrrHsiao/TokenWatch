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
    nonisolated func aggregate(_ entries: [ParsedUsageEntry]) -> AggregatedStats {
        guard !entries.isEmpty else {
            logger.warning("无可用数据，返回空统计")
            return .zero
        }

        // 计算 unique 数据源数（session + agent 组合）
        let uniqueFiles = Set(entries.map { entry in
            "\(entry.sessionID)\(entry.agentId.map { "_\($0)" } ?? "")"
        })

        logger.info("开始聚合：\(entries.count) 条记录，\(uniqueFiles.count) 个数据源")

        return AggregatedStats(
            overall: aggregateEntries(entries),
            byDay: groupAndAggregate(entries) { dateKey(from: $0.timestamp, format: "yyyy-MM-dd") },
            byWeek: groupAndAggregate(entries) { weekKey(from: $0.timestamp) },
            byMonth: groupAndAggregate(entries) { dateKey(from: $0.timestamp, format: "yyyy-MM") },
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
                // cacheCreationInputTokens + ephemeral 分解
                mCacheCreation += entry.usage.cacheCreationInputTokens
                    + entry.usage.cacheCreation.ephemeral5mInputTokens
                    + entry.usage.cacheCreation.ephemeral1hInputTokens

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

    /// 生成日期 key
    private func dateKey(from date: Date?, format: String) -> String {
        guard let date = date else { return "unknown" }
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

    /// 生成 ISO 8601 周 key，格式: "2026-W24"
    private func weekKey(from date: Date?) -> String {
        guard let date = date else { return "unknown" }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        guard let year = components.yearForWeekOfYear, let week = components.weekOfYear else {
            return "unknown"
        }
        return String(format: "%d-W%02d", year, week)
    }
}
