import Foundation
import Testing
@testable import TokenWatch

@MainActor
@Suite("WidgetSnapshotBuilder")
struct WidgetSnapshotBuilderTests {

    @Test("有 token 数据时构建 ready 快照并映射热力图和今日折线")
    func buildsReadySnapshotFromTokenData() {
        let calendar = utcCalendar(firstWeekday: 2)
        let now = dateTime(2026, 6, 17, hour: 14, minute: 30, calendar: calendar)
        let states: [ProviderID: TokenStatsViewModel.ProviderState] = [
            .claude: .init(
                stats: makeStats(
                    byHour: [
                        "2026-06-17T10": makeSummary(total: 1_000),
                        "2026-06-17T14": makeSummary(total: 2_000),
                    ],
                    byDay: [
                        "2026-06-10": makeSummary(total: 500),
                        "2026-06-17": makeSummary(total: 2_000),
                    ]
                ),
                isLoading: false,
                errorMessage: nil,
                needsAuthorization: false
            ),
            .codex: .init(
                stats: makeStats(
                    byHour: ["2026-06-17T14": makeSummary(total: 99_000)],
                    byDay: ["2026-06-17": makeSummary(total: 99_000)]
                ),
                isLoading: false,
                errorMessage: nil,
                needsAuthorization: true
            ),
        ]

        let snapshot = WidgetSnapshotBuilder.build(
            states: states,
            now: now,
            calendar: calendar,
            language: .ptBR
        )

        #expect(snapshot.generatedAt == now)
        #expect(snapshot.languageIdentifier == "pt-BR")
        #expect(snapshot.status == .ready)
        #expect(snapshot.heatmap.title == "Últimas 22 semanas")
        #expect(snapshot.heatmap.summary.monthTokens == 2_500)
        #expect(snapshot.heatmap.summary.weekTokens == 2_000)
        #expect(snapshot.heatmap.summary.todayTokens == 2_000)
        #expect(snapshot.heatmap.maxDailyTokens == 2_000)
        #expect(snapshot.heatmap.cells.count == 154)
        #expect(snapshot.todayLine.totalTokens == 3_000)
        #expect(snapshot.todayLine.maxHourlyTokens == 2_000)
        #expect(snapshot.todayLine.currentHourKey == "2026-06-17T14")
        #expect(snapshot.todayLine.buckets.count == 24)
        #expect(snapshot.todayLine.bucket("2026-06-17T10")?.normalizedHeight == 0.5)
        #expect(snapshot.todayLine.bucket("2026-06-17T14")?.isCurrentHour == true)
        #expect(snapshot.todayLine.bucket("2026-06-17T14")?.totalTokens == 2_000)

        let todayCell = snapshot.heatmap.cell(dateKey: "2026-06-17")
        #expect(todayCell?.kind == .day)
        #expect(todayCell?.dateKey == "2026-06-17")
        #expect(todayCell?.totalTokens == 2_000)
        #expect(todayCell?.isToday == true)
        #expect(todayCell?.isFuture == false)

        let placeholder = snapshot.heatmap.cells.last
        #expect(placeholder?.kind == .placeholder)
        #expect(placeholder?.dateKey == nil)
        #expect(placeholder?.totalTokens == 0)
        #expect(placeholder?.intensity == 0)
        #expect(placeholder?.isToday == false)
        #expect(placeholder?.isFuture == false)
    }

    @Test("全部已知 provider 未授权时返回 needsAuthorization 并保留空 shape")
    func buildsNeedsAuthorizationSnapshotWhenAllKnownProvidersNeedAuthorization() {
        let calendar = utcCalendar(firstWeekday: 2)
        let now = dateTime(2026, 6, 17, hour: 14, minute: 30, calendar: calendar)
        let states = Dictionary(uniqueKeysWithValues: knownProviderIDs().map {
            ($0, TokenStatsViewModel.ProviderState(
                stats: nil,
                isLoading: false,
                errorMessage: nil,
                needsAuthorization: true
            ))
        })

        let snapshot = WidgetSnapshotBuilder.build(
            states: states,
            now: now,
            calendar: calendar,
            language: .en
        )

        #expect(snapshot.status == .needsAuthorization)
        #expect(snapshot.languageIdentifier == "en")
        #expect(snapshot.heatmap.cells.count == 154)
        #expect(snapshot.heatmap.cells.allSatisfy { $0.totalTokens == 0 })
        #expect(snapshot.todayLine.buckets.count == 24)
        #expect(snapshot.todayLine.buckets.allSatisfy { $0.totalTokens == 0 })
    }

