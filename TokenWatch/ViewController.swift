//
//  ViewController.swift
//  TokenWatch
//
//  Created by OrrHsiao on 2026/6/13.
//

import Cocoa

/// 主视图控制器 — 左侧原生侧边栏 + 右侧 provider 详情容器。
/// 每个 provider 的详情页仍由 ProviderStatsViewController 提供。
class ViewController: NSViewController {

    private let providers = ProviderRegistry.allProviders
    private let splitViewController = NSSplitViewController()
    private let detailContainerViewController = NSViewController()
    private lazy var sidebarViewController = ProviderSidebarViewController(providers: providers)

    private var detailViewControllers: [ProviderID: ProviderStatsViewController] = [:]
    private var currentDetailViewController: ProviderStatsViewController?
    private var selectedProviderID: ProviderID?

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

    /// 安装左右布局并选中第一个 provider。
    private func installSplitLayout() {
        detailContainerViewController.view = NSView(frame: .zero)

        sidebarViewController.onSelectProvider = { [weak self] providerID in
            self?.showProvider(providerID)
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

        if let firstProvider = providers.first {
            sidebarViewController.selectProvider(firstProvider.id)
            showProvider(firstProvider.id)
        }
    }

    private func makeSidebarItem() -> NSSplitViewItem {
        let item = NSSplitViewItem(sidebarWithViewController: sidebarViewController)
        item.canCollapse = false
        item.minimumThickness = 150
        item.maximumThickness = 220
        item.preferredThicknessFraction = 0.28
        return item
    }

    private func showProvider(_ providerID: ProviderID) {
        guard selectedProviderID != providerID,
              let provider = ProviderRegistry.provider(for: providerID) else { return }

        currentDetailViewController?.view.removeFromSuperview()
        currentDetailViewController?.removeFromParent()

        let detailViewController = detailViewController(for: provider)
        detailContainerViewController.addChild(detailViewController)
        detailViewController.view.translatesAutoresizingMaskIntoConstraints = false
        detailContainerViewController.view.addSubview(detailViewController.view)

        NSLayoutConstraint.activate([
            detailViewController.view.leadingAnchor.constraint(equalTo: detailContainerViewController.view.leadingAnchor),
            detailViewController.view.trailingAnchor.constraint(equalTo: detailContainerViewController.view.trailingAnchor),
            detailViewController.view.topAnchor.constraint(equalTo: detailContainerViewController.view.topAnchor),
            detailViewController.view.bottomAnchor.constraint(equalTo: detailContainerViewController.view.bottomAnchor),
        ])

        currentDetailViewController = detailViewController
        selectedProviderID = providerID
    }

    private func detailViewController(for provider: any UsageProvider) -> ProviderStatsViewController {
        if let existing = detailViewControllers[provider.id] {
            return existing
        }
        let viewController = ProviderStatsViewController(provider: provider)
        detailViewControllers[provider.id] = viewController
        return viewController
    }

    /// 把 ViewModel 的状态变更回调多路复用到 Notification,
    /// 详情 ProviderStatsViewController 自行订阅自己 provider id 的事件。
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

/// Provider 原生侧边栏列表,负责展示 provider 顺序并发出选择事件。
private final class ProviderSidebarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {

    private static let columnIdentifier = NSUserInterfaceItemIdentifier("ProviderColumn")
    private static let cellIdentifier = NSUserInterfaceItemIdentifier("ProviderSidebarCell")

    private let providers: [any UsageProvider]
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()

    var onSelectProvider: ((ProviderID) -> Void)?

    init(providers: [any UsageProvider]) {
        self.providers = providers
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("ProviderSidebarViewController 必须用 init(providers:) 构造")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 170, height: 280))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupSidebar()
    }

    func selectProvider(_ providerID: ProviderID) {
        loadViewIfNeeded()
        guard let row = providers.firstIndex(where: { $0.id == providerID }) else { return }
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
        providers.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: Self.cellIdentifier, owner: self) as? NSTableCellView
            ?? makeCellView()
        cell.textField?.stringValue = providers[row].displayName
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard providers.indices.contains(row) else { return }
        onSelectProvider?(providers[row].id)
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
