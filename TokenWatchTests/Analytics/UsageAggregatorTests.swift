import Foundation
import Testing
@testable import TokenWatch

/// 聚合器测试
/// 验证多维度聚合逻辑的正确性
struct UsageAggregatorTests {

    let aggregator = UsageAggregator()

    // MARK: - 空数据

    @Test("空条目返回零统计")
    func emptyEntriesReturnsZero() {
        let stats = aggregator.aggregate([])
        #expect(stats.overall.totalTokens == 0)
        #expect(stats.overall.cost == 0.0)
        #expect(stats.overall.entryCount == 0)
        #expect(stats.dataSourceCount == 0)
        #expect(stats.byDay.isEmpty)
        #expect(stats.byModel.isEmpty)
    }

    // MARK: - 基础聚合

    @Test("单条记录聚合")
    func singleEntryAggregation() {
        let entries = [
            makeEntry(
                sessionID: "session-1",
                date: date(2026, 6, 13),
                model: "deepseek-v4-pro",
                input: 1000, output: 500,
                cacheRead: 200, cacheCreation: 0
            )
        ]

        let stats = aggregator.aggregate(entries)

        #expect(stats.overall.inputTokens == 1000)
        #expect(stats.overall.outputTokens == 500)
        #expect(stats.overall.cacheReadTokens == 200)
        #expect(stats.overall.totalTokens == 1700)
        #expect(stats.overall.entryCount == 1)
        #expect(stats.dataSourceCount == 1)

        // 按模型
        #expect(stats.byModel.count == 1)
        #expect(stats.byModel["deepseek-v4-pro"]?.inputTokens == 1000)
    }

    @Test("多条记录聚合")
    func multipleEntriesAggregation() {
        let entries = [
            makeEntry(sessionID: "s1", date: date(2026, 6, 13), model: "deepseek-v4-pro",
                      input: 1000, output: 500),
            makeEntry(sessionID: "s1", date: date(2026, 6, 13), model: "deepseek-v4-pro",
                      input: 2000, output: 1000),
            makeEntry(sessionID: "s2", date: date(2026, 6, 14), model: "deepseek-v4-flash",
                      input: 500, output: 200),
        ]

        let stats = aggregator.aggregate(entries)

        // overall
        #expect(stats.overall.inputTokens == 3500)
        #expect(stats.overall.outputTokens == 1700)
        #expect(stats.overall.entryCount == 3)

        // 按日
        #expect(stats.byDay.count == 2)
        #expect(stats.byDay["2026-06-13"]?.entryCount == 2)
        #expect(stats.byDay["2026-06-14"]?.entryCount == 1)

        // 按模型
        #expect(stats.byModel.count == 2)
        #expect(stats.byModel["deepseek-v4-pro"]?.inputTokens == 3000)
        #expect(stats.byModel["deepseek-v4-flash"]?.inputTokens == 500)
    }

    // MARK: - 按维度聚合

    @Test("按日聚合")
    func dailyAggregation() {
        let entries = [
            makeEntry(sessionID: "s1", date: date(2026, 6, 13), model: "m1", input: 100, output: 50),
            makeEntry(sessionID: "s1", date: date(2026, 6, 13), model: "m1", input: 200, output: 100),
            makeEntry(sessionID: "s2", date: date(2026, 6, 14), model: "m1", input: 300, output: 150),
            makeEntry(sessionID: "s3", date: date(2026, 6, 15), model: "m1", input: 400, output: 200),
        ]

        let stats = aggregator.aggregate(entries)

        #expect(stats.byDay.count == 3)
        #expect(stats.byDay["2026-06-13"]?.inputTokens == 300)
        #expect(stats.byDay["2026-06-14"]?.inputTokens == 300)
        #expect(stats.byDay["2026-06-15"]?.inputTokens == 400)
    }

    @Test("按周聚合")
    func weeklyAggregation() {
        // 2026-06-13 是周六，2026-06-15 是周一
        // 两者在不同周（取决于日历设置）
        let entries = [
            makeEntry(sessionID: "s1", date: date(2026, 6, 13), model: "m1", input: 100, output: 50),
            makeEntry(sessionID: "s2", date: date(2026, 6, 20), model: "m1", input: 200, output: 100),
        ]

        let stats = aggregator.aggregate(entries)

        #expect(stats.byWeek.count == 2)
    }

