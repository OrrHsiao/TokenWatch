import Foundation

/// 最近会话明细页的完整数据快照,供 UI 直接渲染。
struct RecentSessionDetailsSnapshot: Sendable, Equatable {
    let rows: [RecentSessionRow]
    let totalSessionCount: Int
    let totalTokens: Int
    let totalCost: Double
    let loadedProviderCount: Int
    let loadingProviderCount: Int
    let unauthorizedProviderCount: Int
    let errorMessages: [String]
}

/// 最近会话明细中的单行数据。一个 provider + sessionID 对应一行。
struct RecentSessionRow: Sendable, Equatable, Identifiable {
    let id: String
    let provider: ProviderID
    let sessionID: String
    let projectPath: String?
    let primaryModel: String
    let additionalModelCount: Int
    let firstActiveAt: Date?
    let lastActiveAt: Date?
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheCreationTokens: Int
    let reasoningTokens: Int
    let totalTokens: Int
    let cost: Double
    let entryCount: Int
    let modelBreakdown: [String: UsageSummary]
    let upstreamProviderIDs: [String]
    let isSubagentIncluded: Bool

    static func == (lhs: RecentSessionRow, rhs: RecentSessionRow) -> Bool {
        lhs.id == rhs.id
            && lhs.provider == rhs.provider
            && lhs.sessionID == rhs.sessionID
            && lhs.projectPath == rhs.projectPath
            && lhs.primaryModel == rhs.primaryModel
            && lhs.additionalModelCount == rhs.additionalModelCount
            && lhs.firstActiveAt == rhs.firstActiveAt
            && lhs.lastActiveAt == rhs.lastActiveAt
            && lhs.inputTokens == rhs.inputTokens
            && lhs.outputTokens == rhs.outputTokens
            && lhs.cacheReadTokens == rhs.cacheReadTokens
            && lhs.cacheCreationTokens == rhs.cacheCreationTokens
            && lhs.reasoningTokens == rhs.reasoningTokens
            && lhs.totalTokens == rhs.totalTokens
            && lhs.cost == rhs.cost
            && lhs.entryCount == rhs.entryCount
            && summariesEqual(lhs.modelBreakdown, rhs.modelBreakdown)
            && lhs.upstreamProviderIDs == rhs.upstreamProviderIDs
            && lhs.isSubagentIncluded == rhs.isSubagentIncluded
    }

    private static func summariesEqual(
        _ lhs: [String: UsageSummary],
        _ rhs: [String: UsageSummary]
    ) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (key, lhsSummary) in lhs {
            guard let rhsSummary = rhs[key],
                  summaryEqual(lhsSummary, rhsSummary) else {
                return false
            }
        }
        return true
    }

    private static func summaryEqual(_ lhs: UsageSummary, _ rhs: UsageSummary) -> Bool {
        lhs.inputTokens == rhs.inputTokens
            && lhs.outputTokens == rhs.outputTokens
            && lhs.cacheReadTokens == rhs.cacheReadTokens
            && lhs.cacheCreationTokens == rhs.cacheCreationTokens
            && lhs.reasoningTokens == rhs.reasoningTokens
            && lhs.totalTokens == rhs.totalTokens
            && lhs.cost == rhs.cost
            && lhs.entryCount == rhs.entryCount
            && summariesEqual(lhs.modelBreakdown, rhs.modelBreakdown)
    }
}

/// 将多 provider 状态构建为最近会话明细快照。
enum RecentSessionDetailsBuilder {
    /// 汇总指定时间窗口内的 entries,按 provider + sessionID 生成最近会话行。
    /// - Parameters:
    ///   - states: 各 provider 的统计状态;只有 `entries` 中带 timestamp 且落在窗口内的条目参与明细聚合。
    ///   - period: 统计窗口。
    ///   - now: 当前时间,用于确定窗口边界。
    ///   - calendar: 调用方指定的日历配置,用于稳定测试和本地日期计算。
    /// - Returns: 可直接渲染的最近会话明细快照。
    static func build(
        states: [ProviderID: TokenStatsViewModel.ProviderState],
        period: UsageStatsPeriod,
        now: Date,
        calendar: Calendar
    ) -> RecentSessionDetailsSnapshot {
        build(states: states) { timestamp in
            period.containsEntryDate(timestamp, now: now, calendar: calendar)
        }
    }

