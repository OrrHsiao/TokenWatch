import Foundation

enum AppStringKey: CaseIterable, Sendable {
    case languageSystem
    case languageChinese
    case languageEnglish
    case sidebarTotal
    case sidebarRecent12Months
    case sidebarRecent30Days
    case sidebarToday
    case sidebarSettings
    case settingsTitle
    case settingsDescription
    case settingsAuthorizationTitle
    case settingsAuthorizeDirectory
    case settingsAuthorized
    case settingsAuthorize
    case settingsRefreshAllData
    case settingsAutoRefreshInterval
    case settingsLanguage
    case autoRefreshSeconds30
    case autoRefreshMinute1
    case autoRefreshMinutes5
    case autoRefreshMinutes15
    case autoRefreshDisabled
    case totalSubtitle
    case totalModelUsage
    case totalEmptyModels
    case statusLoadingUsage
    case statusNeedsHomeAuthorization
    case statusTotalNoTokenData
    case statusPartialLoading
    case chartTokenUsage
    case chartCost
    case shareTool
    case shareModel
    case shareEmpty
    case shareOther
    case periodSubtitleSuffix
    case periodNoTokenDataSuffix
    case statusMenuOpen
    case refreshNow
    case statusMenuQuit
    case refreshInProgress
    case refreshTotalAccessibility
    case refreshUsageAccessibility
    case refreshTodayAccessibility
    case refreshingTotalAccessibility
    case refreshingUsageAccessibility
    case refreshingTodayAccessibility
    case popoverMonth
    case popoverWeek
    case popoverToday
    case popoverDailyAverage
    case popoverNoTodayTokens
    case popoverLowTodayTokens
    case popoverMediumTodayTokens
    case popoverHighTodayTokens
    case popoverVeryHighTodayTokens
    case popoverExtremeTodayTokens
    case heatmapRecent22Weeks
    case chartTokenAccessibility
    case chartCostAccessibility
    case statusBarTokenUnit
    case homeAccessMessage
    case authorizeAccessPrompt
    case errorCannotAccessHome
    case errorLoadFailedPrefix
}

enum AppStrings {
    /// Returns localized text for a stable app string key.
    static func text(_ key: AppStringKey, language: AppLanguage) -> String {
        text(key, language: language, zhHans: zhHans, en: en)
    }

    static func text(
        _ key: AppStringKey,
        language: AppLanguage,
        zhHans zhHansTable: [AppStringKey: String],
        en enTable: [AppStringKey: String]
    ) -> String {
        switch language {
        case .zhHans:
            return zhHansTable[key] ?? enTable[key] ?? String(describing: key)
        case .en:
            return enTable[key] ?? String(describing: key)
        }
    }

    private static let zhHans: [AppStringKey: String] = [
        .languageSystem: "跟随系统",
        .languageChinese: "中文",
        .languageEnglish: "English",
        .sidebarTotal: "总计",
        .sidebarRecent12Months: "最近 12 个月",
        .sidebarRecent30Days: "最近 30 天",
        .sidebarToday: "本日",
        .sidebarSettings: "设置",
        .settingsTitle: "设置",
        .settingsDescription: "管理 TokenWatch 的通用访问权限和数据刷新。",
        .settingsAuthorizationTitle: "通用访问权限",
        .settingsAuthorizeDirectory: "授权访问用户目录",
        .settingsAuthorized: "已授权",
        .settingsAuthorize: "去授权",
        .settingsRefreshAllData: "刷新全部数据",
        .settingsAutoRefreshInterval: "自动刷新间隔",
        .settingsLanguage: "语言",
        .autoRefreshSeconds30: "30 秒",
        .autoRefreshMinute1: "1 分钟",
        .autoRefreshMinutes5: "5 分钟",
        .autoRefreshMinutes15: "15 分钟",
        .autoRefreshDisabled: "关闭自动刷新",
        .totalSubtitle: "跨 provider 全量汇总",
        .totalModelUsage: "模型消耗",
        .totalEmptyModels: "暂无模型数据",
        .statusLoadingUsage: "正在加载用量数据...",
        .statusNeedsHomeAuthorization: "请先在设置中授权访问用户目录",
        .statusTotalNoTokenData: "总计暂无 token 数据",
        .statusPartialLoading: "部分数据仍在加载",
        .chartTokenUsage: "Token 用量",
        .chartCost: "费用",
        .shareTool: "工具占比",
        .shareModel: "模型占比",
        .shareEmpty: "暂无数据",
        .shareOther: "其他",
        .periodSubtitleSuffix: "跨 provider 汇总",
        .periodNoTokenDataSuffix: "暂无 token 数据",
        .statusMenuOpen: "打开 TokenWatch",
        .refreshNow: "立即刷新",
        .statusMenuQuit: "退出 TokenWatch",
        .refreshInProgress: "正在刷新",
        .refreshTotalAccessibility: "刷新总计数据",
        .refreshUsageAccessibility: "刷新用量数据",
        .refreshTodayAccessibility: "刷新本日 token 消耗",
        .refreshingTotalAccessibility: "正在刷新总计数据",
        .refreshingUsageAccessibility: "正在刷新用量数据",
        .refreshingTodayAccessibility: "正在刷新本日 token 消耗",
        .popoverMonth: "本月",
        .popoverWeek: "本周",
        .popoverToday: "今日",
        .popoverDailyAverage: "日均",
        .popoverNoTodayTokens: "本日还没有消耗 token 哦～",
        .popoverLowTodayTokens: "本日 token 消耗很克制～",
        .popoverMediumTodayTokens: "本日 token 消耗正在加速～",
        .popoverHighTodayTokens: "本日 token 消耗有点上头～",
        .popoverVeryHighTodayTokens: "本日 token 消耗火力全开～",
        .popoverExtremeTodayTokens: "本日 token 消耗爆表～",
        .heatmapRecent22Weeks: "最近 22 周",
        .chartTokenAccessibility: "最近 12 个月 token 柱状图",
        .chartCostAccessibility: "最近 12 个月费用柱状图",
        .statusBarTokenUnit: "Tokens",
        .homeAccessMessage: "TokenWatch 想访问用户目录",
        .authorizeAccessPrompt: "授权访问",
        .errorCannotAccessHome: "无法访问用户目录,请重新授权",
        .errorLoadFailedPrefix: "数据加载失败",
    ]

