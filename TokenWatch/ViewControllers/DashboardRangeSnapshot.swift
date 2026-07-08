import Foundation

enum DashboardNavigationItem: String, CaseIterable {
    case overview
    case sessions
    case settings

    var title: String {
        title(language: .zhHans)
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .overview:
            return AppStrings.text(.dashboardOverviewNavigation, language: language)
        case .sessions:
            return AppStrings.text(.dashboardSessionsNavigation, language: language)
        case .settings:
            return AppStrings.text(.sidebarSettings, language: language)
        }
    }

    var symbolName: String {
        switch self {
        case .overview: return "waveform.path.ecg"
        case .sessions: return "message"
        case .settings: return "gearshape"
        }
    }
}

enum DashboardRange: String, CaseIterable {
    case day
    case sevenDays
    case month
    case all

    var title: String {
        title(language: .zhHans)
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .day:
            return AppStrings.text(.dashboardRangeDay, language: language)
        case .sevenDays:
            return AppStrings.text(.dashboardRange7Days, language: language)
        case .month:
            return AppStrings.text(.dashboardRange30Days, language: language)
        case .all:
            return AppStrings.text(.dashboardRangeAll, language: language)
        }
    }

    var bucketCount: Int? {
        switch self {
        case .day: return 24
        case .sevenDays: return 7
        case .month: return 30
        case .all:
            return nil
        }
    }

    func bucketStarts(now: Date, calendar: Calendar) -> [Date] {
        switch self {
        case .day:
            let dayStart = calendar.startOfDay(for: now)
            return (0..<24).compactMap {
                calendar.date(byAdding: .hour, value: $0, to: dayStart)
            }
        case .sevenDays, .month:
            let today = calendar.startOfDay(for: now)
            let count = bucketCount ?? 0
            guard let start = calendar.date(byAdding: .day, value: -(count - 1), to: today) else {
                return [today]
            }
            return (0..<count).compactMap {
                calendar.date(byAdding: .day, value: $0, to: start)
            }
        case .all:
            return []
        }
    }

    func bucketKey(for date: Date, calendar: Calendar) -> String {
        switch self {
        case .day:
            let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
            return String(
                format: "%04d-%02d-%02dT%02d",
                components.year ?? 0,
                components.month ?? 0,
                components.day ?? 0,
                components.hour ?? 0
            )
        case .sevenDays, .month:
            return Self.dayKey(for: date, calendar: calendar)
        case .all:
            let components = calendar.dateComponents([.year, .month], from: date)
            return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
        }
    }

    func bucketLabel(for date: Date, calendar: Calendar, language: AppLanguage) -> String {
        switch self {
        case .day:
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
        case .sevenDays, .month:
            let components = calendar.dateComponents([.month, .day], from: date)
            return "\(components.month ?? 0)/\(components.day ?? 0)"
        case .all:
            let components = calendar.dateComponents([.year, .month], from: date)
            return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
        }
    }

    func summary(in stats: AggregatedStats, for key: String) -> UsageSummary? {
        switch self {
        case .day:
            return stats.byHour[key]
        case .sevenDays, .month:
            return stats.byDay[key]
        case .all:
            return stats.byMonth[key]
        }
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
}

struct DashboardRangeSnapshot {
    let summary: DashboardUsageSummary
    let trendBuckets: [DashboardTrendBucket]
    let toolShareSlices: [UsageShareSlice]
    let totalTokens: Int
    let loadedProviderCount: Int
    let loadingProviderCount: Int
    let unauthorizedProviderCount: Int
    let errorMessages: [String]

    static func build(
        states: [ProviderID: TokenStatsViewModel.ProviderState],
        range: DashboardRange,
        now: Date,
        calendar: Calendar,
        language: AppLanguage
    ) -> DashboardRangeSnapshot {
        if range == .all {
            return buildAll(states: states)
        }
        return buildWindow(
            states: states,
            range: range,
            now: now,
            calendar: calendar,
            language: language
        )
    }

