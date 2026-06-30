import Foundation
import os.log

/// 聚合用量条目的抽象边界,让 ViewModel 可以在测试中替换为计数实现。
protocol UsageAggregating: Sendable {
    /// 将解析后的用量条目聚合为多维统计。
    /// - Parameter entries: 已去重的用量条目。
    /// - Returns: 供 UI 展示的聚合统计。
    func aggregate(_ entries: [ParsedUsageEntry]) -> AggregatedStats
}

/// Token 用量聚合器
/// 将 ParsedUsageEntry 列表按多维度聚合为 AggregatedStats
/// 参考 ccusage 的 daily/weekly/monthly/session 报告聚合逻辑
final class UsageAggregator: UsageAggregating {

    private let costResolver = UsageCostResolver()
    private let logger = Logger(subsystem: "com.xiaoao.TokenWatch", category: "UsageAggregator")

    /// 主入口：聚合所有条目
    /// - Parameter entries: 解析后的用量条目列表
    /// - Returns: 多维度聚合统计结果
    func aggregate(_ entries: [ParsedUsageEntry]) -> AggregatedStats {
        guard !entries.isEmpty else {
            logger.warning("无可用数据，返回空统计")
            return .zero
        }

        var uniqueFiles = Set<String>()

        logger.info("开始聚合：\(entries.count) 条记录")

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

        var overall = UsageSummaryAccumulator()
        var overallByModel: [String: UsageSummaryAccumulator] = [:]
        var byHour = UsageDimensionAccumulator()
        var byDay = UsageDimensionAccumulator()
        var byWeek = UsageDimensionAccumulator()
        var byMonth = UsageDimensionAccumulator()
        var bySession = UsageDimensionAccumulator()
        var byModel = UsageDimensionAccumulator()
        var byProject = UsageDimensionAccumulator()

        for entry in entries {
            uniqueFiles.insert("\(entry.sessionID)\(entry.agentId.map { "_\($0)" } ?? "")")

            let cost = costResolver.resolvedCost(for: entry)
            overall.add(entry, cost: cost)
            overallByModel[entry.model, default: UsageSummaryAccumulator()].add(entry, cost: cost)

            byHour.add(key: hourKey(from: entry.timestamp, calendar: calendar), entry: entry, cost: cost)
            byDay.add(key: dayKey(from: entry.timestamp, calendar: calendar), entry: entry, cost: cost)
            byWeek.add(key: weekKey(from: entry.timestamp, calendar: isoCalendar), entry: entry, cost: cost)
            byMonth.add(key: monthKey(from: entry.timestamp, calendar: calendar), entry: entry, cost: cost)
            bySession.add(key: entry.sessionID, entry: entry, cost: cost)
            byModel.add(key: entry.model, entry: entry, cost: cost)
            byProject.add(key: entry.cwd ?? "unknown", entry: entry, cost: cost)
        }
        logger.info("聚合完成：\(entries.count) 条记录，\(uniqueFiles.count) 个数据源")

        return AggregatedStats(
            overall: overall.makeSummary(modelBreakdown: overallByModel.makeSummaries()),
            byHour: byHour.makeSummaries(),
            byDay: byDay.makeSummaries(),
            byWeek: byWeek.makeSummaries(),
            byMonth: byMonth.makeSummaries(),
            bySession: bySession.makeSummaries(),
            byModel: byModel.makeSummaries(),
            byProject: byProject.makeSummaries(),
            dataSourceCount: uniqueFiles.count
        )
    }

    // MARK: - Private Aggregation

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

private struct UsageSummaryAccumulator {
    private(set) var inputTokens = 0
    private(set) var outputTokens = 0
    private(set) var cacheReadTokens = 0
    private(set) var cacheCreationTokens = 0
    private(set) var reasoningTokens = 0
    private(set) var cost = 0.0
    private(set) var entryCount = 0

    mutating func add(_ entry: ParsedUsageEntry, cost entryCost: Double) {
        inputTokens += entry.usage.inputTokens
        outputTokens += entry.usage.outputTokens
        cacheReadTokens += entry.usage.cacheReadInputTokens
        // cache_creation_input_tokens 与 ephemeral_5m/1h 是总分关系
        // 由 TokenUsage.totalCacheCreationTokens 统一处理，避免 double-count
        cacheCreationTokens += entry.usage.totalCacheCreationTokens
        reasoningTokens += entry.usage.reasoningTokens
        cost += entryCost
        entryCount += 1
    }

    func makeSummary(modelBreakdown: [String: UsageSummary] = [:]) -> UsageSummary {
        UsageSummary(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheReadTokens,
            cacheCreationTokens: cacheCreationTokens,
            reasoningTokens: reasoningTokens,
            totalTokens: inputTokens + outputTokens + cacheReadTokens + cacheCreationTokens + reasoningTokens,
            cost: cost,
            entryCount: entryCount,
            modelBreakdown: modelBreakdown
        )
    }
}

private struct UsageDimensionAccumulator {
    private var totals: [String: UsageSummaryAccumulator] = [:]
    private var modelTotals: [String: [String: UsageSummaryAccumulator]] = [:]

    mutating func add(key: String, entry: ParsedUsageEntry, cost: Double) {
        totals[key, default: UsageSummaryAccumulator()].add(entry, cost: cost)
        modelTotals[key, default: [:]][entry.model, default: UsageSummaryAccumulator()].add(entry, cost: cost)
    }

    func makeSummaries() -> [String: UsageSummary] {
        var summaries: [String: UsageSummary] = [:]
        summaries.reserveCapacity(totals.count)
        for (key, total) in totals {
            summaries[key] = total.makeSummary(
                modelBreakdown: modelTotals[key]?.makeSummaries() ?? [:]
            )
        }
        return summaries
    }
}

private extension Dictionary where Key == String, Value == UsageSummaryAccumulator {
    func makeSummaries() -> [String: UsageSummary] {
        mapValues { $0.makeSummary() }
    }
}
