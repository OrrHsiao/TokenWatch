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

    // MARK: - Helpers

    private func makeEntry(
        sessionID: String,
        date: Date,
        model: String,
        input: Int,
        output: Int,
        cacheRead: Int = 0,
        cacheCreation: Int = 0,
        cwd: String = "/test"
    ) -> ParsedUsageEntry {
        // 每条记录使用全新 UUID 作为 messageId，确保聚合测试中不会被 dedup 合并
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
                serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
                serviceTier: "standard",
                cacheCreation: CacheCreation(ephemeral1hInputTokens: 0, ephemeral5mInputTokens: 0),
                inferenceGeo: "",
                iterations: [],
                speed: "standard"
            ),
            isSubagent: false
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        let components = DateComponents(year: year, month: month, day: day)
        return Calendar.current.date(from: components)!
    }
}
