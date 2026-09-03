import Foundation
import os.log

/// 支持按应用内语言生成错误详情的错误类型。
protocol AppLocalizedError: Error {
    func localizedDescription(language: AppLanguage) -> String
}

enum AppStringKey: String, CaseIterable, Sendable {
    case languageSystem
    case languageChinese
    case languageEnglish
    case appTagline
    case sidebarTotal
    case sidebarRecent12Months
    case sidebarRecent7Days
    case sidebarRecent30Days
    case sidebarToday
    case sidebarSettings
    case dashboardOverviewNavigation
    case dashboardWidgetsNavigation
    case dashboardSessionsNavigation
    case dashboardOverviewTitle
    case dashboardOverviewSubtitle
    case dashboardWidgetsTitle
    case dashboardWidgetsSubtitle
    case dashboardSessionsTitle
    case dashboardSessionsSubtitle
    case dashboardDataSources
    case dashboardLastLocalScan
    case dashboardMetricTotalTokens
    case dashboardMetricTotalCost
    case dashboardMetricSessions
    case dashboardMetricRecords
    case dashboardTrendTitle
    case dashboardTrendSubtitle
    case dashboardTrendTokenLegend
    case dashboardModelRankTitle
    case dashboardSourceShareTitle
    case dashboardProjectUsageTitle
    case dashboardNoProjectData
    case dashboardRangeDay
    case dashboardRange7Days
    case dashboardRange30Days
    case dashboardRangeAll
    case dashboardTotalSourcesProjectsFormat
    case dashboardScanUpdating
    case dashboardScanPending
    case dashboardScanUpdatedFormat
    case dashboardJustNow
    case dashboardMinutesAgoFormat
    case dashboardHoursAgoFormat
    case dashboardUnauthorized
    case dashboardPreviousPage
    case dashboardNextPage
    case dashboardShowingSessionsFormat
    case dashboardLatestTime
    case dashboardSessionID
    case dashboardPrimaryModel
    case dashboardNoSessions
    case dashboardCopySessionIDAccessibility
    case dashboardCopyIDAccessibilityDescription
    case dashboardInput
    case dashboardOutput
    case dashboardCache
    case dashboardCacheHitRate
    case dashboardReasoning
    case dashboardSessionsEmptyToday
    case settingsTitle
    case settingsDescription
    case settingsDataFoldersTitle
    case settingsDataRefreshTitle
    case settingsAppPreferencesTitle
    case settingsDirectoryNotSelected
    case settingsDirectorySelected
    case settingsDirectoryNeedsReselection
    case settingsDirectoryNoData
    case settingsChooseDirectory
    case settingsReselectDirectory
    case settingsChooseAgain
    case settingsAuthorized
    case settingsAutoRefreshInterval
    case settingsLaunchAtLogin
    case settingsLaunchAtLoginRequiresApproval
    case settingsOpenLoginItemsSettings
    case settingsLanguage
    case initialDirectoryAuthorizationGuideTitle
    case initialDirectoryAuthorizationGuideMessage
    case initialDirectoryAuthorizationGuideOpenSettings
    case initialDirectoryAuthorizationGuideLater
    case autoRefreshSeconds30
    case autoRefreshMinute1
    case autoRefreshMinutes5
    case autoRefreshMinutes15
    case autoRefreshDisabled
    case totalModelUsage
    case totalEmptyModels
    case statusLoadingUsage
    case statusNeedsDataDirectorySelection
    case statusTotalNoTokenData
    case statusPartialLoading
    case chartTokenUsage
    case chartCost
    case shareTool
    case shareModel
    case shareEmpty
    case shareOther
    case recentDetailsTitle
    case recentDetailsEmpty
    case recentDetailsTime
    case recentDetailsSession
    case recentDetailsTool
    case recentDetailsProject
    case recentDetailsModel
    case recentDetailsTokens
    case recentDetailsCost
    case recentDetailsRecords
    case periodNoTokenDataFormat
    case statusMenuOpen
    case refreshNow
    case support
    case statusMenuQuit
    case mainMenuAbout
    case privacyPolicy
    case mainMenuSettings
    case mainMenuHide
    case mainMenuHideOthers
    case mainMenuShowAll
    case mainMenuWindow
    case mainMenuMinimize
    case mainMenuZoom
    case mainMenuBringAllToFront
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
    case widgetHeatmapTitle
    case widgetTodayUsageTitle
    case widgetDatedUsageTitleFormat
    case widgetUpdatedThroughTitleFormat
    case widgetNotReadyMessage
    case widgetMonthlyBudgetTitle
    case widgetMonthlyBudgetSettingsTitle
    case widgetMonthlyBudgetForecastTitle
    case widgetMonthlyBudgetUnconfiguredMessage
    case widgetMonthlyBudgetForecastOverBudgetMessage
    case widgetPurchaseLockedTitle
    case widgetPurchaseLockedDescription
    case widgetPurchaseUnlockedTitle
    case widgetPurchaseUnlockedDescription
    case widgetPurchaseLockedStatus
    case widgetPurchaseUnlockedStatus
    case widgetPurchaseLoadingMessage
    case widgetPurchasePurchasingMessage
    case widgetPurchaseRestoringMessage
    case widgetPurchasePendingMessage
    case widgetPurchaseNoPurchaseMessage
    case widgetPurchaseUnavailableMessage
    case widgetPurchaseFailedMessage
    case widgetPurchaseEntitlementPersistenceFailedMessage
    case widgetPurchaseVerificationFailedMessage
    case widgetPurchaseUnavailableTitle
    case widgetPurchaseRestoreTitle
    case widgetPurchaseActionFormat
    case chartTokenAccessibility
    case chartCostAccessibility
    case chartTokenAccessibilityFormat
    case chartCostAccessibilityFormat
    case periodAxisValueName
    case statusBarTokenUnit
    case claudeDataDirectoryOpenPanelMessage
    case codexDataDirectoryOpenPanelMessage
    case openCodeDataDirectoryOpenPanelMessage
    case antigravityDataDirectoryOpenPanelMessage
    case chooseDirectoryPrompt
    case errorCannotAccessProviderDirectoryFormat
    case errorProviderDirectoryAuthorizationFailedFormat
    case errorLoadFailedPrefix
    case errorOpenCodeDatabaseNotFoundFormat
    case errorOpenCodeDatabaseOpenFailedFormat
    case errorOpenCodeDatabaseQueryFailedFormat
    case commonUnknown
    case errorDirectoryNotDirectoryFormat
    case errorCannotEnumerateDirectoryFormat
    case errorProviderDidNotReturnEntries
}