    private static func buildWindow(
        states: [ProviderID: TokenStatsViewModel.ProviderState],
        range: DashboardRange,
        now: Date,
        calendar: Calendar,
        language: AppLanguage
    ) -> DashboardRangeSnapshot {
        let bucketStarts = range.bucketStarts(now: now, calendar: calendar)
        let bucketKeys = bucketStarts.map { range.bucketKey(for: $0, calendar: calendar) }
        let currentKey = range.bucketKey(for: now, calendar: calendar)

        var summaries = Dictionary(uniqueKeysWithValues: bucketKeys.map { ($0, UsageSummary.zero) })
        var toolTotals: [ProviderID: Int] = [:]
        var projectTotals: [String: Int] = [:]
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
            for key in bucketKeys {
                guard let summary = range.summary(in: stats, for: key) else { continue }
                summaries[key, default: .zero] = summaries[key, default: .zero].merged(with: summary)
                providerVisibleTokens += summary.totalTokens
                for (project, projectSummary) in summary.projectBreakdown {
                    projectTotals[project, default: 0] += projectSummary.totalTokens
                }
            }
            if providerVisibleTokens > 0 {
                toolTotals[providerID, default: 0] += providerVisibleTokens
            }
        }

        let maxTokens = summaries.values.map(\.totalTokens).max() ?? 0
        let maxCost = summaries.values.map(\.cost).max() ?? 0
        let bucketRows = zip(bucketStarts, bucketKeys).map { bucketStart, key in
            let summary = summaries[key, default: .zero]
            let label = range.bucketLabel(for: bucketStart, calendar: calendar, language: language)
            return DashboardTrendBucket(
                id: key,
                key: key,
                label: label,
                totalTokens: summary.totalTokens,
                totalCost: summary.cost,
                normalizedHeight: maxTokens > 0 ? Double(summary.totalTokens) / Double(maxTokens) : 0,
                normalizedCostHeight: maxCost > 0 ? summary.cost / maxCost : 0,
                isCurrent: key == currentKey
            )
        }
        let orderedSummaries = bucketKeys.map { key in
            (key: key, label: bucketRows.first(where: { $0.key == key })?.label ?? key, summary: summaries[key, default: .zero])
        }
        let summary = makeWindowSummary(
            orderedSummaries: orderedSummaries,
            projectTotals: projectTotals
        )

