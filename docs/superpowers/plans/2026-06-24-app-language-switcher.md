# App Language Switcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an in-app language selector with System, Chinese, and English options, and refresh TokenWatch UI copy immediately after changes.

**Architecture:** Add a small localization layer made of `AppLanguagePreference`, `AppLanguageSettings`, `AppStringKey`, and `AppStrings`. UI controllers keep their current AppKit structure, subscribe to language changes, and rerender strings without triggering data reloads.

**Tech Stack:** Swift 6, AppKit, Swift Testing, UserDefaults, existing file-system-synchronized Xcode groups.

---

## File Structure

- Create `TokenWatch/Localization/AppLanguage.swift`
  - Owns language preference, resolved language, `UserDefaults` persistence, and main-actor observers.
- Create `TokenWatch/Localization/AppStrings.swift`
  - Owns stable string keys and Chinese/English text tables.
- Create `TokenWatchTests/Localization/AppLanguageSettingsTests.swift`
  - Tests persistence, fallback, system-language resolution, and observer notification.
- Modify `TokenWatch/ViewController.swift`
  - Inject or default language settings into the main controller, sidebar, and settings page.
  - Add Settings language popup and rerender sidebar/settings copy on language changes.
- Modify `TokenWatch/ViewControllers/TotalStatsViewController.swift`
  - Localize static labels, status text, refresh tooltip, accessibility text.
- Modify `TokenWatch/ViewControllers/MonthlyStatsViewController.swift`
  - Localize period titles, chart titles, status text, refresh tooltip, and chart configuration language.
- Modify `TokenWatch/ViewControllers/MonthlyTokenChartBuilder.swift`
  - Make period labels, subtitles, empty text, bucket labels, and "Other" model segment language-aware.
- Modify `TokenWatch/ViewControllers/MonthlyTokenChartView.swift`
  - Make axis labels, hover text, legend axis names, accessibility label, and "Other" color key language-aware.
- Modify `TokenWatch/ViewControllers/MonthlyCostChartView.swift`
  - Mirror token chart language handling for axis labels, hover text, and accessibility label.
- Modify `TokenWatch/ViewControllers/UsageSharePieChartView.swift`
  - Allow title updates, language-aware empty state, hover text, tooltip, and compacted "Other" slice.
- Modify `TokenWatch/ViewControllers/CalendarHeatmapBuilder.swift`
  - Make month title and weekday symbols language-aware.
- Modify `TokenWatch/ViewControllers/StatusPopoverViewController.swift`
  - Localize summary cards, daily description, refresh tooltip, and hover state after language changes.
- Modify `TokenWatch/ViewControllers/StatusBarController.swift`
  - Localize menu items, status title unit, and auto-refresh option titles.
- Modify `TokenWatch/Providers/UsageProvider.swift`
  - Localize the user-visible home access message.
- Modify `TokenWatch/Services/SecurityScopedBookmarkManager.swift`
  - Localize the open-panel prompt.
- Modify `TokenWatch/ViewModels/TokenStatsViewModel.swift`
  - Localize generic authorization and load-failure wrappers while preserving provider/error details.
- Modify existing view-controller tests where current assertions inspect Chinese text.

The project uses `PBXFileSystemSynchronizedRootGroup`; new Swift files under `TokenWatch` and `TokenWatchTests` are picked up by the targets automatically. Do not edit `TokenWatch.xcodeproj/project.pbxproj` for file references.

## Task 1: Language Settings Foundation

**Files:**
- Create: `TokenWatch/Localization/AppLanguage.swift`
- Create: `TokenWatch/Localization/AppStrings.swift`
- Create: `TokenWatchTests/Localization/AppLanguageSettingsTests.swift`

- [ ] **Step 1: Write failing language settings tests**

Add `TokenWatchTests/Localization/AppLanguageSettingsTests.swift`:

```swift
import Foundation
import Testing
@testable import TokenWatch

@MainActor
@Suite("AppLanguageSettings")
struct AppLanguageSettingsTests {
    @Test("缺失值回落到跟随系统")
    func missingPreferenceFallsBackToSystem() throws {
        try withTemporaryDefaults { defaults in
            let settings = AppLanguageSettings(defaults: defaults, preferredLanguagesProvider: { ["zh-Hans-US"] })

            #expect(settings.selectedPreference == .system)
            #expect(settings.resolvedLanguage == .zhHans)
        }
    }

    @Test("非法值回落到跟随系统")
    func invalidPreferenceFallsBackToSystem() throws {
        try withTemporaryDefaults { defaults in
            defaults.set("fr", forKey: AppLanguageSettings.storageKey)
            let settings = AppLanguageSettings(defaults: defaults, preferredLanguagesProvider: { ["en-US"] })

            #expect(settings.selectedPreference == .system)
            #expect(settings.resolvedLanguage == .en)
        }
    }

    @Test("中文系统语言解析为中文")
    func systemChineseResolvesToChinese() throws {
        try withTemporaryDefaults { defaults in
            let settings = AppLanguageSettings(defaults: defaults, preferredLanguagesProvider: { ["zh-Hant-TW"] })

            #expect(settings.resolvedLanguage == .zhHans)
        }
    }

    @Test("英文系统语言解析为英文")
    func systemEnglishResolvesToEnglish() throws {
        try withTemporaryDefaults { defaults in
            let settings = AppLanguageSettings(defaults: defaults, preferredLanguagesProvider: { ["en-US"] })

            #expect(settings.resolvedLanguage == .en)
        }
    }

    @Test("其他系统语言回落到英文")
    func unsupportedSystemLanguageFallsBackToEnglish() throws {
        try withTemporaryDefaults { defaults in
            let settings = AppLanguageSettings(defaults: defaults, preferredLanguagesProvider: { ["ja-JP"] })

            #expect(settings.resolvedLanguage == .en)
        }
    }

    @Test("选择英文会持久化并通知观察者")
    func selectingEnglishPersistsAndNotifies() throws {
        try withTemporaryDefaults { defaults in
            let settings = AppLanguageSettings(defaults: defaults, preferredLanguagesProvider: { ["zh-Hans-US"] })
            var notificationCount = 0
            let token = settings.observe { notificationCount += 1 }

            settings.selectedPreference = .en

            #expect(defaults.string(forKey: AppLanguageSettings.storageKey) == "en")
            #expect(settings.resolvedLanguage == .en)
            #expect(notificationCount == 1)

            settings.removeObserver(token)
            settings.selectedPreference = .zhHans
            #expect(notificationCount == 1)
        }
    }

    @Test("基础文案按语言返回")
    func stringsReturnLocalizedText() {
        #expect(AppStrings.text(.settingsTitle, language: .zhHans) == "设置")
        #expect(AppStrings.text(.settingsTitle, language: .en) == "Settings")
        #expect(AppLanguagePreference.system.title(language: .zhHans) == "跟随系统")
        #expect(AppLanguagePreference.system.title(language: .en) == "System")
    }
}

private func withTemporaryDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
    let suiteName = "AppLanguageSettingsTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    try body(defaults)
}
```

- [ ] **Step 2: Run the failing tests**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/AppLanguageSettingsTests test
```

Expected: FAIL because `AppLanguageSettings`, `AppLanguagePreference`, `AppLanguage`, `AppStringKey`, and `AppStrings` do not exist.

- [ ] **Step 3: Implement language settings**

Create `TokenWatch/Localization/AppLanguage.swift`:

```swift
import Foundation