    private static let en: [AppStringKey: String] = [
        .languageSystem: "System",
        .languageChinese: "Chinese",
        .languageEnglish: "English",
        .sidebarTotal: "Total",
        .sidebarRecent12Months: "Last 12 Months",
        .sidebarRecent30Days: "Last 30 Days",
        .sidebarToday: "Today",
        .sidebarSettings: "Settings",
        .settingsTitle: "Settings",
        .settingsDescription: "Manage TokenWatch access permissions and data refresh.",
        .settingsAuthorizationTitle: "General Access",
        .settingsAuthorizeDirectory: "Authorize Home Folder",
        .settingsAuthorized: "Authorized",
        .settingsAuthorize: "Authorize",
        .settingsRefreshAllData: "Refresh All Data",
        .settingsAutoRefreshInterval: "Auto Refresh Interval",
        .settingsLanguage: "Language",
        .autoRefreshSeconds30: "30 seconds",
        .autoRefreshMinute1: "1 minute",
        .autoRefreshMinutes5: "5 minutes",
        .autoRefreshMinutes15: "15 minutes",
        .autoRefreshDisabled: "Disable Auto Refresh",
        .totalSubtitle: "All-time summary across providers",
        .totalModelUsage: "Model Usage",
        .totalEmptyModels: "No model data",
        .statusLoadingUsage: "Loading usage data...",
        .statusNeedsHomeAuthorization: "Authorize home folder access in Settings first",
        .statusTotalNoTokenData: "No total token data",
        .statusPartialLoading: "Some data is still loading",
        .chartTokenUsage: "Token Usage",
        .chartCost: "Cost",
        .shareTool: "Tool Share",
        .shareModel: "Model Share",
        .shareEmpty: "No data",
        .shareOther: "Other",
        .periodSubtitleSuffix: "Summary across providers",
        .periodNoTokenDataSuffix: "has no token data",
        .statusMenuOpen: "Open TokenWatch",
        .refreshNow: "Refresh Now",
        .statusMenuQuit: "Quit TokenWatch",
        .refreshInProgress: "Refreshing",
        .refreshTotalAccessibility: "Refresh total data",
        .refreshUsageAccessibility: "Refresh usage data",
        .refreshTodayAccessibility: "Refresh today's token usage",
        .refreshingTotalAccessibility: "Refreshing total data",
        .refreshingUsageAccessibility: "Refreshing usage data",
        .refreshingTodayAccessibility: "Refreshing today's token usage",
        .popoverMonth: "Month",
        .popoverWeek: "Week",
        .popoverToday: "Today",
        .popoverDailyAverage: "Daily Avg",
        .popoverNoTodayTokens: "No token usage today",
        .popoverLowTodayTokens: "Today's token usage is light",
        .popoverMediumTodayTokens: "Today's token usage is picking up",
        .popoverHighTodayTokens: "Today's token usage is high",
        .popoverVeryHighTodayTokens: "Today's token usage is running hot",
        .popoverExtremeTodayTokens: "Today's token usage is off the charts",
        .heatmapRecent22Weeks: "Last 22 Weeks",
        .chartTokenAccessibility: "Last 12 months token bar chart",
        .chartCostAccessibility: "Last 12 months cost bar chart",
        .statusBarTokenUnit: "Tokens",
        .homeAccessMessage: "TokenWatch wants to access your home folder",
        .authorizeAccessPrompt: "Authorize",
        .errorCannotAccessHome: "Cannot access home folder. Please authorize again",
        .errorLoadFailedPrefix: "Data load failed",
    ]
}