        return DashboardRangeSnapshot(
            summary: summary,
            trendBuckets: bucketRows,
            toolShareSlices: makeToolShareSlices(toolTotals),
            totalTokens: summary.totalTokens,
            loadedProviderCount: loadedProviderCount,
            loadingProviderCount: loadingProviderCount,
            unauthorizedProviderCount: unauthorizedProviderCount,
            errorMessages: errorMessages
        )
    }

    private static func buildAll(states: [ProviderID: TokenStatsViewModel.ProviderState]) -> DashboardRangeSnapshot {
        var monthSummaries: [String: UsageSummary] = [:]
        var toolTotals: [ProviderID: Int] = [:]
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
            if stats.overall.totalTokens > 0 {
                toolTotals[providerID, default: 0] += stats.overall.totalTokens
            }
            for (month, summary) in stats.byMonth {
                monthSummaries[month, default: .zero] = monthSummaries[month, default: .zero].merged(with: summary)
            }
        }

        let sortedMonths = monthSummaries.keys.sorted()
        let maxTokens = monthSummaries.values.map(\.totalTokens).max() ?? 0
        let maxCost = monthSummaries.values.map(\.cost).max() ?? 0
        let trendBuckets = sortedMonths.map { month in
            let summary = monthSummaries[month, default: .zero]
            return DashboardTrendBucket(
                id: month,
                key: month,
                label: month,
                totalTokens: summary.totalTokens,
                totalCost: summary.cost,
                normalizedHeight: maxTokens > 0 ? Double(summary.totalTokens) / Double(maxTokens) : 0,
                normalizedCostHeight: maxCost > 0 ? summary.cost / maxCost : 0,
                isCurrent: sortedMonths.last == month
            )
        }
        let summary = DashboardUsageSummary.makeTotal(from: states)

        return DashboardRangeSnapshot(
            summary: summary,
            trendBuckets: trendBuckets,
            toolShareSlices: makeToolShareSlices(toolTotals),
            totalTokens: summary.totalTokens,
            loadedProviderCount: loadedProviderCount,
            loadingProviderCount: loadingProviderCount,
            unauthorizedProviderCount: unauthorizedProviderCount,
            errorMessages: errorMessages
        )
    }

    private static func makeWindowSummary(
        orderedSummaries: [(key: String, label: String, summary: UsageSummary)],
        projectTotals: [String: Int]
    ) -> DashboardUsageSummary {
        let total = orderedSummaries.reduce(UsageSummary.zero) { partial, row in
            partial.merged(with: row.summary)
        }
        let projects = DashboardProjectRows.makeRows(fromTokenTotals: projectTotals)

        return DashboardUsageSummary(
            inputTokens: total.inputTokens,
            outputTokens: total.outputTokens,
            cacheReadTokens: total.cacheReadTokens,
            cacheCreationTokens: total.cacheCreationTokens,
            reasoningTokens: total.reasoningTokens,
            totalTokens: total.totalTokens,
            cost: total.cost,
            entryCount: total.entryCount,
            projectCount: projects.count,
            projects: projects
        )
    }

    static func modelText(for row: RecentSessionRow) -> String {
        let model = row.primaryModel.isEmpty ? "-" : row.primaryModel
        guard row.additionalModelCount > 0 else { return model }
        return "\(model) +\(row.additionalModelCount)"
    }

    static func formatDetailDate(_ date: Date?) -> String {
        guard let date else { return "-" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private static func makeToolShareSlices(_ totals: [ProviderID: Int]) -> [UsageShareSlice] {
        let totalTokens = totals.values.reduce(0, +)
        guard totalTokens > 0 else { return [] }
        return totals
            .filter { $0.value > 0 }
            .sorted { lhs, rhs in
                if lhs.value != rhs.value {
                    return lhs.value > rhs.value
                }
                return providerName(lhs.key).localizedCaseInsensitiveCompare(providerName(rhs.key)) == .orderedAscending
            }
            .map { providerID, tokens in
                UsageShareSlice(
                    id: providerID.rawValue,
                    label: providerName(providerID),
                    totalTokens: tokens,
                    percentage: Double(tokens) / Double(totalTokens)
                )
            }
    }

    static func displayProjectName(_ path: String) -> String {
        DashboardProjectRows.displayName(for: path)
    }

    private static func providerName(_ id: ProviderID) -> String {
        ProviderRegistry.provider(for: id)?.displayName ?? id.rawValue
    }
}

struct DashboardUsageSummary {
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheCreationTokens: Int
    let reasoningTokens: Int
    let totalTokens: Int
    let cost: Double
    let entryCount: Int
    let projectCount: Int
    let projects: [DashboardProjectRow]

    static func makeTotal(from states: [ProviderID: TokenStatsViewModel.ProviderState]) -> DashboardUsageSummary {
        var inputTokens = 0
        var outputTokens = 0
        var cacheReadTokens = 0
        var cacheCreationTokens = 0
        var reasoningTokens = 0
        var totalTokens = 0
        var cost = 0.0
        var entryCount = 0
        var projects: [String: UsageSummary] = [:]

        for (_, state) in states {
            guard let stats = state.stats else { continue }
            inputTokens += stats.overall.inputTokens
            outputTokens += stats.overall.outputTokens
            cacheReadTokens += stats.overall.cacheReadTokens
            cacheCreationTokens += stats.overall.cacheCreationTokens
            reasoningTokens += stats.overall.reasoningTokens
            totalTokens += stats.overall.totalTokens
            cost += stats.overall.cost
            entryCount += stats.overall.entryCount
            for (project, summary) in stats.byProject {
                projects[project, default: .zero] = projects[project, default: .zero].merged(with: summary)
            }
        }

        return DashboardUsageSummary(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheReadTokens,
            cacheCreationTokens: cacheCreationTokens,
            reasoningTokens: reasoningTokens,
            totalTokens: totalTokens,
            cost: cost,
            entryCount: entryCount,
            projectCount: DashboardProjectRows.projectCount(fromSummaries: projects),
            projects: makeProjectRows(projects)
        )
    }

    private static func makeProjectRows(_ projects: [String: UsageSummary]) -> [DashboardProjectRow] {
        DashboardProjectRows.makeRows(fromSummaries: projects)
    }

}

struct DashboardProjectRow {
    let name: String
    let tokens: Int
}

private enum DashboardProjectRows {
    static func makeRows(fromSummaries projects: [String: UsageSummary]) -> [DashboardProjectRow] {
        makeRows(fromTokenTotals: projects.mapValues(\.totalTokens))
    }

    static func makeRows(fromTokenTotals projects: [String: Int]) -> [DashboardProjectRow] {
        mergedDisplayTotals(projects)
            .sorted { lhs, rhs in
                if lhs.value != rhs.value {
                    return lhs.value > rhs.value
                }
                return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
            }
            .prefix(4)
            .map { DashboardProjectRow(name: $0.key, tokens: $0.value) }
    }

    static func projectCount(fromSummaries projects: [String: UsageSummary]) -> Int {
        mergedDisplayTotals(projects.mapValues(\.totalTokens)).count
    }

    static func displayName(for path: String) -> String {
        displayNameOrNil(for: path) ?? "unknown"
    }

    private static func displayNameOrNil(for path: String) -> String? {
        let path = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, path != "unknown" else { return nil }
        guard !isPencilDocumentPath(path) else { return nil }
        guard !isMacOSTemporaryRootPath(path) else { return nil }

        if let claudeParentProject = parentProjectBeforeClaudeWorktree(in: path) {
            return fallbackDisplayName(for: claudeParentProject)
        }
        if let codexWorktreeProject = projectInsideCodexWorktree(in: path) {
            return fallbackDisplayName(for: codexWorktreeProject)
        }
        return fallbackDisplayName(for: path)
    }

    private static func fallbackDisplayName(for path: String) -> String {
        let components = path.split(separator: "/")
        return components.last.map(String.init) ?? path
    }

    private static func mergedDisplayTotals(_ projects: [String: Int]) -> [String: Int] {
        var totals: [String: Int] = [:]
        for (project, tokens) in projects where tokens > 0 {
            guard let displayName = displayNameOrNil(for: project) else { continue }
            totals[displayName, default: 0] += tokens
        }
        return totals
    }

    private static func isPencilDocumentPath(_ path: String) -> Bool {
        let components = path.split(separator: "/").map(String.init)
        guard let pencilIndex = components.firstIndex(of: ".pencil"),
              components.indices.contains(pencilIndex + 1)
        else {
            return false
        }
        return components[pencilIndex + 1] == "documents"
    }

    private static func isMacOSTemporaryRootPath(_ path: String) -> Bool {
        let components = path.split(separator: "/").map(String.init)
        guard components.last == "T" else { return false }
        if components.count == 5 {
            return components[0] == "var" && components[1] == "folders"
        }
        if components.count == 6 {
            return components[0] == "private" && components[1] == "var" && components[2] == "folders"
        }
        return false
    }

    private static func parentProjectBeforeClaudeWorktree(in path: String) -> String? {
        guard let range = path.range(of: "/.claude/worktrees/") else { return nil }
        let parent = String(path[..<range.lowerBound])
        return parent.isEmpty ? nil : parent
    }

    private static func projectInsideCodexWorktree(in path: String) -> String? {
        let components = path.split(separator: "/").map(String.init)
        guard let codexIndex = components.firstIndex(of: ".codex"),
              components.indices.contains(codexIndex + 3),
              components[codexIndex + 1] == "worktrees"
        else {
            return nil
        }
        return components[codexIndex + 3]
    }
}

private extension UsageSummary {
    func merged(with other: UsageSummary) -> UsageSummary {
        UsageSummary(
            inputTokens: inputTokens + other.inputTokens,
            outputTokens: outputTokens + other.outputTokens,
            cacheReadTokens: cacheReadTokens + other.cacheReadTokens,
            cacheCreationTokens: cacheCreationTokens + other.cacheCreationTokens,
            reasoningTokens: reasoningTokens + other.reasoningTokens,
            totalTokens: totalTokens + other.totalTokens,
            cost: cost + other.cost,
            entryCount: entryCount + other.entryCount,
            modelBreakdown: modelBreakdown.merging(other.modelBreakdown) { $0.merged(with: $1) },
            projectBreakdown: projectBreakdown.merging(other.projectBreakdown) { $0.merged(with: $1) }
        )
    }
}