    @Test("周聚合使用 ISO 8601 规则(周一起点),与 ccusage 对齐")
    func weeklyAggregationFollowsISO8601() {
        // 2026-05-03 是周日 → ISO W18 末日
        // 2026-05-04 是周一 → ISO W19 首日
        // 若 app 误用 zh_CN 周(周日起点),两者会被错误归入同一周,
        // 与 ccusage codex weekly 对账时金额漂移
        let entries = [
            makeEntry(sessionID: "s1", date: date(2026, 5, 3),
                      model: "gpt-5.5", input: 100, output: 10),
            makeEntry(sessionID: "s2", date: date(2026, 5, 4),
                      model: "gpt-5.5", input: 200, output: 20),
        ]

        let stats = aggregator.aggregate(entries)

        #expect(stats.byWeek.count == 2, "周日(05-03)与周一(05-04)必须落在不同 ISO 周")
        #expect(stats.byWeek["2026-W18"]?.inputTokens == 100)
        #expect(stats.byWeek["2026-W19"]?.inputTokens == 200)
    }

    @Test("周编号遵循 ISO 8601(2026-04-07 周二归 W15)")
    func weeklyKeyMatchesISOWeekNumber() {
        // ISO 8601: 2026-04-07 是 W15 周二
        // zh_CN  : 同日是 W14 周三(firstWeekday=1, minDays=5 → 整年偏移 1)
        let entries = [
            makeEntry(sessionID: "s1", date: date(2026, 4, 7),
                      model: "gpt-5.4", input: 100, output: 10),
        ]

        let stats = aggregator.aggregate(entries)

        #expect(stats.byWeek["2026-W15"]?.inputTokens == 100)
        #expect(stats.byWeek["2026-W14"] == nil)
    }

    @Test("按会话聚合")
    func sessionAggregation() {
        let entries = [
            makeEntry(sessionID: "session-a", date: date(2026, 6, 13), model: "m1", input: 100, output: 50),
            makeEntry(sessionID: "session-a", date: date(2026, 6, 13), model: "m1", input: 200, output: 100),
            makeEntry(sessionID: "session-b", date: date(2026, 6, 14), model: "m1", input: 300, output: 150),
        ]

        let stats = aggregator.aggregate(entries)

        #expect(stats.bySession.count == 2)
        #expect(stats.bySession["session-a"]?.inputTokens == 300)
        #expect(stats.bySession["session-b"]?.inputTokens == 300)
    }

    @Test("按项目聚合")
    func projectAggregation() {
        let entries = [
            makeEntry(sessionID: "s1", date: date(2026, 6, 13), model: "m1", input: 100, output: 50, cwd: "/project-a"),
            makeEntry(sessionID: "s2", date: date(2026, 6, 13), model: "m1", input: 200, output: 100, cwd: "/project-a"),
            makeEntry(sessionID: "s3", date: date(2026, 6, 14), model: "m1", input: 300, output: 150, cwd: "/project-b"),
        ]

        let stats = aggregator.aggregate(entries)

        #expect(stats.byProject.count == 2)
        #expect(stats.byProject["/project-a"]?.inputTokens == 300)
        #expect(stats.byProject["/project-b"]?.inputTokens == 300)
    }

    // MARK: - 按小时聚合

    @Test("按小时聚合 key 使用 yyyy-MM-ddTHH 格式")
    func hourlyAggregationKeyFormat() {
        // 同一日(2026-06-13)的两条记录,小时不同 → 应进入两个不同的 byHour 桶
        let entries = [
            makeEntry(sessionID: "s1",
                      date: dateTime(2026, 6, 13, 9, 30),
                      model: "m1", input: 100, output: 50),
            makeEntry(sessionID: "s1",
                      date: dateTime(2026, 6, 13, 14, 5),
                      model: "m1", input: 200, output: 100),
        ]

        let stats = aggregator.aggregate(entries)

        #expect(stats.byHour.count == 2)
        #expect(stats.byHour["2026-06-13T09"]?.inputTokens == 100)
        #expect(stats.byHour["2026-06-13T14"]?.inputTokens == 200)
    }

