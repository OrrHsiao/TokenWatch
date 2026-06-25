import Foundation

/// 跨 provider 汇总页支持的时间窗口。
enum UsageStatsPeriod: Sendable, Equatable {
    case recent12Months
    case recent30Days
    case today

    var title: String {
        title(language: .zhHans)
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .recent12Months:
            return AppStrings.text(.sidebarRecent12Months, language: language)
        case .recent30Days:
            return AppStrings.text(.sidebarRecent30Days, language: language)
        case .today:
            return AppStrings.text(.sidebarToday, language: language)
        }
    }

    var emptyDataText: String {
        emptyDataText(language: .zhHans)
    }

    func emptyDataText(language: AppLanguage) -> String {
        switch language {
        case .zhHans, .zhHant, .ja, .ko:
            return "\(title(language: language))\(AppStrings.text(.periodNoTokenDataSuffix, language: language))"
        case .en, .es, .de, .fr, .ptBR, .it, .nl, .pl:
            return "\(title(language: language)) \(AppStrings.text(.periodNoTokenDataSuffix, language: language))"
        }
    }

    func tokenChartAccessibilityLabel(language: AppLanguage) -> String {
        "\(title(language: language)) \(AppStrings.text(.chartTokenAccessibilitySuffix, language: language))"
    }

    func costChartAccessibilityLabel(language: AppLanguage) -> String {
        "\(title(language: language)) \(AppStrings.text(.chartCostAccessibilitySuffix, language: language))"
    }

    fileprivate var bucketCount: Int {
        switch self {
        case .recent12Months:
            return 12
        case .recent30Days:
            return 30
        case .today:
            return 24
        }
    }

    fileprivate var calendarComponent: Calendar.Component {
        switch self {
        case .recent12Months:
            return .month
        case .recent30Days:
            return .day
        case .today:
            return .hour
        }
    }

    fileprivate func currentBucketStart(now: Date, calendar: Calendar) -> Date {
        switch self {
        case .recent12Months:
            return calendar.dateInterval(of: .month, for: now)?.start
                ?? calendar.startOfDay(for: now)
        case .recent30Days:
            return calendar.startOfDay(for: now)
        case .today:
            return calendar.dateInterval(of: .hour, for: now)?.start
                ?? calendar.startOfDay(for: now)
        }
    }

    fileprivate func windowStart(currentBucketStart: Date, now: Date, calendar: Calendar) -> Date {
        switch self {
        case .today:
            // 本日视图展示自然日 00...23 点,不能用最近 24 小时滚动窗口。
            return calendar.startOfDay(for: now)
        case .recent12Months, .recent30Days:
            return calendar.date(
                byAdding: calendarComponent,
                value: -(bucketCount - 1),
                to: currentBucketStart
            ) ?? currentBucketStart
        }
    }

    fileprivate func bucketKey(for date: Date, calendar: Calendar) -> String {
        switch self {
        case .recent12Months:
            return Self.monthKey(for: date, calendar: calendar)
        case .recent30Days:
            return Self.dayKey(for: date, calendar: calendar)
        case .today:
            return Self.hourKey(for: date, calendar: calendar)
        }
    }

    fileprivate func bucketLabel(for date: Date, calendar: Calendar, language: AppLanguage) -> String {
        switch self {
        case .recent12Months:
            let month = calendar.component(.month, from: date)
            return Self.shortMonthName(for: month, language: language)
        case .recent30Days:
            let components = calendar.dateComponents([.month, .day], from: date)
            return "\(components.month ?? 0)/\(components.day ?? 0)"
        case .today:
            let hour = calendar.component(.hour, from: date)
            switch language {
            case .zhHans, .zhHant:
                return "\(hour)时"
            case .ja:
                return "\(hour)時"
            case .ko:
                return "\(hour)시"
            case .en, .es, .de, .fr, .ptBR, .it, .nl, .pl:
                return "\(hour)"
            }
        }
    }

    fileprivate func summary(in stats: AggregatedStats, for key: String) -> UsageSummary? {
        switch self {
        case .recent12Months:
            return stats.byMonth[key]
        case .recent30Days:
            return stats.byDay[key]
        case .today:
            return stats.byHour[key]
        }
    }

    private static func monthKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }

    private static func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private static func hourKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        return String(
            format: "%04d-%02d-%02dT%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0
        )
    }

    static func englishShortMonthName(for month: Int) -> String {
        shortMonthName(for: month, language: .en)
    }

    static func shortMonthName(for month: Int, language: AppLanguage) -> String {
        guard (1...12).contains(month) else { return "\(month)" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.localeIdentifier)
        let names = formatter.shortMonthSymbols ?? []
        guard names.indices.contains(month - 1) else { return "\(month)" }
        return names[month - 1]
    }
}

