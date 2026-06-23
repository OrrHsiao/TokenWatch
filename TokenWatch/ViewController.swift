//
//  ViewController.swift
//  TokenWatch
//
//  Created by OrrHsiao on 2026/6/13.
//

import Cocoa

/// 主视图控制器 — 左侧原生侧边栏 + 右侧汇总详情容器。
class ViewController: NSViewController {

    private let splitViewController = NSSplitViewController()
    private let detailContainerViewController = NSViewController()
    private let sidebarViewController = ProviderSidebarViewController()
    private let settingsViewController = SettingsViewController()
    private let totalStatsViewController = TotalStatsViewController()
    private let monthlyStatsViewController = MonthlyStatsViewController()
    private let recentThirtyDaysStatsViewController = MonthlyStatsViewController(period: .recent30Days)
    private let todayStatsViewController = MonthlyStatsViewController(period: .today)

    private var currentDetailViewController: NSViewController?
    private var selectedContent: SidebarContent?

    /// 通过 NSApp.delegate 获取与 AppDelegate 同一个 ViewModel 实例
    private var viewModel: TokenStatsViewModel? {
        (NSApp.delegate as? AppDelegate)?.viewModel
    }

    /// observer 凭证 — 用于 deinit 时取消订阅,避免 ViewModel 持有失效闭包
    private var observerToken: TokenStatsViewModel.ObservationToken?

    override func viewDidLoad() {
        super.viewDidLoad()
        installSplitLayout()
        bindViewModel()
    }

    /// 安装左右布局并选中总计页。
    private func installSplitLayout() {
        detailContainerViewController.view = NSView(frame: .zero)

        sidebarViewController.onSelectTotal = { [weak self] in
            self?.showTotal()
        }
        sidebarViewController.onSelectMonthly = { [weak self] in
            self?.showMonthly()
        }
        sidebarViewController.onSelectRecentThirtyDays = { [weak self] in
            self?.showRecentThirtyDays()
        }
        sidebarViewController.onSelectToday = { [weak self] in
            self?.showToday()
        }
        sidebarViewController.onSelectSettings = { [weak self] in
            self?.showSettings()
        }

        splitViewController.splitView.isVertical = true
        splitViewController.addSplitViewItem(makeSidebarItem())
        splitViewController.addSplitViewItem(NSSplitViewItem(viewController: detailContainerViewController))

        addChild(splitViewController)
        splitViewController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(splitViewController.view)

        NSLayoutConstraint.activate([
            splitViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            splitViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            splitViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            splitViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        sidebarViewController.selectTotal()
        showTotal()
    }

    private func makeSidebarItem() -> NSSplitViewItem {
        let item = NSSplitViewItem(sidebarWithViewController: sidebarViewController)
        item.canCollapse = false
        item.minimumThickness = 150
        item.maximumThickness = 220
        item.preferredThicknessFraction = 0.28
        return item
    }

    private func showSettings() {
        guard selectedContent != .settings else { return }
        installDetailViewController(settingsViewController)
        selectedContent = .settings
    }

    private func showTotal() {
        guard selectedContent != .total else { return }
        installDetailViewController(totalStatsViewController)
        selectedContent = .total
    }

    private func showMonthly() {
        guard selectedContent != .monthly else { return }
        installDetailViewController(monthlyStatsViewController)
        selectedContent = .monthly
    }

    private func showRecentThirtyDays() {
        guard selectedContent != .recentThirtyDays else { return }
        installDetailViewController(recentThirtyDaysStatsViewController)
        selectedContent = .recentThirtyDays
    }

    private func showToday() {
        guard selectedContent != .today else { return }
        installDetailViewController(todayStatsViewController)
        selectedContent = .today
    }

    private func installDetailViewController(_ viewController: NSViewController) {
        currentDetailViewController?.view.removeFromSuperview()
        currentDetailViewController?.removeFromParent()

        detailContainerViewController.addChild(viewController)
        viewController.view.translatesAutoresizingMaskIntoConstraints = false
        detailContainerViewController.view.addSubview(viewController.view)

        NSLayoutConstraint.activate([
            viewController.view.leadingAnchor.constraint(equalTo: detailContainerViewController.view.leadingAnchor),
            viewController.view.trailingAnchor.constraint(equalTo: detailContainerViewController.view.trailingAnchor),
            viewController.view.topAnchor.constraint(equalTo: detailContainerViewController.view.topAnchor),
            viewController.view.bottomAnchor.constraint(equalTo: detailContainerViewController.view.bottomAnchor),
        ])

        currentDetailViewController = viewController
    }

    /// 把 ViewModel 的状态变更回调多路复用到 Notification,
    /// 汇总页面自行订阅并按需刷新。
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
        guard let token = observerToken else { return }
        // 由 AppDelegate 强引用的 ViewModel 仍存活;deinit 在 main actor 调度路径中触发,
        // 用 assumeIsolated 同步移除,避免 fire-and-forget Task 在销毁后仍 fire 闭包
        MainActor.assumeIsolated {
            (NSApp.delegate as? AppDelegate)?.viewModel.removeObserver(token)
        }
    }
}

private enum SidebarContent: Equatable {
    case total
    case monthly
    case recentThirtyDays
    case today
    case settings
}

private enum ProviderSidebarItem {
    case total
    case monthly
    case recentThirtyDays
    case today
    case settings