    /// 汇总所有可用 entries,按 provider + sessionID 生成最近会话行。
    /// - Parameter states: 各 provider 的统计状态;只有带 timestamp 的明细条目参与聚合。
    /// - Returns: 可直接渲染的最近会话明细快照。
    static func buildAll(states: [ProviderID: TokenStatsViewModel.ProviderState]) -> RecentSessionDetailsSnapshot {
        build(states: states) { _ in true }
    }

    private static func build(
        states: [ProviderID: TokenStatsViewModel.ProviderState],
        includesEntryAt includesEntry: (Date) -> Bool
    ) -> RecentSessionDetailsSnapshot {
        let costResolver = UsageCostResolver()
        var accumulators: [RecentSessionKey: RecentSessionAccumulator] = [:]
        var loadedProviderCount = 0
        var loadingProviderCount = 0
        var unauthorizedProviderCount = 0
        var errorMessages: [String] = []

        for (providerID, state) in states {
            if state.isLoading {
                loadingProviderCount += 1
            }
            if state.needsAuthorization {
                unauthorizedProviderCount += 1
            }
            if let errorMessage = state.errorMessage, !errorMessage.isEmpty {
                errorMessages.append(errorMessage)
            }
            if state.stats != nil || state.entries != nil {
                loadedProviderCount += 1
            }

            for entry in state.entries ?? [] {
                guard let timestamp = entry.timestamp,
                      includesEntry(timestamp) else {
                    continue
                }

                let key = RecentSessionKey(provider: providerID, sessionID: entry.sessionID)
                let cost = costResolver.resolvedCost(for: entry)
                var accumulator = accumulators[key]
                    ?? RecentSessionAccumulator(provider: providerID, sessionID: entry.sessionID)
                accumulator.add(entry, timestamp: timestamp, cost: cost)
                accumulators[key] = accumulator
            }
        }

        let rows = accumulators.values
            .map { $0.makeRow() }
            .sorted { lhs, rhs in
                let lhsLastActiveAt = lhs.lastActiveAt ?? .distantPast
                let rhsLastActiveAt = rhs.lastActiveAt ?? .distantPast
                if lhsLastActiveAt != rhsLastActiveAt {
                    return lhsLastActiveAt > rhsLastActiveAt
                }
                if lhs.totalTokens != rhs.totalTokens {
                    return lhs.totalTokens > rhs.totalTokens
                }
                if lhs.provider.rawValue != rhs.provider.rawValue {
                    return lhs.provider.rawValue < rhs.provider.rawValue
                }
                return lhs.sessionID < rhs.sessionID
            }

        return RecentSessionDetailsSnapshot(
            rows: rows,
            totalSessionCount: rows.count,
            totalTokens: rows.reduce(0) { $0.addingSaturated($1.totalTokens) },
            totalCost: rows.reduce(0) { $0 + $1.cost },
            loadedProviderCount: loadedProviderCount,
            loadingProviderCount: loadingProviderCount,
            unauthorizedProviderCount: unauthorizedProviderCount,
            errorMessages: errorMessages
        )
    }
}

private struct RecentSessionKey: Hashable {
    let provider: ProviderID
    let sessionID: String
}

private struct RecentSessionAccumulator {
    let provider: ProviderID
    let sessionID: String

    private var usage = RecentSessionUsageAccumulator()
    private var modelUsage: [String: RecentSessionUsageAccumulator] = [:]
    private var upstreamProviderIDs: Set<String> = []
    private var latestProjectTimestamp: Date?

    private(set) var projectPath: String?
    private(set) var firstActiveAt: Date?
    private(set) var lastActiveAt: Date?
    private(set) var isSubagentIncluded = false

