import Foundation

/// 日历热力图的完整数据快照,供 UI 直接渲染。
struct CalendarHeatmapSnapshot: Sendable, Equatable {
    let monthKey: String
    let monthTitle: String
    let weekdaySymbols: [String]
    let cells: [CalendarHeatmapCell]
    let monthTotalTokens: Int
    let maxDailyTokens: Int
}

/// 日历热力图网格单元。
enum CalendarHeatmapCell: Sendable, Equatable, Identifiable {
    case placeholder(id: String)
    case day(CalendarHeatmapDay)

    var id: String {
        switch self {
        case .placeholder(let id):
            id
        case .day(let day):
            day.id
        }
    }
}

/// 单日热力图数据。
struct CalendarHeatmapDay: Sendable, Equatable, Identifiable {
    let id: String
    let date: Date
    let dateKey: String
    let dayNumber: Int
    let totalTokens: Int
    let intensity: Int
    let isToday: Bool
    let isFuture: Bool
}

/// 将多 provider 统计数据构建为最近五个月日历热力图快照。
enum CalendarHeatmapBuilder {
    /// 构建以指定日期为终点的最近五个月热力图快照。
    /// - Parameters:
    ///   - states: 各 provider 的统计状态;未授权或无统计数据的 provider 会被忽略。
    ///   - month: 窗口终点所在日期;保留旧参数名以兼容现有调用点。
    ///   - now: 当前时间,用于防止生成未来日期。
    ///   - calendar: 调用方指定的日历配置,包含时区与 firstWeekday。
    /// - Returns: 可直接渲染的近五个月热力图快照。
    static func build(
        states: [ProviderID: TokenStatsViewModel.ProviderState],
        month: Date,
        now: Date,
        calendar: Calendar
    ) -> CalendarHeatmapSnapshot {
        let today = calendar.startOfDay(for: now)
        let requestedEnd = calendar.startOfDay(for: month)
        let rangeEnd = min(requestedEnd, today)
        let rangeStart = calendar.startOfDay(
            for: calendar.date(byAdding: .month, value: -5, to: rangeEnd) ?? rangeEnd
        )
        let rangeStartKey = dateKey(for: rangeStart, calendar: calendar)
        let rangeEndKey = dateKey(for: rangeEnd, calendar: calendar)
        let rangeKey = "\(rangeStartKey)...\(rangeEndKey)"

        var dayTotals: [String: Int] = [:]
        for state in states.values {
            guard let stats = state.stats else { continue }

            for (dateKey, summary) in stats.byDay
            where dateKey >= rangeStartKey && dateKey <= rangeEndKey {
                dayTotals[dateKey, default: 0] += summary.totalTokens
            }
        }

        let dayDates = dates(from: rangeStart, through: rangeEnd, calendar: calendar)
        let effectiveTotals = dayDates.map { date in
            let key = dateKey(for: date, calendar: calendar)
            return dayTotals[key, default: 0]
        }
        let monthTotalTokens = effectiveTotals.reduce(0, +)
        let maxDailyTokens = effectiveTotals.max() ?? 0

        let alignedStart = calendar.date(
            byAdding: .day,
            value: -leadingPlaceholderCount(for: rangeStart, calendar: calendar),
            to: rangeStart
        ) ?? rangeStart
        let alignedEnd = calendar.date(
            byAdding: .day,
            value: trailingPlaceholderCount(for: rangeEnd, calendar: calendar),
            to: rangeEnd
        ) ?? rangeEnd

        var placeholderIndex = 0
        let cells = dates(from: alignedStart, through: alignedEnd, calendar: calendar).map { date in
            guard date >= rangeStart && date <= rangeEnd else {
                let cell = CalendarHeatmapCell.placeholder(id: "\(rangeKey)-placeholder-\(placeholderIndex)")
                placeholderIndex += 1
                return cell
            }

            let key = dateKey(for: date, calendar: calendar)
            let dayNumber = calendar.component(.day, from: date)
            let isFuture = date > today
            let totalTokens = isFuture ? 0 : dayTotals[key, default: 0]
            let heatmapDay = CalendarHeatmapDay(
                id: key,
                date: date,
                dateKey: key,
                dayNumber: dayNumber,
                totalTokens: totalTokens,
                intensity: intensity(for: totalTokens, maxDailyTokens: maxDailyTokens),
                isToday: calendar.isDate(date, inSameDayAs: today),
                isFuture: isFuture
            )
            return .day(heatmapDay)
        }

        return CalendarHeatmapSnapshot(
            monthKey: rangeKey,
            monthTitle: "最近 5 个月",
            weekdaySymbols: weekdaySymbols(firstWeekday: calendar.firstWeekday),
            cells: cells,
            monthTotalTokens: monthTotalTokens,
            maxDailyTokens: maxDailyTokens
        )
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

    private static func trailingPlaceholderCount(for rangeEnd: Date, calendar: Calendar) -> Int {
        let weekdayIndex = leadingPlaceholderCount(for: rangeEnd, calendar: calendar)
        return 6 - weekdayIndex
    }

    private static func dates(from startDate: Date, through endDate: Date, calendar: Calendar) -> [Date] {
        var dates: [Date] = []
        var current = startDate

        while current <= endDate {
            dates.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current),
                  next > current else {
                break
            }
            current = next
        }

        return dates
    }

    private static func weekdaySymbols(firstWeekday: Int) -> [String] {
        let symbols = ["日", "一", "二", "三", "四", "五", "六"]
        let startIndex = max(0, min(6, firstWeekday - 1))
        return Array(symbols[startIndex...]) + Array(symbols[..<startIndex])
    }

    private static func intensity(for totalTokens: Int, maxDailyTokens: Int) -> Int {
        guard totalTokens > 0, maxDailyTokens > 0 else { return 0 }
        let scaled = Int(ceil(Double(totalTokens) / Double(maxDailyTokens) * 4.0))
        return max(1, min(4, scaled))
    }
}
