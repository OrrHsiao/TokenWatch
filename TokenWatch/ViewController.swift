//
//  ViewController.swift
//  TokenWatch
//
//  Created by OrrHsiao on 2026/6/13.
//

import Cocoa

extension Notification.Name {
    static let providerStateDidChange = Notification.Name("providerStateDidChange")
}

/// 主视图控制器 — 承载 Pencil 设计稿对应的深色 Dashboard 主界面。
class ViewController: NSViewController {

    private let languageSettings: AppLanguageSettings
    private let settingsViewController: SettingsViewController
    private let dashboardViewController: DashboardViewController

    /// 通过 NSApp.delegate 获取与 AppDelegate 同一个 ViewModel 实例
    private var viewModel: TokenStatsViewModel? {
        (NSApp.delegate as? AppDelegate)?.viewModel
    }

    /// observer 凭证 — 用于 deinit 时取消订阅,避免 ViewModel 持有失效闭包
    private var observerToken: TokenStatsViewModel.ObservationToken?

    /// - Parameters:
    ///   - languageSettings: 界面语言设置。
    ///   - widgetPurchaseController: 小组件与订阅额度共用的购买控制器。
    ///   - quotaAccess: 订阅额度解锁状态；nil 时按购买控制器派生。
    ///   - quotaStore: 与状态栏共享的订阅额度 store；设置页数据源区块用它授权 Claude 额度文件。
    init(
        languageSettings: AppLanguageSettings = .shared,
        widgetPurchaseController: WidgetPurchaseController? = nil,
        quotaAccess: SubscriptionQuotaAccess? = nil,
        quotaStore: SubscriptionQuotaStore? = nil
    ) {
        self.languageSettings = languageSettings
        self.settingsViewController = SettingsViewController(
            languageSettings: languageSettings,
            quotaAccess: quotaAccess ?? SubscriptionQuotaAccess(purchaseController: widgetPurchaseController),
            quotaStore: quotaStore
        )
        self.dashboardViewController = DashboardViewController(
            settingsViewController: settingsViewController,
            widgetPurchaseController: widgetPurchaseController,
            languageSettings: languageSettings
        )
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        let languageSettings = AppLanguageSettings.shared
        self.languageSettings = languageSettings
        self.settingsViewController = SettingsViewController(languageSettings: languageSettings)
        self.dashboardViewController = DashboardViewController(
            settingsViewController: settingsViewController,
            widgetPurchaseController: nil,
            languageSettings: languageSettings
        )
        super.init(coder: coder)
    }

    override func loadView() {
        view = DashboardGlassBackgroundView(
            frame: NSRect(origin: .zero, size: MainWindowFactory.contentSize),
            acceptsFirstResponder: true
        )
        view.setAccessibilityIdentifier("DashboardRootView")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        installDashboard()
        bindViewModel()
    }

    /// 安装 Pencil Dashboard 根视图。
    private func installDashboard() {
        addChild(dashboardViewController)
        dashboardViewController.view.translatesAutoresizingMaskIntoConstraints = false
        if let rootView = view as? DashboardGlassBackgroundView {
            rootView.addContentSubview(dashboardViewController.view)
        } else {
            view.addSubview(dashboardViewController.view)
        }

        NSLayoutConstraint.activate([
            dashboardViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dashboardViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dashboardViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            dashboardViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    /// 响应主菜单设置入口,同步选中侧边栏设置项并展示设置页。
    @objc func showSettingsFromMainMenu(_ sender: Any?) {
        dashboardViewController.showSettings()
    }

    /// 展示设置页并滚动到“状态栏订阅额度”区块,用于状态栏弹窗的解锁入口。
    func showStatusBarQuotaSettings() {
        dashboardViewController.showSettings()
        settingsViewController.revealStatusBarQuotaSection()
    }

    /// 把 ViewModel 的状态变更回调多路复用到 Notification,
    /// Dashboard 自行订阅并按需刷新。
    private func bindViewModel() {
        observerToken = viewModel?.observe { providerID in
            NotificationCenter.default.post(
                name: .providerStateDidChange,
                object: nil,
                userInfo: ["providerID": providerID]
            )
        }
    }

    deinit {
        MainActor.assumeIsolated {
            if let token = observerToken {
                // 由 AppDelegate 强引用的 ViewModel 仍存活;deinit 在 main actor 调度路径中触发,
                // 用 assumeIsolated 同步移除,避免 fire-and-forget Task 在销毁后仍 fire 闭包
                (NSApp.delegate as? AppDelegate)?.viewModel.removeObserver(token)
            }
        }
    }
}

/// 设置页滚动内容使用翻转坐标,内容不足一屏时保持顶部对齐。
private final class SettingsDocumentView: NSView {
    override var isFlipped: Bool { true }
}

private final class VerticallyCenteredTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        centeredTextRect(forBounds: rect)
    }

    private func centeredTextRect(forBounds rect: NSRect) -> NSRect {
        let contentRect = super.drawingRect(forBounds: rect)
        guard let font else { return contentRect }

        // AppKit keeps the native text baseline when a regular field is stretched
        // to the shared 32pt settings-control height, so center its single line explicitly.
        let lineHeight = min(
            ceil(font.ascender - font.descender + font.leading),
            contentRect.height
        )
        return NSRect(
            x: contentRect.minX,
            y: floor(contentRect.midY - lineHeight / 2),
            width: contentRect.width,
            height: lineHeight
        )
    }
}

private final class VerticallyCenteredTextField: NSTextField {
    override class var cellClass: AnyClass? {
        get { VerticallyCenteredTextFieldCell.self }
        set {}
    }
}

/// 设置页统一的透明描边下拉框。
final class SettingsPopUpButton: NSPopUpButton, DashboardAppearanceRefreshable {
    init() {
        super.init(frame: .zero, pullsDown: false)
        userInterfaceLayoutDirection = .leftToRight
        menu?.userInterfaceLayoutDirection = .leftToRight
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.borderWidth = 1
        isBordered = false
        focusRingType = .none
        font = .systemFont(ofSize: 13, weight: .medium)
        contentTintColor = DashboardPalette.primaryText
        applyDashboardLayerColors()
    }

    required init?(coder: NSCoder) {
        fatalError("SettingsPopUpButton 必须用 init() 构造")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshDashboardAppearance()
    }

    func refreshDashboardAppearance() {
        applyDashboardLayerColors()
    }

    func applyDashboardLayerColors() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.borderColor = DashboardLayerColor.cgColor(DashboardPalette.glassControlBorder, for: self)
    }
}

private final class SettingsStatusDotView: NSView, DashboardAppearanceRefreshable {
    private var color: NSColor

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 4
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 8),
            heightAnchor.constraint(equalToConstant: 8),
        ])
        updateColor()
    }

    required init?(coder: NSCoder) {
        fatalError("SettingsStatusDotView 必须使用 init(color:) 构造")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshDashboardAppearance()
    }

    func setColor(_ color: NSColor) {
        self.color = color
        updateColor()
    }

    func refreshDashboardAppearance() {
        updateColor()
    }

    private func updateColor() {
        layer?.backgroundColor = DashboardLayerColor.cgColor(color, for: self)
    }
}

enum ProviderDirectoryActionStyle: Sendable, Equatable {
    case primary
    case neutral
}