    @Test("byHour 同日各桶之和等于 byDay 该日总桶")
    func hourSumEqualsDay() {
        // 同日 3 条记录落入 3 个不同小时,断言: byDay[day] = sum(byHour where prefix == day)
        let entries = [
            makeEntry(sessionID: "s1",
                      date: dateTime(2026, 6, 13, 0, 15),
                      model: "m1", input: 100, output: 50, cacheRead: 10, cacheCreation: 5),
            makeEntry(sessionID: "s1",
                      date: dateTime(2026, 6, 13, 12, 0),
                      model: "m1", input: 200, output: 100, cacheRead: 20, cacheCreation: 10),
            makeEntry(sessionID: "s2",
                      date: dateTime(2026, 6, 13, 23, 59),
                      model: "m2", input: 300, output: 150, cacheRead: 30, cacheCreation: 15),
        ]

        let stats = aggregator.aggregate(entries)

        let dayKey = "2026-06-13"
        let day = stats.byDay[dayKey]
        #expect(day != nil, "byDay 应该有 \(dayKey) 桶")

        let hourBuckets = stats.byHour.filter { $0.key.hasPrefix("\(dayKey)T") }
        #expect(hourBuckets.count == 3, "三条记录应落入三个独立小时桶")

        let sumInput = hourBuckets.values.reduce(0) { $0 + $1.inputTokens }
        let sumOutput = hourBuckets.values.reduce(0) { $0 + $1.outputTokens }
        let sumCacheRead = hourBuckets.values.reduce(0) { $0 + $1.cacheReadTokens }
        let sumCacheCreation = hourBuckets.values.reduce(0) { $0 + $1.cacheCreationTokens }
        let sumTotal = hourBuckets.values.reduce(0) { $0 + $1.totalTokens }
        let sumEntryCount = hourBuckets.values.reduce(0) { $0 + $1.entryCount }

        #expect(sumInput == day?.inputTokens)
        #expect(sumOutput == day?.outputTokens)
        #expect(sumCacheRead == day?.cacheReadTokens)
        #expect(sumCacheCreation == day?.cacheCreationTokens)
        #expect(sumTotal == day?.totalTokens)
        #expect(sumEntryCount == day?.entryCount)
    }

    @Test("timestamp 为 nil 的条目落入 byHour['unknown'] 桶,不丢数据")
    func hourlyAggregationHandlesMissingTimestamp() {
        // 一条带 timestamp 的正常记录 + 一条 timestamp 为 nil 的记录
        // 后者必须落入 "unknown" 桶,与 dayKey/monthKey 行为一致
        let entries = [
            makeEntry(sessionID: "s1",
                      date: dateTime(2026, 6, 13, 10, 0),
                      model: "m1", input: 100, output: 50),
            makeEntryWithoutTimestamp(sessionID: "s2",
                                      model: "m1", input: 999, output: 0),
        ]

        let stats = aggregator.aggregate(entries)

        #expect(stats.byHour["2026-06-13T10"]?.inputTokens == 100)
        #expect(stats.byHour["unknown"]?.inputTokens == 999)
    }

    // MARK: - 模型细分

    @Test("modelBreakdown 包含模型细分")
    func modelBreakdownIncluded() {
        let entries = [
            makeEntry(sessionID: "s1", date: date(2026, 6, 13), model: "deepseek-v4-pro", input: 1000, output: 500),
            makeEntry(sessionID: "s1", date: date(2026, 6, 13), model: "deepseek-v4-flash", input: 100, output: 50),
        ]

        let stats = aggregator.aggregate(entries)

        #expect(stats.overall.modelBreakdown.count == 2)
        #expect(stats.overall.modelBreakdown["deepseek-v4-pro"]?.inputTokens == 1000)
        #expect(stats.overall.modelBreakdown["deepseek-v4-flash"]?.inputTokens == 100)
    }

