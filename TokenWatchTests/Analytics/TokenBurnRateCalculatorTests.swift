import Foundation
import Testing
@testable import TokenWatch

@Suite("TokenBurnRateCalculator")
struct TokenBurnRateCalculatorTests {

    @Test("空条目返回零速率")
    func emptyEntriesReturnZero() {
        let now = Date()
        let rate = TokenBurnRateCalculator.calculate(entries: [], now: now)
        #expect(rate == 0.0)
    }

    @Test("最新记录超过 15 分钟视为空闲并返回零速率")
    func idleWhenLatestEntryOlderThan15Minutes() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let oldTimestamp = now.addingTimeInterval(-16 * 60) // 16 分钟前
        let entries = [
            makeEntry(timestamp: oldTimestamp, totalTokens: 10_000)
        ]
        let rate = TokenBurnRateCalculator.calculate(entries: entries, now: now)
        #expect(rate == 0.0)
    }

    @Test("15 分钟窗口内的活跃记录正确计算每分钟消耗速率")
    func activeRateCalculationWithinWindow() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = [
            // 5 分钟前：15,000 tokens
            makeEntry(timestamp: now.addingTimeInterval(-5 * 60), totalTokens: 15_000),
            // 10 分钟前：15,000 tokens
            makeEntry(timestamp: now.addingTimeInterval(-10 * 60), totalTokens: 15_000),
            // 16 分钟前：50,000 tokens（超出 15 分钟窗口，不计入）
            makeEntry(timestamp: now.addingTimeInterval(-16 * 60), totalTokens: 50_000),
        ]
        // 窗口内总量 30,000 tokens / 15 分钟 = 2,000 tok/min
        let rate = TokenBurnRateCalculator.calculate(entries: entries, now: now)
        #expect(rate == 2000.0)
    }

    @Test("多 Provider 聚合状态下计算燃烧速率")
    func multiProviderStatesCalculation() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let claudeEntries = [
            makeEntry(provider: .claude, timestamp: now.addingTimeInterval(-2 * 60), totalTokens: 6_000)
        ]
        let codexEntries = [
            makeEntry(provider: .codex, timestamp: now.addingTimeInterval(-4 * 60), totalTokens: 9_000)
        ]
        let states: [ProviderID: TokenStatsViewModel.ProviderState] = [
            .claude: .init(stats: nil, entries: claudeEntries, isLoading: false, errorMessage: nil, needsAuthorization: false),
            .codex: .init(stats: nil, entries: codexEntries, isLoading: false, errorMessage: nil, needsAuthorization: false),
        ]
        // 窗口内总量 15,000 tokens / 15 分钟 = 1,000 tok/min
        let rate = TokenBurnRateCalculator.calculate(states: states, now: now)
        #expect(rate == 1000.0)
    }

    @Test("速率格式化支持零、百位、千位与百万位")
    func formatRateSupportsVariousMagnitudes() {
        #expect(TokenBurnRateCalculator.formatRate(0.0) == "0 /min")
        #expect(TokenBurnRateCalculator.formatRate(-5.0) == "0 /min")
        #expect(TokenBurnRateCalculator.formatRate(450.4) == "450 /min")
        #expect(TokenBurnRateCalculator.formatRate(999.0) == "999 /min")
        #expect(TokenBurnRateCalculator.formatRate(1_000.0) == "1.0k /min")
        #expect(TokenBurnRateCalculator.formatRate(1_520.0) == "1.5k /min")
        #expect(TokenBurnRateCalculator.formatRate(23_400.0) == "23.4k /min")
        #expect(TokenBurnRateCalculator.formatRate(2_500_000.0) == "2.5M /min")
    }

    @Test("描述文案在今日无消耗时保持原有文案不追加空闲状态")
    func descriptionTextPreservesBaseWhenTodayZero() {
        let base = "今日还没有消耗 token 哦～"
        let result = TokenBurnRateCalculator.descriptionText(
            baseText: base,
            todayTokens: 0,
            burnRate: 0.0,
            language: .zhHans
        )
        #expect(result == base)
    }

    @Test("描述文案在今日有消耗时区分活跃与空闲状态")
    func descriptionTextAppendsBurnRateOrIdleWhenTodayPositive() {
        let baseZh = "本日 token 消耗很克制～"
        let activeZh = TokenBurnRateCalculator.descriptionText(
            baseText: baseZh,
            todayTokens: 50_000,
            burnRate: 1500.0,
            language: .zhHans
        )
        #expect(activeZh == "本日 token 消耗很克制～ · 🔥 1.5k /min")

        let idleZh = TokenBurnRateCalculator.descriptionText(
            baseText: baseZh,
            todayTokens: 50_000,
            burnRate: 0.0,
            language: .zhHans
        )
        #expect(idleZh == "本日 token 消耗很克制～ · 空闲")

        let baseEn = "Today's token usage is light"
        let activeEn = TokenBurnRateCalculator.descriptionText(
            baseText: baseEn,
            todayTokens: 50_000,
            burnRate: 1500.0,
            language: .en
        )
        #expect(activeEn == "Today's token usage is light · 🔥 1.5k /min")

        let idleEn = TokenBurnRateCalculator.descriptionText(
            baseText: baseEn,
            todayTokens: 50_000,
            burnRate: 0.0,
            language: .en
        )
        #expect(idleEn == "Today's token usage is light · Idle")
    }

    // MARK: - Helper

    private func makeEntry(
        provider: ProviderID = .claude,
        timestamp: Date,
        totalTokens: Int
    ) -> ParsedUsageEntry {
        let id = UUID().uuidString
        return ParsedUsageEntry(
            recordUUID: id,
            messageId: id,
            requestId: nil,
            sessionID: "test-session",
            timestamp: timestamp,
            model: "claude-3-7-sonnet",
            cwd: "/test",
            agentId: nil,
            usage: TokenUsage(
                inputTokens: totalTokens / 2,
                cacheCreationInputTokens: 0,
                cacheReadInputTokens: 0,
                outputTokens: totalTokens - (totalTokens / 2),
                serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
                serviceTier: "standard",
                cacheCreation: nil,
                inferenceGeo: "",
                iterations: [],
                speed: "standard"
            ),
            isSubagent: false,
            provider: provider,
            upstreamProviderID: nil,
            upstreamCost: nil
        )
    }
}