    init(provider: ProviderID, sessionID: String) {
        self.provider = provider
        self.sessionID = sessionID
    }

    mutating func add(_ entry: ParsedUsageEntry, timestamp: Date, cost: Double) {
        usage.add(entry, cost: cost)
        modelUsage[entry.model, default: RecentSessionUsageAccumulator()].add(entry, cost: cost)

        if let cwd = entry.cwd, !cwd.isEmpty,
           latestProjectTimestamp == nil || timestamp >= (latestProjectTimestamp ?? .distantPast) {
            projectPath = cwd
            latestProjectTimestamp = timestamp
        }

        if let upstreamProviderID = entry.upstreamProviderID, !upstreamProviderID.isEmpty {
            upstreamProviderIDs.insert(upstreamProviderID)
        }

        if firstActiveAt == nil || timestamp < (firstActiveAt ?? .distantFuture) {
            firstActiveAt = timestamp
        }
        if lastActiveAt == nil || timestamp > (lastActiveAt ?? .distantPast) {
            lastActiveAt = timestamp
        }
        isSubagentIncluded = isSubagentIncluded || entry.isSubagent
    }

    func makeRow() -> RecentSessionRow {
        let modelBreakdown = modelUsage.mapValues { $0.makeSummary() }
        let primaryModel = modelBreakdown
            .sorted { lhs, rhs in
                if lhs.value.totalTokens != rhs.value.totalTokens {
                    return lhs.value.totalTokens > rhs.value.totalTokens
                }
                return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
            }
            .first?
            .key ?? ""

        return RecentSessionRow(
            id: "\(provider.rawValue):\(sessionID)",
            provider: provider,
            sessionID: sessionID,
            projectPath: projectPath,
            primaryModel: primaryModel,
            additionalModelCount: max(0, modelBreakdown.count - 1),
            firstActiveAt: firstActiveAt,
            lastActiveAt: lastActiveAt,
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens,
            cacheReadTokens: usage.cacheReadTokens,
            cacheCreationTokens: usage.cacheCreationTokens,
            reasoningTokens: usage.reasoningTokens,
            totalTokens: usage.totalTokens,
            cost: usage.cost,
            entryCount: usage.entryCount,
            modelBreakdown: modelBreakdown,
            upstreamProviderIDs: upstreamProviderIDs.sorted(),
            isSubagentIncluded: isSubagentIncluded
        )
    }
}

private struct RecentSessionUsageAccumulator {
    private(set) var inputTokens = 0
    private(set) var outputTokens = 0
    private(set) var cacheReadTokens = 0
    private(set) var cacheCreationTokens = 0
    private(set) var reasoningTokens = 0
    private(set) var cost = 0.0
    private(set) var entryCount = 0

    var totalTokens: Int {
        [
            inputTokens,
            outputTokens,
            cacheReadTokens,
            cacheCreationTokens,
            reasoningTokens,
        ].reduce(0) { $0.addingSaturated($1) }
    }

    mutating func add(_ entry: ParsedUsageEntry, cost entryCost: Double) {
        inputTokens = inputTokens.addingSaturated(entry.usage.inputTokens)
        outputTokens = outputTokens.addingSaturated(entry.usage.outputTokens)
        cacheReadTokens = cacheReadTokens.addingSaturated(entry.usage.cacheReadInputTokens)
        cacheCreationTokens = cacheCreationTokens.addingSaturated(
            entry.usage.totalCacheCreationTokens
        )
        reasoningTokens = reasoningTokens.addingSaturated(entry.usage.reasoningTokens)
        cost += entryCost
        entryCount += 1
    }

    func makeSummary() -> UsageSummary {
        UsageSummary(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheReadTokens,
            cacheCreationTokens: cacheCreationTokens,
            reasoningTokens: reasoningTokens,
            totalTokens: totalTokens,
            cost: cost,
            entryCount: entryCount,
            modelBreakdown: [:]
        )
    }
}