    @Test("全部 provider 未授权但保留旧 stats 时不发布旧 token")
    func ignoresStaleStatsWhenAllKnownProvidersNeedAuthorization() {
        let calendar = utcCalendar(firstWeekday: 2)
        let now = dateTime(2026, 6, 17, hour: 14, minute: 30, calendar: calendar)
        let staleStats = makeStats(
            byHour: ["2026-06-17T14": makeSummary(total: 8_000)],
            byDay: ["2026-06-17": makeSummary(total: 8_000)]
        )
        let states = Dictionary(uniqueKeysWithValues: knownProviderIDs().map {
            ($0, TokenStatsViewModel.ProviderState(
                stats: staleStats,
                isLoading: false,
                errorMessage: nil,
                needsAuthorization: true
            ))
        })

        let snapshot = WidgetSnapshotBuilder.build(
            states: states,
            now: now,
            calendar: calendar,
            language: .zhHans
        )

        #expect(snapshot.status == .needsAuthorization)
        #expect(snapshot.heatmap.summary.monthTokens == 0)
        #expect(snapshot.heatmap.summary.weekTokens == 0)
        #expect(snapshot.heatmap.summary.todayTokens == 0)
        #expect(snapshot.heatmap.maxDailyTokens == 0)
        #expect(snapshot.heatmap.cells.allSatisfy { $0.totalTokens == 0 })
        #expect(snapshot.todayLine.totalTokens == 0)
        #expect(snapshot.todayLine.maxHourlyTokens == 0)
        #expect(snapshot.todayLine.buckets.allSatisfy { $0.totalTokens == 0 })
    }

    @Test("已授权但没有 token 数据时返回 empty")
    func buildsEmptySnapshotWhenAuthorizedStatsHaveNoTokenData() {
        let calendar = utcCalendar(firstWeekday: 2)
        let now = dateTime(2026, 6, 17, hour: 14, minute: 30, calendar: calendar)
        let states: [ProviderID: TokenStatsViewModel.ProviderState] = [
            .claude: .init(stats: .zero, isLoading: false, errorMessage: nil, needsAuthorization: false),
        ]

        let snapshot = WidgetSnapshotBuilder.build(
            states: states,
            now: now,
            calendar: calendar,
            language: .zhHans
        )

        #expect(snapshot.status == .empty)
        #expect(snapshot.heatmap.summary.monthTokens == 0)
        #expect(snapshot.heatmap.maxDailyTokens == 0)
        #expect(snapshot.todayLine.totalTokens == 0)
        #expect(snapshot.todayLine.maxHourlyTokens == 0)
    }

    @Test("没有任何 stats 时返回 empty")
    func buildsEmptySnapshotWhenNoStatsExist() {
        let calendar = utcCalendar(firstWeekday: 2)
        let now = dateTime(2026, 6, 17, hour: 14, minute: 30, calendar: calendar)
        let states: [ProviderID: TokenStatsViewModel.ProviderState] = [
            .claude: .init(stats: nil, isLoading: false, errorMessage: nil, needsAuthorization: false),
        ]

        let snapshot = WidgetSnapshotBuilder.build(
            states: states,
            now: now,
            calendar: calendar,
            language: .zhHans
        )

        #expect(snapshot.status == .empty)
        #expect(snapshot.heatmap.cells.count == 154)
        #expect(snapshot.todayLine.buckets.count == 24)
    }

    @Test("历史二十二周窗口内有数据但今日为零时仍返回 ready")
    func remainsReadyWhenHistoricalHeatmapWindowHasDataButTodayIsZero() {
        let calendar = utcCalendar(firstWeekday: 2)
        let now = dateTime(2026, 6, 17, hour: 14, minute: 30, calendar: calendar)
        let states: [ProviderID: TokenStatsViewModel.ProviderState] = [
            .claude: .init(
                stats: makeStats(byDay: ["2026-02-10": makeSummary(total: 900)]),
                isLoading: false,
                errorMessage: nil,
                needsAuthorization: false
            ),
        ]

        let snapshot = WidgetSnapshotBuilder.build(
            states: states,
            now: now,
            calendar: calendar,
            language: .zhHans
        )

        #expect(snapshot.status == .ready)
        #expect(snapshot.heatmap.summary.monthTokens == 0)
        #expect(snapshot.todayLine.totalTokens == 0)
        #expect(snapshot.heatmap.cell(dateKey: "2026-02-10")?.totalTokens == 900)
    }

    private func utcCalendar(firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = firstWeekday
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

    private func makeSummary(total: Int) -> UsageSummary {
        UsageSummary(
            inputTokens: total,
            outputTokens: 0,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            reasoningTokens: 0,
            totalTokens: total,
            cost: 0,
            entryCount: 1,
            modelBreakdown: [:]
        )
    }

    private func makeStats(
        byHour: [String: UsageSummary] = [:],
        byDay: [String: UsageSummary] = [:]
    ) -> AggregatedStats {
        let overallTotal = max(totalTokens(in: byHour), totalTokens(in: byDay))
        return AggregatedStats(
            overall: makeSummary(total: overallTotal),
            byHour: byHour,
            byDay: byDay,
            byWeek: [:],
            byMonth: [:],
            bySession: [:],
            byModel: [:],
            byProject: [:],
            dataSourceCount: 1
        )
    }

    private func totalTokens(in summaries: [String: UsageSummary]) -> Int {
        summaries.values.reduce(0) { $0 + $1.totalTokens }
    }

    private func knownProviderIDs() -> [ProviderID] {
        ProviderRegistry.allProviders.map(\.id)
    }
}

private extension TokenWatchWidgetHeatmapSnapshot {
    func cell(dateKey: String) -> TokenWatchWidgetHeatmapCell? {
        cells.first { $0.dateKey == dateKey }
    }
}

private extension TokenWatchWidgetTodayLineSnapshot {
    func bucket(_ hourKey: String) -> TokenWatchWidgetTodayLineBucket? {
        buckets.first { $0.hourKey == hourKey }
    }
}
