import Foundation
import Testing
@testable import TokenWatch

@Suite("RecentSessionDetailsBuilder")
struct RecentSessionDetailsBuilderTests {

    @Test("会话内与跨会话极值 token 汇总饱和到 Int.max")
    func extremeSessionTokenReducersSaturateAtIntMax() throws {
        let calendar = utcCalendar()
        let now = dateTime(2026, 6, 20, hour: 12, minute: 0, calendar: calendar)
        let timestamp = dateTime(2026, 6, 20, hour: 10, minute: 0, calendar: calendar)
        let entries = [
            makeEntry(
                provider: .claude,
                sessionID: "extreme",
                timestamp: timestamp,
                input: .max,
                output: 0
            ),
            makeEntry(
                provider: .claude,
                sessionID: "extreme",
                timestamp: timestamp,
                input: 1,
                output: 0
            ),
            makeEntry(
                provider: .claude,
                sessionID: "other",
                timestamp: timestamp,
                input: 1,
                output: 0
            ),
        ]

        let snapshot = RecentSessionDetailsBuilder.build(
            states: [.claude: .init(
                stats: nil,
                entries: entries,
                isLoading: false,
                errorMessage: nil,
                needsAuthorization: false
            )],
            period: .recent7Days,
            now: now,
            calendar: calendar
        )
        let row = try #require(snapshot.rows.first { $0.sessionID == "extreme" })

        #expect(row.inputTokens == Int.max)
        #expect(row.totalTokens == Int.max)
        #expect(snapshot.totalTokens == Int.max)
    }

    @Test("同名 session 按 provider 隔离分组")
    func groupsByProviderAndSessionID() {
        let calendar = utcCalendar()
        let now = dateTime(2026, 6, 20, hour: 12, minute: 0, calendar: calendar)

        let snapshot = RecentSessionDetailsBuilder.build(
            states: [
                .claude: .init(
                    stats: nil,
                    entries: [
                        makeEntry(
                            provider: .claude,
                            sessionID: "same",
                            timestamp: dateTime(2026, 6, 20, hour: 9, minute: 0, calendar: calendar),
                            input: 50,
                            output: 70
                        ),
                    ],
                    isLoading: false,
                    errorMessage: nil,
                    needsAuthorization: false
                ),
                .codex: .init(
                    stats: nil,
                    entries: [
                        makeEntry(
                            provider: .codex,
                            sessionID: "same",
                            timestamp: dateTime(2026, 6, 20, hour: 10, minute: 0, calendar: calendar),
                            input: 100,
                            output: 140
                        ),
                    ],
                    isLoading: false,
                    errorMessage: nil,
                    needsAuthorization: false
                ),
            ],
            period: .recent7Days,
            now: now,
            calendar: calendar
        )

        #expect(snapshot.rows.map(\.id) == ["codex:same", "claude:same"])
        #expect(snapshot.rows.map(\.totalTokens) == [240, 120])
        #expect(snapshot.totalSessionCount == 2)
        #expect(snapshot.loadedProviderCount == 2)
    }

    @Test("明细使用 period helper 的半开窗口过滤")
    func filtersEntriesByPeriodWindow() throws {
        let calendar = utcCalendar()
        let now = dateTime(2026, 6, 20, hour: 12, minute: 0, calendar: calendar)

        let snapshot = RecentSessionDetailsBuilder.build(
            states: [
                .claude: .init(
                    stats: nil,
                    entries: [
                        makeEntry(
                            provider: .claude,
                            sessionID: "window",
                            timestamp: dateTime(2026, 6, 13, hour: 23, minute: 59, calendar: calendar),
                            input: 10,
                            output: 0
                        ),
                        makeEntry(
                            provider: .claude,
                            sessionID: "window",
                            timestamp: dateTime(2026, 6, 14, hour: 0, minute: 0, calendar: calendar),
                            input: 100,
                            output: 0
                        ),
                        makeEntry(
                            provider: .claude,
                            sessionID: "window",
                            timestamp: dateTime(2026, 6, 20, hour: 23, minute: 59, calendar: calendar),
                            input: 230,
                            output: 0
                        ),
                        makeEntry(
                            provider: .claude,
                            sessionID: "window",
                            timestamp: dateTime(2026, 6, 21, hour: 0, minute: 0, calendar: calendar),
                            input: 1_000,
                            output: 0
                        ),
                    ],
                    isLoading: false,
                    errorMessage: nil,
                    needsAuthorization: false
                ),
            ],
            period: .recent7Days,
            now: now,
            calendar: calendar
        )

        let row = try #require(snapshot.rows.first)
        #expect(row.totalTokens == 330)
        #expect(row.firstActiveAt == dateTime(2026, 6, 14, hour: 0, minute: 0, calendar: calendar))
        #expect(row.lastActiveAt == dateTime(2026, 6, 20, hour: 23, minute: 59, calendar: calendar))
    }