    var title: String {
        switch self {
        case .total:
            return "总计"
        case .monthly:
            return "最近 12 个月"
        case .recentThirtyDays:
            return "最近 30 天"
        case .today:
            return "本日"
        case .settings:
            return "设置"
        }
    }
}

/// 原生侧边栏列表,负责展示汇总页面并发出选择事件。
private final class ProviderSidebarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {

    private static let columnIdentifier = NSUserInterfaceItemIdentifier("ProviderColumn")
    private static let cellIdentifier = NSUserInterfaceItemIdentifier("ProviderSidebarCell")

    private let items: [ProviderSidebarItem]
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()

    var onSelectTotal: (() -> Void)?
    var onSelectMonthly: (() -> Void)?
    var onSelectRecentThirtyDays: (() -> Void)?
    var onSelectToday: (() -> Void)?
    var onSelectSettings: (() -> Void)?

    init() {
        self.items = [.total, .monthly, .recentThirtyDays, .today, .settings]
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("ProviderSidebarViewController 必须用 init() 构造")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 170, height: 280))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupSidebar()
    }

    func selectTotal() {
        loadViewIfNeeded()
        guard let row = items.firstIndex(where: {
            if case .total = $0 { return true }
            return false
        }) else { return }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    private func setupSidebar() {
        let column = NSTableColumn(identifier: Self.columnIdentifier)
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        tableView.headerView = nil
        tableView.style = .sourceList
        tableView.rowHeight = 28
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.allowsEmptySelection = false
        tableView.allowsMultipleSelection = false
        tableView.backgroundColor = .clear
        tableView.delegate = self
        tableView.dataSource = self

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        tableView.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = items[row]
        let cell = tableView.makeView(withIdentifier: Self.cellIdentifier, owner: self) as? NSTableCellView
            ?? makeCellView()
        cell.textField?.stringValue = item.title
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard items.indices.contains(row) else { return }
        switch items[row] {
        case .total:
            onSelectTotal?()
        case .monthly:
            onSelectMonthly?()
        case .recentThirtyDays:
            onSelectRecentThirtyDays?()
        case .today:
            onSelectToday?()
        case .settings:
            onSelectSettings?()
        }
    }

    private func makeCellView() -> NSTableCellView {
        let cell = NSTableCellView(frame: .zero)
        cell.identifier = Self.cellIdentifier

        let textField = NSTextField(labelWithString: "")
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.font = .systemFont(ofSize: 13)
        textField.lineBreakMode = .byTruncatingTail

        cell.addSubview(textField)
        cell.textField = textField

        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
            textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])

        return cell
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
    private let isAuthorized: @MainActor () -> Bool
    private let autoRefreshSettings: AutoRefreshSettings

    private var viewModel: TokenStatsViewModel? {
        (NSApp.delegate as? AppDelegate)?.viewModel
    }

    init(isAuthorized: @escaping @MainActor () -> Bool = {
        SecurityScopedBookmarkManager.shared.hasBookmark(forKey: ProviderAuthorization.homeBookmarkKey)
    }, autoRefreshSettings: AutoRefreshSettings = .shared) {
        self.isAuthorized = isAuthorized
        self.autoRefreshSettings = autoRefreshSettings
        super.init(nibName: nil, bundle: nil)
    }

    convenience init(isAuthorized: @escaping @MainActor () -> Bool, defaults: UserDefaults) {
        self.init(isAuthorized: isAuthorized, autoRefreshSettings: AutoRefreshSettings(defaults: defaults))
    }

    required init?(coder: NSCoder) {
        fatalError("SettingsViewController 必须用 init(isAuthorized:autoRefreshSettings:) 构造")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 280))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupSubviews()
        renderAuthorizationState()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        renderAuthorizationState()
    }

    private func setupSubviews() {
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)

        descriptionLabel.font = .systemFont(ofSize: 13)
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.lineBreakMode = .byWordWrapping
        descriptionLabel.maximumNumberOfLines = 0

        authorizationTitleLabel.font = .systemFont(ofSize: 13)

        autoRefreshIntervalLabel.font = .systemFont(ofSize: 13)

        autoRefreshIntervalPopUpButton.addItems(withTitles: AutoRefreshIntervalOption.allCases.map(\.title))
        autoRefreshIntervalPopUpButton.selectItem(withTitle: autoRefreshSettings.selectedOption.title)
        autoRefreshIntervalPopUpButton.target = self
        autoRefreshIntervalPopUpButton.action = #selector(autoRefreshIntervalChanged)

        authorizationActionButton.bezelStyle = .rounded
        authorizationActionButton.target = self
        authorizationActionButton.action = #selector(authorizationActionButtonClicked)

        refreshButton.bezelStyle = .rounded
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

        let buttonStack = NSStackView(views: [refreshButton])
        buttonStack.orientation = .vertical
        buttonStack.alignment = .leading
        buttonStack.spacing = 8

        let contentStack = NSStackView(views: [
            titleLabel,
            descriptionLabel,
            authorizationStack,
            autoRefreshIntervalStack,
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
    }

    private func renderAuthorizationState() {
        if isAuthorized() {
            authorizationActionButton.title = "已授权"
            authorizationActionButton.isEnabled = false
        } else {
            authorizationActionButton.title = "去授权"
            authorizationActionButton.isEnabled = true
        }
    }

    @objc private func autoRefreshIntervalChanged() {
        guard let selectedTitle = autoRefreshIntervalPopUpButton.titleOfSelectedItem,
              let option = AutoRefreshIntervalOption.option(titled: selectedTitle) else { return }
        autoRefreshSettings.selectedOption = option
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
}