/// 跨 provider 时间窗口 token 柱状图的完整数据快照,供 UI 直接渲染。
struct MonthlyTokenChartSnapshot: Sendable, Equatable {
    let monthBuckets: [MonthlyTokenBucket]
    let totalTokens: Int
    let totalCost: Double
    let maxMonthlyTokens: Int
    let maxMonthlyCost: Double
    let toolShareSlices: [UsageShareSlice]
    let modelShareSlices: [UsageShareSlice]
    let loadedProviderCount: Int
    let loadingProviderCount: Int
    let unauthorizedProviderCount: Int
    let errorMessages: [String]
}

/// token 占比饼图的一块数据。
struct UsageShareSlice: Sendable, Equatable, Identifiable {
    let id: String
    let label: String
    let totalTokens: Int
    let percentage: Double
}

/// 单月柱状图中某个模型的 token 分段。
struct MonthlyTokenModelSegment: Sendable, Equatable, Identifiable {
    static let overflowID = "__tokenwatch_other__"

    let id: String
    let modelName: String
    let totalTokens: Int
    let totalCost: Double
    let percentage: Double
    let isOverflow: Bool

    init(
        id: String? = nil,
        modelName: String,
        totalTokens: Int,
        totalCost: Double = 0,
        percentage: Double,
        isOverflow: Bool = false
    ) {
        self.id = id ?? modelName
        self.modelName = modelName
        self.totalTokens = totalTokens
        self.totalCost = totalCost
        self.percentage = percentage
        self.isOverflow = isOverflow
    }
}

/// 单月 token 柱状图数据。
struct MonthlyTokenBucket: Sendable, Equatable, Identifiable {
    let id: String
    let monthKey: String
    let monthLabel: String
    let totalTokens: Int
    let totalCost: Double
    let normalizedHeight: Double
    let normalizedCostHeight: Double
    let isCurrentMonth: Bool
    let modelSegments: [MonthlyTokenModelSegment]

    init(
        id: String,
        monthKey: String,
        monthLabel: String,
        totalTokens: Int,
        totalCost: Double,
        normalizedHeight: Double,
        normalizedCostHeight: Double,
        isCurrentMonth: Bool,
        modelSegments: [MonthlyTokenModelSegment] = []
    ) {
        self.id = id
        self.monthKey = monthKey
        self.monthLabel = monthLabel
        self.totalTokens = totalTokens
        self.totalCost = totalCost
        self.normalizedHeight = normalizedHeight
        self.normalizedCostHeight = normalizedCostHeight
        self.isCurrentMonth = isCurrentMonth
        self.modelSegments = modelSegments
    }
}

/// 将多 provider 状态构建为指定时间窗口的 token 柱状图快照。
enum MonthlyTokenChartBuilder {
    private static let maxModelSegmentCount = 5

    private struct ModelSegmentLegendEntry {
        let id: String
        let modelName: String
        let isOverflow: Bool
    }