    @Test("行按最近活动时间和稳定兜底规则排序")
    func sortsRowsByRecentActivityAndStableTieBreakers() {
        let calendar = utcCalendar()
        let now = dateTime(2026, 6, 20, hour: 12, minute: 0, calendar: calendar)
        let latest = dateTime(2026, 6, 20, hour: 11, minute: 0, calendar: calendar)
        let tied = dateTime(2026, 6, 20, hour: 10, minute: 0, calendar: calendar)

        let snapshot = RecentSessionDetailsBuilder.build(
            states: [
                .claude: .init(
                    stats: nil,
                    entries: [
                        makeEntry(provider: .claude, sessionID: "a", timestamp: tied, input: 70, output: 30),
                        makeEntry(provider: .claude, sessionID: "b", timestamp: tied, input: 50, output: 50),
                    ],
                    isLoading: false,
                    errorMessage: nil,
                    needsAuthorization: false
                ),
                .codex: .init(
                    stats: nil,
                    entries: [
                        makeEntry(provider: .codex, sessionID: "a", timestamp: latest, input: 10, output: 0),
                    ],
                    isLoading: false,
                    errorMessage: nil,
                    needsAuthorization: false
                ),
            ],
            period: .recent7Days,
            now: now,
            calendar: calendar
        )

        #expect(snapshot.rows.map(\.id) == ["codex:a", "claude:a", "claude:b"])
    }

    @Test("主模型选择 token 最大且并列按名称升序")
    func primaryModelUsesLargestTokenModel() throws {
        let calendar = utcCalendar()
        let now = dateTime(2026, 6, 20, hour: 12, minute: 0, calendar: calendar)

        let snapshot = RecentSessionDetailsBuilder.build(
            states: [
                .opencode: .init(
                    stats: nil,
                    entries: [
                        makeEntry(
                            provider: .opencode,
                            sessionID: "s",
                            timestamp: dateTime(2026, 6, 20, hour: 9, minute: 0, calendar: calendar),
                            model: "b-model",
                            input: 100,
                            output: 0,
                            upstreamProviderID: "openai"
                        ),
                        makeEntry(
                            provider: .opencode,
                            sessionID: "s",
                            timestamp: dateTime(2026, 6, 20, hour: 10, minute: 0, calendar: calendar),
                            model: "a-model",
                            input: 100,
                            output: 0,
                            upstreamProviderID: "anthropic"
                        ),
                        makeEntry(
                            provider: .opencode,
                            sessionID: "s",
                            timestamp: dateTime(2026, 6, 20, hour: 11, minute: 0, calendar: calendar),
                            model: "z-model",
                            input: 50,
                            output: 0,
                            upstreamProviderID: "openai"
                        ),
                    ],
                    isLoading: false,
                    errorMessage: nil,
                    needsAuthorization: false
                ),
            ],
            period: .recent7Days,
            now: now,
            calendar: calendar
        )

        let row = try #require(snapshot.rows.first)
        #expect(row.primaryModel == "a-model")
        #expect(row.additionalModelCount == 2)
        #expect(row.upstreamProviderIDs == ["anthropic", "openai"])
    }

    @Test("项目路径使用最近非空 cwd 且聚合 subagent 标记")
    func projectPathUsesLatestNonEmptyCwdAndSubagentFlagAggregates() throws {
        let calendar = utcCalendar()
        let now = dateTime(2026, 6, 20, hour: 12, minute: 0, calendar: calendar)

        let snapshot = RecentSessionDetailsBuilder.build(
            states: [
                .claude: .init(
                    stats: nil,
                    entries: [
                        makeEntry(
                            provider: .claude,
                            sessionID: "path",
                            timestamp: dateTime(2026, 6, 20, hour: 8, minute: 0, calendar: calendar),
                            input: 10,
                            output: 0,
                            cwd: "/old"
                        ),
                        makeEntry(
                            provider: .claude,
                            sessionID: "path",
                            timestamp: dateTime(2026, 6, 20, hour: 9, minute: 0, calendar: calendar),
                            input: 10,
                            output: 0,
                            isSubagent: true
                        ),
                        makeEntry(
                            provider: .claude,
                            sessionID: "path",
                            timestamp: dateTime(2026, 6, 20, hour: 10, minute: 0, calendar: calendar),
                            input: 10,
                            output: 0,
                            cwd: "/new"
                        ),
                    ],
                    isLoading: false,
                    errorMessage: nil,
                    needsAuthorization: false
                ),
            ],
            period: .recent7Days,
            now: now,
            calendar: calendar
        )

        let row = try #require(snapshot.rows.first)
        #expect(row.projectPath == "/new")
        #expect(row.isSubagentIncluded)
    }

