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

        // 周聚合必须用 ISO 8601 周(周一起点 + minimumDaysInFirstWeek=4)
        // 设计原因:Calendar.current 在 zh_CN 等 locale 下 firstWeekday=1(周日)且
        // minimumDaysInFirstWeek=5,会与 ccusage / Rust chrono 输出的周编号偏移 1,
        // 同时把 (周一) 错误划入上一周(周日起点),导致与 ccusage weekly 对账时数字漂移。
        // 改用专用 ISO 日历仅作 week 分组,day/month 仍沿用本地 Calendar。
        var isoCalendar = Calendar(identifier: .iso8601)
        isoCalendar.timeZone = calendar.timeZone
        isoCalendar.firstWeekday = 2
        isoCalendar.minimumDaysInFirstWeek = 4

        return AggregatedStats(
            overall: aggregateEntries(entries),
            byHour: groupAndAggregate(entries) { hourKey(from: $0.timestamp, calendar: calendar) },
            byDay: groupAndAggregate(entries) { dayKey(from: $0.timestamp, calendar: calendar) },
            byWeek: groupAndAggregate(entries) { weekKey(from: $0.timestamp, calendar: isoCalendar) },
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
    /// 调用方需传入 ISO 8601 日历(`firstWeekday=2`, `minimumDaysInFirstWeek=4`),
    /// 否则 yearForWeekOfYear/weekOfYear 会按 locale 的本地周规则输出,与 ccusage 不一致
    private func weekKey(from date: Date?, calendar: Calendar) -> String {
        guard let date = date else { return "unknown" }
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        guard let year = components.yearForWeekOfYear, let week = components.weekOfYear else {
            return "unknown"
        }
        return String(format: "%d-W%02d", year, week)
    }

    /// 生成小时 key,格式: "yyyy-MM-ddTHH"(如 "2026-06-13T14")
    /// 设计原因:与 dayKey 共用同一份本地 Calendar,保证 byHour 的所有 key 都能与
    /// byDay 的 key 通过 prefix("yyyy-MM-dd") 完全匹配,UI 取数零歧义。
    /// 与 ISO 8601 datetime 同款分隔符 'T',字符串字典序即时间序。
    private func hourKey(from date: Date?, calendar: Calendar) -> String {
        guard let date = date else { return "unknown" }
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day,
              let hour = components.hour else {
            return "unknown"
        }
        return String(format: "%04d-%02d-%02dT%02d", year, month, day, hour)
    }
}
