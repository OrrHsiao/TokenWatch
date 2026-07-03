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
        view = NSView(frame: NSRect(origin: .zero, size: MainWindowFactory.contentSize))
        view.wantsLayer = true
        view.layer?.backgroundColor = DashboardPalette.appBackground.cgColor
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

/// 通用设置页,承载跨 provider 的授权、刷新和自动刷新配置。
final class SettingsViewController: NSViewController {

    private let titleLabel = NSTextField(labelWithString: "设置")
    private let descriptionLabel = NSTextField(labelWithString: "管理 TokenWatch 的通用访问权限和数据刷新。")
    private let authorizationTitleLabel = NSTextField(labelWithString: "通用访问权限")
    private let authorizationActionButton = NSButton(title: "授权访问用户目录", target: nil, action: nil)
    private let refreshButton = NSButton(title: "刷新全部数据", target: nil, action: nil)
    private let autoRefreshIntervalLabel = NSTextField(labelWithString: "自动刷新间隔")
    private let autoRefreshIntervalPopUpButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private let launchAtLoginLabel = NSTextField(labelWithString: "开机自启动")
    private let launchAtLoginSwitch = NSSwitch(frame: .zero)
    private let languageLabel = NSTextField(labelWithString: "语言")
    private let languagePopUpButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private let isAuthorized: @MainActor () -> Bool
    private let loginItemSettings: LoginItemSettingsControlling
    private let autoRefreshSettings: AutoRefreshSettings
    private let languageSettings: AppLanguageSettings
    private var languageSettingsObserverToken: AppLanguageSettings.ObservationToken?

    private var viewModel: TokenStatsViewModel? {
        (NSApp.delegate as? AppDelegate)?.viewModel
    }

