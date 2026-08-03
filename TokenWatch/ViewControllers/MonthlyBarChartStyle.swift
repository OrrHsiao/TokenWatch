import Foundation

enum MonthlyBarChartStyle {
    static func monthAxisLabel(for monthKey: String, language: AppLanguage = .zhHans) -> String {
        if let hourSeparatorRange = monthKey.range(of: "T"),
           let hour = Int(monthKey[hourSeparatorRange.upperBound...]) {
            return "\(hour)"
        }

        let parts = monthKey.split(separator: "-")
        if parts.count == 3,
           let month = Int(parts[1]),
           let day = Int(parts[2]) {
            return "\(month)/\n\(day)"
        }
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]) else {
            return monthKey
        }
        let yearLabel = language.yearAxisSuffix.map { "\(year)\($0)" } ?? "\(year)"
        return "\(yearLabel)\n\(UsageStatsPeriod.shortMonthName(for: month, language: language))"
    }

    static func hoverPeriodLabel(
        for monthKey: String,
        fallback: String,
        language: AppLanguage = .zhHans
    ) -> String {
        if language.usesCompactCJKFormatting {
            return fallback
        }
        return monthAxisLabel(for: monthKey, language: language)
            .replacingOccurrences(of: "\n", with: " ")
    }

    static func tokenAxisLabel(for value: Double) -> String {
        WidgetChartNumberFormatter.axis(value)
    }

    static func costAxisLabel(for value: Double) -> String {
        guard value.isFinite, value > 0 else { return "$0" }
        return String(
            format: "$%.0f",
            locale: Locale(identifier: "en_US_POSIX"),
            value.rounded()
        )
    }
}
