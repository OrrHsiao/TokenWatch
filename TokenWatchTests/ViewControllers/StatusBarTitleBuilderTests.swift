import Testing
@testable import TokenWatch

struct StatusBarTitleBuilderTests {

    private let today = "2026-06-15"

    /// 全部 provider 未授权 → 文本为破折号
    @Test func allUnauthorizedShowsDash() {
        let states: [ProviderID: TokenStatsViewModel.ProviderState] = [
            .claude: .init(stats: nil, isLoading: false, errorMessage: nil, needsAuthorization: true),
            .codex: .init(stats: nil, isLoading: false, errorMessage: nil, needsAuthorization: true),
            .opencode: .init(stats: nil, isLoading: false, errorMessage: nil, needsAuthorization: true),
        ]
        #expect(StatusBarTitleBuilder.build(states: states, todayKey: today) == "—")
    }

    /// 首次启动:授权过但还没数据 + isLoading → 省略号
    @Test func loadingWithNoStatsShowsEllipsis() {
        let states: [ProviderID: TokenStatsViewModel.ProviderState] = [
            .claude: .init(stats: nil, isLoading: true, errorMessage: nil, needsAuthorization: false),
            .codex: .init(stats: nil, isLoading: false, errorMessage: nil, needsAuthorization: false),
            .opencode: .init(stats: nil, isLoading: false, errorMessage: nil, needsAuthorization: false),
        ]
        #expect(StatusBarTitleBuilder.build(states: states, todayKey: today) == "…")
    }

    /// 已经有数据后再刷新,即便 isLoading=true 也展示已有汇总(避免闪烁)
    @Test func loadingWithExistingStatsShowsSum() {
        let stats = makeStats(byDay: [today: makeSummary(input: 1_000, output: 2_000)])
        let states: [ProviderID: TokenStatsViewModel.ProviderState] = [
            .claude: .init(stats: stats, isLoading: true, errorMessage: nil, needsAuthorization: false),
            .codex: .init(stats: nil, isLoading: false, errorMessage: nil, needsAuthorization: false),
            .opencode: .init(stats: nil, isLoading: false, errorMessage: nil, needsAuthorization: false),
        ]
        #expect(StatusBarTitleBuilder.build(states: states, todayKey: today) == "3.0k")
    }

    /// 跨 provider 求和
    @Test func sumsAcrossProviders() {
        let claudeStats = makeStats(byDay: [today: makeSummary(input: 100_000, output: 200_000)])
        let codexStats = makeStats(byDay: [today: makeSummary(input: 50_000, output: 0, cacheRead: 30_000)])
        let opencodeStats = makeStats(byDay: [today: makeSummary(input: 0, output: 20_000, cacheCreation: 10_000)])

        let states: [ProviderID: TokenStatsViewModel.ProviderState] = [
            .claude: .init(stats: claudeStats, isLoading: false, errorMessage: nil, needsAuthorization: false),
            .codex: .init(stats: codexStats, isLoading: false, errorMessage: nil, needsAuthorization: false),
            .opencode: .init(stats: opencodeStats, isLoading: false, errorMessage: nil, needsAuthorization: false),
        ]

        // 100k+200k+50k+30k+20k+10k = 410_000 → "410.0k"
        #expect(StatusBarTitleBuilder.build(states: states, todayKey: today) == "410.0k")
    }

    /// 某 provider 的 byDay 没有 today key → 视作 0,其它正常累加
    @Test func missingTodayBucketTreatedAsZero() {
        let claudeStats = makeStats(byDay: [today: makeSummary(input: 1_500, output: 0)])
        let codexStats = makeStats(byDay: ["2026-06-14": makeSummary(input: 999_999, output: 0)])

        let states: [ProviderID: TokenStatsViewModel.ProviderState] = [
            .claude: .init(stats: claudeStats, isLoading: false, errorMessage: nil, needsAuthorization: false),
            .codex: .init(stats: codexStats, isLoading: false, errorMessage: nil, needsAuthorization: false),
            .opencode: .init(stats: nil, isLoading: false, errorMessage: nil, needsAuthorization: true),
        ]
        #expect(StatusBarTitleBuilder.build(states: states, todayKey: today) == "1.5k")
    }

    /// 部分授权部分未授权:已授权部分有数据则展示总和(不显示破折号)
    @Test func partialAuthorizationStillSums() {
        let claudeStats = makeStats(byDay: [today: makeSummary(input: 5_000, output: 5_000)])
        let states: [ProviderID: TokenStatsViewModel.ProviderState] = [
            .claude: .init(stats: claudeStats, isLoading: false, errorMessage: nil, needsAuthorization: false),
            .codex: .init(stats: nil, isLoading: false, errorMessage: nil, needsAuthorization: true),
            .opencode: .init(stats: nil, isLoading: false, errorMessage: nil, needsAuthorization: true),
        ]
        #expect(StatusBarTitleBuilder.build(states: states, todayKey: today) == "10.0k")
    }

    // MARK: - Helpers

    private func makeSummary(
        input: Int = 0,
        output: Int = 0,
        cacheRead: Int = 0,
        cacheCreation: Int = 0
    ) -> UsageSummary {
        UsageSummary(
            inputTokens: input,
            outputTokens: output,
            cacheReadTokens: cacheRead,
            cacheCreationTokens: cacheCreation,
            reasoningTokens: 0,
            totalTokens: input + output + cacheRead + cacheCreation,
            cost: 0,
            entryCount: 0,
            modelBreakdown: [:]
        )
    }

    private func makeStats(byDay: [String: UsageSummary]) -> AggregatedStats {
        AggregatedStats(
            overall: .zero,
            byHour: [:], byDay: byDay, byWeek: [:], byMonth: [:],
            bySession: [:], byModel: [:], byProject: [:],
            dataSourceCount: 1
        )
    }
}