enum ProviderDirectoryStatusStyle: Sendable, Equatable {
    case success
    case warning
    case error
}

struct ProviderDirectoryRowModel: Sendable, Equatable {
    let providerID: ProviderID
    let providerName: String
    let statusText: String
    let statusStyle: ProviderDirectoryStatusStyle
    let showsStatus: Bool
    let actionTitle: String
    let actionStyle: ProviderDirectoryActionStyle
    let showsAction: Bool
    let isActionEnabled: Bool

    /// 根据单一 provider 状态生成设置行，不读取共享 bookmark 或其他 provider。
    static func make(
        provider: any UsageProvider,
        state: TokenStatsViewModel.ProviderState,
        language: AppLanguage
    ) -> ProviderDirectoryRowModel {
        let statusKey: AppStringKey
        let actionKey: AppStringKey
        let actionStyle: ProviderDirectoryActionStyle
        let statusStyle: ProviderDirectoryStatusStyle
        let showsStatus: Bool
        let showsAction: Bool
        switch state.directoryState {
        case .notSelected:
            statusKey = .settingsDirectoryNotSelected
            actionKey = .settingsChooseDirectory
            actionStyle = .primary
            statusStyle = state.directoryAuthorizationErrorMessage == nil ? .warning : .error
            showsStatus = true
            showsAction = true
        case .selected:
            statusKey = .settingsDirectorySelected
            actionKey = .settingsReselectDirectory
            actionStyle = .neutral
            statusStyle = .success
            showsStatus = true
            showsAction = true
        case .selectedNoData:
            statusKey = .settingsDirectoryNoData
            actionKey = .settingsReselectDirectory
            actionStyle = .neutral
            statusStyle = .warning
            showsStatus = true
            showsAction = true
        case .needsReselection:
            statusKey = .settingsDirectoryNeedsReselection
            actionKey = .settingsChooseAgain
            actionStyle = .neutral
            statusStyle = state.directoryAuthorizationErrorMessage == nil ? .warning : .error
            showsStatus = true
            showsAction = true
        }

        let statusText = state.directoryAuthorizationErrorMessage
            ?? AppStrings.text(statusKey, language: language)

        return ProviderDirectoryRowModel(
            providerID: provider.id,
            providerName: provider.displayName,
            statusText: statusText,
            statusStyle: statusStyle,
            showsStatus: showsStatus,
            actionTitle: AppStrings.text(actionKey, language: language),
            actionStyle: actionStyle,
            showsAction: showsAction,
            isActionEnabled: showsAction && !state.isLoading && !state.isAuthorizing
        )
    }
}

/// 设置页数据源区块中“Claude 额度文件”行的展示模型。
///
/// 额度文件不是 token 统计 provider，授权状态来自 `SubscriptionQuotaStore`，
/// 文案与配色沿用目录行，使两类数据源在同一区块内保持一致。
struct ClaudeQuotaFileRowModel: Sendable, Equatable {
    let statusText: String
    let statusStyle: ProviderDirectoryStatusStyle
    let actionTitle: String
    let actionStyle: ProviderDirectoryActionStyle
    let isActionEnabled: Bool

    /// - Parameters:
    ///   - hasBookmark: 是否已保存 `.claude.json` 的 bookmark。
    ///   - state: store 中 Claude 额度的最近读取状态。
    ///   - isAuthorizing: 文件面板是否正在展示。
    ///   - language: 界面语言。
    static func make(
        hasBookmark: Bool,
        state: SubscriptionQuotaProviderState,
        isAuthorizing: Bool,
        language: AppLanguage
    ) -> ClaudeQuotaFileRowModel {
        let statusKey: AppStringKey
        let statusStyle: ProviderDirectoryStatusStyle
        let actionKey: AppStringKey
        let actionStyle: ProviderDirectoryActionStyle
        if !hasBookmark {
            statusKey = .settingsDirectoryNotSelected
            statusStyle = .warning
            actionKey = .settingsChooseDirectory
            actionStyle = .primary
        } else if state.result == .notAuthorized {
            // 有 bookmark 却读成未授权，只会是 bookmark 恢复失败（文件被移动或授权失效）。
            statusKey = .settingsDirectoryNeedsReselection
            statusStyle = .warning
            actionKey = .settingsChooseAgain
            actionStyle = .neutral
        } else if state.lastReadFailed {
            statusKey = .quotaReadFailed
            statusStyle = .error
            actionKey = .settingsReselectDirectory
            actionStyle = .neutral
        } else {
            statusKey = .settingsDirectorySelected
            statusStyle = .success
            actionKey = .settingsReselectDirectory
            actionStyle = .neutral
        }
        return ClaudeQuotaFileRowModel(
            statusText: AppStrings.text(statusKey, language: language),
            statusStyle: statusStyle,
            actionTitle: AppStrings.text(actionKey, language: language),
            actionStyle: actionStyle,
            isActionEnabled: !isAuthorizing
        )
    }
}

/// 通用设置页，承载各 provider 目录、刷新、自动刷新、应用偏好与状态栏订阅额度配置。
final class SettingsViewController: NSViewController {
    static let minimumContentHeight: CGFloat = 810
    private static let directoryActionHorizontalPadding: CGFloat = 24
    private static let valueControlWidth: CGFloat = 132
    private static let valueControlHeight: CGFloat = 32

    private struct ProviderDirectoryRowViews {
        let nameLabel: NSTextField
        let statusDotView: SettingsStatusDotView
        let statusLabel: NSTextField
        let actionButton: DashboardRangeButton
        let actionButtonWidthConstraint: NSLayoutConstraint
    }

    private let titleLabel = NSTextField(labelWithString: "")
    private let descriptionLabel = NSTextField(labelWithString: "")
    private let dataFoldersTitleLabel = NSTextField(labelWithString: "")
    private let dataRefreshTitleLabel = NSTextField(labelWithString: "")
    private let appPreferencesTitleLabel = NSTextField(labelWithString: "")
    private let providerDirectoryStack = NSStackView()
    private let refreshButton = DashboardRangeButton(title: "", target: nil, action: nil)
    private let autoRefreshIntervalLabel = NSTextField(labelWithString: "")
    private let autoRefreshIntervalPopUpButton = SettingsPopUpButton()
    private let launchAtLoginLabel = NSTextField(labelWithString: "")
    private let launchAtLoginSwitch = NSSwitch(frame: .zero)
    private let launchAtLoginStatusLabel = NSTextField(labelWithString: "")
    private let openLoginItemsSettingsButton = DashboardRangeButton(title: "", target: nil, action: nil)
    private let openLoginItemsSettingsRow = NSStackView()
    private let languageLabel = NSTextField(labelWithString: "")
    private let languagePopUpButton = SettingsPopUpButton()
    private let monthlyBudgetLabel = NSTextField(labelWithString: "")
    private let monthlyBudgetTextField = VerticallyCenteredTextField(string: "")
    private let statusBarQuotaTitleLabel = NSTextField(labelWithString: "")
    private let scrollView = NSScrollView()
    private var statusBarQuotaSection: NSView?
    private var statusBarQuotaSettingsView: StatusBarQuotaSettingsView?

