import Foundation

/// 单次用量聚合结果
/// 参考 ccusage 的 UsageSummary 设计，支持按模型和项目细分
struct UsageSummary: Sendable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheCreationTokens: Int
    let reasoningTokens: Int
    let totalTokens: Int
    let cost: Double             // USD
    let entryCount: Int          // 包含的 assistant 记录数
    let modelBreakdown: [String: UsageSummary]  // 按模型细分
    let projectBreakdown: [String: UsageSummary]  // 按项目细分

    init(
        inputTokens: Int,
        outputTokens: Int,
        cacheReadTokens: Int,
        cacheCreationTokens: Int,
        reasoningTokens: Int,
        totalTokens: Int,
        cost: Double,
        entryCount: Int,
        modelBreakdown: [String: UsageSummary],
        projectBreakdown: [String: UsageSummary] = [:]
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.reasoningTokens = reasoningTokens
        self.totalTokens = totalTokens
        self.cost = cost
        self.entryCount = entryCount
        self.modelBreakdown = modelBreakdown
        self.projectBreakdown = projectBreakdown
    }

    /// 创建空的聚合结果
    static var zero: UsageSummary {
        UsageSummary(
            inputTokens: 0, outputTokens: 0,
            cacheReadTokens: 0, cacheCreationTokens: 0,
            reasoningTokens: 0,
            totalTokens: 0, cost: 0, entryCount: 0,
            modelBreakdown: [:],
            projectBreakdown: [:]
        )
    }
}

/// 按多维度聚合的完整统计结果
/// 参考 ccusage 的 daily/weekly/monthly/session 报告结构
struct AggregatedStats: Sendable {
    let overall: UsageSummary
    let byHour: [String: UsageSummary]      // key: "2026-06-13T14"
    let byDay: [String: UsageSummary]       // key: "2026-06-13"
    let byWeek: [String: UsageSummary]      // key: "2026-W24"
    let byMonth: [String: UsageSummary]     // key: "2026-06"
    let bySession: [String: UsageSummary]   // key: sessionID
    let byModel: [String: UsageSummary]     // key: model name
    let byProject: [String: UsageSummary]   // key: cwd / project path
    let dataSourceCount: Int                // 扫描的唯一数据源数

    /// 创建空的统计结果
    static var zero: AggregatedStats {
        AggregatedStats(
            overall: .zero,
            byHour: [:], byDay: [:], byWeek: [:], byMonth: [:],
            bySession: [:], byModel: [:], byProject: [:],
            dataSourceCount: 0
        )
    }
}
