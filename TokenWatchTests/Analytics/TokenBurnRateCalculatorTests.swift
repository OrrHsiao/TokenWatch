import Foundation
import Testing
@testable import TokenWatch

@Suite("TokenBurnRateCalculator")
struct TokenBurnRateCalculatorTests {

    @Test("空条目返回零速率且状态为空闲")
    func emptyEntriesReturnZero() {
        let now = Date()
        let rate = TokenBurnRateCalculator.calculate(entries: [], now: now)
        #expect(rate == 0.0)

        let rateModel = TokenBurnRateCalculator.calculateRate(entries: [], now: now)
        #expect(rateModel == .idle)
        #expect(rateModel.level == .idle)
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

        let rateModel = TokenBurnRateCalculator.calculateRate(entries: entries, now: now)
        #expect(rateModel == .idle)
    }

    @Test("15 分钟完整窗口内的活跃记录正确计算每秒消耗速率")
    func activeRateCalculationWithinFullWindow() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = [
            // 15 分钟前（落在窗口起点边界）：15,000 tokens
            makeEntry(timestamp: now.addingTimeInterval(-15 * 60), totalTokens: 15_000),
            // 5 分钟前：18,000 tokens
            makeEntry(timestamp: now.addingTimeInterval(-5 * 60), totalTokens: 18_000),
            // 10 分钟前：12,000 tokens
            makeEntry(timestamp: now.addingTimeInterval(-10 * 60), totalTokens: 12_000),
            // 16 分钟前：50,000 tokens（超出 15 分钟窗口，不计入）
            makeEntry(timestamp: now.addingTimeInterval(-16 * 60), totalTokens: 50_000),
        ]
        // 窗口内最早记录为 15 分钟前，跨度 900 秒，窗口内净活跃总量 45,000 tokens / 900 秒 = 50 tok/s
        let rate = TokenBurnRateCalculator.calculate(entries: entries, now: now)
        #expect(rate == 50.0)
    }

    @Test("冷启动时动态时间跨度平滑夹紧至最小 30 秒")
    func coldStartClampingToMinimumActiveDuration() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        // 用户刚刚在 10 秒前发起一次调用，产生 3,000 tokens
        let entries = [
            makeEntry(timestamp: now.addingTimeInterval(-10), totalTokens: 3_000)
        ]
        // 跨度 10 秒夹紧至 30 秒，计算速率为 3,000 / 30 = 100 tok/s（而非除以 900 秒得到 3.3，或除以 10 激增到 300）
        let rate = TokenBurnRateCalculator.calculate(entries: entries, now: now)
        #expect(rate == 100.0)
    }

    @Test("对齐 ccusage：净活跃速率剥离 Cache Read 避免指示器虚高")
    func cacheReadExcludedFromActiveRate() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = [
            // 60 秒前交互：输入 1,000、输出 2,000，但命中 200,000 cache read
            makeEntry(
                timestamp: now.addingTimeInterval(-60),
                inputTokens: 1_000,
                outputTokens: 2_000,
                cacheReadTokens: 200_000
            )
        ]
        let result = TokenBurnRateCalculator.calculateRate(entries: entries, now: now)
        // 净活跃 Token = 1,000 + 2,000 = 3,000，跨度 60 秒 -> 50 tok/s
        #expect(result.activeTokensPerSecond == 50.0)
        // 全量 Token 包含 cache read 200,000 + 3,000 = 203,000 -> 203,000 / 60 ≈ 3383.3 tok/s
        #expect(result.totalTokensPerSecond > 3_000.0)
    }

    @Test("成本燃烧率基于 UsageCostResolver 准确计算 USD/hr")
    func costPerHourCalculation() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = [
            // 60 秒前调用，单条记录花费 0.05 美元
            makeEntry(
                timestamp: now.addingTimeInterval(-60),
                inputTokens: 1_000,
                outputTokens: 1_000,
                upstreamCost: 0.05
            )
        ]
        let result = TokenBurnRateCalculator.calculateRate(entries: entries, now: now)
        // 0.05 USD / 60 秒 * 3600 秒 = 3.00 USD/hr
        #expect(result.costPerHour == 3.0)
    }

    @Test("对齐 ccusage 活跃指示器等级阈值")
    func ccusageIndicatorLevelThresholds() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        // Normal: < 2,000 tok/min (< 33.33 tok/s)
        // 60 秒内 1,200 tokens -> 20 tok/s (1,200 tok/min)
        let normalEntries = [makeEntry(timestamp: now.addingTimeInterval(-60), totalTokens: 1_200)]
        let normalRate = TokenBurnRateCalculator.calculateRate(entries: normalEntries, now: now)
        #expect(normalRate.level == .normal)

        // Moderate: 2,000 ~ 5,000 tok/min (33.33 ~ 83.33 tok/s)
        // 60 秒内 3,000 tokens -> 50 tok/s (3,000 tok/min)
        let moderateEntries = [makeEntry(timestamp: now.addingTimeInterval(-60), totalTokens: 3_000)]
        let moderateRate = TokenBurnRateCalculator.calculateRate(entries: moderateEntries, now: now)
        #expect(moderateRate.level == .moderate)

        // High: >= 5,000 tok/min (>= 83.33 tok/s)
        // 60 秒内 6,000 tokens -> 100 tok/s (6,000 tok/min)
        let highEntries = [makeEntry(timestamp: now.addingTimeInterval(-60), totalTokens: 6_000)]
        let highRate = TokenBurnRateCalculator.calculateRate(entries: highEntries, now: now)
        #expect(highRate.level == .high)
    }

    @Test("多 Provider 聚合状态下按实际活跃区间计算燃烧速率")
    func multiProviderStatesCalculation() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let claudeEntries = [
            makeEntry(provider: .claude, timestamp: now.addingTimeInterval(-2 * 60), totalTokens: 18_000)
        ]
        let codexEntries = [
            makeEntry(provider: .codex, timestamp: now.addingTimeInterval(-4 * 60), totalTokens: 9_000)
        ]
        let states: [ProviderID: TokenStatsViewModel.ProviderState] = [
            .claude: .init(stats: nil, entries: claudeEntries, isLoading: false, errorMessage: nil, needsAuthorization: false),
            .codex: .init(stats: nil, entries: codexEntries, isLoading: false, errorMessage: nil, needsAuthorization: false),
        ]
        // 最早记录为 4 分钟前（240 秒），总量 27,000 tokens / 240 秒 = 112.5 tok/s
        let rate = TokenBurnRateCalculator.calculate(states: states, now: now)
        #expect(rate == 112.5)

        let rateModel = TokenBurnRateCalculator.calculateRate(states: states, now: now)
        #expect(rateModel.activeTokensPerSecond == 112.5)
        #expect(rateModel.level == .high)
    }

    @Test("速率格式化支持零、小数、十位、百位、千位与百万位")
    func formatRateSupportsVariousMagnitudes() {
        #expect(TokenBurnRateCalculator.formatRate(0.0) == "0 /s")
        #expect(TokenBurnRateCalculator.formatRate(-5.0) == "0 /s")
        #expect(TokenBurnRateCalculator.formatRate(0.02) == "<0.1 /s")
        #expect(TokenBurnRateCalculator.formatRate(0.54) == "0.5 /s")
        #expect(TokenBurnRateCalculator.formatRate(2.0) == "2 /s")
        #expect(TokenBurnRateCalculator.formatRate(8.4) == "8.4 /s")
        #expect(TokenBurnRateCalculator.formatRate(45.4) == "45 /s")
        #expect(TokenBurnRateCalculator.formatRate(450.4) == "450 /s")
        #expect(TokenBurnRateCalculator.formatRate(999.0) == "999 /s")
        #expect(TokenBurnRateCalculator.formatRate(1_000.0) == "1.0k /s")
        #expect(TokenBurnRateCalculator.formatRate(1_520.0) == "1.5k /s")
        #expect(TokenBurnRateCalculator.formatRate(23_400.0) == "23.4k /s")
        #expect(TokenBurnRateCalculator.formatRate(2_500_000.0) == "2.5M /s")
    }

    @Test("成本燃烧率格式化支持零、微小金额与常见金额")
    func formatCostPerHourSupportsVariousRanges() {
        #expect(TokenBurnRateCalculator.formatCostPerHour(0.0) == "$0.00/hr")
        #expect(TokenBurnRateCalculator.formatCostPerHour(-1.0) == "$0.00/hr")
        #expect(TokenBurnRateCalculator.formatCostPerHour(0.005) == "<$0.01/hr")
        #expect(TokenBurnRateCalculator.formatCostPerHour(0.15) == "$0.15/hr")
        #expect(TokenBurnRateCalculator.formatCostPerHour(1.234) == "$1.23/hr")
        #expect(TokenBurnRateCalculator.formatCostPerHour(12.5) == "$12.50/hr")
        #expect(TokenBurnRateCalculator.formatCostPerHour(150.2) == "$150/hr")
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

    @Test("描述文案在今日有消耗时支持燃烧速率与成本燃烧率组合展示")
    func descriptionTextAppendsBurnRateAndCostPerHour() {
        let baseZh = "本日 token 消耗很克制～"
        // 1. 仅有速率，成本为 0
        let activeZh = TokenBurnRateCalculator.descriptionText(
            baseText: baseZh,
            todayTokens: 50_000,
            burnRate: 25.0,
            costPerHour: 0.0,
            language: .zhHans
        )
        #expect(activeZh == "本日 token 消耗很克制～ · 🔥 25 /s")

        // 2. 同时具有速率与有效成本燃烧率
        let activeWithCostZh = TokenBurnRateCalculator.descriptionText(
            baseText: baseZh,
            todayTokens: 50_000,
            burnRate: 25.0,
            costPerHour: 0.15,
            language: .zhHans
        )
        #expect(activeWithCostZh == "本日 token 消耗很克制～ · 🔥 25 /s ($0.15/hr)")

        // 3. 空闲状态
        let idleZh = TokenBurnRateCalculator.descriptionText(
            baseText: baseZh,
            todayTokens: 50_000,
            burnRate: 0.0,
            costPerHour: 0.0,
            language: .zhHans
        )
        #expect(idleZh == "本日 token 消耗很克制～ · 空闲")

        // 4. 英文语言
        let baseEn = "Today's token usage is light"
        let activeWithCostEn = TokenBurnRateCalculator.descriptionText(
            baseText: baseEn,
            todayTokens: 50_000,
            burnRate: 25.0,
            costPerHour: 0.25,
            language: .en
        )
        #expect(activeWithCostEn == "Today's token usage is light · 🔥 25 /s ($0.25/hr)")
    }

    // MARK: - Helper

    private func makeEntry(
        provider: ProviderID = .claude,
        timestamp: Date,
        totalTokens: Int
    ) -> ParsedUsageEntry {
        makeEntry(
            provider: provider,
            timestamp: timestamp,
            inputTokens: totalTokens / 2,
            outputTokens: totalTokens - (totalTokens / 2),
            cacheReadTokens: 0,
            upstreamCost: nil
        )
    }

    private func makeEntry(
        provider: ProviderID = .claude,
        timestamp: Date,
        inputTokens: Int,
        outputTokens: Int,
        cacheReadTokens: Int = 0,
        upstreamCost: Double? = nil
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
                inputTokens: inputTokens,
                cacheCreationInputTokens: 0,
                cacheReadInputTokens: cacheReadTokens,
                outputTokens: outputTokens,
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
            upstreamCost: upstreamCost
        )
    }
}
