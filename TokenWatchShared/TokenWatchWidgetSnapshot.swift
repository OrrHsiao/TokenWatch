import Foundation

enum TokenWatchWidgetDataStatus: String, Codable, Equatable, Sendable {
    case ready
    case needsAuthorization
    case empty
}

struct TokenWatchWidgetSnapshot: Codable, Equatable, Sendable {
    let generatedAt: Date
    let languageIdentifier: String
    let status: TokenWatchWidgetDataStatus
    let heatmap: TokenWatchWidgetHeatmapSnapshot
    let todayLine: TokenWatchWidgetTodayLineSnapshot

    static func empty(
        generatedAt: Date = Date(),
        languageIdentifier: String = "zh-Hans",
        status: TokenWatchWidgetDataStatus = .empty
    ) -> TokenWatchWidgetSnapshot {
        TokenWatchWidgetSnapshot(
            generatedAt: generatedAt,
            languageIdentifier: languageIdentifier,
            status: status,
            heatmap: .empty(title: TokenWatchWidgetCopy.text(.recent22Weeks, languageIdentifier: languageIdentifier)),
            todayLine: .empty()
        )
    }

    static func sample(
        generatedAt: Date = Date(),
        languageIdentifier: String = "zh-Hans"
    ) -> TokenWatchWidgetSnapshot {
        let heatmapCells = (0..<154).map { index in
            TokenWatchWidgetHeatmapCell(
                id: "sample-\(index)",
                kind: .day,
                dateKey: "2026-06-\((index % 27) + 1)",
                totalTokens: index % 5 == 0 ? 0 : (index + 1) * 12_345,
                intensity: index % 5,
                isToday: index == 153,
                isFuture: false
            )
        }
        var hourlyBuckets: [TokenWatchWidgetTodayLineBucket] = []
        hourlyBuckets.reserveCapacity(24)
        for hour in 0..<24 {
            let hourKey = String(format: "2026-06-27T%02d", hour)
            let totalTokens = hour <= 14 ? (hour + 1) * 42_000 : 0
            let normalizedHeight = hour <= 14 ? Double(hour + 1) / 15.0 : 0
            hourlyBuckets.append(
                TokenWatchWidgetTodayLineBucket(
                    id: hourKey,
                    hourKey: hourKey,
                    hourLabel: "\(hour)",
                    totalTokens: totalTokens,
                    normalizedHeight: normalizedHeight,
                    isCurrentHour: hour == 14
                )
            )
        }

        return TokenWatchWidgetSnapshot(
            generatedAt: generatedAt,
            languageIdentifier: languageIdentifier,
            status: .ready,
            heatmap: TokenWatchWidgetHeatmapSnapshot(
                title: TokenWatchWidgetCopy.text(.recent22Weeks, languageIdentifier: languageIdentifier),
                summary: TokenWatchWidgetHeatmapSummary(
                    monthTokens: 3_200_000,
                    weekTokens: 820_000,
                    todayTokens: 630_000,
                    averageDailyTokens: 118_000
                ),
                cells: heatmapCells,
                maxDailyTokens: 1_900_000
            ),
            todayLine: TokenWatchWidgetTodayLineSnapshot(
                totalTokens: hourlyBuckets.reduce(0) { $0 + $1.totalTokens },
                maxHourlyTokens: hourlyBuckets.map { $0.totalTokens }.max() ?? 0,
                currentHourKey: "2026-06-27T14",
                buckets: hourlyBuckets
            )
        )
    }
}

struct TokenWatchWidgetHeatmapSnapshot: Codable, Equatable, Sendable {
    let title: String
    let summary: TokenWatchWidgetHeatmapSummary
    let cells: [TokenWatchWidgetHeatmapCell]
    let maxDailyTokens: Int

    static func empty(title: String) -> TokenWatchWidgetHeatmapSnapshot {
        TokenWatchWidgetHeatmapSnapshot(
            title: title,
            summary: TokenWatchWidgetHeatmapSummary(
                monthTokens: 0,
                weekTokens: 0,
                todayTokens: 0,
                averageDailyTokens: 0
            ),
            cells: (0..<154).map {
                TokenWatchWidgetHeatmapCell(
                    id: "empty-\($0)",
                    kind: .placeholder,
                    dateKey: nil,
                    totalTokens: 0,
                    intensity: 0,
                    isToday: false,
                    isFuture: false
                )
            },
            maxDailyTokens: 0
        )
    }
}

struct TokenWatchWidgetHeatmapSummary: Codable, Equatable, Sendable {
    let monthTokens: Int
    let weekTokens: Int
    let todayTokens: Int
    let averageDailyTokens: Int
}

enum TokenWatchWidgetHeatmapCellKind: String, Codable, Equatable, Sendable {
    case placeholder
    case day
}

struct TokenWatchWidgetHeatmapCell: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let kind: TokenWatchWidgetHeatmapCellKind
    let dateKey: String?
    let totalTokens: Int
    let intensity: Int
    let isToday: Bool
    let isFuture: Bool
}

struct TokenWatchWidgetTodayLineSnapshot: Codable, Equatable, Sendable {
    let totalTokens: Int
    let maxHourlyTokens: Int
    let currentHourKey: String?
    let buckets: [TokenWatchWidgetTodayLineBucket]

    static func empty() -> TokenWatchWidgetTodayLineSnapshot {
        let buckets = (0..<24).map { hour in
            TokenWatchWidgetTodayLineBucket(
                id: String(format: "empty-%02d", hour),
                hourKey: String(format: "empty-%02d", hour),
                hourLabel: "\(hour)",
                totalTokens: 0,
                normalizedHeight: 0,
                isCurrentHour: false
            )
        }
        return TokenWatchWidgetTodayLineSnapshot(
            totalTokens: 0,
            maxHourlyTokens: 0,
            currentHourKey: nil,
            buckets: buckets
        )
    }
}

