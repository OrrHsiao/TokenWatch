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

    init(languageSettings: AppLanguageSettings = .shared) {
        self.languageSettings = languageSettings
        self.settingsViewController = SettingsViewController(languageSettings: languageSettings)
        self.dashboardViewController = DashboardViewController(
            settingsViewController: settingsViewController,
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
            languageSettings: languageSettings
        )
        super.init(coder: coder)
    }

    override func loadView() {
        view = DashboardBackgroundView(
            frame: NSRect(origin: .zero, size: MainWindowFactory.contentSize),
            backgroundColor: DashboardPalette.appBackground,
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
        view.addSubview(dashboardViewController.view)

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

private final class SettingsPopUpButton: NSPopUpButton, DashboardAppearanceRefreshable {
    init() {
        super.init(frame: .zero, pullsDown: false)
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
        layer?.backgroundColor = DashboardLayerColor.cgColor(DashboardPalette.panelBackground, for: self)
        layer?.borderColor = DashboardLayerColor.cgColor(DashboardPalette.border, for: self)
    }
}

enum ProviderDirectoryActionStyle: Sendable, Equatable {
    case primary
    case neutral
}

struct ProviderDirectoryRowModel: Sendable, Equatable {
    let providerID: ProviderID
    let providerName: String
    let statusText: String
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
        let showsAction: Bool
        switch state.directoryState {
        case .notSelected:
            statusKey = .dashboardUnauthorized
            actionKey = .settingsChooseDirectory
            actionStyle = .primary
            showsAction = true
        case .selected, .selectedNoData:
            statusKey = .settingsAuthorized
            actionKey = .settingsAuthorized
            actionStyle = .neutral
            showsAction = false
        case .needsReselection:
            statusKey = .settingsDirectoryNeedsReselection
            actionKey = .settingsChooseAgain
            actionStyle = .primary
            showsAction = true
        }

        let statusText = state.directoryAuthorizationErrorMessage
            ?? AppStrings.text(statusKey, language: language)

        return ProviderDirectoryRowModel(
            providerID: provider.id,
            providerName: provider.displayName,
            statusText: statusText,
            actionTitle: AppStrings.text(actionKey, language: language),
            actionStyle: actionStyle,
            showsAction: showsAction,
            isActionEnabled: showsAction && !state.isLoading && !state.isAuthorizing
        )
    }
}

/// 通用设置页，承载各 provider 目录、刷新和自动刷新配置。
final class SettingsViewController: NSViewController {
    static let minimumContentHeight: CGFloat = 540

    private struct ProviderDirectoryRowViews {
        let nameLabel: NSTextField
        let statusLabel: NSTextField
        let actionButton: DashboardRangeButton
    }

    private let titleLabel = NSTextField(labelWithString: "")
    private let descriptionLabel = NSTextField(labelWithString: "")
    private let dataFoldersTitleLabel = NSTextField(labelWithString: "")
    private let providerDirectoryStack = NSStackView()
    private let refreshButton = DashboardRangeButton(title: "", target: nil, action: nil)
    private let autoRefreshIntervalLabel = NSTextField(labelWithString: "")
    private let autoRefreshIntervalPopUpButton = SettingsPopUpButton()
    private let launchAtLoginLabel = NSTextField(labelWithString: "")
    private let launchAtLoginSwitch = NSSwitch(frame: .zero)
    private let launchAtLoginStatusLabel = NSTextField(labelWithString: "")
    private let openLoginItemsSettingsButton = DashboardRangeButton(title: "", target: nil, action: nil)
    private let languageLabel = NSTextField(labelWithString: "")
    private let languagePopUpButton = SettingsPopUpButton()

    private let providers: [any UsageProvider]
    private let providerState:
        @MainActor (ProviderID) -> TokenStatsViewModel.ProviderState?
    private let authorizationAction:
        @MainActor (ProviderID) async -> Bool
    private let loginItemSettings: LoginItemSettingsControlling
    private let autoRefreshSettings: AutoRefreshSettings
    private let languageSettings: AppLanguageSettings

    private var providerDirectoryRows:
        [ProviderID: ProviderDirectoryRowViews] = [:]
    private var languageSettingsObserverToken:
        AppLanguageSettings.ObservationToken?

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
        languageSettings: AppLanguageSettings = .shared
    ) {
        self.providers = providers
        self.providerState = providerState
        self.authorizationAction = authorizationAction
        self.loginItemSettings = loginItemSettings
        self.autoRefreshSettings = autoRefreshSettings
        self.languageSettings = languageSettings
        super.init(nibName: nil, bundle: nil)
    }

    convenience init(
        isAuthorized: @escaping @MainActor () -> Bool,
        loginItemSettings: LoginItemSettingsControlling = LoginItemSettings.shared,
        autoRefreshSettings: AutoRefreshSettings = .shared,
        languageSettings: AppLanguageSettings = .shared
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
            languageSettings: languageSettings
        )
    }

    convenience init(isAuthorized: @escaping @MainActor () -> Bool, defaults: UserDefaults) {
        self.init(
            isAuthorized: isAuthorized,
            autoRefreshSettings: AutoRefreshSettings(defaults: defaults),
            languageSettings: AppLanguageSettings(defaults: defaults)
        )
    }

    required init?(coder: NSCoder) {
        fatalError("SettingsViewController 必须使用代码 initializer 构造")
    }

    override func loadView() {
        view = DashboardBackgroundView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: 480,
                height: Self.minimumContentHeight
            ),
            backgroundColor: DashboardPalette.appBackground
        )
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupSubviews()
        subscribeToLanguageSettings()
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
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = DashboardPalette.primaryText

        descriptionLabel.font = .systemFont(ofSize: 13)
        descriptionLabel.textColor = DashboardPalette.secondaryText
        descriptionLabel.lineBreakMode = .byWordWrapping
        descriptionLabel.maximumNumberOfLines = 0

        dataFoldersTitleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        dataFoldersTitleLabel.textColor = DashboardPalette.primaryText
        dataFoldersTitleLabel.identifier = NSUserInterfaceItemIdentifier(
            "DataFoldersTitleLabel"
        )
        dataFoldersTitleLabel.setAccessibilityIdentifier("DataFoldersTitleLabel")

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

        configureSettingsButton(refreshButton)
        refreshButton.identifier = NSUserInterfaceItemIdentifier("RefreshAllDataButton")
        refreshButton.setAccessibilityIdentifier("RefreshAllDataButton")
        refreshButton.target = self
        refreshButton.action = #selector(refreshButtonClicked)

        let autoRefreshIntervalStack = NSStackView(views: [autoRefreshIntervalLabel, autoRefreshIntervalPopUpButton])
        autoRefreshIntervalStack.orientation = .horizontal
        autoRefreshIntervalStack.alignment = .centerY
        autoRefreshIntervalStack.spacing = 8

        let launchAtLoginControlRow = NSStackView(views: [launchAtLoginLabel, launchAtLoginSwitch])
        launchAtLoginControlRow.orientation = .horizontal
        launchAtLoginControlRow.alignment = .centerY
        launchAtLoginControlRow.spacing = 8

        let launchAtLoginSettingsStack = NSStackView(views: [
            launchAtLoginControlRow,
            launchAtLoginStatusLabel,
            openLoginItemsSettingsButton,
        ])
        launchAtLoginSettingsStack.orientation = .vertical
        launchAtLoginSettingsStack.alignment = .leading
        launchAtLoginSettingsStack.spacing = 8

        let languageStack = NSStackView(views: [languageLabel, languagePopUpButton])
        languageStack.orientation = .horizontal
        languageStack.alignment = .centerY
        languageStack.spacing = 8

        let buttonStack = NSStackView(views: [refreshButton])
        buttonStack.orientation = .vertical
        buttonStack.alignment = .leading
        buttonStack.spacing = 8

        let contentStack = NSStackView(views: [
            titleLabel,
            descriptionLabel,
            dataFoldersTitleLabel,
            providerDirectoryStack,
            autoRefreshIntervalStack,
            launchAtLoginSettingsStack,
            languageStack,
            buttonStack,
        ])
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 12

        let panel = DashboardRoundedView(
            backgroundColor: DashboardPalette.panelBackground,
            cornerRadius: 8,
            borderColor: DashboardPalette.border,
            borderWidth: 1
        )
        panel.identifier = NSUserInterfaceItemIdentifier("SettingsPanel")
        panel.setAccessibilityIdentifier("SettingsPanel")
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(contentStack)
        view.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: 28
            ),
            panel.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -28
            ),
            panel.topAnchor.constraint(
                equalTo: view.topAnchor,
                constant: 28
            ),
            panel.bottomAnchor.constraint(
                lessThanOrEqualTo: view.bottomAnchor,
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
            descriptionLabel.widthAnchor.constraint(
                equalTo: contentStack.widthAnchor
            ),
            providerDirectoryStack.widthAnchor.constraint(
                equalTo: contentStack.widthAnchor
            ),
        ])

        reloadLocalizedText()
    }

    /// 依照注入 providers 的稳定顺序建立目录设置行。
    private func configureProviderDirectoryRows() {
        providerDirectoryStack.orientation = .vertical
        // 与其余设置项一致，目录行按内容宽度从左侧开始，不随宽窗口拉散。
        providerDirectoryStack.alignment = .leading
        providerDirectoryStack.distribution = .fill
        providerDirectoryStack.spacing = 8

        for (index, provider) in providers.enumerated() {
            let nameLabel = NSTextField(labelWithString: provider.displayName)
            nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
            nameLabel.textColor = DashboardPalette.primaryText
            nameLabel.identifier = NSUserInterfaceItemIdentifier(
                "ProviderDirectoryName.\(provider.id.rawValue)"
            )
            nameLabel.setAccessibilityIdentifier(
                "ProviderDirectoryName.\(provider.id.rawValue)"
            )
            nameLabel.setContentHuggingPriority(.required, for: .horizontal)
            nameLabel.setContentCompressionResistancePriority(
                .required,
                for: .horizontal
            )
            nameLabel.widthAnchor.constraint(
                greaterThanOrEqualToConstant: 88
            ).isActive = true

            let statusLabel = NSTextField(labelWithString: "")
            statusLabel.font = .systemFont(ofSize: 12)
            statusLabel.textColor = DashboardPalette.secondaryText
            statusLabel.maximumNumberOfLines = 0
            statusLabel.lineBreakMode = .byWordWrapping
            statusLabel.identifier = NSUserInterfaceItemIdentifier(
                "ProviderDirectoryStatus.\(provider.id.rawValue)"
            )
            statusLabel.setAccessibilityIdentifier(
                "ProviderDirectoryStatus.\(provider.id.rawValue)"
            )
            statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
            statusLabel.setContentCompressionResistancePriority(
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
                "ProviderDirectoryAction.\(provider.id.rawValue)"
            )
            actionButton.setAccessibilityIdentifier(
                "ProviderDirectoryAction.\(provider.id.rawValue)"
            )
            actionButton.target = self
            actionButton.action = #selector(directoryAuthorizationButtonClicked(_:))
            actionButton.tag = index
            actionButton.setContentHuggingPriority(.required, for: .horizontal)
            actionButton.setContentCompressionResistancePriority(
                .required,
                for: .horizontal
            )
            actionButton.widthAnchor.constraint(
                greaterThanOrEqualToConstant: 92
            ).isActive = true

            let row = NSStackView(views: [nameLabel, statusLabel, actionButton])
            row.translatesAutoresizingMaskIntoConstraints = false
            row.orientation = .horizontal
            row.alignment = .centerY
            row.distribution = .fill
            row.spacing = 12
            row.identifier = NSUserInterfaceItemIdentifier(
                "ProviderDirectoryRow.\(provider.id.rawValue)"
            )
            row.setAccessibilityIdentifier(
                "ProviderDirectoryRow.\(provider.id.rawValue)"
            )
            row.heightAnchor.constraint(
                greaterThanOrEqualToConstant: 36
            ).isActive = true
            // 状态文字可换行，但目录行保持与普通设置项相近的紧凑宽度。
            row.widthAnchor.constraint(equalToConstant: 360).isActive = true

            providerDirectoryRows[provider.id] = ProviderDirectoryRowViews(
                nameLabel: nameLabel,
                statusLabel: statusLabel,
                actionButton: actionButton
            )
            providerDirectoryStack.addArrangedSubview(row)
        }
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
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: textColor,
            ]
        )
    }

    private func renderAllDirectoryRows() {
        for provider in providers {
            renderDirectoryRow(for: provider.id)
        }
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

        row.nameLabel.stringValue = model.providerName
        row.statusLabel.stringValue = model.statusText
        row.statusLabel.setAccessibilityLabel(
            "\(model.providerName), \(model.statusText)"
        )
        row.actionButton.isHidden = !model.showsAction
        row.actionButton.isEnabled = model.isActionEnabled

        switch model.actionStyle {
        case .primary:
            applySettingsButtonStyle(
                row.actionButton,
                title: model.actionTitle,
                backgroundColor: DashboardPalette.accent,
                borderColor: DashboardPalette.accent,
                textColor: DashboardPalette.rangeSelectedText
            )
        case .neutral:
            applySettingsButtonStyle(
                row.actionButton,
                title: model.actionTitle,
                backgroundColor: DashboardPalette.panelBackground,
                borderColor: DashboardPalette.border,
                textColor: DashboardPalette.primaryText
            )
        }
        row.actionButton.setAccessibilityLabel(
            "\(model.providerName), \(model.actionTitle)"
        )
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
        case .unavailable:
            launchAtLoginSwitch.state = .off
            launchAtLoginSwitch.isEnabled = false
            statusKey = .settingsLaunchAtLoginUnavailable
            showsOpenSettings = false
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
            .settingsDataFoldersTitle,
            language: language
        )
        applySettingsButtonStyle(
            refreshButton,
            title: AppStrings.text(.settingsRefreshAllData, language: language),
            backgroundColor: DashboardPalette.panelBackground,
            borderColor: DashboardPalette.border,
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
        applySettingsButtonStyle(
            openLoginItemsSettingsButton,
            title: AppStrings.text(.settingsOpenLoginItemsSettings, language: language),
            backgroundColor: DashboardPalette.panelBackground,
            borderColor: DashboardPalette.border,
            textColor: DashboardPalette.primaryText
        )
        reloadAutoRefreshIntervalPopUp(language: language)
        reloadLanguagePopUp(language: language)
        renderAllDirectoryRows()
        renderLaunchAtLoginState()
    }

    private func subscribeToLanguageSettings() {
        languageSettingsObserverToken = languageSettings.observe { [weak self] in
            self?.reloadLocalizedText()
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

    deinit {
        MainActor.assumeIsolated {
            NotificationCenter.default.removeObserver(self)
            if let token = languageSettingsObserverToken {
                languageSettings.removeObserver(token)
            }
        }
    }
}