enum AppLanguage: String, Sendable, Equatable {
    case zhHans
    case en
}

enum AppLanguagePreference: String, CaseIterable, Sendable, Equatable {
    case system
    case zhHans = "zh-Hans"
    case en

    func title(language: AppLanguage) -> String {
        switch self {
        case .system:
            return AppStrings.text(.languageSystem, language: language)
        case .zhHans:
            return AppStrings.text(.languageChinese, language: language)
        case .en:
            return AppStrings.text(.languageEnglish, language: language)
        }
    }
}

@MainActor
final class AppLanguageSettings {
    struct ObservationToken: Hashable, Sendable {
        let id: UUID
    }

    static let shared = AppLanguageSettings(defaults: .standard)
    static let storageKey = "TokenWatch.languagePreference"

    private let defaults: UserDefaults
    private let preferredLanguagesProvider: () -> [String]
    private var observers: [ObservationToken: @MainActor () -> Void] = [:]

    init(
        defaults: UserDefaults,
        preferredLanguagesProvider: @escaping () -> [String] = { Locale.preferredLanguages }
    ) {
        self.defaults = defaults
        self.preferredLanguagesProvider = preferredLanguagesProvider
    }

    var selectedPreference: AppLanguagePreference {
        get {
            defaults.string(forKey: Self.storageKey)
                .flatMap(AppLanguagePreference.init(rawValue:))
                ?? .system
        }
        set {
            guard selectedPreference != newValue else { return }
            defaults.set(newValue.rawValue, forKey: Self.storageKey)
            notifyChange()
        }
    }

    var resolvedLanguage: AppLanguage {
        switch selectedPreference {
        case .system:
            return Self.resolveSystemLanguage(preferredLanguagesProvider())
        case .zhHans:
            return .zhHans
        case .en:
            return .en
        }
    }

    static func resolveSystemLanguage(_ preferredLanguages: [String]) -> AppLanguage {
        guard let identifier = preferredLanguages.first?.lowercased() else {
            return .en
        }
        if identifier.hasPrefix("zh") {
            return .zhHans
        }
        if identifier.hasPrefix("en") {
            return .en
        }
        return .en
    }

    @discardableResult
    func observe(_ handler: @escaping @MainActor () -> Void) -> ObservationToken {
        let token = ObservationToken(id: UUID())
        observers[token] = handler
        return token
    }

    func removeObserver(_ token: ObservationToken) {
        observers.removeValue(forKey: token)
    }