    @Test("各维度 summary 仍包含该桶内的模型和项目细分")
    func groupedSummariesIncludeModelAndProjectBreakdowns() {
        let entries = [
            makeEntry(sessionID: "s1", date: dateTime(2026, 6, 13, 9, 0),
                      model: "deepseek-v4-pro", input: 1000, output: 500,
                      cwd: "/project-a"),
            makeEntry(sessionID: "s2", date: dateTime(2026, 6, 13, 9, 30),
                      model: "deepseek-v4-flash", input: 200, output: 100,
                      cwd: "/project-a"),
            makeEntry(sessionID: "s3", date: dateTime(2026, 6, 14, 10, 0),
                      model: "deepseek-v4-pro", input: 300, output: 150,
                      cwd: "/project-b"),
        ]

        let stats = aggregator.aggregate(entries)

        #expect(stats.overall.projectBreakdown["/project-a"]?.inputTokens == 1200)
        #expect(stats.overall.projectBreakdown["/project-b"]?.totalTokens == 450)
        #expect(stats.byDay["2026-06-13"]?.modelBreakdown["deepseek-v4-pro"]?.inputTokens == 1000)
        #expect(stats.byDay["2026-06-13"]?.modelBreakdown["deepseek-v4-flash"]?.inputTokens == 200)
        #expect(stats.byDay["2026-06-13"]?.projectBreakdown["/project-a"]?.totalTokens == 1800)
        #expect(stats.byHour["2026-06-13T09"]?.modelBreakdown.count == 2)
        #expect(stats.byHour["2026-06-13T09"]?.projectBreakdown["/project-a"]?.entryCount == 2)
        #expect(stats.byProject["/project-a"]?.modelBreakdown["deepseek-v4-flash"]?.outputTokens == 100)
        #expect(stats.bySession["s3"]?.modelBreakdown["deepseek-v4-pro"]?.totalTokens == 450)
        #expect(stats.byModel["deepseek-v4-pro"]?.projectBreakdown["/project-b"]?.totalTokens == 450)
    }

    // MARK: - Reasoning 聚合

    @Test("reasoningTokens 参与 byModel/byDay/overall 求和与 totalTokens")
    func reasoningAggregation() {
        let entries = [
            makeEntry(sessionID: "s1", date: date(2026, 6, 13), model: "gpt-5",
                      input: 100, output: 50, reasoning: 200),
            makeEntry(sessionID: "s1", date: date(2026, 6, 13), model: "gpt-5",
                      input: 200, output: 100, reasoning: 400),
            makeEntry(sessionID: "s2", date: date(2026, 6, 14), model: "gpt-5-mini",
                      input: 50, output: 20, reasoning: 30),
        ]

        let stats = aggregator.aggregate(entries)

        #expect(stats.overall.reasoningTokens == 630)
        // totalTokens 包含 reasoning:300+150+30 input/output + 0 cache + 630 reasoning = 1110
        #expect(stats.overall.totalTokens
                == stats.overall.inputTokens + stats.overall.outputTokens
                 + stats.overall.cacheReadTokens + stats.overall.cacheCreationTokens
                 + stats.overall.reasoningTokens)

