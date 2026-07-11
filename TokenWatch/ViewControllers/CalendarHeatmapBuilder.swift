import Foundation

/// 日历热力图的完整数据快照,供 UI 直接渲染。
struct CalendarHeatmapSnapshot: Sendable, Equatable {
    let monthKey: String
    let monthTitle: String
    let weekdaySymbols: [String]
    let cells: [CalendarHeatmapCell]
    let summary: CalendarHeatmapSummary
    let monthTotalTokens: Int
    let maxDailyTokens: Int
}

/// 热力图上方摘要统计。
struct CalendarHeatmapSummary: Sendable, Equatable {
    let monthTokens: Int
    let weekTokens: Int
    let todayTokens: Int
    let averageDailyTokens: Int
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

/// 将多 provider 统计数据构建为固定周列日历热力图快照。
enum CalendarHeatmapBuilder {
    private static let columnCount = 22
    private static let rowCount = 7

    /// 构建以指定日期所在周为终点的 22 列热力图快照。
    /// - Parameters:
    ///   - states: 各 provider 的统计状态;未授权或无统计数据的 provider 会被忽略。
    ///   - month: 窗口终点所在日期;保留旧参数名以兼容现有调用点。
    ///   - now: 当前时间,用于防止生成未来日期。
    ///   - calendar: 调用方指定的日历配置,包含时区与 firstWeekday。
    ///   - language: 快照中文案使用的语言。
    /// - Returns: 可直接渲染的近 22 周热力图快照。
    static func build(
        states: [ProviderID: TokenStatsViewModel.ProviderState],
        month: Date,
        now: Date,
        calendar: Calendar,
        language: AppLanguage = .zhHans
    ) -> CalendarHeatmapSnapshot {
        let today = calendar.startOfDay(for: now)
        let requestedEnd = calendar.startOfDay(for: month)
        let rangeEnd = min(requestedEnd, today)
        let alignedEnd = calendar.date(
            byAdding: .day,
            value: trailingPlaceholderCount(for: rangeEnd, calendar: calendar),
            to: rangeEnd
        ) ?? rangeEnd
        let rangeStart = calendar.date(
            byAdding: .day,
            value: -(columnCount * rowCount - 1),
            to: alignedEnd
        ) ?? rangeEnd
        let rangeStartKey = dateKey(for: rangeStart, calendar: calendar)
        let rangeEndKey = dateKey(for: rangeEnd, calendar: calendar)
        let rangeKey = "\(rangeStartKey)...\(rangeEndKey)"

        var dayTotals: [String: Int] = [:]
        for state in states.values {
            guard let stats = state.stats else { continue }

            for (dateKey, summary) in stats.byDay
            where dateKey >= rangeStartKey && dateKey <= rangeEndKey {
                dayTotals[dateKey, default: 0] = dayTotals[dateKey, default: 0]
                    .addingSaturated(summary.totalTokens)
            }
        }

        let dayDates = dates(from: rangeStart, through: rangeEnd, calendar: calendar)
        let effectiveTotals = dayDates.map { date in
            let key = dateKey(for: date, calendar: calendar)
            return dayTotals[key, default: 0]
        }
        let monthTotalTokens = effectiveTotals.reduce(0) { $0.addingSaturated($1) }
        let maxDailyTokens = effectiveTotals.max() ?? 0

        var placeholderIndex = 0
        let cells = dates(from: rangeStart, through: alignedEnd, calendar: calendar).map { date in
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
            monthTitle: AppStrings.text(.heatmapRecent22Weeks, language: language),
            weekdaySymbols: weekdaySymbols(firstWeekday: calendar.firstWeekday, language: language),
            cells: cells,
            summary: summary(states: states, now: now, calendar: calendar),
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

    private static func summary(
        states: [ProviderID: TokenStatsViewModel.ProviderState],
        now: Date,
        calendar: Calendar
    ) -> CalendarHeatmapSummary {
        let today = calendar.startOfDay(for: now)
        let todayKey = dateKey(for: today, calendar: calendar)
        let monthStart = calendar.dateInterval(of: .month, for: today)?.start ?? today
        let weekStart = calendar.date(
            byAdding: .day,
            value: -leadingPlaceholderCount(for: today, calendar: calendar),
            to: today
        ) ?? today

        let monthTokens = totalTokens(
            states: states,
            from: dateKey(for: monthStart, calendar: calendar),
            through: todayKey
        )
        let weekTokens = totalTokens(
            states: states,
            from: dateKey(for: weekStart, calendar: calendar),
            through: todayKey
        )
        let todayTokens = totalTokens(states: states, on: todayKey)
        let elapsedDays = max(1, (calendar.dateComponents([.day], from: monthStart, to: today).day ?? 0) + 1)

        return CalendarHeatmapSummary(
            monthTokens: monthTokens,
            weekTokens: weekTokens,
            todayTokens: todayTokens,
            averageDailyTokens: monthTokens / elapsedDays
        )
    }

    private static func totalTokens(
        states: [ProviderID: TokenStatsViewModel.ProviderState],
        from startKey: String,
        through endKey: String
    ) -> Int {
        states.values.reduce(0) { total, state in
            guard let stats = state.stats else { return total }
            let providerTotal = stats.byDay.reduce(0) { partial, entry in
                guard entry.key >= startKey, entry.key <= endKey else { return partial }
                return partial.addingSaturated(entry.value.totalTokens)
            }
            return total.addingSaturated(providerTotal)
        }
    }

    private static func totalTokens(
        states: [ProviderID: TokenStatsViewModel.ProviderState],
        on dateKey: String
    ) -> Int {
        states.values.reduce(0) { total, state in
            total.addingSaturated(state.stats?.byDay[dateKey]?.totalTokens ?? 0)
        }
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

    private static func weekdaySymbols(firstWeekday: Int, language: AppLanguage) -> [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.localeIdentifier)
        let symbols: [String]
        switch language {
        case .zhHans, .zhHant, .ja, .ko:
            symbols = formatter.veryShortStandaloneWeekdaySymbols ?? []
        case .en, .es, .de, .fr, .ptBR, .it, .nl, .pl:
            symbols = formatter.shortStandaloneWeekdaySymbols ?? []
        }
        guard symbols.count == 7 else {
            return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        }
        let startIndex = max(0, min(6, firstWeekday - 1))
        return Array(symbols[startIndex...]) + Array(symbols[..<startIndex])
    }

    private static func intensity(for totalTokens: Int, maxDailyTokens: Int) -> Int {
        guard totalTokens > 0, maxDailyTokens > 0 else { return 0 }
        let scaled = Int(ceil(Double(totalTokens) / Double(maxDailyTokens) * 4.0))
        return max(1, min(4, scaled))
    }
}