    private func notifyChange() {
        for handler in Array(observers.values) {
            handler()
        }
    }
}
```

- [ ] **Step 4: Implement the first string table**

Create `TokenWatch/Localization/AppStrings.swift` with the keys needed by all planned tasks:

```swift
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
    static func text(_ key: AppStringKey, language: AppLanguage) -> String {
        switch language {
        case .zhHans:
            return zhHans[key] ?? en[key]!
        case .en:
            return en[key]!
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
```

- [ ] **Step 5: Run tests and commit**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/AppLanguageSettingsTests test
```

Expected: PASS.

Commit:

```bash
git add TokenWatch/Localization/AppLanguage.swift TokenWatch/Localization/AppStrings.swift TokenWatchTests/Localization/AppLanguageSettingsTests.swift
git commit -m "feat(i18n): 添加语言设置基础"
```

## Task 2: Settings Page And Sidebar Language Picker

**Files:**
- Modify: `TokenWatch/ViewController.swift`
- Modify: `TokenWatch/ViewControllers/StatusBarController.swift`
- Modify: `TokenWatchTests/TokenWatchTests.swift`

- [ ] **Step 1: Write failing settings and sidebar tests**

Append these tests to `TokenWatchTests/TokenWatchTests.swift`:

```swift
@MainActor
@Test func settingsShowsLanguageMenu() throws {
    try withTemporaryDefaults { defaults in
        let languageSettings = AppLanguageSettings(defaults: defaults, preferredLanguagesProvider: { ["zh-Hans-US"] })
        let settingsViewController = SettingsViewController(
            isAuthorized: { false },
            autoRefreshSettings: AutoRefreshSettings(defaults: defaults),
            languageSettings: languageSettings
        )
        settingsViewController.loadViewIfNeeded()

        #expect(settingsViewController.debugLanguageItemTitles == ["跟随系统", "中文", "English"])
        #expect(settingsViewController.debugLanguageSelectedTitle == "跟随系统")
    }
}

@MainActor
@Test func changingLanguagePersistsSelectionAndRefreshesSettingsLabels() throws {
    try withTemporaryDefaults { defaults in
        let languageSettings = AppLanguageSettings(defaults: defaults, preferredLanguagesProvider: { ["zh-Hans-US"] })
        let settingsViewController = SettingsViewController(
            isAuthorized: { false },
            autoRefreshSettings: AutoRefreshSettings(defaults: defaults),
            languageSettings: languageSettings
        )
        settingsViewController.loadViewIfNeeded()

        settingsViewController.debugSelectLanguagePreference(.en)

        let labels = settingsViewController.view.allDescendants(ofType: NSTextField.self).map(\.stringValue)
        #expect(defaults.string(forKey: AppLanguageSettings.storageKey) == "en")
        #expect(labels.contains("Settings"))
        #expect(labels.contains("Language"))
        #expect(settingsViewController.debugLanguageItemTitles == ["System", "Chinese", "English"])
        #expect(settingsViewController.debugLanguageSelectedTitle == "English")
    }
}

@MainActor
@Test func sidebarUsesEnglishTitlesWhenLanguageIsEnglish() throws {
    try withTemporaryDefaults { defaults in
        let languageSettings = AppLanguageSettings(defaults: defaults, preferredLanguagesProvider: { ["zh-Hans-US"] })
        languageSettings.selectedPreference = .en
        let viewController = ViewController(languageSettings: languageSettings)
        viewController.loadViewIfNeeded()

        let sidebar = try #require(viewController.view.firstDescendant(ofType: NSTableView.self))
        let displayedTitles = (0..<sidebar.numberOfRows).compactMap { row in
            (sidebar.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView)?
                .textField?
                .stringValue
        }

        #expect(displayedTitles == ["Total", "Last 12 Months", "Last 30 Days", "Today", "Settings"])
    }
}
```

- [ ] **Step 2: Run the failing tests**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/TokenWatchTests test
```

Expected: FAIL because `ViewController(languageSettings:)`, `SettingsViewController(...languageSettings:)`, and settings debug accessors do not exist.

- [ ] **Step 3: Localize auto-refresh option titles**

In `TokenWatch/ViewControllers/StatusBarController.swift`, replace `AutoRefreshIntervalOption.title` with:

```swift
func title(language: AppLanguage) -> String {
    switch self {
    case .seconds30:
        return AppStrings.text(.autoRefreshSeconds30, language: language)
    case .minute1:
        return AppStrings.text(.autoRefreshMinute1, language: language)
    case .minutes5:
        return AppStrings.text(.autoRefreshMinutes5, language: language)
    case .minutes15:
        return AppStrings.text(.autoRefreshMinutes15, language: language)
    case .disabled:
        return AppStrings.text(.autoRefreshDisabled, language: language)
    }
}
```

Keep this compatibility helper for existing code while updating call sites:

```swift
var title: String {
    title(language: .zhHans)
}
```

- [ ] **Step 4: Add language injection and sidebar refresh**

In `TokenWatch/ViewController.swift`, change stored properties so `ViewController` can be created from tests or storyboard:

```swift
private let languageSettings: AppLanguageSettings
private let splitViewController = NSSplitViewController()
private let detailContainerViewController = NSViewController()
private let sidebarViewController: ProviderSidebarViewController
private let settingsViewController: SettingsViewController
private let totalStatsViewController = TotalStatsViewController()
private let monthlyStatsViewController = MonthlyStatsViewController()
private let recentThirtyDaysStatsViewController = MonthlyStatsViewController(period: .recent30Days)
private let todayStatsViewController = MonthlyStatsViewController(period: .today)
private var languageObserverToken: AppLanguageSettings.ObservationToken?

init(languageSettings: AppLanguageSettings = .shared) {
    self.languageSettings = languageSettings
    self.sidebarViewController = ProviderSidebarViewController(languageSettings: languageSettings)
    self.settingsViewController = SettingsViewController(languageSettings: languageSettings)
    super.init(nibName: nil, bundle: nil)
}

required init?(coder: NSCoder) {
    self.languageSettings = .shared
    self.sidebarViewController = ProviderSidebarViewController(languageSettings: .shared)
    self.settingsViewController = SettingsViewController(languageSettings: .shared)
    super.init(coder: coder)
}
```

Task 3 and Task 4 add language injection to `TotalStatsViewController` and `MonthlyStatsViewController`; Task 2 must not call those future initializer overloads yet.

Add language observation in `viewDidLoad`:

```swift
override func viewDidLoad() {
    super.viewDidLoad()
    installSplitLayout()
    bindViewModel()
    bindLanguageSettings()
}

private func bindLanguageSettings() {
    languageObserverToken = languageSettings.observe { [weak self] in
        self?.sidebarViewController.reloadLocalizedText()
    }
}
```

In `deinit`, remove both observer tokens:

```swift
if let languageObserverToken {
    languageSettings.removeObserver(languageObserverToken)
}
```

Update `ProviderSidebarItem`:

```swift
func title(language: AppLanguage) -> String {
    switch self {
    case .total:
        return AppStrings.text(.sidebarTotal, language: language)
    case .monthly:
        return AppStrings.text(.sidebarRecent12Months, language: language)
    case .recentThirtyDays:
        return AppStrings.text(.sidebarRecent30Days, language: language)
    case .today:
        return AppStrings.text(.sidebarToday, language: language)
    case .settings:
        return AppStrings.text(.sidebarSettings, language: language)
    }
}
```

Update `ProviderSidebarViewController`:

```swift
private let languageSettings: AppLanguageSettings

init(languageSettings: AppLanguageSettings = .shared) {
    self.items = [.total, .monthly, .recentThirtyDays, .today, .settings]
    self.languageSettings = languageSettings
    super.init(nibName: nil, bundle: nil)
}

func reloadLocalizedText() {
    loadViewIfNeeded()
    tableView.reloadData()
}

func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let item = items[row]
    let cell = tableView.makeView(withIdentifier: Self.cellIdentifier, owner: self) as? NSTableCellView
        ?? makeCellView()
    cell.textField?.stringValue = item.title(language: languageSettings.resolvedLanguage)
    return cell
}
```

- [ ] **Step 5: Add the settings language popup**

In `SettingsViewController`, add properties:

```swift
private let languageLabel = NSTextField(labelWithString: "")
private let languagePopUpButton = NSPopUpButton(frame: .zero, pullsDown: false)
private let languageSettings: AppLanguageSettings
private var languageObserverToken: AppLanguageSettings.ObservationToken?

var debugLanguageItemTitles: [String] {
    languagePopUpButton.itemTitles
}

var debugLanguageSelectedTitle: String? {
    languagePopUpButton.titleOfSelectedItem
}

func debugSelectLanguagePreference(_ preference: AppLanguagePreference) {
    guard let index = AppLanguagePreference.allCases.firstIndex(of: preference) else { return }
    languagePopUpButton.selectItem(at: index)
    languageSelectionChanged()
}
```

Change the initializer:

```swift
init(
    isAuthorized: @escaping @MainActor () -> Bool = {
        SecurityScopedBookmarkManager.shared.hasBookmark(forKey: ProviderAuthorization.homeBookmarkKey)
    },
    autoRefreshSettings: AutoRefreshSettings = .shared,
    languageSettings: AppLanguageSettings = .shared
) {
    self.isAuthorized = isAuthorized
    self.autoRefreshSettings = autoRefreshSettings
    self.languageSettings = languageSettings
    super.init(nibName: nil, bundle: nil)
}

convenience init(isAuthorized: @escaping @MainActor () -> Bool, defaults: UserDefaults) {
    self.init(
        isAuthorized: isAuthorized,
        autoRefreshSettings: AutoRefreshSettings(defaults: defaults),
        languageSettings: AppLanguageSettings(defaults: defaults)
    )
}
```

In `setupSubviews()`, create the language row after the auto-refresh row:

```swift
languageLabel.font = .systemFont(ofSize: 13)
languagePopUpButton.target = self
languagePopUpButton.action = #selector(languagePopUpButtonChanged)

let languageStack = NSStackView(views: [languageLabel, languagePopUpButton])
languageStack.orientation = .horizontal
languageStack.alignment = .centerY
languageStack.spacing = 8
```

Place `languageStack` in `contentStack` between `autoRefreshIntervalStack` and `buttonStack`.

Add localization methods:

```swift
private func bindLanguageSettings() {
    languageObserverToken = languageSettings.observe { [weak self] in
        self?.applyLocalizedText()
    }
}

private func applyLocalizedText() {
    let language = languageSettings.resolvedLanguage
    titleLabel.stringValue = AppStrings.text(.settingsTitle, language: language)
    descriptionLabel.stringValue = AppStrings.text(.settingsDescription, language: language)
    authorizationTitleLabel.stringValue = AppStrings.text(.settingsAuthorizationTitle, language: language)
    refreshButton.title = AppStrings.text(.settingsRefreshAllData, language: language)
    autoRefreshIntervalLabel.stringValue = AppStrings.text(.settingsAutoRefreshInterval, language: language)
    languageLabel.stringValue = AppStrings.text(.settingsLanguage, language: language)
    rebuildAutoRefreshMenu(language: language)
    rebuildLanguageMenu(language: language)
    renderAuthorizationState()
}

private func rebuildAutoRefreshMenu(language: AppLanguage) {
    let selectedOption = autoRefreshSettings.selectedOption
    autoRefreshIntervalPopUpButton.removeAllItems()
    autoRefreshIntervalPopUpButton.addItems(withTitles: AutoRefreshIntervalOption.allCases.map { $0.title(language: language) })
    if let index = AutoRefreshIntervalOption.allCases.firstIndex(of: selectedOption) {
        autoRefreshIntervalPopUpButton.selectItem(at: index)
    }
}

private func rebuildLanguageMenu(language: AppLanguage) {
    let selectedPreference = languageSettings.selectedPreference
    languagePopUpButton.removeAllItems()
    languagePopUpButton.addItems(withTitles: AppLanguagePreference.allCases.map { $0.title(language: language) })
    if let index = AppLanguagePreference.allCases.firstIndex(of: selectedPreference) {
        languagePopUpButton.selectItem(at: index)
    }
}
```

Call `bindLanguageSettings()` and `applyLocalizedText()` from `viewDidLoad()` before `renderAuthorizationState()`:

```swift
override func viewDidLoad() {
    super.viewDidLoad()
    setupSubviews()
    bindLanguageSettings()
    applyLocalizedText()
}
```

Update button and popup actions:

```swift
private func renderAuthorizationState() {
    let language = languageSettings.resolvedLanguage
    if isAuthorized() {
        authorizationActionButton.title = AppStrings.text(.settingsAuthorized, language: language)
        authorizationActionButton.isEnabled = false
    } else {
        authorizationActionButton.title = AppStrings.text(.settingsAuthorize, language: language)
        authorizationActionButton.isEnabled = true
    }
}

@objc private func autoRefreshIntervalChanged() {
    let selectedIndex = autoRefreshIntervalPopUpButton.indexOfSelectedItem
    guard AutoRefreshIntervalOption.allCases.indices.contains(selectedIndex) else { return }
    autoRefreshSettings.selectedOption = AutoRefreshIntervalOption.allCases[selectedIndex]
}

@objc private func languagePopUpButtonChanged() {
    languageSelectionChanged()
}

private func languageSelectionChanged() {
    let selectedIndex = languagePopUpButton.indexOfSelectedItem
    guard AppLanguagePreference.allCases.indices.contains(selectedIndex) else { return }
    languageSettings.selectedPreference = AppLanguagePreference.allCases[selectedIndex]
}
```

Remove `languageObserverToken` in `deinit`:

```swift
deinit {
    if let languageObserverToken {
        languageSettings.removeObserver(languageObserverToken)
    }
}
```

- [ ] **Step 6: Run tests and commit**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/TokenWatchTests test
```

Expected: PASS.

Commit:

```bash
git add TokenWatch/ViewController.swift TokenWatch/ViewControllers/StatusBarController.swift TokenWatchTests/TokenWatchTests.swift
git commit -m "feat(i18n): 在设置页添加语言下拉列表"
```

## Task 3: Total Stats Page Localization

**Files:**
- Modify: `TokenWatch/ViewControllers/TotalStatsViewController.swift`
- Modify: `TokenWatchTests/ViewControllers/TotalStatsViewControllerTests.swift`

- [ ] **Step 1: Write failing English total-page test**

Append to `TotalStatsViewControllerTests`:

```swift
@MainActor
@Test("英文下展示总计页文案")
func rendersEnglishCopy() throws {
    let settings = AppLanguageSettings(defaults: temporaryDefaults(), preferredLanguagesProvider: { ["zh-Hans-US"] })
    settings.selectedPreference = .en
    let viewController = TotalStatsViewController(
        stateProvider: {
            [.claude: .init(stats: makeStats(total: 0), isLoading: false, errorMessage: nil, needsAuthorization: false)]
        },
        languageSettings: settings
    )

    viewController.loadViewIfNeeded()

    let labels = viewController.view.allDescendants(ofType: NSTextField.self).map(\.stringValue)
    #expect(labels.contains("Total"))
    #expect(labels.contains("All-time summary across providers"))
    #expect(labels.contains("Model Usage"))
    #expect(viewController.debugStatusText == "No total token data")
    #expect(viewController.debugRefreshButtonToolTip == "Refresh Now")
}
```

Add this helper near the test file helpers:

```swift
private func temporaryDefaults() -> UserDefaults {
    let suiteName = "TotalStatsViewControllerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
```

- [ ] **Step 2: Run the failing test**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/TotalStatsViewControllerTests/rendersEnglishCopy test
```

Expected: FAIL because `TotalStatsViewController` does not accept `languageSettings` and still uses hard-coded Chinese copy.

- [ ] **Step 3: Add language settings and localized text application**

In `TotalStatsViewController`, add:

```swift
private let languageSettings: AppLanguageSettings
private var languageObserverToken: AppLanguageSettings.ObservationToken?

private var language: AppLanguage {
    languageSettings.resolvedLanguage
}
```

Change the initializer signature:

```swift
init(
    stateProvider: @escaping @MainActor () -> [ProviderID: TokenStatsViewModel.ProviderState] = {
        (NSApp.delegate as? AppDelegate)?.viewModel.states ?? [:]
    },
    refreshAction: @escaping @MainActor () async -> Void = {
        if let viewModel = (NSApp.delegate as? AppDelegate)?.viewModel {
            await viewModel.loadAllStats()
        }
    },
    languageSettings: AppLanguageSettings = .shared
) {
    self.stateProvider = stateProvider
    self.refreshAction = refreshAction
    self.languageSettings = languageSettings
    super.init(nibName: nil, bundle: nil)
    self.title = AppStrings.text(.sidebarTotal, language: languageSettings.resolvedLanguage)
}
```

Replace hard-coded label initialization:

```swift
private let titleLabel = NSTextField(labelWithString: "")
private let subtitleLabel = NSTextField(labelWithString: "")
private let modelSectionTitleLabel = NSTextField(labelWithString: "")
private let emptyModelLabel = NSTextField(labelWithString: "")
```

Add language binding:

```swift
private func bindLanguageSettings() {
    languageObserverToken = languageSettings.observe { [weak self] in
        self?.applyLocalizedText()
        self?.render()
    }
}

private func applyLocalizedText() {
    title = AppStrings.text(.sidebarTotal, language: language)
    titleLabel.stringValue = AppStrings.text(.sidebarTotal, language: language)
    subtitleLabel.stringValue = AppStrings.text(.totalSubtitle, language: language)
    modelSectionTitleLabel.stringValue = AppStrings.text(.totalModelUsage, language: language)
    emptyModelLabel.stringValue = AppStrings.text(.totalEmptyModels, language: language)
    setRefreshButtonLoading(!refreshButton.isEnabled)
}
```

Call `bindLanguageSettings()` and `applyLocalizedText()` in `viewDidLoad()` before `render()`.

Remove the observer in `deinit`:

```swift
if let languageObserverToken {
    languageSettings.removeObserver(languageObserverToken)
}
```

- [ ] **Step 4: Localize status and refresh copy**

Replace `partialLoadingStatusText` comparisons with the localized value:

```swift
private var partialLoadingStatusText: String {
    AppStrings.text(.statusPartialLoading, language: language)
}

private func applyStatusText(_ text: String) {
    if text == partialLoadingStatusText {
        partialLoadingStatusLabel.stringValue = text
        partialLoadingStatusLabel.isHidden = false
        statusLabel.stringValue = ""
        statusLabel.isHidden = true
        return
    }
    partialLoadingStatusLabel.stringValue = ""
    partialLoadingStatusLabel.isHidden = true
    statusLabel.stringValue = text
    statusLabel.isHidden = text.isEmpty
}
```

Update refresh copy:

```swift
private func setRefreshButtonLoading(_ isLoading: Bool) {
    let symbolName = isLoading
        ? Self.refreshButtonLoadingSymbolName
        : Self.refreshButtonDefaultSymbolName
    let imageDescription = isLoading
        ? AppStrings.text(.refreshInProgress, language: language)
        : AppStrings.text(.refreshNow, language: language)
    setRefreshButtonSymbol(symbolName, accessibilityDescription: imageDescription)

    refreshButton.isEnabled = !isLoading
    refreshButton.toolTip = imageDescription
    refreshButton.setAccessibilityLabel(isLoading
        ? AppStrings.text(.refreshingTotalAccessibility, language: language)
        : AppStrings.text(.refreshTotalAccessibility, language: language))
}
```

Update status text:

```swift
private func statusText(for snapshot: TotalStatsSnapshot, totalProviderCount: Int) -> String {
    if totalProviderCount > 0
        && snapshot.loadingProviderCount == totalProviderCount
        && snapshot.loadedProviderCount == 0 {
        return AppStrings.text(.statusLoadingUsage, language: language)
    }
    if snapshot.loadedProviderCount == 0 && snapshot.unauthorizedProviderCount > 0 {
        return AppStrings.text(.statusNeedsHomeAuthorization, language: language)
    }
    if snapshot.loadedProviderCount == 0, let errorMessage = snapshot.errorMessages.first {
        return errorMessage
    }
    if snapshot.totalTokens == 0 {
        return AppStrings.text(.statusTotalNoTokenData, language: language)
    }
    if snapshot.loadingProviderCount > 0 {
        return AppStrings.text(.statusPartialLoading, language: language)
    }
    if let errorMessage = snapshot.errorMessages.first {
        return errorMessage
    }
    return ""
}
```

- [ ] **Step 5: Run total stats tests and commit**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/TotalStatsViewControllerTests test
```

Expected: PASS.

Commit:

```bash
git add TokenWatch/ViewControllers/TotalStatsViewController.swift TokenWatchTests/ViewControllers/TotalStatsViewControllerTests.swift
git commit -m "feat(i18n): 本地化总计页面"
```

## Task 4: Monthly Stats, Charts, And Share Views Localization

**Files:**
- Modify: `TokenWatch/ViewControllers/MonthlyStatsViewController.swift`
- Modify: `TokenWatch/ViewControllers/MonthlyTokenChartBuilder.swift`
- Modify: `TokenWatch/ViewControllers/MonthlyTokenChartView.swift`
- Modify: `TokenWatch/ViewControllers/MonthlyCostChartView.swift`
- Modify: `TokenWatch/ViewControllers/UsageSharePieChartView.swift`
- Modify: `TokenWatchTests/ViewControllers/MonthlyStatsViewControllerTests.swift`
- Modify: `TokenWatchTests/ViewControllers/MonthlyTokenChartViewTests.swift`
- Modify: `TokenWatchTests/ViewControllers/MonthlyCostChartViewTests.swift`
- Modify: `TokenWatchTests/ViewControllers/UsageSharePieChartViewTests.swift`
- Modify: `TokenWatchTests/ViewControllers/MonthlyTokenChartBuilderTests.swift`

- [ ] **Step 1: Write failing English monthly-page test**

Append to `MonthlyStatsViewControllerTests`:

```swift
@MainActor
@Test("英文下展示时间窗口页文案")
func rendersEnglishCopy() throws {
    let calendar = utcCalendar()
    let settings = AppLanguageSettings(defaults: temporaryDefaults(), preferredLanguagesProvider: { ["zh-Hans-US"] })
    settings.selectedPreference = .en
    let viewController = MonthlyStatsViewController(
        period: .recent30Days,
        stateProvider: {
            [.claude: .init(
                stats: makeStats(byDay: ["2026-06-20": makeSummary(total: 0)], byMonth: [:]),
                isLoading: false,
                errorMessage: nil,
                needsAuthorization: false
            )]
        },
        nowProvider: { date(2026, 6, 20, calendar: calendar) },
        calendar: calendar,
        languageSettings: settings
    )

    viewController.loadViewIfNeeded()

    let labels = viewController.view.allDescendants(ofType: NSTextField.self).map(\.stringValue)
    #expect(labels.contains("Last 30 Days"))
    #expect(labels.contains("Last 30 Days, Summary across providers"))
    #expect(labels.contains("Token Usage"))
    #expect(labels.contains("Cost"))
    #expect(labels.contains("Tool Share"))
    #expect(labels.contains("Model Share"))
    #expect(viewController.debugStatusText == "Last 30 Days has no token data")
    #expect(viewController.debugRefreshButtonToolTip == "Refresh Now")
}

private func temporaryDefaults() -> UserDefaults {
    let suiteName = "MonthlyStatsViewControllerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
```

- [ ] **Step 2: Write failing builder/chart English tests**

Add to `MonthlyTokenChartBuilderTests`:

```swift
@Test("英文标题、说明、空状态和小时标签")
func periodTextUsesEnglish() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 9))!
    let snapshot = MonthlyTokenChartBuilder.build(
        states: [:],
        period: .today,
        now: now,
        calendar: calendar,
        language: .en
    )

    #expect(UsageStatsPeriod.recent12Months.title(language: .en) == "Last 12 Months")
    #expect(UsageStatsPeriod.recent30Days.subtitle(language: .en) == "Last 30 Days, Summary across providers")
    #expect(UsageStatsPeriod.today.emptyDataText(language: .en) == "Today has no token data")
    #expect(snapshot.monthBuckets[9].monthLabel == "9")
}
```

Add to `MonthlyTokenChartViewTests`:

```swift
@MainActor
@Test("英文横轴标签使用英文格式")
func xAxisLabelsUseEnglishFormat() {
    let view = MonthlyTokenChartView()
    view.configure(with: MonthlyTokenChartSnapshot(
        monthBuckets: [
            MonthlyTokenBucket(
                id: "2026-06",
                monthKey: "2026-06",
                monthLabel: "Jun",
                totalTokens: 1_200_000,
                totalCost: 0,
                normalizedHeight: 1,
                normalizedCostHeight: 0,
                isCurrentMonth: true
            )
        ],
        totalTokens: 1_200_000,
        totalCost: 0,
        maxMonthlyTokens: 1_200_000,
        maxMonthlyCost: 0,
        toolShareSlices: [],
        modelShareSlices: [],
        loadedProviderCount: 1,
        loadingProviderCount: 0,
        unauthorizedProviderCount: 0,
        errorMessages: []
    ), language: .en)

    #expect(view.debugXAxisLabels == ["2026\nJun"])
}
```

- [ ] **Step 3: Run the failing monthly tests**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/MonthlyStatsViewControllerTests/rendersEnglishCopy test
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/MonthlyTokenChartBuilderTests/periodTextUsesEnglish test
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/MonthlyTokenChartViewTests/xAxisLabelsUseEnglishFormat test
```

Expected: FAIL because the monthly flow is not language-aware.

- [ ] **Step 4: Make period and builder language-aware**

In `UsageStatsPeriod`, replace text properties with language-aware methods and keep Chinese-compatible properties:

```swift
var title: String { title(language: .zhHans) }
var subtitle: String { subtitle(language: .zhHans) }
var emptyDataText: String { emptyDataText(language: .zhHans) }

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

func subtitle(language: AppLanguage) -> String {
    "\(title(language: language)), \(AppStrings.text(.periodSubtitleSuffix, language: language))"
}

func emptyDataText(language: AppLanguage) -> String {
    switch language {
    case .zhHans:
        return "\(title(language: language))\(AppStrings.text(.periodNoTokenDataSuffix, language: language))"
    case .en:
        return "\(title(language: language)) \(AppStrings.text(.periodNoTokenDataSuffix, language: language))"
    }
}
```

Change bucket labels:

```swift
fileprivate func bucketLabel(for date: Date, calendar: Calendar, language: AppLanguage) -> String {
    switch self {
    case .recent12Months:
        let month = calendar.component(.month, from: date)
        return Self.monthName(month, language: language)
    case .recent30Days:
        let components = calendar.dateComponents([.month, .day], from: date)
        return "\(components.month ?? 0)/\(components.day ?? 0)"
    case .today:
        let hour = calendar.component(.hour, from: date)
        return language == .zhHans ? "\(hour)时" : "\(hour)"
    }
}

private static func monthName(_ month: Int, language: AppLanguage) -> String {
    switch language {
    case .zhHans:
        return "\(month)月"
    case .en:
        let symbols = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        guard (1...12).contains(month) else { return "\(month)" }
        return symbols[month - 1]
    }
}
```

Change `MonthlyTokenChartBuilder.build` signature and call sites:

```swift
static func build(
    states: [ProviderID: TokenStatsViewModel.ProviderState],
    period: UsageStatsPeriod = .recent12Months,
    now: Date,
    calendar: Calendar,
    language: AppLanguage = .zhHans
) -> MonthlyTokenChartSnapshot
```

Use `period.bucketLabel(for: bucketStart, calendar: calendar, language: language)` and `AppStrings.text(.shareOther, language: language)` for the compacted model segment.

- [ ] **Step 5: Make chart and share views language-aware**

In `MonthlyBarChartStyle`, add a language parameter:

```swift
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
    case .zhHans:
        return "\(year)年\n\(month)月"
    case .en:
        return "\(year)\n\(englishMonthName(month))"
    }
}