    private let providers: [any UsageProvider]
    private let providerState:
        @MainActor (ProviderID) -> TokenStatsViewModel.ProviderState?
    private let authorizationAction:
        @MainActor (ProviderID) async -> Bool
    private let loginItemSettings: LoginItemSettingsControlling
    private let autoRefreshSettings: AutoRefreshSettings
    private let languageSettings: AppLanguageSettings
    private let monthlyBudgetSettings: MonthlyBudgetSettings
    private let displaySettings: StatusBarDisplaySettings
    private let quotaAccess: SubscriptionQuotaAccess
    /// 订阅额度 store；nil 时（测试、预览）不展示 Claude 额度文件行。
    private let quotaStore: SubscriptionQuotaStore?

    private var providerDirectoryRows:
        [ProviderID: ProviderDirectoryRowViews] = [:]
    private var claudeQuotaFileRow: ProviderDirectoryRowViews?
    /// Claude 额度文件行及其上方分隔线，未解锁订阅额度时整体隐藏。
    private var claudeQuotaFileRowContainers: [NSView] = []
    private var isAuthorizingClaudeQuotaFile = false
    private var languageSettingsObserverToken:
        AppLanguageSettings.ObservationToken?
    private var quotaStoreObserverToken: SubscriptionQuotaStore.ObservationToken?
    private var quotaAccessObserverToken: SubscriptionQuotaAccess.ObservationToken?

    private var viewModel: TokenStatsViewModel? {
        (NSApp.delegate as? AppDelegate)?.viewModel
    }

    init(
        providers: [any UsageProvider] = ProviderRegistry.allProviders,
        providerState: @escaping @MainActor (ProviderID) -> TokenStatsViewModel.ProviderState? = { id in
            (NSApp.delegate as? AppDelegate)?.viewModel.states[id]
        },
        authorizationAction: @escaping @MainActor (ProviderID) async -> Bool = { id in
            guard let viewModel = (NSApp.delegate as? AppDelegate)?.viewModel else {
                return false
            }
            return await viewModel.requestAuthorization(for: id)
        },
        loginItemSettings: LoginItemSettingsControlling = LoginItemSettings.shared,
        autoRefreshSettings: AutoRefreshSettings = .shared,
        languageSettings: AppLanguageSettings = .shared,
        monthlyBudgetSettings: MonthlyBudgetSettings = .shared,
        displaySettings: StatusBarDisplaySettings = .shared,
        quotaAccess: SubscriptionQuotaAccess = SubscriptionQuotaAccess(isUnlocked: false),
        quotaStore: SubscriptionQuotaStore? = nil
    ) {
        self.providers = providers
        self.providerState = providerState
        self.authorizationAction = authorizationAction
        self.loginItemSettings = loginItemSettings
        self.autoRefreshSettings = autoRefreshSettings
        self.languageSettings = languageSettings
        self.monthlyBudgetSettings = monthlyBudgetSettings
        self.displaySettings = displaySettings
        self.quotaAccess = quotaAccess
        self.quotaStore = quotaStore
        super.init(nibName: nil, bundle: nil)
    }

    convenience init(
        isAuthorized: @escaping @MainActor () -> Bool,
        loginItemSettings: LoginItemSettingsControlling = LoginItemSettings.shared,
        autoRefreshSettings: AutoRefreshSettings = .shared,
        languageSettings: AppLanguageSettings = .shared,
        monthlyBudgetSettings: MonthlyBudgetSettings = .shared,
        displaySettings: StatusBarDisplaySettings = .shared,
        quotaAccess: SubscriptionQuotaAccess = SubscriptionQuotaAccess(isUnlocked: false)
    ) {
        self.init(
            providers: ProviderRegistry.allProviders,
            providerState: { _ in
                let authorized = isAuthorized()
                return .init(
                    stats: nil,
                    entries: nil,
                    needsAuthorization: !authorized,
                    directoryState: authorized ? .selected : .notSelected
                )
            },
            authorizationAction: { _ in false },
            loginItemSettings: loginItemSettings,
            autoRefreshSettings: autoRefreshSettings,
            languageSettings: languageSettings,
            monthlyBudgetSettings: monthlyBudgetSettings,
            displaySettings: displaySettings,
            quotaAccess: quotaAccess
        )
    }

    convenience init(isAuthorized: @escaping @MainActor () -> Bool, defaults: UserDefaults) {
        self.init(
            isAuthorized: isAuthorized,
            autoRefreshSettings: AutoRefreshSettings(defaults: defaults),
            languageSettings: AppLanguageSettings(defaults: defaults),
            monthlyBudgetSettings: MonthlyBudgetSettings(defaults: defaults),
            displaySettings: StatusBarDisplaySettings(defaults: defaults)
        )
    }

    required init?(coder: NSCoder) {
        fatalError("SettingsViewController 必须使用代码 initializer 构造")
    }

