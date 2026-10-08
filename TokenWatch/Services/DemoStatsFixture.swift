//
//  DemoStatsFixture.swift
//  TokenWatch
//
//  Created for automated screenshots and preview/demo mode.
//

import Foundation

/// 为 App Store 截图、Demo 演示及自动化测试提供确定性、高真实度且已脱敏的统计数据。
enum DemoStatsFixture {
    static let argumentKey = "-TokenWatch.useDemoData"
    static let userDefaultsKey = "TokenWatch.useDemoData"

    /// 是否开启了 Demo 数据模式（支持命令行参数与 UserDefaults）
    static var isDemoModeEnabled: Bool {
        if CommandLine.arguments.contains(argumentKey) || CommandLine.arguments.contains("--demo-mode") {
            return true
        }
        return UserDefaults.standard.bool(forKey: userDefaultsKey)
    }

    /// 生成覆盖三款 Provider（Claude Code, Codex, OpenCode）的确定性演示状态
    static func makeDemoStates(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ProviderID: TokenStatsViewModel.ProviderState] {
        let (claudeStats, claudeEntries) = makeClaudeData(now: now, calendar: calendar)
        let (codexStats, codexEntries) = makeCodexData(now: now, calendar: calendar)
        let (opencodeStats, opencodeEntries) = makeOpenCodeData(now: now, calendar: calendar)

        return [
            .claude: TokenStatsViewModel.ProviderState(
                stats: claudeStats,
                entries: claudeEntries,
                isLoading: false,
                errorMessage: nil,
                needsAuthorization: false,
                lastRefreshedAt: now,
                directoryState: .selected,
                directoryAuthorizationErrorMessage: nil,
                isAuthorizing: false
            ),
            .codex: TokenStatsViewModel.ProviderState(
                stats: codexStats,
                entries: codexEntries,
                isLoading: false,
                errorMessage: nil,
                needsAuthorization: false,
                lastRefreshedAt: now,
                directoryState: .selected,
                directoryAuthorizationErrorMessage: nil,
                isAuthorizing: false
            ),
            .opencode: TokenStatsViewModel.ProviderState(
                stats: opencodeStats,
                entries: opencodeEntries,
                isLoading: false,
                errorMessage: nil,
                needsAuthorization: false,
                lastRefreshedAt: now,
                directoryState: .selected,
                directoryAuthorizationErrorMessage: nil,
                isAuthorizing: false
            ),
        ]
    }

    // MARK: - Private Generators

    private static func makeClaudeData(
        now: Date,
        calendar: Calendar
    ) -> (AggregatedStats, [ParsedUsageEntry]) {
        let totalTokens = 28_400_000
        let totalCost = 41.80
        let entryCount = 84

        let modelBreakdown: [String: UsageSummary] = [
            "claude-3-5-sonnet-20241022": makeSummary(
                total: 24_100_000,
                cost: 36.15,
                entries: 68
            ),
            "claude-3-5-haiku-20241022": makeSummary(
                total: 4_300_000,
                cost: 5.65,
                entries: 16
            ),
        ]

        let projectBreakdown: [String: UsageSummary] = [
            "TokenWatch": makeSummary(total: 16_200_000, cost: 23.85, entries: 48),
            "CoreEngine": makeSummary(total: 8_400_000, cost: 12.35, entries: 24),
            "DevTools": makeSummary(total: 3_800_000, cost: 5.60, entries: 12),
        ]

        let (byDay, byHour, byMonth) = generateTimeline(
            totalTokens: totalTokens,
            totalCost: totalCost,
            now: now,
            calendar: calendar,
            weight: 0.66,
            modelWeights: [
                "claude-3-5-sonnet-20241022": 24.1 / 28.4,
                "claude-3-5-haiku-20241022": 4.3 / 28.4,
            ],
            projectWeights: [
                "TokenWatch": 16.2 / 28.4,
                "CoreEngine": 8.4 / 28.4,
                "DevTools": 3.8 / 28.4,
            ]
        )

        let overall = UsageSummary(
            inputTokens: totalTokens * 3 / 4,
            outputTokens: totalTokens / 4,
            cacheReadTokens: totalTokens * 2 / 5,
            cacheCreationTokens: totalTokens / 10,
            reasoningTokens: 0,
            totalTokens: totalTokens,
            cost: totalCost,
            entryCount: entryCount,
            modelBreakdown: modelBreakdown,
            projectBreakdown: projectBreakdown
        )

        let stats = AggregatedStats(
            overall: overall,
            byHour: byHour,
            byDay: byDay,
            byWeek: [:],
            byMonth: byMonth,
            bySession: [:],
            byModel: modelBreakdown,
            byProject: projectBreakdown,
            dataSourceCount: 1
        )

        let entries = [
            makeEntry(
                title: "Refactor networking layer and retry policy",
                model: "claude-3-5-sonnet-20241022",
                project: "TokenWatch",
                tokens: 184_500,
                cost: 0.28,
                minutesAgo: 25,
                now: now,
                provider: .claude
            ),
            makeEntry(
                title: "Implement calendar heatmap visualization",
                model: "claude-3-5-sonnet-20241022",
                project: "TokenWatch",
                tokens: 342_100,
                cost: 0.51,
                minutesAgo: 80,
                now: now,
                provider: .claude
            ),
            makeEntry(
                title: "Add interactive desktop widgets support",
                model: "claude-3-5-sonnet-20241022",
                project: "TokenWatch",
                tokens: 520_800,
                cost: 0.78,
                minutesAgo: 160,
                now: now,
                provider: .claude
            ),
            makeEntry(
                title: "Setup automated App Store screenshot pipeline",
                model: "claude-3-5-sonnet-20241022",
                project: "TokenWatch",
                tokens: 210_400,
                cost: 0.31,
                minutesAgo: 240,
                now: now,
                provider: .claude
            ),
            makeEntry(
                title: "Parse Anthropic JSONL streaming chunks",
                model: "claude-3-5-haiku-20241022",
                project: "CoreEngine",
                tokens: 145_200,
                cost: 0.19,
                minutesAgo: 380,
                now: now,
                provider: .claude
            ),
        ]

        return (stats, entries)
    }