private static func englishMonthName(_ month: Int) -> String {
    let symbols = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    guard (1...12).contains(month) else { return "\(month)" }
    return symbols[month - 1]
}
```

Change `MonthlyTokenChartView.configure`:

```swift
private var language: AppLanguage = .zhHans

func configure(with snapshot: MonthlyTokenChartSnapshot, language: AppLanguage = .zhHans) {
    self.language = language
    buckets = snapshot.monthBuckets
    debugNormalizedHeights = snapshot.monthBuckets.map { clampNormalizedHeight($0.normalizedHeight) }
    debugMonthLabels = snapshot.monthBuckets.map(\.monthLabel)
    debugXAxisLabels = snapshot.monthBuckets.map { MonthlyBarChartStyle.monthAxisLabel(for: $0.monthKey, language: language) }
    chartHost.rootView = AnyView(MonthlyTokenBarChartContent(
        buckets: snapshot.monthBuckets,
        language: language,
        onHoverMonthKeyChange: { [weak self] monthKey in
            self?.updateHoverText(monthKey: monthKey)
        }
    ))
}
```

Add `language` to `MonthlyTokenBarChartContent` and use it in axis and accessibility label:

```swift
let language: AppLanguage
...
Text(MonthlyBarChartStyle.monthAxisLabel(for: monthKey, language: language))
...
.accessibilityLabel(AppStrings.text(.chartTokenAccessibility, language: language))
```

Mirror the same changes in `MonthlyCostChartView`, using `.chartCostAccessibility`.

In `UsageSharePieChartView`, make title and language mutable:

```swift
private var language: AppLanguage = .zhHans
var debugTitle: String { titleLabel.stringValue }

