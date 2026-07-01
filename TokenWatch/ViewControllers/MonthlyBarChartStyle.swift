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
        switch language {
        case .zhHans, .zhHant, .ja:
            return "\(year)年\n\(UsageStatsPeriod.shortMonthName(for: month, language: language))"
        case .ko:
            return "\(year)년\n\(UsageStatsPeriod.shortMonthName(for: month, language: language))"
        case .en, .es, .de, .fr, .ptBR, .it, .nl, .pl:
            return "\(year)\n\(UsageStatsPeriod.shortMonthName(for: month, language: language))"
        }
    }

    static func hoverPeriodLabel(
        for monthKey: String,
        fallback: String,
        language: AppLanguage = .zhHans
    ) -> String {
        switch language {
        case .zhHans, .zhHant, .ja, .ko:
            return fallback
        case .en, .es, .de, .fr, .ptBR, .it, .nl, .pl:
            return monthAxisLabel(for: monthKey, language: language)
                .replacingOccurrences(of: "\n", with: " ")
        }
    }

    static func tokenAxisLabel(for value: Double) -> String {
        let tokens = max(0, Int(value.rounded()))
        if tokens < 1_000 {
            return String(tokens)
        }
        if tokens < 1_000_000 {
            return "\(Int((Double(tokens) / 1_000).rounded()))k"
        }
        return "\(Int((Double(tokens) / 1_000_000).rounded()))M"
    }

    static func costAxisLabel(for value: Double) -> String {
        "$\(max(0, Int(value.rounded())))"
    }
}