    @Test("统计 provider 状态和错误")
    func countsProviderStatesAndErrors() {
        let calendar = utcCalendar()
        let now = dateTime(2026, 6, 20, hour: 12, minute: 0, calendar: calendar)

        let snapshot = RecentSessionDetailsBuilder.build(
            states: [
                .claude: .init(
                    stats: makeStats(),
                    entries: [],
                    isLoading: false,
                    errorMessage: nil,
                    needsAuthorization: false
                ),
                .codex: .init(
                    stats: nil,
                    entries: nil,
                    isLoading: true,
                    errorMessage: nil,
                    needsAuthorization: false
                ),
                .opencode: .init(
                    stats: nil,
                    entries: nil,
                    isLoading: false,
                    errorMessage: "opencode failed",
                    needsAuthorization: true
                ),
            ],
            period: .recent7Days,
            now: now,
            calendar: calendar
        )

        #expect(snapshot.loadedProviderCount == 1)
        #expect(snapshot.loadingProviderCount == 1)
        #expect(snapshot.unauthorizedProviderCount == 1)
        #expect(snapshot.errorMessages == ["opencode failed"])
    }

    @Test("会话行、模型和快照总量都不重复加入 reasoning")
    func reasoningIsExcludedFromSessionTotals() throws {
        let calendar = utcCalendar()
        let now = dateTime(2026, 6, 20, hour: 12, minute: 0, calendar: calendar)
        let entry = makeEntry(
            provider: .opencode,
            sessionID: "reasoning",
            timestamp: dateTime(2026, 6, 20, hour: 10, minute: 0, calendar: calendar),
            model: "gpt-5",
            input: 100,
            output: 50,
            cacheRead: 20,
            cacheCreation: 10,
            reasoning: 200
        )

        let snapshot = RecentSessionDetailsBuilder.build(
            states: [.opencode: .init(
                stats: nil,
                entries: [entry],
                isLoading: false,
                errorMessage: nil,
                needsAuthorization: false
            )],
            period: .recent7Days,
            now: now,
            calendar: calendar
        )
        let row = try #require(snapshot.rows.first)
        let model = try #require(row.modelBreakdown["gpt-5"])

        #expect(row.reasoningTokens == 200)
        #expect(row.totalTokens == 180)
        #expect(model.reasoningTokens == 200)
        #expect(model.totalTokens == 180)
        #expect(snapshot.totalTokens == 180)
    }

    private func makeEntry(
        provider: ProviderID,
        sessionID: String,
        timestamp: Date?,
        model: String = "test-model",
        input: Int,
        output: Int,
        cacheRead: Int = 0,
        cacheCreation: Int = 0,
        reasoning: Int = 0,
        cwd: String? = nil,
        isSubagent: Bool = false,
        upstreamProviderID: String? = nil
    ) -> ParsedUsageEntry {
        let suffix = [
            provider.rawValue,
            sessionID,
            "\(timestamp?.timeIntervalSince1970 ?? -1)",
            model,
            "\(input)",
            "\(output)",
            "\(cacheRead)",
            "\(cacheCreation)",
            "\(reasoning)",
            cwd ?? "nil",
            upstreamProviderID ?? "nil",
        ].joined(separator: "-")

        return ParsedUsageEntry(
            recordUUID: "record-\(suffix)",
            messageId: "message-\(suffix)",
            requestId: nil,
            sessionID: sessionID,
            timestamp: timestamp,
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
                serviceTier: "",
                cacheCreation: CacheCreation(
                    ephemeral1hInputTokens: 0,
                    ephemeral5mInputTokens: cacheCreation
                ),
                inferenceGeo: "",
                iterations: [],
                speed: ""
            ),
            isSubagent: isSubagent,
            provider: provider,
            upstreamProviderID: upstreamProviderID,
            upstreamCost: nil
        )
    }

    private func makeStats() -> AggregatedStats {
        .zero
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }

    private func dateTime(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