    /// 构建包含 `now` 所在桶、按指定窗口向前回溯的 token 快照。
    /// - Parameters:
    ///   - states: 各 provider 的统计状态;没有 stats 的 provider 不参与 token 求和。
    ///   - period: 统计窗口,默认保持最近 12 个月。
    ///   - now: 当前日期,用于确定窗口范围和当前桶高亮。
    ///   - calendar: 调用方指定的日历配置,用于稳定测试和本地日期计算。
    /// - Returns: 可直接渲染的 token 图表快照。
    static func build(
        states: [ProviderID: TokenStatsViewModel.ProviderState],
        period: UsageStatsPeriod = .recent12Months,
        now: Date,
        calendar: Calendar,
        language: AppLanguage = .zhHans
    ) -> MonthlyTokenChartSnapshot {
        let currentBucketStart = period.currentBucketStart(now: now, calendar: calendar)
        let windowStart = period.windowStart(currentBucketStart: currentBucketStart, now: now, calendar: calendar)
        let bucketStarts = (0..<period.bucketCount).compactMap { offset in
            calendar.date(byAdding: period.calendarComponent, value: offset, to: windowStart)
        }
        let bucketKeys = bucketStarts.map { period.bucketKey(for: $0, calendar: calendar) }
        var totals = Dictionary(uniqueKeysWithValues: bucketKeys.map { ($0, 0) })
        var costs = Dictionary(uniqueKeysWithValues: bucketKeys.map { ($0, 0.0) })
        var modelTotalsByBucket = Dictionary(uniqueKeysWithValues: bucketKeys.map { ($0, [String: Int]()) })
        var modelCostsByBucket = Dictionary(uniqueKeysWithValues: bucketKeys.map { ($0, [String: Double]()) })
        var toolTotals: [ProviderID: Int] = [:]
        var modelTotals: [String: Int] = [:]

        var loadedProviderCount = 0
        var loadingProviderCount = 0
        var unauthorizedProviderCount = 0
        var errorMessages: [String] = []

        for (providerID, state) in states {
            if state.isLoading {
                loadingProviderCount += 1
            }
            if state.needsAuthorization {
                unauthorizedProviderCount += 1
            }
            if let errorMessage = state.errorMessage {
                errorMessages.append(errorMessage)
            }
            guard let stats = state.stats else { continue }
            loadedProviderCount += 1

            var providerVisibleTokens = 0
            for bucketKey in bucketKeys {
                let summary = period.summary(in: stats, for: bucketKey)
                let monthTokens = summary?.totalTokens ?? 0
                providerVisibleTokens += monthTokens
                totals[bucketKey, default: 0] += monthTokens
                costs[bucketKey, default: 0] += summary?.cost ?? 0

                for (model, modelSummary) in summary?.modelBreakdown ?? [:] {
                    modelTotals[model, default: 0] += modelSummary.totalTokens
                    modelTotalsByBucket[bucketKey, default: [:]][model, default: 0] += modelSummary.totalTokens
                    modelCostsByBucket[bucketKey, default: [:]][model, default: 0] += modelSummary.cost
                }
            }
            if providerVisibleTokens > 0 {
                toolTotals[providerID, default: 0] += providerVisibleTokens
            }
        }

        let maxMonthlyTokens = totals.values.max() ?? 0
        let maxMonthlyCost = costs.values.max() ?? 0
        let modelSegmentLegendEntries = buildModelSegmentLegendEntries(
            modelTotals,
            otherModelSegmentName: AppStrings.text(.shareOther, language: language)
        )
        let buckets = bucketStarts.map { bucketStart in
            let key = period.bucketKey(for: bucketStart, calendar: calendar)
            let totalTokens = totals[key, default: 0]
            let totalCost = costs[key, default: 0]
            let normalizedHeight = maxMonthlyTokens > 0
                ? Double(totalTokens) / Double(maxMonthlyTokens)
                : 0
            let normalizedCostHeight = maxMonthlyCost > 0
                ? totalCost / maxMonthlyCost
                : 0
            return MonthlyTokenBucket(
                id: key,
                monthKey: key,
                monthLabel: period.bucketLabel(for: bucketStart, calendar: calendar, language: language),
                totalTokens: totalTokens,
                totalCost: totalCost,
                normalizedHeight: normalizedHeight,
                normalizedCostHeight: normalizedCostHeight,
                isCurrentMonth: key == period.bucketKey(for: currentBucketStart, calendar: calendar),
                modelSegments: buildModelSegments(
                    modelTotalsByBucket[key, default: [:]],
                    costs: modelCostsByBucket[key, default: [:]],
                    monthTotalTokens: totalTokens,
                    legendEntries: modelSegmentLegendEntries
                )
            )
        }

        return MonthlyTokenChartSnapshot(
            monthBuckets: buckets,
            totalTokens: buckets.reduce(0) { $0 + $1.totalTokens },
            totalCost: buckets.reduce(0) { $0 + $1.totalCost },
            maxMonthlyTokens: maxMonthlyTokens,
            maxMonthlyCost: maxMonthlyCost,
            toolShareSlices: buildToolShareSlices(toolTotals),
            modelShareSlices: buildModelShareSlices(modelTotals),
            loadedProviderCount: loadedProviderCount,
            loadingProviderCount: loadingProviderCount,
            unauthorizedProviderCount: unauthorizedProviderCount,
            errorMessages: errorMessages
        )
    }