func setTitle(_ title: String) {
    titleLabel.stringValue = title
}

func configure(slices: [UsageShareSlice], language: AppLanguage = .zhHans) {
    self.language = language
    let visibleSlices = slices.filter {
        $0.totalTokens > 0 && $0.percentage.isFinite && $0.percentage > 0
    }
    self.slices = Self.compactSlices(visibleSlices, language: language)
    drawingView.configure(slices: self.slices)
    rebuildLegend()
    updateHoverText(slice: nil)
    emptyLabel.stringValue = AppStrings.text(.shareEmpty, language: language)
    emptyLabel.isHidden = !self.slices.isEmpty
    legendStack.isHidden = self.slices.isEmpty
}

private static func compactSlices(_ slices: [UsageShareSlice], language: AppLanguage) -> [UsageShareSlice] {
    guard slices.count > maxLegendRowCount else { return slices }
    let leadingCount = maxLegendRowCount - 1
    let leadingSlices = Array(slices.prefix(leadingCount))
    let overflowSlices = slices.dropFirst(leadingCount)
    let otherTokens = overflowSlices.reduce(0) { $0 + $1.totalTokens }
    let otherPercentage = overflowSlices.reduce(0) { $0 + $1.percentage }
    guard otherTokens > 0, otherPercentage > 0 else { return leadingSlices }
    return leadingSlices + [
        UsageShareSlice(
            id: "other",
            label: AppStrings.text(.shareOther, language: language),
            totalTokens: otherTokens,
            percentage: otherPercentage
        ),
    ]
}
```

- [ ] **Step 6: Localize `MonthlyStatsViewController`**

Add language settings:

```swift
private let languageSettings: AppLanguageSettings
private var languageObserverToken: AppLanguageSettings.ObservationToken?

