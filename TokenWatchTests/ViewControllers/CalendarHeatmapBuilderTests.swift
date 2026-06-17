import Foundation
import Testing
@testable import TokenWatch

@Suite("CalendarHeatmapBuilder")
struct CalendarHeatmapBuilderTests {

    @Test("生成当前月 day cell 并补齐首周 placeholder")
    func buildsCurrentMonthCellsWithLeadingPlaceholders() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2 // Monday

        let snapshot = CalendarHeatmapBuilder.build(
            states: [:],
            month: date(2026, 6, 17, calendar: calendar),
            now: date(2026, 6, 17, calendar: calendar),
            calendar: calendar
        )

        #expect(snapshot.monthKey == "2026-06")
        #expect(snapshot.monthTitle == "2026 年 6 月")
        #expect(snapshot.weekdaySymbols == ["一", "二", "三", "四", "五", "六", "日"])
        #expect(snapshot.cells.count == 30)
        #expect(snapshot.dayCells.count == 30)
        #expect(snapshot.dayCells.first?.dateKey == "2026-06-01")
        #expect(snapshot.dayCells.last?.dateKey == "2026-06-30")
    }

    @Test("按 firstWeekday 生成首周 placeholder")
    func leadingPlaceholdersRespectCalendarFirstWeekday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 1 // Sunday

        let snapshot = CalendarHeatmapBuilder.build(
            states: [:],
            month: date(2026, 6, 17, calendar: calendar),
            now: date(2026, 6, 17, calendar: calendar),
            calendar: calendar
        )

        let placeholders = snapshot.cells.prefix { cell in
            if case .placeholder = cell { return true }
            return false
        }
        #expect(placeholders.count == 1)
        #expect(snapshot.dayCells.first?.dateKey == "2026-06-01")
    }

    @Test("快照、cell、day 支持等值比较和稳定 identity")
    func exposesStableIdentityAndEquatableModels() {
        let calendar = utcCalendar(firstWeekday: 1)
        let snapshot = CalendarHeatmapBuilder.build(
            states: [:],
            month: date(2026, 6, 17, calendar: calendar),
            now: date(2026, 6, 17, calendar: calendar),
            calendar: calendar
        )

        assertSendableEquatable(snapshot)

        let firstCell = snapshot.cells.first
        if case .placeholder(let id)? = firstCell {
            #expect(id == "2026-06-placeholder-0")
            #expect(firstCell?.id == id)
            assertIdentifiable(firstCell)
        } else {
            Issue.record("首个 cell 应为 placeholder")
        }

        let firstDay = snapshot.day("2026-06-01")
        #expect(firstDay?.id == "2026-06-01")
        #expect(firstDay?.dayNumber == 1)
        if let firstDay {
            assertSendableEquatable(firstDay)
            assertIdentifiable(firstDay)
            assertSendableEquatable(CalendarHeatmapCell.day(firstDay))
            assertIdentifiable(CalendarHeatmapCell.day(firstDay))
        }
    }

    @Test("跨 provider 合并 byDay token")
    func sumsDailyTokensAcrossProviders() {
        let calendar = utcCalendar(firstWeekday: 2)
        let claudeStats = makeStats(
            byDay: ["2026-06-10": makeSummary(total: 100)],
            byMonth: ["2026-06": makeSummary(total: 100)]
        )
        let codexStats = makeStats(
            byDay: ["2026-06-10": makeSummary(total: 25)],
            byMonth: ["2026-06": makeSummary(total: 25)]
        )
        let snapshot = CalendarHeatmapBuilder.build(
            states: [
                .claude: .init(stats: claudeStats, isLoading: false, errorMessage: nil, needsAuthorization: false),
                .codex: .init(stats: codexStats, isLoading: false, errorMessage: nil, needsAuthorization: false),
                .opencode: .init(stats: nil, isLoading: false, errorMessage: nil, needsAuthorization: true),
            ],
            month: date(2026, 6, 17, calendar: calendar),
            now: date(2026, 6, 17, calendar: calendar),
            calendar: calendar
        )

        #expect(snapshot.day("2026-06-10")?.totalTokens == 125)
        #expect(snapshot.monthTotalTokens == 125)
    }

    @Test("缺失日期补 0")
    func missingDayBucketsAreZero() {
        let calendar = utcCalendar(firstWeekday: 2)
        let stats = makeStats(
            byDay: ["2026-06-05": makeSummary(total: 300)],
            byMonth: ["2026-06": makeSummary(total: 300)]
        )

        let snapshot = CalendarHeatmapBuilder.build(
            states: [.claude: .init(stats: stats, isLoading: false, errorMessage: nil, needsAuthorization: false)],
            month: date(2026, 6, 17, calendar: calendar),
            now: date(2026, 6, 17, calendar: calendar),
            calendar: calendar
        )

        #expect(snapshot.day("2026-06-04")?.totalTokens == 0)
        #expect(snapshot.day("2026-06-05")?.totalTokens == 300)
    }

    @Test("优先使用 byMonth 作为月总量")
    func usesByMonthForMonthTotalWhenPresent() {
        let calendar = utcCalendar(firstWeekday: 2)
        let stats = makeStats(
            byDay: ["2026-06-01": makeSummary(total: 10)],
            byMonth: ["2026-06": makeSummary(total: 999)]
        )

        let snapshot = CalendarHeatmapBuilder.build(
            states: [.claude: .init(stats: stats, isLoading: false, errorMessage: nil, needsAuthorization: false)],
            month: date(2026, 6, 17, calendar: calendar),
            now: date(2026, 6, 17, calendar: calendar),
            calendar: calendar
        )

        #expect(snapshot.monthTotalTokens == 999)
    }

    @Test("byMonth 缺失时用本月 byDay fallback")
    func fallsBackToCurrentMonthDaySumWhenMonthBucketMissing() {
        let calendar = utcCalendar(firstWeekday: 2)
        let stats = makeStats(
            byDay: [
                "2026-06-01": makeSummary(total: 10),
                "2026-06-02": makeSummary(total: 20),
                "2026-05-31": makeSummary(total: 999),
            ],
            byMonth: [:]
        )

        let snapshot = CalendarHeatmapBuilder.build(
            states: [.claude: .init(stats: stats, isLoading: false, errorMessage: nil, needsAuthorization: false)],
            month: date(2026, 6, 17, calendar: calendar),
            now: date(2026, 6, 17, calendar: calendar),
            calendar: calendar
        )

        #expect(snapshot.monthTotalTokens == 30)
    }

    @Test("token 强度映射到 0...4")
    func intensityUsesDailyMaximum() {
        let calendar = utcCalendar(firstWeekday: 2)
        let stats = makeStats(
            byDay: [
                "2026-06-01": makeSummary(total: 0),
                "2026-06-02": makeSummary(total: 1),
                "2026-06-03": makeSummary(total: 26),
                "2026-06-04": makeSummary(total: 50),
                "2026-06-05": makeSummary(total: 100),
            ],
            byMonth: ["2026-06": makeSummary(total: 176)]
        )

        let snapshot = CalendarHeatmapBuilder.build(
            states: [.claude: .init(stats: stats, isLoading: false, errorMessage: nil, needsAuthorization: false)],
            month: date(2026, 6, 17, calendar: calendar),
            now: date(2026, 6, 17, calendar: calendar),
            calendar: calendar
        )

        #expect(snapshot.maxDailyTokens == 100)
        #expect(snapshot.day("2026-06-01")?.intensity == 0)
        #expect(snapshot.day("2026-06-02")?.intensity == 1)
        #expect(snapshot.day("2026-06-03")?.intensity == 2)
        #expect(snapshot.day("2026-06-04")?.intensity == 2)
        #expect(snapshot.day("2026-06-05")?.intensity == 4)
    }

    @Test("未来日期弱化并视作 0")
    func futureDaysAreZeroIntensity() {
        let calendar = utcCalendar(firstWeekday: 2)
        let stats = makeStats(
            byDay: ["2026-06-20": makeSummary(total: 1_000)],
            byMonth: ["2026-06": makeSummary(total: 1_000)]
        )

        let snapshot = CalendarHeatmapBuilder.build(
            states: [.claude: .init(stats: stats, isLoading: false, errorMessage: nil, needsAuthorization: false)],
            month: date(2026, 6, 1, calendar: calendar),
            now: date(2026, 6, 17, calendar: calendar),
            calendar: calendar
        )

        #expect(snapshot.day("2026-06-20")?.isFuture == true)
        #expect(snapshot.day("2026-06-20")?.totalTokens == 0)
        #expect(snapshot.day("2026-06-20")?.intensity == 0)
    }

    private func utcCalendar(firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
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
        byDay: [String: UsageSummary],
        byMonth: [String: UsageSummary]
    ) -> AggregatedStats {
        AggregatedStats(
            overall: .zero,
            byHour: [:],
            byDay: byDay,
            byWeek: [:],
            byMonth: byMonth,
            bySession: [:],
            byModel: [:],
            byProject: [:],
            dataSourceCount: 1
        )
    }
}

private extension CalendarHeatmapSnapshot {
    var dayCells: [CalendarHeatmapDay] {
        cells.compactMap { cell in
            if case .day(let day) = cell { return day }
            return nil
        }
    }

    func day(_ key: String) -> CalendarHeatmapDay? {
        dayCells.first { $0.dateKey == key }
    }
}

private func assertSendableEquatable<T: Sendable & Equatable>(_ value: T) {
    #expect(value == value)
}

private func assertIdentifiable<T: Identifiable>(_ value: T?) {
    _ = value?.id
}