    private static func buildToolShareSlices(_ totals: [ProviderID: Int]) -> [UsageShareSlice] {
        let values = totals.map { providerID, totalTokens in
            (
                id: providerID.rawValue,
                label: ProviderRegistry.provider(for: providerID)?.displayName ?? providerID.rawValue,
                totalTokens: totalTokens
            )
        }
        return buildShareSlices(values)
    }

    private static func buildModelShareSlices(_ totals: [String: Int]) -> [UsageShareSlice] {
        let values = totals.map { model, totalTokens in
            (id: model, label: model, totalTokens: totalTokens)
        }
        return buildShareSlices(values)
    }

    private static func buildModelSegments(
        _ totals: [String: Int],
        costs: [String: Double],
        monthTotalTokens: Int,
        legendEntries: [ModelSegmentLegendEntry]
    ) -> [MonthlyTokenModelSegment] {
        guard monthTotalTokens > 0, !legendEntries.isEmpty else { return [] }
        let leadingModelNames = legendEntries.filter { !$0.isOverflow }.map(\.modelName)
        let leadingModelNameSet = Set(leadingModelNames)

        return legendEntries.compactMap { entry in
            let totalTokens: Int
            let totalCost: Double
            if entry.isOverflow {
                totalTokens = totals.reduce(0) { partialResult, entry in
                    guard !leadingModelNameSet.contains(entry.key), entry.value > 0 else {
                        return partialResult
                    }
                    return partialResult + entry.value
                }
                totalCost = costs.reduce(0) { partialResult, entry in
                    guard !leadingModelNameSet.contains(entry.key), entry.value > 0 else {
                        return partialResult
                    }
                    return partialResult + entry.value
                }
            } else {
                totalTokens = totals[entry.modelName, default: 0]
                totalCost = costs[entry.modelName, default: 0]
            }

            guard totalTokens > 0 else { return nil }
            return MonthlyTokenModelSegment(
                id: entry.id,
                modelName: entry.modelName,
                totalTokens: totalTokens,
                totalCost: totalCost,
                percentage: Double(totalTokens) / Double(monthTotalTokens),
                isOverflow: entry.isOverflow
            )
        }
    }

    private static func buildShareSlices(
        _ values: [(id: String, label: String, totalTokens: Int)]
    ) -> [UsageShareSlice] {
        let visibleValues = values.filter { $0.totalTokens > 0 }
        let grandTotal = visibleValues.reduce(0) { $0 + $1.totalTokens }
        guard grandTotal > 0 else { return [] }

        return visibleValues.sorted { lhs, rhs in
            if lhs.totalTokens != rhs.totalTokens {
                return lhs.totalTokens > rhs.totalTokens
            }
            return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }.map { value in
            UsageShareSlice(
                id: value.id,
                label: value.label,
                totalTokens: value.totalTokens,
                percentage: Double(value.totalTokens) / Double(grandTotal)
            )
        }
    }

    private static func buildModelSegmentLegendEntries(
        _ totals: [String: Int],
        otherModelSegmentName: String
    ) -> [ModelSegmentLegendEntry] {
        let sortedNames = totals
            .filter { $0.value > 0 }
            .sorted { lhs, rhs in
                if lhs.value != rhs.value {
                    return lhs.value > rhs.value
                }
                return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
            }
            .map(\.key)

        let visibleNames = sortedNames.count > maxModelSegmentCount
            ? Array(sortedNames.prefix(maxModelSegmentCount - 1))
            : sortedNames
        var entries = visibleNames.map {
            ModelSegmentLegendEntry(id: $0, modelName: $0, isOverflow: false)
        }
        if sortedNames.count > maxModelSegmentCount {
            entries.append(ModelSegmentLegendEntry(
                id: MonthlyTokenModelSegment.overflowID,
                modelName: otherModelSegmentName,
                isOverflow: true
            ))
        }
        return entries
    }
}
