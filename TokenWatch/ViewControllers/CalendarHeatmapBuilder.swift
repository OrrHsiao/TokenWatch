import Foundation

/// 日历热力图的完整数据快照,供 UI 直接渲染。
struct CalendarHeatmapSnapshot: Sendable {
    let monthKey: String
    let monthTitle: String
    let weekdaySymbols: [String]
    let cells: [CalendarHeatmapCell]
    let monthTotalTokens: Int
    let maxDailyTokens: Int
}

/// 日历热力图网格单元。
enum CalendarHeatmapCell: Sendable {
    case placeholder
    case day(CalendarHeatmapDay)
}

/// 单日热力图数据。
struct CalendarHeatmapDay: Sendable {
    let date: Date
    let dateKey: String
    let day: Int
    let totalTokens: Int
    let intensity: Int
    let isToday: Bool
    let isFuture: Bool
}

/// 将多 provider 统计数据构建为月视图日历热力图快照。
enum CalendarHeatmapBuilder {
    /// 构建指定月份的热力图快照。
    /// - Parameters:
    ///   - states: 各 provider 的统计状态;未授权或无统计数据的 provider 会被忽略。
    ///   - month: 需要展示的月份内任意日期。
    ///   - now: 当前时间,用于判断今天与未来日期。
    ///   - calendar: 调用方指定的日历配置,包含时区与 firstWeekday。
    /// - Returns: 可直接渲染的月历热力图快照。
    static func build(
        states: [ProviderID: TokenStatsViewModel.ProviderState],
        month: Date,
        now: Date,
        calendar: Calendar
    ) -> CalendarHeatmapSnapshot {
        let monthStart = startOfMonth(for: month, calendar: calendar)
        let monthComponents = calendar.dateComponents([.year, .month], from: monthStart)
        let year = monthComponents.year ?? 0
        let monthNumber = monthComponents.month ?? 0
        let monthKey = String(format: "%04d-%02d", year, monthNumber)
        let dayRange = calendar.range(of: .day, in: .month, for: monthStart) ?? 1..<1
        let today = calendar.startOfDay(for: now)

        var dayTotals: [String: Int] = [:]
        var monthTotalTokens = 0
        for state in states.values {
            guard let stats = state.stats else { continue }

            if let monthSummary = stats.byMonth[monthKey] {
                monthTotalTokens += monthSummary.totalTokens
            } else {
                monthTotalTokens += stats.byDay
                    .filter { $0.key.hasPrefix("\(monthKey)-") }
                    .reduce(0) { $0 + $1.value.totalTokens }
            }

            for (dateKey, summary) in stats.byDay where dateKey.hasPrefix("\(monthKey)-") {
                dayTotals[dateKey, default: 0] += summary.totalTokens
            }
        }

        let dayDates = dayRange.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: monthStart)
        }
        let effectiveTotals = dayDates.map { date in
            let key = dateKey(for: date, calendar: calendar)
            return calendar.startOfDay(for: date) > today ? 0 : dayTotals[key, default: 0]
        }
        let maxDailyTokens = effectiveTotals.max() ?? 0

        var cells = Array(repeating: CalendarHeatmapCell.placeholder, count: leadingPlaceholderCount(for: monthStart, calendar: calendar))
        for date in dayDates {
            let key = dateKey(for: date, calendar: calendar)
            let day = calendar.component(.day, from: date)
            let isFuture = calendar.startOfDay(for: date) > today
            let totalTokens = isFuture ? 0 : dayTotals[key, default: 0]
            let heatmapDay = CalendarHeatmapDay(
                date: date,
                dateKey: key,
                day: day,
                totalTokens: totalTokens,
                intensity: intensity(for: totalTokens, maxDailyTokens: maxDailyTokens),
                isToday: calendar.isDate(date, inSameDayAs: today),
                isFuture: isFuture
            )
            cells.append(.day(heatmapDay))
        }

        return CalendarHeatmapSnapshot(
            monthKey: monthKey,
            monthTitle: "\(year) 年 \(monthNumber) 月",
            weekdaySymbols: weekdaySymbols(firstWeekday: calendar.firstWeekday),
            cells: cells,
            monthTotalTokens: monthTotalTokens,
            maxDailyTokens: maxDailyTokens
        )
    }

    private static func startOfMonth(for date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    private static func dateKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private static func leadingPlaceholderCount(for monthStart: Date, calendar: Calendar) -> Int {
        let weekday = calendar.component(.weekday, from: monthStart)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private static func weekdaySymbols(firstWeekday: Int) -> [String] {
        let symbols = ["日", "一", "二", "三", "四", "五", "六"]
        let startIndex = max(0, min(6, firstWeekday - 1))
        return Array(symbols[startIndex...]) + Array(symbols[..<startIndex])
    }

    private static func intensity(for totalTokens: Int, maxDailyTokens: Int) -> Int {
        guard totalTokens > 0, maxDailyTokens > 0 else { return 0 }
        let scaled = Int((Double(totalTokens) / Double(maxDailyTokens) * 4).rounded(.down))
        return max(1, min(4, scaled))
    }
}