    init(isAuthorized: @escaping @MainActor () -> Bool = {
        SecurityScopedBookmarkManager.shared.hasBookmark(forKey: ProviderAuthorization.homeBookmarkKey)
    }, loginItemSettings: LoginItemSettingsControlling = LoginItemSettings.shared,
       autoRefreshSettings: AutoRefreshSettings = .shared, languageSettings: AppLanguageSettings = .shared) {
        self.isAuthorized = isAuthorized
        self.loginItemSettings = loginItemSettings
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

    required init?(coder: NSCoder) {
        fatalError("SettingsViewController 必须用 init(isAuthorized:autoRefreshSettings:) 构造")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupSubviews()
        subscribeToLanguageSettings()
        renderAuthorizationState()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        renderAuthorizationState()
        renderLaunchAtLoginState()
    }

    private func setupSubviews() {
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)

        descriptionLabel.font = .systemFont(ofSize: 13)
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.lineBreakMode = .byWordWrapping
        descriptionLabel.maximumNumberOfLines = 0

        authorizationTitleLabel.font = .systemFont(ofSize: 13)

        autoRefreshIntervalLabel.font = .systemFont(ofSize: 13)

        autoRefreshIntervalPopUpButton.identifier = NSUserInterfaceItemIdentifier("AutoRefreshIntervalPopUpButton")
        autoRefreshIntervalPopUpButton.setAccessibilityIdentifier("AutoRefreshIntervalPopUpButton")
        autoRefreshIntervalPopUpButton.target = self
        autoRefreshIntervalPopUpButton.action = #selector(autoRefreshIntervalChanged)

        launchAtLoginLabel.font = .systemFont(ofSize: 13)
        launchAtLoginSwitch.identifier = NSUserInterfaceItemIdentifier("LaunchAtLoginSwitch")
        launchAtLoginSwitch.setAccessibilityIdentifier("LaunchAtLoginSwitch")
        launchAtLoginSwitch.target = self
        launchAtLoginSwitch.action = #selector(launchAtLoginSwitchChanged)

        languageLabel.font = .systemFont(ofSize: 13)
        languagePopUpButton.identifier = NSUserInterfaceItemIdentifier("LanguagePreferencePopUpButton")
        languagePopUpButton.setAccessibilityIdentifier("LanguagePreferencePopUpButton")
        languagePopUpButton.target = self
        languagePopUpButton.action = #selector(languagePreferenceChanged)

        authorizationActionButton.bezelStyle = .rounded
        authorizationActionButton.identifier = NSUserInterfaceItemIdentifier("AuthorizationActionButton")
        authorizationActionButton.setAccessibilityIdentifier("AuthorizationActionButton")
        authorizationActionButton.target = self
        authorizationActionButton.action = #selector(authorizationActionButtonClicked)

        refreshButton.bezelStyle = .rounded
        refreshButton.identifier = NSUserInterfaceItemIdentifier("RefreshAllDataButton")
        refreshButton.setAccessibilityIdentifier("RefreshAllDataButton")
        refreshButton.target = self
        refreshButton.action = #selector(refreshButtonClicked)

        let authorizationStack = NSStackView(views: [
            authorizationTitleLabel,
            authorizationActionButton,
        ])
        authorizationStack.orientation = .horizontal
        authorizationStack.alignment = .centerY
        authorizationStack.spacing = 8

        let autoRefreshIntervalStack = NSStackView(views: [autoRefreshIntervalLabel, autoRefreshIntervalPopUpButton])
        autoRefreshIntervalStack.orientation = .horizontal
        autoRefreshIntervalStack.alignment = .centerY
        autoRefreshIntervalStack.spacing = 8

        let launchAtLoginStack = NSStackView(views: [launchAtLoginLabel, launchAtLoginSwitch])
        launchAtLoginStack.orientation = .horizontal
        launchAtLoginStack.alignment = .centerY
        launchAtLoginStack.spacing = 8

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
            authorizationStack,
            autoRefreshIntervalStack,
            launchAtLoginStack,
            languageStack,
            buttonStack,
        ])
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 14

        view.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
            contentStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 32),
        ])

        reloadLocalizedText()
    }

    private func renderAuthorizationState() {
        if isAuthorized() {
            authorizationActionButton.title = AppStrings.text(.settingsAuthorized, language: languageSettings.resolvedLanguage)
            authorizationActionButton.isEnabled = false
        } else {
            authorizationActionButton.title = AppStrings.text(.settingsAuthorize, language: languageSettings.resolvedLanguage)
            authorizationActionButton.isEnabled = true
        }
    }

    private func renderLaunchAtLoginState() {
        launchAtLoginSwitch.state = loginItemSettings.isEnabled ? .on : .off
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
        let shouldEnable = launchAtLoginSwitch.state == .on
        do {
            try loginItemSettings.setEnabled(shouldEnable)
        } catch {
            NSLog("TokenWatch failed to update launch-at-login setting: \(error)")
        }
        renderLaunchAtLoginState()
    }

    @objc private func authorizationActionButtonClicked() {
        guard !isAuthorized() else { return }
        requestAuthorization()
    }

    private func requestAuthorization() {
        guard let providerID = ProviderRegistry.allProviders.first?.id else { return }
        Task { @MainActor in
            await viewModel?.requestAuthorization(for: providerID)
            renderAuthorizationState()
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
        descriptionLabel.stringValue = AppStrings.text(.settingsDescription, language: language)
        authorizationTitleLabel.stringValue = AppStrings.text(.settingsAuthorizationTitle, language: language)
        refreshButton.title = AppStrings.text(.settingsRefreshAllData, language: language)
        autoRefreshIntervalLabel.stringValue = AppStrings.text(.settingsAutoRefreshInterval, language: language)
        launchAtLoginLabel.stringValue = AppStrings.text(.settingsLaunchAtLogin, language: language)
        languageLabel.stringValue = AppStrings.text(.settingsLanguage, language: language)
        reloadAutoRefreshIntervalPopUp(language: language)
        reloadLanguagePopUp(language: language)
        renderAuthorizationState()
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
    }

    private func reloadLanguagePopUp(language: AppLanguage) {
        let selectedPreference = languageSettings.selectedPreference
        languagePopUpButton.removeAllItems()
        languagePopUpButton.addItems(withTitles: AppLanguagePreference.allCases.map { $0.title(language: language) })
        if let selectedIndex = AppLanguagePreference.allCases.firstIndex(of: selectedPreference) {
            languagePopUpButton.selectItem(at: selectedIndex)
        }
    }

    deinit {
        MainActor.assumeIsolated {
            if let token = languageSettingsObserverToken {
                languageSettings.removeObserver(token)
            }
        }
    }
}