private var language: AppLanguage {
    languageSettings.resolvedLanguage
}
```

Change the initializer:

```swift
init(
    period: UsageStatsPeriod = .recent12Months,
    stateProvider: @escaping @MainActor () -> [ProviderID: TokenStatsViewModel.ProviderState] = {
        (NSApp.delegate as? AppDelegate)?.viewModel.states ?? [:]
    },
    refreshAction: @escaping @MainActor () async -> Void = {
        if let viewModel = (NSApp.delegate as? AppDelegate)?.viewModel {
            await viewModel.loadAllStats()
        }
    },
    nowProvider: @escaping () -> Date = Date.init,
    calendar: Calendar = .current,
    languageSettings: AppLanguageSettings = .shared
) {
    self.period = period
    self.stateProvider = stateProvider
    self.refreshAction = refreshAction
    self.nowProvider = nowProvider
    self.calendar = calendar
    self.languageSettings = languageSettings
    super.init(nibName: nil, bundle: nil)
    self.title = period.title(language: languageSettings.resolvedLanguage)
}
```

Replace hard-coded label initializers with empty strings for title, subtitle, token chart title, and cost chart title. Add:

```swift
private func bindLanguageSettings() {
    languageObserverToken = languageSettings.observe { [weak self] in
        self?.applyLocalizedText()
        self?.render()
    }
}