enum AppStrings {
    private static let logger = Logger(
        subsystem: "com.xiaoao.TokenWatch",
        category: "AppStrings"
    )
    private static let missingLocalizationSentinel = "__TOKENWATCH_MISSING_LOCALIZATION__"

    /// Returns localized text for a stable app string key.
    static func text(_ key: AppStringKey, language: AppLanguage) -> String {
        text(key, language: language, bundle: .main)
    }

    /// Resolves a key from an explicitly supplied bundle, primarily for deterministic fallback testing.
    static func text(_ key: AppStringKey, language: AppLanguage, bundle: Bundle) -> String {
        text(key, language: language) { targetLanguage, targetKey in
            localizedValue(targetKey, language: targetLanguage, bundle: bundle)
        }
    }

    /// Resolves the target locale first, then English, and finally the stable raw key.
    static func text(
        _ key: AppStringKey,
        language: AppLanguage,
        lookup: (AppLanguage, AppStringKey) -> String?
    ) -> String {
        lookup(language, key) ?? lookup(.en, key) ?? key.rawValue
    }

    private static func localizedValue(
        _ key: AppStringKey,
        language: AppLanguage,
        bundle: Bundle
    ) -> String? {
        guard let resourceURL = bundle.url(
            forResource: language.resourceIdentifier,
            withExtension: "lproj"
        ), let localizedBundle = Bundle(url: resourceURL) else {
            logger.error(
                "缺少本地化资源：locale=\(language.resourceIdentifier, privacy: .public)，key=\(key.rawValue, privacy: .public)"
            )
            return nil
        }

        let value = localizedBundle.localizedString(
            forKey: key.rawValue,
            value: missingLocalizationSentinel,
            table: "Localizable"
        )
        guard value != missingLocalizationSentinel else {
            logger.error(
                "缺少本地化文案：locale=\(language.resourceIdentifier, privacy: .public)，key=\(key.rawValue, privacy: .public)"
            )
            return nil
        }
        return value
    }
}