    private static func makeCodexData(
        now: Date,
        calendar: Calendar
    ) -> (AggregatedStats, [ParsedUsageEntry]) {
        let totalTokens = 9_600_000
        let totalCost = 12.15
        let entryCount = 28

        let modelBreakdown: [String: UsageSummary] = [
            "gpt-4o": makeSummary(
                total: 9_600_000,
                cost: 12.15,
                entries: entryCount
            ),
        ]

        let projectBreakdown: [String: UsageSummary] = [
            "AgentFlow": makeSummary(total: 6_200_000, cost: 7.85, entries: 18),
            "TokenWatch": makeSummary(total: 3_400_000, cost: 4.30, entries: 10),
        ]

        let (byDay, byHour, byMonth) = generateTimeline(
            totalTokens: totalTokens,
            totalCost: totalCost,
            now: now,
            calendar: calendar,
            weight: 0.23,
            modelWeights: [
                "gpt-4o": 1.0,
            ],
            projectWeights: [
                "TokenWatch": 6.2 / 9.6,
                "AgentFlow": 3.4 / 9.6,
            ]
        )

        let overall = UsageSummary(
            inputTokens: totalTokens * 3 / 4,
            outputTokens: totalTokens / 4,
            cacheReadTokens: totalTokens / 3,
            cacheCreationTokens: 0,
            reasoningTokens: 0,
            totalTokens: totalTokens,
            cost: totalCost,
            entryCount: entryCount,
            modelBreakdown: modelBreakdown,
            projectBreakdown: projectBreakdown
        )

        let stats = AggregatedStats(
            overall: overall,
            byHour: byHour,
            byDay: byDay,
            byWeek: [:],
            byMonth: byMonth,
            bySession: [:],
            byModel: modelBreakdown,
            byProject: projectBreakdown,
            dataSourceCount: 1
        )

        let entries = [
            makeEntry(
                title: "Fix macOS status bar popover animation",
                model: "gpt-4o",
                project: "TokenWatch",
                tokens: 96_400,
                cost: 0.14,
                minutesAgo: 45,
                now: now,
                provider: .codex
            ),
            makeEntry(
                title: "Hardening StoreKit IAP verification and restore",
                model: "gpt-4o",
                project: "TokenWatch",
                tokens: 112_800,
                cost: 0.16,
                minutesAgo: 195,
                now: now,
                provider: .codex
            ),
            makeEntry(
                title: "Optimize async event monitoring debounce",
                model: "gpt-4o",
                project: "AgentFlow",
                tokens: 78_200,
                cost: 0.11,
                minutesAgo: 310,
                now: now,
                provider: .codex
            ),
        ]

        return (stats, entries)
    }