        #expect(stats.byModel["gpt-5"]?.reasoningTokens == 600)
        #expect(stats.byModel["gpt-5-mini"]?.reasoningTokens == 30)
        #expect(stats.byDay["2026-06-13"]?.reasoningTokens == 600)
        #expect(stats.byDay["2026-06-14"]?.reasoningTokens == 30)
    }

    @Test("reasoning=0 时不影响既有维度求和(向后兼容)")
    func reasoningZeroIsNoOp() {
        let entries = [
            makeEntry(sessionID: "s1", date: date(2026, 6, 13), model: "claude-sonnet-4-5",
                      input: 100, output: 50, reasoning: 0),
        ]
        let stats = aggregator.aggregate(entries)
        #expect(stats.overall.reasoningTokens == 0)
        #expect(stats.overall.totalTokens == 150)  // 100 + 50,不被 reasoning 污染
    }

    // MARK: - Cost Fallback

    @Test("PricingEngine miss 且 upstreamCost > 0 → 走 fallback")
    func upstreamCostFallback() {
        // "private-unknown-model" 必定不在 PricingTable 中
        let entries = [
            makeEntry(sessionID: "s1", date: date(2026, 6, 13),
                      model: "private-unknown-model", input: 1000, output: 500,
                      upstreamCost: 0.123),
        ]
        let stats = aggregator.aggregate(entries)
        #expect(stats.overall.cost == 0.123)
    }

    @Test("PricingEngine miss 且 upstreamCost 缺失 → cost 为 0")
    func upstreamCostFallbackMissing() {
        let entries = [
            makeEntry(sessionID: "s1", date: date(2026, 6, 13),
                      model: "private-unknown-model", input: 1000, output: 500),
        ]
        let stats = aggregator.aggregate(entries)
        #expect(stats.overall.cost == 0.0)
    }

    @Test("upstreamCost 不污染 PricingEngine 命中的模型 cost")
    func upstreamCostDoesNotPolluteEngineCost() {
        // claude-sonnet-4-5 必在 PricingTable 中,即便传了 upstreamCost 也应忽略
        let claudeEntries = [
            makeEntry(sessionID: "s1", date: date(2026, 6, 13),
                      model: "claude-sonnet-4-5", input: 1000, output: 500,
                      upstreamCost: 999.99),
        ]
        let claudeStats = aggregator.aggregate(claudeEntries)
        #expect(claudeStats.overall.cost > 0.0)
        #expect(claudeStats.overall.cost < 100.0,
                "命中 PricingEngine 应使用引擎计算的小额 cost,而非 upstream 999.99")
    }

    // MARK: - Helpers

    private func makeEntry(
        sessionID: String,
        date: Date,
        model: String,
        input: Int,
        output: Int,
        cacheRead: Int = 0,
        cacheCreation: Int = 0,
        reasoning: Int = 0,
        cwd: String = "/test",
        upstreamProviderID: String? = nil,
        upstreamCost: Double? = nil
    ) -> ParsedUsageEntry {
        let id = UUID().uuidString
        return ParsedUsageEntry(
            recordUUID: id,
            messageId: id,
            requestId: nil,
            sessionID: sessionID,
            timestamp: date,
            model: model,
            cwd: cwd,
            agentId: nil,
            usage: TokenUsage(
                inputTokens: input,
                cacheCreationInputTokens: cacheCreation,
                cacheReadInputTokens: cacheRead,
                outputTokens: output,
                reasoningTokens: reasoning,
                serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
                serviceTier: "standard",
                cacheCreation: nil,
                inferenceGeo: "",
                iterations: [],
                speed: "standard"
            ),
            isSubagent: false,
            provider: .claude,
            upstreamProviderID: upstreamProviderID,
            upstreamCost: upstreamCost
        )
    }

    /// 构造 timestamp 为 nil 的条目,用于验证聚合器对缺失时间戳的兜底
    private func makeEntryWithoutTimestamp(
        sessionID: String,
        model: String,
        input: Int,
        output: Int,
        cwd: String = "/test"
    ) -> ParsedUsageEntry {
        let id = UUID().uuidString
        return ParsedUsageEntry(
            recordUUID: id,
            messageId: id,
            requestId: nil,
            sessionID: sessionID,
            timestamp: nil,
            model: model,
            cwd: cwd,
            agentId: nil,
            usage: TokenUsage(
                inputTokens: input,
                cacheCreationInputTokens: 0,
                cacheReadInputTokens: 0,
                outputTokens: output,
                serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
                serviceTier: "standard",
                cacheCreation: CacheCreation(ephemeral1hInputTokens: 0, ephemeral5mInputTokens: 0),
                inferenceGeo: "",
                iterations: [],
                speed: "standard"
            ),
            isSubagent: false,
            provider: .claude,
            upstreamProviderID: nil,
            upstreamCost: nil
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        let components = DateComponents(year: year, month: month, day: day)
        return Calendar.current.date(from: components)!
    }

    /// 构造带具体小时/分钟的 Date,用于小时聚合测试
    private func dateTime(_ year: Int, _ month: Int, _ day: Int,
                          _ hour: Int, _ minute: Int) -> Date {
        let components = DateComponents(year: year, month: month, day: day,
                                        hour: hour, minute: minute)
        return Calendar.current.date(from: components)!
    }
}
