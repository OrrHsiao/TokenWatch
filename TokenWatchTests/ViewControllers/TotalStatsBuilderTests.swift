import Foundation
import Testing
@testable import TokenWatch

@Suite("TotalStatsBuilder")
struct TotalStatsBuilderTests {

    @Test("跨 provider 汇总总 token、费用和同模型 token、费用")
    func sumsTotalsAndMergesModelsAcrossProviders() {
        let claudeStats = makeStats(
            total: 1_200,
            cost: 12.50,
            byModel: [
                "claude-sonnet": (tokens: 900, cost: 9.25),
                "claude-haiku": (tokens: 300, cost: 3.25),
            ]
        )
        let codexStats = makeStats(
            total: 800,
            cost: 4.25,
            byModel: [
                "gpt-5": (tokens: 500, cost: 2.00),
                "claude-haiku": (tokens: 300, cost: 2.25),
            ]
        )

        let snapshot = TotalStatsBuilder.build(states: [
            .claude: .init(stats: claudeStats, isLoading: false, errorMessage: nil, needsAuthorization: false),
            .codex: .init(stats: codexStats, isLoading: false, errorMessage: nil, needsAuthorization: false),
        ])

        #expect(snapshot.totalTokens == 2_000)
        #expect(snapshot.totalCost == 16.75)
        #expect(snapshot.modelRows.map(\.modelName) == ["claude-sonnet", "claude-haiku", "gpt-5"])
        #expect(snapshot.modelRows.map(\.totalTokens) == [900, 600, 500])
        #expect(snapshot.modelRows.map(\.totalCost) == [9.25, 5.50, 2.00])
    }

    @Test("模型 token 相同时按模型名排序并过滤零值")
    func sortsEqualTokenModelsByNameAndFiltersZeroRows() {
        let stats = makeStats(
            total: 300,
            cost: 1.00,
            byModel: [
                "zeta": 100,
                "Alpha": 100,
                "empty": 0,
                "beta": 100,
            ]
        )

        let snapshot = TotalStatsBuilder.build(states: [
            .claude: .init(stats: stats, isLoading: false, errorMessage: nil, needsAuthorization: false),
        ])

        #expect(snapshot.modelRows.map(\.modelName) == ["Alpha", "beta", "zeta"])
        #expect(snapshot.modelRows.map(\.totalTokens) == [100, 100, 100])
    }

    @Test("统计 provider 状态")
    func countsProviderStatesAndCollectsErrors() {
        let snapshot = TotalStatsBuilder.build(states: [
            .claude: .init(stats: makeStats(total: 10), isLoading: false, errorMessage: nil, needsAuthorization: false),
            .codex: .init(stats: nil, isLoading: true, errorMessage: nil, needsAuthorization: false),
            .opencode: .init(stats: nil, isLoading: false, errorMessage: "OpenCode 失败", needsAuthorization: true),
        ])

        #expect(snapshot.loadedProviderCount == 1)
        #expect(snapshot.loadingProviderCount == 1)
        #expect(snapshot.unauthorizedProviderCount == 1)
        #expect(snapshot.errorMessages == ["OpenCode 失败"])
    }

    private func makeStats(
        total: Int,
        cost: Double = 0,
        byModel: [String: Int] = [:]
    ) -> AggregatedStats {
        makeStats(
            total: total,
            cost: cost,
            byModel: byModel.mapValues { (tokens: $0, cost: 0) }
        )
    }

    private func makeStats(
        total: Int,
        cost: Double = 0,
        byModel: [String: (tokens: Int, cost: Double)]
    ) -> AggregatedStats {
        let modelSummaries = byModel.mapValues { modelSummary in
            UsageSummary(
                inputTokens: modelSummary.tokens,
                outputTokens: 0,
                cacheReadTokens: 0,
                cacheCreationTokens: 0,
                reasoningTokens: 0,
                totalTokens: modelSummary.tokens,
                cost: modelSummary.cost,
                entryCount: modelSummary.tokens > 0 ? 1 : 0,
                modelBreakdown: [:]
            )
        }
        return AggregatedStats(
            overall: UsageSummary(
                inputTokens: total,
                outputTokens: 0,
                cacheReadTokens: 0,
                cacheCreationTokens: 0,
                reasoningTokens: 0,
                totalTokens: total,
                cost: cost,
                entryCount: total > 0 ? 1 : 0,
                modelBreakdown: modelSummaries
            ),
            byHour: [:],
            byDay: [:],
            byWeek: [:],
            byMonth: [:],
            bySession: [:],
            byModel: modelSummaries,
            byProject: [:],
            dataSourceCount: 1
        )
    }
}