    private static func makeOpenCodeData(
        now: Date,
        calendar: Calendar
    ) -> (AggregatedStats, [ParsedUsageEntry]) {
        let totalTokens = 4_840_000
        let totalCost = 4.47
        let entryCount = 16

        let modelBreakdown: [String: UsageSummary] = [
            "deepseek-coder": makeSummary(
                total: 4_840_000,
                cost: 4.47,
                entries: entryCount
            ),
        ]

        let projectBreakdown: [String: UsageSummary] = [
            "CoreEngine": makeSummary(total: 4_840_000, cost: 4.47, entries: entryCount),
        ]

        let (byDay, byHour, byMonth) = generateTimeline(
            totalTokens: totalTokens,
            totalCost: totalCost,
            now: now,
            calendar: calendar,
            weight: 0.11,
            modelWeights: [
                "deepseek-coder": 1.0,
            ],
            projectWeights: [
                "CoreEngine": 1.0,
            ]
        )

        let overall = UsageSummary(
            inputTokens: totalTokens * 4 / 5,
            outputTokens: totalTokens / 5,
            cacheReadTokens: totalTokens / 2,
            cacheCreationTokens: 0,
            reasoningTokens: 0,
            totalTokens: totalTokens,
            cost: totalCost,
            entryCount: entryCount,
            modelBreakdown: modelBreakdown,
            projectBreakdown: projectBreakdown
        )

        let stats = AggregatedStats(
            overall: overall,
            byHour: byHour,
            byDay: byDay,
            byWeek: [:],
            byMonth: byMonth,
            bySession: [:],
            byModel: modelBreakdown,
            byProject: projectBreakdown,
            dataSourceCount: 1
        )

        let entries = [
            makeEntry(
                title: "Optimize SQLite database indexing and queries",
                model: "deepseek-coder",
                project: "CoreEngine",
                tokens: 78_500,
                cost: 0.05,
                minutesAgo: 110,
                now: now,
                provider: .opencode
            ),
            makeEntry(
                title: "Multi-provider usage aggregation benchmarking",
                model: "deepseek-coder",
                project: "CoreEngine",
                tokens: 65_300,
                cost: 0.04,
                minutesAgo: 275,
                now: now,
                provider: .opencode
            ),
        ]

        return (stats, entries)
    }

    private static func generateTimeline(
        totalTokens: Int,
        totalCost: Double,
        now: Date,
        calendar: Calendar,
        weight: Double,
        modelWeights: [String: Double] = [:],
        projectWeights: [String: Double] = [:]
    ) -> ([String: UsageSummary], [String: UsageSummary], [String: UsageSummary]) {
        var byDay: [String: UsageSummary] = [:]
        var byHour: [String: UsageSummary] = [:]
        var byMonth: [String: UsageSummary] = [:]

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.calendar = calendar

        let hourFormatter = DateFormatter()
        hourFormatter.dateFormat = "yyyy-MM-dd'T'HH"
        hourFormatter.calendar = calendar

        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "yyyy-MM"
        monthFormatter.calendar = calendar

        // 1. 生成 154 天（22 周）饱满的日历热力图数据
        for dayOffset in 0..<154 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: now) else { continue }
            let dayKey = dayFormatter.string(from: date)
            let weekday = calendar.component(.weekday, from: date) // 1=Sun, 7=Sat
            let isWeekend = (weekday == 1 || weekday == 7)

            // 具有科技波动的正弦基底 + 周期特征
            let cycle = sin(Double(dayOffset) * 0.28) * 0.4 + 0.6
            let baseTokens = isWeekend ? 60_000 : 380_000
            let dayTokens = Int(Double(baseTokens) * cycle * weight * 1.5)
            let dayCost = (Double(dayTokens) / Double(totalTokens)) * totalCost * 1.2
            let effectiveTokens = max(dayTokens, 15_000)
            let entries = max(effectiveTokens / 40_000, 1)

            var dayModelBreakdown: [String: UsageSummary] = [:]
            for (model, ratio) in modelWeights {
                let mTokens = Int(Double(effectiveTokens) * ratio)
                let mCost = dayCost * ratio
                dayModelBreakdown[model] = makeSummary(
                    total: mTokens,
                    cost: mCost,
                    entries: max(1, Int(Double(entries) * ratio))
                )
            }