private func applyLocalizedText() {
    title = period.title(language: language)
    titleLabel.stringValue = period.title(language: language)
    subtitleLabel.stringValue = period.subtitle(language: language)
    tokenChartTitleLabel.stringValue = AppStrings.text(.chartTokenUsage, language: language)
    costChartTitleLabel.stringValue = AppStrings.text(.chartCost, language: language)
    toolSharePieView.setTitle(AppStrings.text(.shareTool, language: language))
    modelSharePieView.setTitle(AppStrings.text(.shareModel, language: language))
    setRefreshButtonLoading(!refreshButton.isEnabled)
}
```

In `render()`, pass language:

```swift
let snapshot = MonthlyTokenChartBuilder.build(
    states: states,
    period: period,
    now: nowProvider(),
    calendar: calendar,
    language: language
)
chartView.configure(with: snapshot, language: language)
costChartView.configure(with: snapshot, language: language)
toolSharePieView.configure(slices: snapshot.toolShareSlices, language: language)
modelSharePieView.configure(slices: snapshot.modelShareSlices, language: language)
```

Update status and refresh copy the same way as Task 3, using `.refreshUsageAccessibility` and `.refreshingUsageAccessibility`.

- [ ] **Step 7: Run monthly and chart tests, then commit**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/MonthlyStatsViewControllerTests test
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/MonthlyTokenChartBuilderTests test
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/MonthlyTokenChartViewTests test
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/MonthlyCostChartViewTests test
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/UsageSharePieChartViewTests test
```

Expected: PASS.

Commit:

```bash
git add TokenWatch/ViewControllers/MonthlyStatsViewController.swift TokenWatch/ViewControllers/MonthlyTokenChartBuilder.swift TokenWatch/ViewControllers/MonthlyTokenChartView.swift TokenWatch/ViewControllers/MonthlyCostChartView.swift TokenWatch/ViewControllers/UsageSharePieChartView.swift TokenWatchTests/ViewControllers/MonthlyStatsViewControllerTests.swift TokenWatchTests/ViewControllers/MonthlyTokenChartBuilderTests.swift TokenWatchTests/ViewControllers/MonthlyTokenChartViewTests.swift TokenWatchTests/ViewControllers/MonthlyCostChartViewTests.swift TokenWatchTests/ViewControllers/UsageSharePieChartViewTests.swift
git commit -m "feat(i18n): 本地化时间窗口统计页"
```

## Task 5: Status Bar, Popover, Heatmap, Authorization Copy

**Files:**
- Modify: `TokenWatch/ViewControllers/StatusBarController.swift`
- Modify: `TokenWatch/ViewControllers/StatusPopoverViewController.swift`
- Modify: `TokenWatch/ViewControllers/CalendarHeatmapBuilder.swift`
- Modify: `TokenWatch/Providers/UsageProvider.swift`
- Modify: `TokenWatch/Services/SecurityScopedBookmarkManager.swift`
- Modify: `TokenWatch/ViewModels/TokenStatsViewModel.swift`
- Modify: `TokenWatchTests/ViewControllers/StatusBarControllerTests.swift`
- Modify: `TokenWatchTests/ViewControllers/StatusPopoverViewControllerTests.swift`
- Modify: `TokenWatchTests/ViewControllers/CalendarHeatmapBuilderTests.swift`
- Modify: `TokenWatchTests/ViewModels/TokenStatsViewModelObserverTests.swift`

- [ ] **Step 1: Write failing status bar and popover tests**

Add to `StatusBarControllerTests`:

```swift
@MainActor
@Test func statusMenuUsesEnglishTitles() throws {
    let suiteName = "StatusBarControllerTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let languageSettings = AppLanguageSettings(defaults: defaults, preferredLanguagesProvider: { ["zh-Hans-US"] })
    languageSettings.selectedPreference = .en
    let controller = StatusBarController(
        viewModel: TokenStatsViewModel(),
        autoRefreshSettings: AutoRefreshSettings(defaults: defaults),
        languageSettings: languageSettings
    )
    defer { controller.stop() }

    #expect(controller.debugStatusMenuTitles == ["Open TokenWatch", "Refresh Now", "Quit TokenWatch"])
}
```

Add to `StatusPopoverViewControllerTests`:

```swift
@Test("英文下展示摘要和本日文案")
func rendersEnglishCopy() {
    let suiteName = "StatusPopoverViewControllerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let settings = AppLanguageSettings(defaults: defaults, preferredLanguagesProvider: { ["zh-Hans-US"] })
    settings.selectedPreference = .en
    let controller = StatusPopoverViewController(
        viewModel: TokenStatsViewModel(),
        nowProvider: { fixedDate() },
        calendar: fixedCalendar(),
        languageSettings: settings
    )

    controller.loadViewIfNeeded()

    #expect(controller.debugSummaryCards.map(\.title) == ["Month", "Week", "Today", "Daily Avg"])
    #expect(controller.debugTodayDescriptionText == "No token usage today")
    #expect(controller.debugRefreshButtonToolTip == "Refresh Now")
}

@Test("本日 token 英文文案按消耗分档")
func todayDescriptionTextUsesEnglish() {
    #expect(StatusPopoverDailyTokenDescription.text(forTodayTokens: 0, language: .en) == "No token usage today")
    #expect(StatusPopoverDailyTokenDescription.text(forTodayTokens: 100_000, language: .en) == "Today's token usage is picking up")
    #expect(StatusPopoverDailyTokenDescription.text(forTodayTokens: 6_700_000, language: .en) == "Today's token usage is off the charts")
}
```

Use a normal `suiteName` variable in the final test helper to remove the correct persistent domain.

- [ ] **Step 2: Run failing status tests**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/StatusBarControllerTests/statusMenuUsesEnglishTitles test
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/StatusPopoverViewControllerTests/rendersEnglishCopy test
```

Expected: FAIL because these types are not language-aware.

- [ ] **Step 3: Localize status bar menu and token unit**

In `StatusBarController`, add:

```swift
private let languageSettings: AppLanguageSettings
private var languageObserverToken: AppLanguageSettings.ObservationToken?

var debugStatusMenuTitles: [String] {
    statusMenu.items.filter { !$0.isSeparatorItem }.map(\.title)
}