    override func loadView() {
        view = NSView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: 480,
                height: Self.minimumContentHeight
            )
        )
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupSubviews()
        subscribeToLanguageSettings()
        subscribeToQuotaUpdates()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive(_:)),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(providerStateDidChange(_:)),
            name: .providerStateDidChange,
            object: nil
        )
        renderAllDirectoryRows()
        renderLaunchAtLoginState()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        renderAllDirectoryRows()
        renderLaunchAtLoginState()
    }

    private func setupSubviews() {
        titleLabel.font = .systemFont(ofSize: 26, weight: .bold)
        titleLabel.textColor = DashboardPalette.primaryText

        descriptionLabel.font = .systemFont(ofSize: 12)
        descriptionLabel.textColor = DashboardPalette.secondaryText
        descriptionLabel.lineBreakMode = .byWordWrapping
        descriptionLabel.maximumNumberOfLines = 0

        configureSectionTitle(
            dataFoldersTitleLabel,
            identifier: "DataFoldersTitleLabel"
        )
        configureSectionTitle(
            dataRefreshTitleLabel,
            identifier: "DataRefreshTitleLabel"
        )
        configureSectionTitle(
            appPreferencesTitleLabel,
            identifier: "AppPreferencesTitleLabel"
        )
        configureSectionTitle(
            statusBarQuotaTitleLabel,
            identifier: "StatusBarQuotaTitleLabel"
        )

        configureProviderDirectoryRows()

        autoRefreshIntervalLabel.font = .systemFont(ofSize: 13)
        autoRefreshIntervalLabel.textColor = DashboardPalette.primaryText

        autoRefreshIntervalPopUpButton.identifier = NSUserInterfaceItemIdentifier("AutoRefreshIntervalPopUpButton")
        autoRefreshIntervalPopUpButton.setAccessibilityIdentifier("AutoRefreshIntervalPopUpButton")
        autoRefreshIntervalPopUpButton.target = self
        autoRefreshIntervalPopUpButton.action = #selector(autoRefreshIntervalChanged)

        launchAtLoginLabel.font = .systemFont(ofSize: 13)
        launchAtLoginLabel.textColor = DashboardPalette.primaryText
        launchAtLoginSwitch.identifier = NSUserInterfaceItemIdentifier("LaunchAtLoginSwitch")
        launchAtLoginSwitch.setAccessibilityIdentifier("LaunchAtLoginSwitch")
        launchAtLoginSwitch.target = self
        launchAtLoginSwitch.action = #selector(launchAtLoginSwitchChanged)

        launchAtLoginStatusLabel.font = .systemFont(ofSize: 12)
        launchAtLoginStatusLabel.textColor = DashboardPalette.secondaryText
        launchAtLoginStatusLabel.maximumNumberOfLines = 0
        launchAtLoginStatusLabel.lineBreakMode = .byWordWrapping
        launchAtLoginStatusLabel.identifier = NSUserInterfaceItemIdentifier("LaunchAtLoginStatusLabel")
        launchAtLoginStatusLabel.setAccessibilityIdentifier("LaunchAtLoginStatusLabel")

        configureSettingsButton(openLoginItemsSettingsButton)
        openLoginItemsSettingsButton.identifier = NSUserInterfaceItemIdentifier("OpenLoginItemsSettingsButton")
        openLoginItemsSettingsButton.setAccessibilityIdentifier("OpenLoginItemsSettingsButton")
        openLoginItemsSettingsButton.target = self
        openLoginItemsSettingsButton.action = #selector(openLoginItemsSettingsButtonClicked)

        languageLabel.font = .systemFont(ofSize: 13)
        languageLabel.textColor = DashboardPalette.primaryText
        languagePopUpButton.identifier = NSUserInterfaceItemIdentifier("LanguagePreferencePopUpButton")
        languagePopUpButton.setAccessibilityIdentifier("LanguagePreferencePopUpButton")
        languagePopUpButton.target = self
        languagePopUpButton.action = #selector(languagePreferenceChanged)

        monthlyBudgetLabel.font = .systemFont(ofSize: 13)
        monthlyBudgetLabel.textColor = DashboardPalette.primaryText
        monthlyBudgetTextField.identifier = NSUserInterfaceItemIdentifier("MonthlyBudgetTextField")
        monthlyBudgetTextField.setAccessibilityIdentifier("MonthlyBudgetTextField")
        monthlyBudgetTextField.placeholderString = "USD"
        monthlyBudgetTextField.alignment = .right
        monthlyBudgetTextField.font = .systemFont(ofSize: 13)
        monthlyBudgetTextField.target = self
        monthlyBudgetTextField.action = #selector(monthlyBudgetChanged)

        configureSettingsButton(refreshButton)
        refreshButton.identifier = NSUserInterfaceItemIdentifier("RefreshAllDataButton")
        refreshButton.setAccessibilityIdentifier("RefreshAllDataButton")
        refreshButton.target = self
        refreshButton.action = #selector(refreshButtonClicked)
        refreshButton.image = NSImage(
            systemSymbolName: "arrow.clockwise",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(
            .init(pointSize: 13, weight: .semibold)
        )
        refreshButton.image?.isTemplate = true
        refreshButton.imagePosition = .imageLeading
        refreshButton.imageHugsTitle = true
        refreshButton.setContentHuggingPriority(.required, for: .horizontal)
        refreshButton.setContentCompressionResistancePriority(
            .required,
            for: .horizontal
        )
        refreshButton.widthAnchor.constraint(
            greaterThanOrEqualToConstant: 104
        ).isActive = true

        let refreshRowSpacer = makeFlexibleSpacer()
        let refreshRow = NSStackView(views: [
            autoRefreshIntervalLabel,
            refreshRowSpacer,
            autoRefreshIntervalPopUpButton,
        ])
        refreshRow.orientation = .horizontal
        refreshRow.alignment = .centerY
        refreshRow.spacing = 12
        autoRefreshIntervalLabel.lineBreakMode = .byTruncatingTail
        autoRefreshIntervalLabel.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )
        autoRefreshIntervalPopUpButton.widthAnchor.constraint(
            equalToConstant: Self.valueControlWidth
        ).isActive = true
        autoRefreshIntervalPopUpButton.heightAnchor.constraint(
            equalToConstant: Self.valueControlHeight
        ).isActive = true

        let titleRowSpacer = makeFlexibleSpacer()
        let titleRow = NSStackView(views: [
            titleLabel,
            titleRowSpacer,
            refreshButton,
        ])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 12

        let languageRowSpacer = makeFlexibleSpacer()
        let languageRow = NSStackView(views: [
            languageLabel,
            languageRowSpacer,
            languagePopUpButton,
        ])
        languageRow.orientation = .horizontal
        languageRow.alignment = .centerY
        languageRow.spacing = 12
        languagePopUpButton.widthAnchor.constraint(
            equalToConstant: Self.valueControlWidth
        ).isActive = true
        languagePopUpButton.heightAnchor.constraint(
            equalToConstant: Self.valueControlHeight
        ).isActive = true

        let monthlyBudgetRowSpacer = makeFlexibleSpacer()
        let monthlyBudgetRow = NSStackView(views: [
            monthlyBudgetLabel,
            monthlyBudgetRowSpacer,
            monthlyBudgetTextField,
        ])
        monthlyBudgetRow.orientation = .horizontal
        monthlyBudgetRow.alignment = .centerY
        monthlyBudgetRow.spacing = 12
        monthlyBudgetLabel.lineBreakMode = .byTruncatingTail
        monthlyBudgetLabel.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )
        monthlyBudgetTextField.widthAnchor.constraint(
            equalToConstant: Self.valueControlWidth
        ).isActive = true
        monthlyBudgetTextField.heightAnchor.constraint(
            equalToConstant: Self.valueControlHeight
        ).isActive = true

        let launchAtLoginRowSpacer = makeFlexibleSpacer()
        let launchAtLoginControlRow = NSStackView(views: [
            launchAtLoginLabel,
            launchAtLoginRowSpacer,
            launchAtLoginSwitch,
        ])
        launchAtLoginControlRow.orientation = .horizontal
        launchAtLoginControlRow.alignment = .centerY
        launchAtLoginControlRow.spacing = 12

        let loginSettingsButtonSpacer = makeFlexibleSpacer()
        openLoginItemsSettingsRow.addArrangedSubview(loginSettingsButtonSpacer)
        openLoginItemsSettingsRow.addArrangedSubview(openLoginItemsSettingsButton)
        openLoginItemsSettingsRow.orientation = .horizontal
        openLoginItemsSettingsRow.alignment = .centerY
        openLoginItemsSettingsRow.spacing = 8

        let preferencesDivider = makeSettingsDivider()
        let launchAtLoginSettingsStack = NSStackView(views: [
            launchAtLoginControlRow,
            launchAtLoginStatusLabel,
            openLoginItemsSettingsRow,
        ])
        launchAtLoginSettingsStack.orientation = .vertical
        launchAtLoginSettingsStack.alignment = .leading
        launchAtLoginSettingsStack.spacing = 6
        NSLayoutConstraint.activate([
            launchAtLoginControlRow.widthAnchor.constraint(
                equalTo: launchAtLoginSettingsStack.widthAnchor
            ),
            launchAtLoginStatusLabel.widthAnchor.constraint(
                equalTo: launchAtLoginSettingsStack.widthAnchor
            ),
            openLoginItemsSettingsRow.widthAnchor.constraint(
                equalTo: launchAtLoginSettingsStack.widthAnchor
            ),
        ])

        let appPreferencesContent = NSStackView(views: [
            languageRow,
            monthlyBudgetRow,
            preferencesDivider,
            launchAtLoginSettingsStack,
        ])
        appPreferencesContent.orientation = .vertical
        appPreferencesContent.alignment = .leading
        appPreferencesContent.spacing = 14
        NSLayoutConstraint.activate([
            languageRow.widthAnchor.constraint(
                equalTo: appPreferencesContent.widthAnchor
            ),
            monthlyBudgetRow.widthAnchor.constraint(
                equalTo: appPreferencesContent.widthAnchor
            ),
            preferencesDivider.widthAnchor.constraint(
                equalTo: appPreferencesContent.widthAnchor
            ),
            launchAtLoginSettingsStack.widthAnchor.constraint(
                equalTo: appPreferencesContent.widthAnchor
            ),
        ])

        let dataFoldersSection = makeSettingsSection(
            identifier: "SettingsDataFoldersSection",
            title: dataFoldersTitleLabel,
            content: [providerDirectoryStack]
        )
        let dataRefreshSection = makeSettingsSection(
            identifier: "SettingsDataRefreshSection",
            title: dataRefreshTitleLabel,
            content: [refreshRow]
        )
        let appPreferencesSection = makeSettingsSection(
            identifier: "SettingsAppPreferencesSection",
            title: appPreferencesTitleLabel,
            content: [appPreferencesContent]
        )
        let statusBarQuotaSettingsView = StatusBarQuotaSettingsView(
            displaySettings: displaySettings,
            quotaAccess: quotaAccess,
            language: languageSettings.resolvedLanguage
        )
        self.statusBarQuotaSettingsView = statusBarQuotaSettingsView
        let statusBarQuotaSection = makeSettingsSection(
            identifier: "SettingsStatusBarQuotaSection",
            title: statusBarQuotaTitleLabel,
            content: [statusBarQuotaSettingsView]
        )
        self.statusBarQuotaSection = statusBarQuotaSection

        let contentStack = NSStackView(views: [
            titleRow,
            descriptionLabel,
            dataFoldersSection,
            dataRefreshSection,
            appPreferencesSection,
            statusBarQuotaSection,
        ])
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 0
        contentStack.setCustomSpacing(4, after: titleRow)
        contentStack.setCustomSpacing(24, after: descriptionLabel)
        contentStack.setCustomSpacing(16, after: dataFoldersSection)
        contentStack.setCustomSpacing(16, after: dataRefreshSection)
        contentStack.setCustomSpacing(16, after: appPreferencesSection)

        let panel = NSView()
        panel.identifier = NSUserInterfaceItemIdentifier("SettingsPanel")
        panel.setAccessibilityIdentifier("SettingsPanel")
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(contentStack)

        // 新增状态栏订阅额度区块后内容高于主窗口，设置页改为纵向滚动；滚动条使用 overlay 不占宽度。
        let documentView = SettingsDocumentView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(panel)
        scrollView.identifier = NSUserInterfaceItemIdentifier("SettingsScrollView")
        scrollView.setAccessibilityIdentifier("SettingsScrollView")
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsetsZero
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            panel.leadingAnchor.constraint(
                equalTo: documentView.leadingAnchor,
                constant: 28
            ),
            panel.trailingAnchor.constraint(
                equalTo: documentView.trailingAnchor,
                constant: -28
            ),
            panel.topAnchor.constraint(
                equalTo: documentView.topAnchor,
                constant: 28
            ),
            panel.bottomAnchor.constraint(
                equalTo: documentView.bottomAnchor,
                constant: -28
            ),
            contentStack.leadingAnchor.constraint(
                equalTo: panel.leadingAnchor,
                constant: 24
            ),
            contentStack.trailingAnchor.constraint(
                equalTo: panel.trailingAnchor,
                constant: -24
            ),
            contentStack.topAnchor.constraint(
                equalTo: panel.topAnchor,
                constant: 24
            ),
            contentStack.bottomAnchor.constraint(
                equalTo: panel.bottomAnchor,
                constant: -24
            ),
            titleRow.widthAnchor.constraint(
                equalTo: contentStack.widthAnchor
            ),
            descriptionLabel.widthAnchor.constraint(
                equalTo: contentStack.widthAnchor
            ),
            dataFoldersSection.widthAnchor.constraint(
                equalTo: contentStack.widthAnchor
            ),
            dataRefreshSection.widthAnchor.constraint(
                equalTo: contentStack.widthAnchor
            ),
            appPreferencesSection.widthAnchor.constraint(
                equalTo: contentStack.widthAnchor
            ),
            statusBarQuotaSection.widthAnchor.constraint(
                equalTo: contentStack.widthAnchor
            ),
        ])

        reloadLocalizedText()
    }

    /// 滚动到“状态栏订阅额度”区块，使其完整可见。
    func revealStatusBarQuotaSection() {
        loadViewIfNeeded()
        view.layoutSubtreeIfNeeded()
        guard let statusBarQuotaSection else { return }
        statusBarQuotaSection.scrollToVisible(statusBarQuotaSection.bounds)
    }

    private func configureSectionTitle(
        _ label: NSTextField,
        identifier: String
    ) {
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = DashboardPalette.primaryText
        label.identifier = NSUserInterfaceItemIdentifier(identifier)
        label.setAccessibilityIdentifier(identifier)
    }

    private func makeSettingsSection(
        identifier: String,
        title: NSTextField,
        content: [NSView]
    ) -> DashboardGlassCardView {
        let section = DashboardGlassCardView(cornerRadius: 12)
        section.identifier = NSUserInterfaceItemIdentifier(identifier)
        section.setAccessibilityIdentifier(identifier)
        section.translatesAutoresizingMaskIntoConstraints = false

        let header = NSStackView()
        header.identifier = NSUserInterfaceItemIdentifier("SettingsSectionHeader.\(identifier)")
        header.setAccessibilityIdentifier("SettingsSectionHeader.\(identifier)")
        header.orientation = .horizontal
        header.alignment = .centerY
        header.addArrangedSubview(title)

        let stack = NSStackView(views: [header] + content)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        section.addContentSubview(stack)

        var constraints = [
            stack.leadingAnchor.constraint(equalTo: section.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: section.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: section.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: section.bottomAnchor, constant: -18),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ]
        for view in content {
            constraints.append(view.widthAnchor.constraint(equalTo: stack.widthAnchor))
        }
        NSLayoutConstraint.activate(constraints)
        return section
    }

    private func makeFlexibleSpacer() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.fittingSizeCompression, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.fittingSizeCompression, for: .horizontal)
        return spacer
    }

    private func makeSettingsDivider() -> DashboardBackgroundView {
        let divider = DashboardBackgroundView(
            backgroundColor: DashboardPalette.glassDivider
        )
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return divider
    }

    /// 依照注入 providers 的稳定顺序建立目录设置行；注入额度 store 时在末尾追加 Claude 额度文件行。
    private func configureProviderDirectoryRows() {
        providerDirectoryStack.orientation = .vertical
        providerDirectoryStack.alignment = .leading
        providerDirectoryStack.distribution = .fill
        providerDirectoryStack.spacing = 0

        for (index, provider) in providers.enumerated() {
            let (row, rowViews) = makeDirectoryRow(
                identifierSuffix: provider.id.rawValue,
                name: provider.displayName,
                action: #selector(directoryAuthorizationButtonClicked(_:))
            )
            rowViews.actionButton.tag = index
            providerDirectoryRows[provider.id] = rowViews
            addDirectoryStackRow(row)

            if index < providers.count - 1 {
                addDirectoryStackRow(makeSettingsDivider())
            }
        }

        guard quotaStore != nil else { return }
        // 订阅额度的 Claude 来源 `.claude.json` 与 token 统计目录同属本地数据源授权，放在同一区块。
        let (row, rowViews) = makeDirectoryRow(
            identifierSuffix: "claudeQuotaFile",
            name: "",
            action: #selector(claudeQuotaFileButtonClicked)
        )
        claudeQuotaFileRow = rowViews
        let divider = makeSettingsDivider()
        claudeQuotaFileRowContainers = providers.isEmpty ? [row] : [divider, row]
        for view in claudeQuotaFileRowContainers {
            addDirectoryStackRow(view)
        }
    }

    /// 创建一行“名称 + 状态 / 操作按钮”的数据源设置行。
    /// - Parameters:
    ///   - identifierSuffix: 拼接在各子视图 accessibility identifier 之后的唯一后缀。
    ///   - name: 名称初始文案；本地化名称在渲染时更新。
    ///   - action: 操作按钮点击后的 selector。
    /// - Returns: 行容器与需要在渲染时更新的子视图。
    private func makeDirectoryRow(
        identifierSuffix: String,
        name: String,
        action: Selector
    ) -> (NSStackView, ProviderDirectoryRowViews) {
        let nameLabel = NSTextField(labelWithString: name)
        nameLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        nameLabel.textColor = DashboardPalette.primaryText
        nameLabel.identifier = NSUserInterfaceItemIdentifier(
            "ProviderDirectoryName.\(identifierSuffix)"
        )
        nameLabel.setAccessibilityIdentifier(
            "ProviderDirectoryName.\(identifierSuffix)"
        )
        nameLabel.setContentHuggingPriority(.required, for: .horizontal)
        nameLabel.setContentCompressionResistancePriority(
            .required,
            for: .horizontal
        )

        let statusDotView = SettingsStatusDotView(
            color: DashboardPalette.yellow
        )
        statusDotView.identifier = NSUserInterfaceItemIdentifier(
            "ProviderDirectoryStatusDot.\(identifierSuffix)"
        )
        statusDotView.setAccessibilityIdentifier(
            "ProviderDirectoryStatusDot.\(identifierSuffix)"
        )
        statusDotView.setAccessibilityElement(false)

        let statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = DashboardPalette.secondaryText
        statusLabel.maximumNumberOfLines = 1
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.identifier = NSUserInterfaceItemIdentifier(
            "ProviderDirectoryStatus.\(identifierSuffix)"
        )
        statusLabel.setAccessibilityIdentifier(
            "ProviderDirectoryStatus.\(identifierSuffix)"
        )
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        statusLabel.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )

        let statusStack = NSStackView(views: [statusDotView, statusLabel])
        statusStack.orientation = .horizontal
        statusStack.alignment = .centerY
        statusStack.spacing = 6
        statusStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        statusStack.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )

        let providerInfoStack = NSStackView(views: [nameLabel, statusStack])
        providerInfoStack.orientation = .vertical
        providerInfoStack.alignment = .leading
        providerInfoStack.spacing = 4
        providerInfoStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        providerInfoStack.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )

        let actionButton = DashboardRangeButton(
            title: "",
            target: nil,
            action: nil
        )
        configureSettingsButton(actionButton)
        actionButton.identifier = NSUserInterfaceItemIdentifier(
            "ProviderDirectoryAction.\(identifierSuffix)"
        )
        actionButton.setAccessibilityIdentifier(
            "ProviderDirectoryAction.\(identifierSuffix)"
        )
        actionButton.target = self
        actionButton.action = action
        actionButton.setContentHuggingPriority(.required, for: .horizontal)
        actionButton.setContentCompressionResistancePriority(
            .required,
            for: .horizontal
        )
        // DashboardRangeButton 使用无边框自定义外观，没有可用的原生内容宽度；
        // 通过标题宽度约束让操作按钮保持紧凑，同时为不同语言预留内边距。
        let actionButtonWidthConstraint = actionButton.widthAnchor.constraint(
            equalToConstant: 64
        )
        actionButtonWidthConstraint.isActive = true

        let trailingSpacer = makeFlexibleSpacer()
        let row = NSStackView(views: [
            providerInfoStack,
            trailingSpacer,
            actionButton,
        ])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 12
        row.identifier = NSUserInterfaceItemIdentifier(
            "ProviderDirectoryRow.\(identifierSuffix)"
        )
        row.setAccessibilityIdentifier(
            "ProviderDirectoryRow.\(identifierSuffix)"
        )
        // 行高与数据源数量共同决定设置页总高度；5 个数据源时 60pt 会超出最小内容高度，
        // 因此固定为 48pt：仍高于按钮(32.5pt)与两行文案(≈37pt)，但不至于顶出可视区域。
        row.heightAnchor.constraint(
            greaterThanOrEqualToConstant: 48
        ).isActive = true

        return (
            row,
            ProviderDirectoryRowViews(
                nameLabel: nameLabel,
                statusDotView: statusDotView,
                statusLabel: statusLabel,
                actionButton: actionButton,
                actionButtonWidthConstraint: actionButtonWidthConstraint
            )
        )
    }

    private func addDirectoryStackRow(_ view: NSView) {
        providerDirectoryStack.addArrangedSubview(view)
        view.widthAnchor.constraint(
            equalTo: providerDirectoryStack.widthAnchor
        ).isActive = true
    }

    private func configureSettingsButton(_ button: DashboardRangeButton) {
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.alignment = .center
        button.wantsLayer = true
        button.layer?.cornerRadius = 7
        button.layer?.borderWidth = 1
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    private func applySettingsButtonStyle(
        _ button: DashboardRangeButton,
        title: String,
        backgroundColor: NSColor,
        borderColor: NSColor,
        textColor: NSColor
    ) {
        button.title = title
        button.setAccessibilityLabel(title)
        button.setDashboardLayerColors(backgroundColor: backgroundColor, borderColor: borderColor)
        button.contentTintColor = textColor
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: textColor,
                .paragraphStyle: paragraphStyle,
            ]
        )
    }

    /// 计算目录操作按钮的内容宽度，保证不同语言文案完整显示。
    private func directoryActionButtonWidth(for title: String) -> CGFloat {
        let titleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
        return ceil(
            (title as NSString).size(withAttributes: [.font: titleFont]).width
                + Self.directoryActionHorizontalPadding
        )
    }

    private func renderAllDirectoryRows() {
        for provider in providers {
            renderDirectoryRow(for: provider.id)
        }
        renderClaudeQuotaFileRow()
    }

    /// 额度为付费功能：未解锁时不读取额度，授权入口与原状态栏菜单一致地隐藏。
    private var isClaudeQuotaFileRowVisible: Bool {
        quotaStore != nil && quotaAccess.isUnlocked
    }

    private func renderClaudeQuotaFileRow() {
        guard let quotaStore, let row = claudeQuotaFileRow else { return }
        let isVisible = isClaudeQuotaFileRowVisible
        for view in claudeQuotaFileRowContainers {
            view.isHidden = !isVisible
        }
        let language = languageSettings.resolvedLanguage
        let model = ClaudeQuotaFileRowModel.make(
            hasBookmark: quotaStore.hasClaudeFileBookmark,
            state: quotaStore.state(for: .claude),
            isAuthorizing: isAuthorizingClaudeQuotaFile,
            language: language
        )
        row.nameLabel.toolTip = AppStrings.text(.claudeQuotaFileOpenPanelMessage, language: language)
        applyDirectoryRowContent(
            row,
            name: AppStrings.text(.settingsClaudeQuotaFile, language: language),
            statusText: model.statusText,
            statusStyle: model.statusStyle,
            showsStatus: true,
            actionTitle: model.actionTitle,
            actionStyle: model.actionStyle,
            showsAction: true,
            isActionEnabled: model.isActionEnabled
        )
    }

    /// 只读取并重绘指定 provider；不得查询其他 providerState。
    private func renderDirectoryRow(for id: ProviderID) {
        guard
            let provider = providers.first(where: { $0.id == id }),
            let row = providerDirectoryRows[id]
        else {
            return
        }

        let state = providerState(id)
            ?? TokenStatsViewModel.ProviderState(stats: nil, entries: nil)
        let model = ProviderDirectoryRowModel.make(
            provider: provider,
            state: state,
            language: languageSettings.resolvedLanguage
        )

        applyDirectoryRowContent(
            row,
            name: model.providerName,
            statusText: model.statusText,
            statusStyle: model.statusStyle,
            showsStatus: model.showsStatus,
            actionTitle: model.actionTitle,
            actionStyle: model.actionStyle,
            showsAction: model.showsAction,
            isActionEnabled: model.isActionEnabled
        )
    }

    /// 把名称、状态与操作按钮文案 / 配色写入一行数据源设置行，并同步操作列宽。
    private func applyDirectoryRowContent(
        _ row: ProviderDirectoryRowViews,
        name: String,
        statusText: String,
        statusStyle: ProviderDirectoryStatusStyle,
        showsStatus: Bool,
        actionTitle: String,
        actionStyle: ProviderDirectoryActionStyle,
        showsAction: Bool,
        isActionEnabled: Bool
    ) {
        row.nameLabel.stringValue = name
        row.statusLabel.stringValue = statusText
        row.statusLabel.isHidden = !showsStatus
        row.statusDotView.isHidden = !showsStatus
        let statusColor = providerStatusColor(for: statusStyle)
        row.statusDotView.setColor(statusColor)
        row.statusLabel.toolTip = showsStatus ? statusText : nil
        row.statusLabel.textColor = statusColor
        row.statusLabel.setAccessibilityLabel(
            "\(name), \(statusText)"
        )
        row.actionButton.isHidden = !showsAction
        row.actionButton.isEnabled = isActionEnabled

        switch actionStyle {
        case .primary:
            applySettingsButtonStyle(
                row.actionButton,
                title: actionTitle,
                backgroundColor: DashboardPalette.rangeSelectedBackground,
                borderColor: DashboardPalette.rangeSelectedBorder,
                textColor: DashboardPalette.rangeSelectedText
            )
        case .neutral:
            applySettingsButtonStyle(
                row.actionButton,
                title: actionTitle,
                backgroundColor: .clear,
                borderColor: DashboardPalette.glassControlBorder,
                textColor: DashboardPalette.primaryText
            )
        }
        row.actionButton.setAccessibilityLabel(
            "\(name), \(actionTitle)"
        )
        synchronizeDirectoryActionButtonWidths()
    }

    private func providerStatusColor(
        for style: ProviderDirectoryStatusStyle
    ) -> NSColor {
        switch style {
        case .success:
            return DashboardPalette.green
        case .warning:
            return DashboardPalette.yellow
        case .error:
            return DashboardPalette.statusInactive
        }
    }

    /// 同步目录操作列宽，让每一行尾部操作保持一致的视觉节奏。
    private func synchronizeDirectoryActionButtonWidths() {
        let claudeQuotaFileRows = [claudeQuotaFileRow].compactMap { $0 }
        // 隐藏的 Claude 额度文件行不参与列宽计算，避免撑宽其他行的按钮。
        let visibleRows = Array(providerDirectoryRows.values)
            + (isClaudeQuotaFileRowVisible ? claudeQuotaFileRows : [])
        let sharedWidth = visibleRows
            .filter { !$0.actionButton.isHidden }
            .map { directoryActionButtonWidth(for: $0.actionButton.title) }
            .max() ?? 64

        for row in Array(providerDirectoryRows.values) + claudeQuotaFileRows {
            row.actionButtonWidthConstraint.constant = sharedWidth
        }
    }

    private func renderLaunchAtLoginState() {
        let statusKey: AppStringKey?
        let showsOpenSettings: Bool

        switch loginItemSettings.state {
        case .notRegistered:
            launchAtLoginSwitch.state = .off
            launchAtLoginSwitch.isEnabled = true
            statusKey = nil
            showsOpenSettings = false
        case .enabled:
            launchAtLoginSwitch.state = .on
            launchAtLoginSwitch.isEnabled = true
            statusKey = nil
            showsOpenSettings = false
        case .requiresApproval:
            launchAtLoginSwitch.state = .on
            launchAtLoginSwitch.isEnabled = true
            statusKey = .settingsLaunchAtLoginRequiresApproval
            showsOpenSettings = true
        }

        if let statusKey {
            launchAtLoginStatusLabel.stringValue = AppStrings.text(
                statusKey,
                language: languageSettings.resolvedLanguage
            )
            launchAtLoginStatusLabel.isHidden = false
        } else {
            launchAtLoginStatusLabel.stringValue = ""
            launchAtLoginStatusLabel.isHidden = true
        }
        openLoginItemsSettingsButton.isHidden = !showsOpenSettings
        openLoginItemsSettingsRow.isHidden = !showsOpenSettings
    }

    @objc private func autoRefreshIntervalChanged() {
        let selectedIndex = autoRefreshIntervalPopUpButton.indexOfSelectedItem
        guard AutoRefreshIntervalOption.allCases.indices.contains(selectedIndex) else { return }
        autoRefreshSettings.selectedOption = AutoRefreshIntervalOption.allCases[selectedIndex]
    }

    @objc private func languagePreferenceChanged() {
        let selectedIndex = languagePopUpButton.indexOfSelectedItem
        guard AppLanguagePreference.allCases.indices.contains(selectedIndex) else { return }
        languageSettings.selectedPreference = AppLanguagePreference.allCases[selectedIndex]
    }

    @objc private func monthlyBudgetChanged() {
        let text = monthlyBudgetTextField.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            monthlyBudgetSettings.monthlyBudgetUSD = nil
            renderMonthlyBudget()
            return
        }

        let formatter = monthlyBudgetNumberFormatter(
            language: languageSettings.resolvedLanguage
        )
        guard let value = formatter.number(from: text)?.doubleValue,
              value.isFinite,
              value > 0 else {
            // Invalid text must not silently erase a previously configured budget.
            renderMonthlyBudget()
            return
        }
        monthlyBudgetSettings.monthlyBudgetUSD = value
        renderMonthlyBudget()
    }

    @objc private func launchAtLoginSwitchChanged() {
        guard launchAtLoginSwitch.isEnabled else {
            renderLaunchAtLoginState()
            return
        }

        do {
            try loginItemSettings.setEnabled(launchAtLoginSwitch.state == .on)
        } catch {
            NSLog("TokenWatch failed to update launch-at-login setting: \(error)")
        }
        renderLaunchAtLoginState()
    }

    @objc private func openLoginItemsSettingsButtonClicked() {
        loginItemSettings.openSystemSettings()
    }

    @objc private func applicationDidBecomeActive(_ notification: Notification) {
        renderLaunchAtLoginState()
    }

    @objc private func providerStateDidChange(_ notification: Notification) {
        guard let id = notification.userInfo?["providerID"] as? ProviderID else {
            return
        }
        renderDirectoryRow(for: id)
    }

    @objc private func directoryAuthorizationButtonClicked(_ sender: NSButton) {
        let tag = sender.tag
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await performDirectoryAuthorization(forButtonTag: tag)
        }
    }

    /// 完成一次 button tag 到 provider 的授权路由。
    /// - Parameter tag: `configureProviderDirectoryRows` 写入的 provider 索引。
    /// - Returns: provider 不存在时为 false；否则原样返回授权动作结果。
    @discardableResult
    func performDirectoryAuthorization(forButtonTag tag: Int) async -> Bool {
        guard providers.indices.contains(tag) else {
            return false
        }
        let id = providers[tag].id
        let result = await authorizationAction(id)
        renderDirectoryRow(for: id)
        return result
    }

    /// 选择 `.claude.json` 并保存只读 bookmark；store 授权成功后会立即重读额度。
    @objc private func claudeQuotaFileButtonClicked() {
        guard let quotaStore, !isAuthorizingClaudeQuotaFile else { return }
        isAuthorizingClaudeQuotaFile = true
        renderClaudeQuotaFileRow()
        Task { @MainActor [weak self] in
            await quotaStore.requestClaudeFileAuthorization()
            guard let self else { return }
            self.isAuthorizingClaudeQuotaFile = false
            self.renderClaudeQuotaFileRow()
        }
    }

    @objc private func refreshButtonClicked() {
        Task { @MainActor in
            await viewModel?.loadAllStats()
        }
    }

    func reloadLocalizedText() {
        let language = languageSettings.resolvedLanguage
        titleLabel.stringValue = AppStrings.text(.settingsTitle, language: language)
        descriptionLabel.stringValue = AppStrings.text(
            .settingsDescription,
            language: language
        )
        dataFoldersTitleLabel.stringValue = AppStrings.text(
            .dashboardDataSources,
            language: language
        )
        dataRefreshTitleLabel.stringValue = AppStrings.text(
            .settingsDataRefreshTitle,
            language: language
        )
        appPreferencesTitleLabel.stringValue = AppStrings.text(
            .settingsAppPreferencesTitle,
            language: language
        )
        statusBarQuotaTitleLabel.stringValue = AppStrings.text(
            .settingsStatusBarQuotaTitle,
            language: language
        )
        statusBarQuotaSettingsView?.reloadLocalizedText(language: language)
        applySettingsButtonStyle(
            refreshButton,
            title: AppStrings.text(.refreshNow, language: language),
            backgroundColor: .clear,
            borderColor: DashboardPalette.glassControlBorder,
            textColor: DashboardPalette.primaryText
        )
        autoRefreshIntervalLabel.stringValue = AppStrings.text(.settingsAutoRefreshInterval, language: language)
        autoRefreshIntervalPopUpButton.setAccessibilityLabel(
            AppStrings.text(.settingsAutoRefreshInterval, language: language)
        )
        launchAtLoginLabel.stringValue = AppStrings.text(.settingsLaunchAtLogin, language: language)
        launchAtLoginSwitch.setAccessibilityLabel(
            AppStrings.text(.settingsLaunchAtLogin, language: language)
        )
        languageLabel.stringValue = AppStrings.text(.settingsLanguage, language: language)
        languagePopUpButton.setAccessibilityLabel(
            AppStrings.text(.settingsLanguage, language: language)
        )
        monthlyBudgetLabel.stringValue = MonthlyBudgetCopy.make(language: language).settingsTitle
        monthlyBudgetTextField.setAccessibilityLabel(monthlyBudgetLabel.stringValue)
        applySettingsButtonStyle(
            openLoginItemsSettingsButton,
            title: AppStrings.text(.settingsOpenLoginItemsSettings, language: language),
            backgroundColor: .clear,
            borderColor: DashboardPalette.glassControlBorder,
            textColor: DashboardPalette.primaryText
        )
        reloadAutoRefreshIntervalPopUp(language: language)
        reloadLanguagePopUp(language: language)
        renderMonthlyBudget()
        renderAllDirectoryRows()
        renderLaunchAtLoginState()
    }

    private func subscribeToLanguageSettings() {
        languageSettingsObserverToken = languageSettings.observe { [weak self] in
            self?.reloadLocalizedText()
        }
    }

    /// 额度读取结果或解锁状态变化时重绘 Claude 额度文件行（授权状态与显隐）。
    private func subscribeToQuotaUpdates() {
        guard let quotaStore else { return }
        quotaStoreObserverToken = quotaStore.observe { [weak self] in
            self?.renderClaudeQuotaFileRow()
        }
        quotaAccessObserverToken = quotaAccess.observe { [weak self] in
            self?.renderClaudeQuotaFileRow()
        }
    }

    private func reloadAutoRefreshIntervalPopUp(language: AppLanguage) {
        let selectedOption = autoRefreshSettings.selectedOption
        autoRefreshIntervalPopUpButton.removeAllItems()
        autoRefreshIntervalPopUpButton.addItems(withTitles: AutoRefreshIntervalOption.allCases.map { $0.title(language: language) })
        if let selectedIndex = AutoRefreshIntervalOption.allCases.firstIndex(of: selectedOption) {
            autoRefreshIntervalPopUpButton.selectItem(at: selectedIndex)
        }
        autoRefreshIntervalPopUpButton.applyDashboardLayerColors()
    }

    private func reloadLanguagePopUp(language: AppLanguage) {
        let selectedPreference = languageSettings.selectedPreference
        languagePopUpButton.removeAllItems()
        languagePopUpButton.addItems(withTitles: AppLanguagePreference.allCases.map { $0.title(language: language) })
        if let selectedIndex = AppLanguagePreference.allCases.firstIndex(of: selectedPreference) {
            languagePopUpButton.selectItem(at: selectedIndex)
        }
        languagePopUpButton.applyDashboardLayerColors()
    }

    private func renderMonthlyBudget() {
        let formatter = monthlyBudgetNumberFormatter(
            language: languageSettings.resolvedLanguage
        )
        monthlyBudgetTextField.stringValue = monthlyBudgetSettings.monthlyBudgetUSD.flatMap {
            formatter.string(from: NSNumber(value: $0))
        } ?? ""
    }

    private func monthlyBudgetNumberFormatter(language: AppLanguage) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: language.localeIdentifier)
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }

    deinit {
        MainActor.assumeIsolated {
            NotificationCenter.default.removeObserver(self)
            if let token = languageSettingsObserverToken {
                languageSettings.removeObserver(token)
            }
            if let token = quotaStoreObserverToken {
                quotaStore?.removeObserver(token)
            }
            if let token = quotaAccessObserverToken {
                quotaAccess.removeObserver(token)
            }
        }
    }
}