            var dayProjectBreakdown: [String: UsageSummary] = [:]
            for (project, ratio) in projectWeights {
                let pTokens = Int(Double(effectiveTokens) * ratio)
                let pCost = dayCost * ratio
                dayProjectBreakdown[project] = makeSummary(
                    total: pTokens,
                    cost: pCost,
                    entries: max(1, Int(Double(entries) * ratio))
                )
            }

            byDay[dayKey] = makeSummary(
                total: effectiveTokens,
                cost: dayCost,
                entries: entries,
                modelBreakdown: dayModelBreakdown,
                projectBreakdown: dayProjectBreakdown
            )

            // 按月聚合
            let monthKey = monthFormatter.string(from: date)
            byMonth[monthKey, default: .zero] = byMonth[monthKey, default: .zero].merged(
                with: byDay[dayKey]!
            )
        }

        // 2. 生成今日 24 小时折线图数据
        for hour in 0..<24 {
            guard let hourDate = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now) else { continue }
            let hourKey = hourFormatter.string(from: hourDate)

            // 工作时间（9点到20点）消耗集中
            let hourFactor: Double
            switch hour {
            case 9...11: hourFactor = 1.6
            case 12...13: hourFactor = 0.8
            case 14...18: hourFactor = 2.1
            case 19...22: hourFactor = 1.2
            default: hourFactor = 0.1
            }

            let hourTokens = Int(Double(totalTokens) / 600.0 * hourFactor * weight)
            let hourCost = (Double(hourTokens) / Double(totalTokens)) * totalCost
            let entries = max(hourTokens / 35_000, 1)

            var hourModelBreakdown: [String: UsageSummary] = [:]
            for (model, ratio) in modelWeights {
                let mTokens = Int(Double(hourTokens) * ratio)
                let mCost = hourCost * ratio
                hourModelBreakdown[model] = makeSummary(
                    total: mTokens,
                    cost: mCost,
                    entries: max(1, Int(Double(entries) * ratio))
                )
            }

            var hourProjectBreakdown: [String: UsageSummary] = [:]
            for (project, ratio) in projectWeights {
                let pTokens = Int(Double(hourTokens) * ratio)
                let pCost = hourCost * ratio
                hourProjectBreakdown[project] = makeSummary(
                    total: pTokens,
                    cost: pCost,
                    entries: max(1, Int(Double(entries) * ratio))
                )
            }

            byHour[hourKey] = makeSummary(
                total: hourTokens,
                cost: hourCost,
                entries: entries,
                modelBreakdown: hourModelBreakdown,
                projectBreakdown: hourProjectBreakdown
            )
        }

        return (byDay, byHour, byMonth)
    }

    private static func makeSummary(
        total: Int,
        cost: Double = 0,
        entries: Int = 1,
        modelBreakdown: [String: UsageSummary] = [:],
        projectBreakdown: [String: UsageSummary] = [:]
    ) -> UsageSummary {
        UsageSummary(
            inputTokens: total * 3 / 4,
            outputTokens: total / 4,
            cacheReadTokens: total * 2 / 5,
            cacheCreationTokens: total / 10,
            reasoningTokens: 0,
            totalTokens: total,
            cost: cost,
            entryCount: entries,
            modelBreakdown: modelBreakdown,
            projectBreakdown: projectBreakdown
        )
    }

    private static func makeEntry(
        title: String,
        model: String,
        project: String,
        tokens: Int,
        cost: Double,
        minutesAgo: Int,
        now: Date,
        provider: ProviderID
    ) -> ParsedUsageEntry {
        let timestamp = now.addingTimeInterval(-Double(minutesAgo * 60))
        let usage = TokenUsage(
            inputTokens: tokens * 3 / 4,
            cacheCreationInputTokens: 0,
            cacheReadInputTokens: tokens / 3,
            outputTokens: tokens / 4,
            reasoningTokens: 0,
            serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
            serviceTier: "standard",
            cacheCreation: nil,
            inferenceGeo: "us",
            iterations: [],
            speed: "standard"
        )

        return ParsedUsageEntry(
            recordUUID: UUID().uuidString,
            messageId: UUID().uuidString,
            requestId: nil,
            sessionID: title,
            timestamp: timestamp,
            model: model,
            upstreamModelID: nil,
            cwd: "/Users/developer/Projects/\(project)",
            agentId: nil,
            usage: usage,
            isSubagent: false,
            isSidechain: false,
            hasSourceMessageID: true,
            provider: provider,
            upstreamProviderID: nil,
            upstreamCost: cost
        )
    }
}