private var language: AppLanguage {
    languageSettings.resolvedLanguage
}
```

Change initializer:

```swift
init(
    viewModel: TokenStatsViewModel,
    autoRefreshSettings: AutoRefreshSettings = .shared,
    languageSettings: AppLanguageSettings = .shared
) {
    self.viewModel = viewModel
    self.autoRefreshSettings = autoRefreshSettings
    self.languageSettings = languageSettings
    self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    configureButton()
    configurePopover()
    installMenu()
    subscribeToViewModel()
    subscribeToAutoRefreshSettings()
    subscribeToLanguageSettings()
    startRefreshTimer()
    renderTitle()
}
```

Make `installMenu()` rebuild the menu:

```swift
private func installMenu() {
    statusMenu.removeAllItems()
    let openItem = NSMenuItem(
        title: AppStrings.text(.statusMenuOpen, language: language),
        action: #selector(openMainWindow),
        keyEquivalent: "0"
    )
    openItem.target = self
    statusMenu.addItem(openItem)

    let refreshItem = NSMenuItem(
        title: AppStrings.text(.refreshNow, language: language),
        action: #selector(refreshNow),
        keyEquivalent: "r"
    )
    refreshItem.target = self
    statusMenu.addItem(refreshItem)

    statusMenu.addItem(NSMenuItem.separator())

    let quitItem = NSMenuItem(
        title: AppStrings.text(.statusMenuQuit, language: language),
        action: #selector(quitApp),
        keyEquivalent: "q"
    )
    quitItem.target = self
    statusMenu.addItem(quitItem)
}
```

Update attributed title:

```swift
result.append(NSAttributedString(
    string: "\n\(AppStrings.text(.statusBarTokenUnit, language: language))",
    attributes: [
        .font: NSFont.systemFont(ofSize: 7),
        .foregroundColor: NSColor.labelColor,
        .paragraphStyle: secondaryParagraph,
    ]
))
```

Add language subscription and cleanup:

```swift
private func subscribeToLanguageSettings() {
    languageObserverToken = languageSettings.observe { [weak self] in
        self?.installMenu()
        self?.renderTitle()
    }
}
```

Remove `languageObserverToken` in `stop()` and `deinit`.

- [ ] **Step 4: Localize popover and heatmap**

Change `CalendarHeatmapBuilder.build` signature:

```swift
static func build(
    states: [ProviderID: TokenStatsViewModel.ProviderState],
    month: Date,
    now: Date,
    calendar: Calendar,
    language: AppLanguage = .zhHans
) -> CalendarHeatmapSnapshot
```

Use:

```swift
monthTitle: AppStrings.text(.heatmapRecent22Weeks, language: language),
weekdaySymbols: weekdaySymbols(firstWeekday: calendar.firstWeekday, language: language),
```

Change weekday symbols:

```swift
private static func weekdaySymbols(firstWeekday: Int, language: AppLanguage) -> [String] {
    let symbols: [String]
    switch language {
    case .zhHans:
        symbols = ["日", "一", "二", "三", "四", "五", "六"]
    case .en:
        symbols = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    }
    let startIndex = max(0, min(6, firstWeekday - 1))
    return Array(symbols[startIndex...]) + Array(symbols[..<startIndex])
}
```

In `StatusPopoverViewController`, add language settings:

```swift
private let languageSettings: AppLanguageSettings
private var languageObserverToken: AppLanguageSettings.ObservationToken?

private var language: AppLanguage {
    languageSettings.resolvedLanguage
}
```

Change initializer:

```swift
init(
    viewModel: TokenStatsViewModel,
    nowProvider: @escaping () -> Date = Date.init,
    calendar: Calendar = .current,
    languageSettings: AppLanguageSettings = .shared
) {
    self.viewModel = viewModel
    self.nowProvider = nowProvider
    self.calendar = calendar
    self.languageSettings = languageSettings
    super.init(nibName: nil, bundle: nil)
    preferredContentSize = Self.contentSize
}
```

Add title updates to `SummaryMetricCardView`:

```swift
func updateTitle(_ title: String) {
    titleLabel.stringValue = title
    toolTip = "\(titleLabel.stringValue) \(valueLabel.stringValue) tokens"
}
```

Add:

```swift
private func applyLocalizedText() {
    let titles = [
        AppStrings.text(.popoverMonth, language: language),
        AppStrings.text(.popoverWeek, language: language),
        AppStrings.text(.popoverToday, language: language),
        AppStrings.text(.popoverDailyAverage, language: language),
    ]
    for (card, title) in zip(summaryCards, titles) {
        card.updateTitle(title)
    }
    applyTodayDescription(todayTokens: snapshot?.summary.todayTokens ?? 0)
    setRefreshButtonLoading(!todayRefreshButton.isEnabled)
}
```

In `render()`, pass language to the heatmap builder and call `applyLocalizedText()` after summary values are applied.

Update daily description:

```swift
static func text(forTodayTokens total: Int, language: AppLanguage = .zhHans) -> String {
    switch max(0, total) {
    case 0:
        return AppStrings.text(.popoverNoTodayTokens, language: language)
    case ..<100_000:
        return AppStrings.text(.popoverLowTodayTokens, language: language)
    case ..<3_300_000:
        return AppStrings.text(.popoverMediumTodayTokens, language: language)
    case ..<5_000_000:
        return AppStrings.text(.popoverHighTodayTokens, language: language)
    case ..<6_700_000:
        return AppStrings.text(.popoverVeryHighTodayTokens, language: language)
    default:
        return AppStrings.text(.popoverExtremeTodayTokens, language: language)
    }
}
```

Update refresh tooltip/accessibility in the same pattern as Task 3, using `.refreshTodayAccessibility` and `.refreshingTodayAccessibility`.

- [ ] **Step 5: Localize authorization and generic error wrappers**

Keep provider structs unchanged. Their `openPanelMessage` values can remain Chinese because `SecurityScopedBookmarkManager` will override the panel's user-visible message at presentation time with the active language.

In `SecurityScopedBookmarkManager.promptUserToSelectDirectory`, replace the panel message and prompt:

```swift
let language = AppLanguageSettings.shared.resolvedLanguage
panel.message = AppStrings.text(.homeAccessMessage, language: language)
panel.prompt = AppStrings.text(.authorizeAccessPrompt, language: language)
```

In `TokenStatsViewModel`, replace generic error assignments:

```swift
states[id]?.errorMessage = AppStrings.text(.errorCannotAccessHome, language: AppLanguageSettings.shared.resolvedLanguage)
...
let prefix = AppStrings.text(.errorLoadFailedPrefix, language: AppLanguageSettings.shared.resolvedLanguage)
states[id]?.errorMessage = "\(prefix): \(error.localizedDescription)"
```

Keep provider names and `error.localizedDescription` unchanged.

- [ ] **Step 6: Run status, heatmap, and view model tests, then commit**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/StatusBarControllerTests test
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/StatusPopoverViewControllerTests test
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/CalendarHeatmapBuilderTests test
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/TokenStatsViewModelObserverTests test
```

Expected: PASS.

Commit:

```bash
git add TokenWatch/ViewControllers/StatusBarController.swift TokenWatch/ViewControllers/StatusPopoverViewController.swift TokenWatch/ViewControllers/CalendarHeatmapBuilder.swift TokenWatch/Providers/UsageProvider.swift TokenWatch/Services/SecurityScopedBookmarkManager.swift TokenWatch/ViewModels/TokenStatsViewModel.swift TokenWatchTests/ViewControllers/StatusBarControllerTests.swift TokenWatchTests/ViewControllers/StatusPopoverViewControllerTests.swift TokenWatchTests/ViewControllers/CalendarHeatmapBuilderTests.swift TokenWatchTests/ViewModels/TokenStatsViewModelObserverTests.swift
git commit -m "feat(i18n): 本地化状态栏和授权文案"
```

## Task 6: Full Verification And Cleanup

**Files:**
- Modify: any test file with stale Chinese-only assertions found by the verification run.
- Modify: any app file still containing user-visible Chinese literals found by the audit.

- [ ] **Step 1: Audit remaining app-facing Chinese literals**

Run:

```bash
rg -n '"[^"\n]*[\p{Han}][^"\n]*"' TokenWatch
```

Expected: remaining matches are comments, log messages, fatalError developer diagnostics, test-only debug values, or intentionally untranslated provider/model names. Any match used as visible UI copy should be converted to `AppStrings`.

- [ ] **Step 2: Run the full unit test suite**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' test
```

Expected: PASS.

- [ ] **Step 3: Build the Debug app**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Debug build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit cleanup if files changed**

If Step 1 or failing tests required cleanup changes, commit them:

```bash
git add TokenWatch TokenWatchTests
git commit -m "test(i18n): 补齐语言切换验证"
```

If no files changed, skip the commit and record that the verification commands passed.