struct TokenWatchWidgetTodayLineBucket: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let hourKey: String
    let hourLabel: String
    let totalTokens: Int
    let normalizedHeight: Double
    let isCurrentHour: Bool
}

enum TokenWatchWidgetCompactNumberFormatter {
    static func format(_ value: Int) -> String {
        guard value > 0 else { return "0" }
        if value < 1_000 { return String(value) }
        if value < 1_000_000 {
            let tenths = value / 100
            return "\(tenths / 10).\(tenths % 10)k"
        }
        let tenths = value / 100_000
        return "\(tenths / 10).\(tenths % 10)M"
    }

    static func formatMillions(_ value: Int) -> String {
        let tenths = max(value, 0) / 100_000
        return "\(tenths / 10).\(tenths % 10)M"
    }

    static func formatHoverTokens(_ value: Int) -> String {
        let safeValue = max(value, 0)
        if safeValue > 0 && safeValue < 100_000 {
            let tenths = safeValue / 100
            return "\(tenths / 10).\(tenths % 10)k"
        }
        return formatMillions(safeValue)
    }
}

enum TokenWatchWidgetCopyKey: Hashable, Sendable {
    case recent22Weeks
    case month
    case week
    case today
    case dailyAverage
    case peakHour
    case updated
    case openAppToAuthorize
    case waitingForRefresh
    case noTokenData
    case dataMayBeStale
    case tokenHeatmapDisplayName
    case tokenHeatmapDescription
    case todayLineDisplayName
    case todayLineDescription
}

enum TokenWatchWidgetCopy {
    static func text(_ key: TokenWatchWidgetCopyKey, languageIdentifier: String) -> String {
        let normalized = languageIdentifier
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
        if isTraditionalChinese(normalized) { return zhHant[key] ?? en[key] ?? String(describing: key) }
        if normalized.hasPrefix("zh") { return zhHans[key] ?? en[key] ?? String(describing: key) }
        return en[key] ?? String(describing: key)
    }

    private static func isTraditionalChinese(_ normalizedLanguageIdentifier: String) -> Bool {
        normalizedLanguageIdentifier.hasPrefix("zh-hant")
            || normalizedLanguageIdentifier.hasPrefix("zh-tw")
            || normalizedLanguageIdentifier.hasPrefix("zh-hk")
            || normalizedLanguageIdentifier.hasPrefix("zh-mo")
    }

    private static let zhHans: [TokenWatchWidgetCopyKey: String] = [
        .recent22Weeks: "最近 22 周",
        .month: "本月",
        .week: "本周",
        .today: "今日",
        .dailyAverage: "日均",
        .peakHour: "峰值小时",
        .updated: "更新于",
        .openAppToAuthorize: "打开 TokenWatch 完成授权",
        .waitingForRefresh: "等待 TokenWatch 刷新",
        .noTokenData: "暂无 token 数据",
        .dataMayBeStale: "数据可能不是最新",
        .tokenHeatmapDisplayName: "Token 热力图",
        .tokenHeatmapDescription: "查看最近 22 周 token 用量热力图。",
        .todayLineDisplayName: "今日 Token",
        .todayLineDescription: "查看今日每小时 token 用量趋势。",
    ]
    private static let zhHant: [TokenWatchWidgetCopyKey: String] = [
        .recent22Weeks: "最近 22 週",
        .month: "本月",
        .week: "本週",
        .today: "今日",
        .dailyAverage: "日均",
        .peakHour: "峰值小時",
        .updated: "更新於",
        .openAppToAuthorize: "開啟 TokenWatch 完成授權",
        .waitingForRefresh: "等待 TokenWatch 重新整理",
        .noTokenData: "暫無 token 資料",
        .dataMayBeStale: "資料可能不是最新",
        .tokenHeatmapDisplayName: "Token 熱力圖",
        .tokenHeatmapDescription: "查看最近 22 週 token 用量熱力圖。",
        .todayLineDisplayName: "今日 Token",
        .todayLineDescription: "查看今日每小時 token 用量趨勢。",
    ]
    private static let en: [TokenWatchWidgetCopyKey: String] = [
        .recent22Weeks: "Recent 22 Weeks",
        .month: "Month",
        .week: "Week",
        .today: "Today",
        .dailyAverage: "Daily Avg",
        .peakHour: "Peak Hour",
        .updated: "Updated",
        .openAppToAuthorize: "Open TokenWatch to authorize",
        .waitingForRefresh: "Waiting for TokenWatch to refresh",
        .noTokenData: "No token data",
        .dataMayBeStale: "Data may be stale",
        .tokenHeatmapDisplayName: "Token Heatmap",
        .tokenHeatmapDescription: "See token usage over the recent 22 weeks.",
        .todayLineDisplayName: "Today Tokens",
        .todayLineDescription: "See today's hourly token usage trend.",
    ]
}

enum TokenWatchWidgetDisplayFamily: Sendable { case small, medium, large }

enum TokenWatchHeatmapWidgetLayout: Equatable, Sendable {
    case compact, summary, expanded
    static func layout(for family: TokenWatchWidgetDisplayFamily) -> TokenWatchHeatmapWidgetLayout {
        switch family { case .small: .compact; case .medium: .summary; case .large: .expanded }
    }
}

enum TokenWatchTodayLineWidgetLayout: Equatable, Sendable {
    case compact, chart, expanded
    static func layout(for family: TokenWatchWidgetDisplayFamily) -> TokenWatchTodayLineWidgetLayout {
        switch family { case .small: .compact; case .medium: .chart; case .large: .expanded }
    }
}
