import AppKit

enum DashboardPalette {
    static let appBackground = NSColor(hex: 0x0B0F14)
    static let sidebarBackground = NSColor(hex: 0x05070A)
    static let panelBackground = NSColor(hex: 0x151B23)
    static let deepPanelBackground = NSColor(hex: 0x05070A)
    static let scanCardBackground = NSColor(hex: 0x0D1117)
    static let border = NSColor(hex: 0x2B3440)
    static let subtleBorder = NSColor(hex: 0x223041)
    static let primaryText = NSColor(hex: 0xF5F7FA)
    static let secondaryText = NSColor(hex: 0x9CA3AF)
    static let mutedText = NSColor(hex: 0x6B7280)
    static let accent = NSColor(hex: 0x5AA2FF)
    static let green = NSColor(hex: 0x5FE3A1)
    static let statusInactive = NSColor(hex: 0x4B5563)
    static let yellow = NSColor(hex: 0xF5C451)
    static let purple = NSColor(hex: 0xA78BFA)
}

private final class DashboardNavigationButton: NSButton {
    private let iconView = NSImageView()
    private let titleTextField = NSTextField(labelWithString: "")

    init(
        title: String,
        symbolName: String,
        identifier: String,
        target: AnyObject?,
        action: Selector?
    ) {
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        self.identifier = NSUserInterfaceItemIdentifier(identifier)
        setAccessibilityIdentifier(identifier)
        setAccessibilityLabel(title)

        alignment = .left
        bezelStyle = .regularSquare
        focusRingType = .none
        isBordered = false
        font = .systemFont(ofSize: 13, weight: .medium)
        wantsLayer = true
        layer?.cornerRadius = 8
        translatesAutoresizingMaskIntoConstraints = false

        configureContent(title: title, symbolName: symbolName, identifier: identifier)
        setVisualTint(DashboardPalette.secondaryText)
    }

    required init?(coder: NSCoder) {
        fatalError("DashboardNavigationButton 必须用指定初始化方法构造")
    }

    override func draw(_ dirtyRect: NSRect) {
        // 内容由子视图排版，避免 AppKit 默认按钮绘制吞掉设计稿里的内边距。
    }

    override var acceptsFirstResponder: Bool {
        false
    }

    func setVisualTint(_ color: NSColor) {
        iconView.contentTintColor = color
        titleTextField.textColor = color
    }

    private func configureContent(title: String, symbolName: String, identifier: String) {
        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        iconView.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: title
        )?.withSymbolConfiguration(symbolConfiguration)
        iconView.image?.isTemplate = true
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.setAccessibilityIdentifier("\(identifier).icon")

        titleTextField.stringValue = title
        titleTextField.font = .systemFont(ofSize: 13, weight: .medium)
        titleTextField.alignment = .left
        titleTextField.lineBreakMode = .byTruncatingTail
        titleTextField.translatesAutoresizingMaskIntoConstraints = false
        titleTextField.setAccessibilityIdentifier("\(identifier).title")

        addSubview(iconView)
        addSubview(titleTextField)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            titleTextField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            titleTextField.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleTextField.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
        ])
    }
}

/// Pencil 设计稿中的 TokenWatch 深色总览 Dashboard。
final class DashboardViewController: NSViewController {
    private static let sidebarWidth: CGFloat = 244
    private static let pageInset: CGFloat = 28
    private static let rowGap: CGFloat = 18
    private static let minimumContentWidth: CGFloat = 860

    private let settingsViewController: SettingsViewController
    private let stateProvider: @MainActor () -> [ProviderID: TokenStatsViewModel.ProviderState]
    private let refreshAction: @MainActor () async -> Void
    private let languageSettings: AppLanguageSettings
    private let nowProvider: () -> Date
    private let calendar: Calendar

    private let sidebarView = NSView()
    private let mainContentContainer = NSView()
    private let overviewScrollView = NSScrollView()
    private let overviewContentView = NSView()
    private let overviewStack = NSStackView()
    private let navButtonsStack = NSStackView()
    private let dataSourceRowsStack = NSStackView()
    private let scanStatusBodyLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "用量总览")
    private let subtitleLabel = NSTextField(labelWithString: "汇总 Claude Code、Codex rollout 与 opencode SQLite 的本地记录")
    private let refreshButton = NSButton(title: "刷新", target: nil, action: nil)
    private let totalTokenValueLabel = NSTextField(labelWithString: "0")
    private let totalTokenDetailLabel = NSTextField(labelWithString: "")
    private let totalCostValueLabel = NSTextField(labelWithString: "$0.00")
    private let totalCostDetailLabel = NSTextField(labelWithString: "")
    private let sessionValueLabel = NSTextField(labelWithString: "0")
    private let sessionDetailLabel = NSTextField(labelWithString: "")
    private let trendView = DashboardTrendView()
    private let modelRowsStack = NSStackView()
    private let emptyModelLabel = NSTextField(labelWithString: "暂无模型数据")
    private let sourceDonutView = DashboardDonutView()
    private let sourceLegendStack = NSStackView()
    private let projectRowsStack = NSStackView()
    private let detailRowsStack = NSStackView()
    private let statusLabel = NSTextField(labelWithString: "")

    private var rangeButtons: [DashboardRange: NSButton] = [:]
    private var navButtons: [DashboardNavigationItem: NSButton] = [:]
    private var selectedRange: DashboardRange = .sevenDays
    private var selectedNavigationItem: DashboardNavigationItem = .overview
    private var currentSettingsController: NSViewController?
    private var overviewConstraints: [NSLayoutConstraint] = []
    private var settingsConstraints: [NSLayoutConstraint] = []
    private var languageSettingsObserverToken: AppLanguageSettings.ObservationToken?

    init(
        settingsViewController: SettingsViewController,
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
        self.settingsViewController = settingsViewController
        self.stateProvider = stateProvider
        self.refreshAction = refreshAction
        self.nowProvider = nowProvider
        self.calendar = calendar
        self.languageSettings = languageSettings
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("DashboardViewController 必须用指定初始化方法构造")
    }

    override func loadView() {
        view = NSView(frame: NSRect(origin: .zero, size: MainWindowFactory.contentSize))
        view.userInterfaceLayoutDirection = .leftToRight
        view.wantsLayer = true
        view.layer?.backgroundColor = DashboardPalette.appBackground.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupLayout()
        subscribe()
        render()
    }

    deinit {
        MainActor.assumeIsolated {
            NotificationCenter.default.removeObserver(self)
            if let token = languageSettingsObserverToken {
                languageSettings.removeObserver(token)
            }
        }
    }

    /// 展示通用设置页,并保持 Pencil 侧边栏可见。
    func showSettings() {
        selectedNavigationItem = .settings
        updateNavigationSelection()
        installSettingsContent()
    }

    private func setupLayout() {
        setupSidebar()
        setupMainContent()

        sidebarView.translatesAutoresizingMaskIntoConstraints = false
        mainContentContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sidebarView)
        view.addSubview(mainContentContainer)
        NSLayoutConstraint.activate([
            sidebarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sidebarView.topAnchor.constraint(equalTo: view.topAnchor),
            sidebarView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sidebarView.widthAnchor.constraint(equalToConstant: Self.sidebarWidth),
            mainContentContainer.leadingAnchor.constraint(equalTo: sidebarView.trailingAnchor),
            mainContentContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mainContentContainer.topAnchor.constraint(equalTo: view.topAnchor),
            mainContentContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        installOverviewContent()
    }

    private func setupSidebar() {
        sidebarView.userInterfaceLayoutDirection = .leftToRight
        sidebarView.wantsLayer = true
        sidebarView.layer?.backgroundColor = DashboardPalette.sidebarBackground.cgColor
        sidebarView.setAccessibilityIdentifier("DashboardSidebar")

        let rootStack = NSStackView()
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.distribution = .gravityAreas
        rootStack.spacing = 26

        addFullWidthArrangedSubview(makeBrandView(), to: rootStack)
        navButtonsStack.orientation = .vertical
        navButtonsStack.alignment = .leading
        navButtonsStack.spacing = 6
        for item in DashboardNavigationItem.allCases {
            let button = makeNavigationButton(item)
            navButtons[item] = button
            navButtonsStack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: navButtonsStack.widthAnchor).isActive = true
        }
        addFullWidthArrangedSubview(navButtonsStack, to: rootStack)
        addFullWidthArrangedSubview(makeDataSourcesView(), to: rootStack)
        addFullWidthArrangedSubview(makeScanStatusView(), to: rootStack)

        sidebarView.addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: sidebarView.leadingAnchor, constant: 20),
            rootStack.trailingAnchor.constraint(equalTo: sidebarView.trailingAnchor, constant: -20),
            rootStack.topAnchor.constraint(equalTo: sidebarView.topAnchor, constant: Self.pageInset),
            rootStack.bottomAnchor.constraint(lessThanOrEqualTo: sidebarView.bottomAnchor, constant: -Self.pageInset),
        ])
        updateNavigationSelection()
    }

    private func setupMainContent() {
        mainContentContainer.userInterfaceLayoutDirection = .leftToRight
        mainContentContainer.wantsLayer = true
        mainContentContainer.layer?.backgroundColor = DashboardPalette.appBackground.cgColor
        mainContentContainer.setAccessibilityIdentifier("DashboardMainContent")

        overviewScrollView.userInterfaceLayoutDirection = .leftToRight
        overviewScrollView.drawsBackground = false
        overviewScrollView.borderType = .noBorder
        overviewScrollView.hasVerticalScroller = true
        overviewScrollView.autohidesScrollers = true
        overviewScrollView.translatesAutoresizingMaskIntoConstraints = false
        overviewScrollView.documentView = overviewContentView

        overviewContentView.userInterfaceLayoutDirection = .leftToRight
        overviewContentView.translatesAutoresizingMaskIntoConstraints = false
        overviewContentView.wantsLayer = true
        overviewContentView.layer?.backgroundColor = DashboardPalette.appBackground.cgColor

        overviewStack.translatesAutoresizingMaskIntoConstraints = false
        overviewStack.orientation = .vertical
        overviewStack.alignment = .leading
        overviewStack.spacing = Self.rowGap
        overviewContentView.addSubview(overviewStack)

        addFullWidthArrangedSubview(makeHeaderView(), to: overviewStack)
        addFullWidthArrangedSubview(makeMetricRow(), to: overviewStack)
        addFullWidthArrangedSubview(makeAnalysisSection(), to: overviewStack)
        addFullWidthArrangedSubview(makeDetailTable(), to: overviewStack)
        addFullWidthArrangedSubview(statusLabel, to: overviewStack)
        configureBodyStatusLabel(statusLabel)

        NSLayoutConstraint.activate([
            overviewContentView.leadingAnchor.constraint(equalTo: overviewScrollView.contentView.leadingAnchor),
            overviewContentView.trailingAnchor.constraint(equalTo: overviewScrollView.contentView.trailingAnchor),
            overviewContentView.topAnchor.constraint(equalTo: overviewScrollView.contentView.topAnchor),
            overviewContentView.widthAnchor.constraint(equalTo: overviewScrollView.contentView.widthAnchor),
            overviewContentView.heightAnchor.constraint(greaterThanOrEqualTo: overviewScrollView.contentView.heightAnchor),
            overviewStack.leadingAnchor.constraint(equalTo: overviewContentView.leadingAnchor, constant: Self.pageInset),
            overviewStack.trailingAnchor.constraint(equalTo: overviewContentView.trailingAnchor, constant: -Self.pageInset),
            overviewStack.topAnchor.constraint(equalTo: overviewContentView.topAnchor, constant: Self.pageInset),
            overviewStack.bottomAnchor.constraint(lessThanOrEqualTo: overviewContentView.bottomAnchor, constant: -Self.pageInset),
            overviewStack.widthAnchor.constraint(greaterThanOrEqualToConstant: Self.minimumContentWidth),
        ])
    }

    private func makeBrandView() -> NSView {
        let mark = NSTextField(labelWithString: "T")
        mark.font = .monospacedSystemFont(ofSize: 16, weight: .bold)
        mark.textColor = .white
        mark.alignment = .center
        mark.setAccessibilityIdentifier("DashboardBrandMark")

        let markContainer = DashboardRoundedView(
            backgroundColor: DashboardPalette.accent,
            cornerRadius: 8
        )
        markContainer.translatesAutoresizingMaskIntoConstraints = false
        markContainer.addSubview(mark)
        mark.translatesAutoresizingMaskIntoConstraints = false

        let name = NSTextField(labelWithString: "TokenWatch")
        name.font = .systemFont(ofSize: 18, weight: .bold)
        name.textColor = .white
        let subtitle = NSTextField(labelWithString: "本地 AI 用量监控")
        subtitle.font = .systemFont(ofSize: 11, weight: .regular)
        subtitle.textColor = DashboardPalette.secondaryText

        let textStack = NSStackView(views: [name, subtitle])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        let row = NSStackView(views: [markContainer, textStack])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        NSLayoutConstraint.activate([
            markContainer.widthAnchor.constraint(equalToConstant: 34),
            markContainer.heightAnchor.constraint(equalToConstant: 34),
            mark.centerXAnchor.constraint(equalTo: markContainer.centerXAnchor),
            mark.centerYAnchor.constraint(equalTo: markContainer.centerYAnchor),
        ])
        return row
    }

    private func makeNavigationButton(_ item: DashboardNavigationItem) -> NSButton {
        let button = DashboardNavigationButton(
            title: item.title,
            symbolName: item.symbolName,
            identifier: "DashboardNav.\(item.rawValue)",
            target: self,
            action: #selector(navigationButtonClicked(_:))
        )
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 39),
        ])
        return button
    }

    private func makeDataSourcesView() -> NSView {
        let title = NSTextField(labelWithString: "数据源")
        title.font = .systemFont(ofSize: 11, weight: .bold)
        title.textColor = DashboardPalette.mutedText

        dataSourceRowsStack.orientation = .vertical
        dataSourceRowsStack.alignment = .leading
        dataSourceRowsStack.spacing = 10

        let stack = NSStackView(views: [title, dataSourceRowsStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        NSLayoutConstraint.activate([
            title.widthAnchor.constraint(equalTo: stack.widthAnchor),
            dataSourceRowsStack.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        return stack
    }

    private func makeScanStatusView() -> NSView {
        let title = NSTextField(labelWithString: "上次本地扫描")
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.textColor = .white

        scanStatusBodyLabel.font = .systemFont(ofSize: 12)
        scanStatusBodyLabel.textColor = DashboardPalette.secondaryText
        scanStatusBodyLabel.maximumNumberOfLines = 0
        scanStatusBodyLabel.lineBreakMode = .byWordWrapping

        let stack = NSStackView(views: [title, scanStatusBodyLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8

        let card = DashboardRoundedView(backgroundColor: DashboardPalette.scanCardBackground, cornerRadius: 8)
        card.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
            title.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scanStatusBodyLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        return card
    }

    private func makeHeaderView() -> NSView {
        titleLabel.font = .systemFont(ofSize: 26, weight: .bold)
        titleLabel.textColor = DashboardPalette.primaryText
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = DashboardPalette.secondaryText

        let titleStack = NSStackView(views: [titleLabel, subtitleLabel])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 1

        let controlsStack = NSStackView()
        controlsStack.orientation = .horizontal
        controlsStack.alignment = .centerY
        controlsStack.spacing = 10
        for range in DashboardRange.allCases {
            let button = makeRangeButton(range)
            rangeButtons[range] = button
            controlsStack.addArrangedSubview(button)
        }
        configureRefreshButton()
        controlsStack.addArrangedSubview(refreshButton)

        let header = NSStackView(views: [titleStack, controlsStack])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.distribution = .gravityAreas
        header.spacing = 18
        header.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            header.heightAnchor.constraint(greaterThanOrEqualToConstant: 64),
        ])
        return header
    }

    private func makeRangeButton(_ range: DashboardRange) -> NSButton {
        let button = NSButton(title: range.title, target: self, action: #selector(rangeButtonClicked(_:)))
        button.identifier = NSUserInterfaceItemIdentifier("DashboardRange.\(range.rawValue)")
        button.setAccessibilityIdentifier("DashboardRange.\(range.rawValue)")
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.font = .systemFont(ofSize: 12, weight: .semibold)
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.layer?.borderWidth = 1
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 35),
        ])
        return button
    }

    private func configureRefreshButton() {
        refreshButton.identifier = NSUserInterfaceItemIdentifier("DashboardRefreshButton")
        refreshButton.setAccessibilityIdentifier("DashboardRefreshButton")
        refreshButton.target = self
        refreshButton.action = #selector(refreshDashboard(_:))
        refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "刷新")
        refreshButton.image?.isTemplate = true
        refreshButton.imagePosition = .imageLeading
        refreshButton.bezelStyle = .regularSquare
        refreshButton.isBordered = false
        refreshButton.font = .systemFont(ofSize: 12, weight: .semibold)
        refreshButton.contentTintColor = DashboardPalette.primaryText
        refreshButton.wantsLayer = true
        refreshButton.layer?.cornerRadius = 8
        refreshButton.layer?.borderWidth = 1
        refreshButton.layer?.borderColor = DashboardPalette.border.cgColor
        refreshButton.layer?.backgroundColor = DashboardPalette.panelBackground.cgColor
        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            refreshButton.heightAnchor.constraint(equalToConstant: 35),
        ])
    }

    private func makeMetricRow() -> NSView {
        let tokenCard = makeMetricCard(
            title: "总 Token",
            valueLabel: totalTokenValueLabel,
            detailLabel: totalTokenDetailLabel
        )
        let costCard = makeMetricCard(
            title: "总费用",
            valueLabel: totalCostValueLabel,
            detailLabel: totalCostDetailLabel
        )
        let sessionCard = makeMetricCard(
            title: "会话数",
            valueLabel: sessionValueLabel,
            detailLabel: sessionDetailLabel
        )
        let row = NSStackView(views: [tokenCard, costCard, sessionCard])
        row.orientation = .horizontal
        row.alignment = .height
        row.distribution = .fillEqually
        row.spacing = 14
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 128),
        ])
        return row
    }

    private func makeMetricCard(title: String, valueLabel: NSTextField, detailLabel: NSTextField) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = DashboardPalette.secondaryText

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 28, weight: .semibold)
        valueLabel.textColor = DashboardPalette.primaryText
        valueLabel.lineBreakMode = .byTruncatingTail

        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = DashboardPalette.secondaryText
        detailLabel.maximumNumberOfLines = 2
        detailLabel.lineBreakMode = .byTruncatingTail

        let stack = NSStackView(views: [titleLabel, valueLabel, detailLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10

        let card = DashboardRoundedView(
            backgroundColor: DashboardPalette.panelBackground,
            cornerRadius: 8,
            borderColor: DashboardPalette.border,
            borderWidth: 1
        )
        card.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -16),
        ])
        return card
    }

    private func makeAnalysisSection() -> NSView {
        let leftColumn = NSStackView()
        leftColumn.orientation = .vertical
        leftColumn.alignment = .leading
        leftColumn.spacing = Self.rowGap
        addFullWidthArrangedSubview(makeTrendPanel(), to: leftColumn)
        addFullWidthArrangedSubview(makeModelRankPanel(), to: leftColumn)

        let rightColumn = NSStackView()
        rightColumn.orientation = .vertical
        rightColumn.alignment = .leading
        rightColumn.spacing = Self.rowGap
        addFullWidthArrangedSubview(makeSourcePanel(), to: rightColumn)
        addFullWidthArrangedSubview(makeProjectPanel(), to: rightColumn)

        let section = NSView()
        section.addSubview(leftColumn)
        section.addSubview(rightColumn)
        leftColumn.translatesAutoresizingMaskIntoConstraints = false
        rightColumn.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leftColumn.leadingAnchor.constraint(equalTo: section.leadingAnchor),
            leftColumn.topAnchor.constraint(equalTo: section.topAnchor),
            leftColumn.bottomAnchor.constraint(equalTo: section.bottomAnchor),
            leftColumn.widthAnchor.constraint(greaterThanOrEqualToConstant: 520),
            rightColumn.leadingAnchor.constraint(equalTo: leftColumn.trailingAnchor, constant: Self.rowGap),
            rightColumn.trailingAnchor.constraint(equalTo: section.trailingAnchor),
            rightColumn.topAnchor.constraint(equalTo: section.topAnchor),
            rightColumn.bottomAnchor.constraint(equalTo: section.bottomAnchor),
            rightColumn.widthAnchor.constraint(equalToConstant: 330),
        ])
        return section
    }

    private func makeTrendPanel() -> NSView {
        trendView.translatesAutoresizingMaskIntoConstraints = false
        return makePanel(
            title: "每小时 Token 与缓存命中率",
            subtitle: "按小时展示 Token 总量及缓存命中率变化",
            content: trendView,
            minimumHeight: 230
        )
    }

    private func makeModelRankPanel() -> NSView {
        modelRowsStack.orientation = .vertical
        modelRowsStack.alignment = .width
        modelRowsStack.spacing = 8
        emptyModelLabel.font = .systemFont(ofSize: 12)
        emptyModelLabel.textColor = DashboardPalette.secondaryText

        let stack = NSStackView(views: [modelRowsStack, emptyModelLabel])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 8
        return makePanel(
            title: "模型消耗排行",
            subtitle: nil,
            content: stack,
            minimumHeight: 232
        )
    }

    private func makeSourcePanel() -> NSView {
        sourceDonutView.translatesAutoresizingMaskIntoConstraints = false
        sourceLegendStack.orientation = .vertical
        sourceLegendStack.alignment = .width
        sourceLegendStack.spacing = 8

        let body = NSStackView(views: [sourceDonutView, sourceLegendStack])
        body.orientation = .horizontal
        body.alignment = .centerY
        body.spacing = 16
        NSLayoutConstraint.activate([
            sourceDonutView.widthAnchor.constraint(equalToConstant: 132),
            sourceDonutView.heightAnchor.constraint(equalToConstant: 132),
        ])
        return makePanel(title: "来源占比", subtitle: nil, content: body, minimumHeight: 230)
    }

    private func makeProjectPanel() -> NSView {
        projectRowsStack.orientation = .vertical
        projectRowsStack.alignment = .width
        projectRowsStack.spacing = 10
        return makePanel(title: "项目消耗", subtitle: nil, content: projectRowsStack, minimumHeight: 232)
    }

    private func makePanel(title: String, subtitle: String?, content: NSView, minimumHeight: CGFloat) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 16, weight: .bold)
        titleLabel.textColor = .white

        var headerViews: [NSView] = [titleLabel]
        if let subtitle {
            let subtitleLabel = NSTextField(labelWithString: subtitle)
            subtitleLabel.font = .systemFont(ofSize: 12)
            subtitleLabel.textColor = DashboardPalette.secondaryText
            headerViews.append(subtitleLabel)
        }
        let headerStack = NSStackView(views: headerViews)
        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 3

        let stack = NSStackView(views: [headerStack, content])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12

        let panel = DashboardRoundedView(backgroundColor: DashboardPalette.deepPanelBackground, cornerRadius: 8)
        panel.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            panel.heightAnchor.constraint(greaterThanOrEqualToConstant: minimumHeight),
            stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: panel.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: panel.bottomAnchor, constant: -18),
            headerStack.widthAnchor.constraint(equalTo: stack.widthAnchor),
            content.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        return panel
    }

    private func makeDetailTable() -> NSView {
        let title = NSTextField(labelWithString: "最近明细")
        title.font = .systemFont(ofSize: 16, weight: .bold)
        title.textColor = .white

        let header = makeDetailRow(
            values: ["时间", "来源", "项目/会话", "模型", "Token", "费用", "占比"],
            isHeader: true
        )
        detailRowsStack.orientation = .vertical
        detailRowsStack.alignment = .width
        detailRowsStack.spacing = 0

        let stack = NSStackView(views: [title, header, detailRowsStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0

        let panel = DashboardRoundedView(backgroundColor: DashboardPalette.deepPanelBackground, cornerRadius: 8)
        panel.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: panel.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -14),
            title.widthAnchor.constraint(equalTo: stack.widthAnchor),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            detailRowsStack.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        return panel
    }

    private func makeDetailRow(values: [String], isHeader: Bool) -> NSView {
        let widths: [CGFloat] = [142, 106, 198, 152, 104, 72, 58]
        let labels = zip(values, widths).map { value, width in
            let label = NSTextField(labelWithString: value)
            label.font = isHeader ? .systemFont(ofSize: 11, weight: .semibold) : .systemFont(ofSize: 11)
            label.textColor = isHeader ? DashboardPalette.secondaryText : DashboardPalette.primaryText
            label.lineBreakMode = .byTruncatingMiddle
            label.translatesAutoresizingMaskIntoConstraints = false
            label.widthAnchor.constraint(equalToConstant: width).isActive = true
            return label
        }
        let row = NSStackView(views: labels)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: isHeader ? 42 : 39),
        ])
        return row
    }

    private func installOverviewContent() {
        currentSettingsController?.view.removeFromSuperview()
        currentSettingsController?.removeFromParent()
        currentSettingsController = nil
        NSLayoutConstraint.deactivate(settingsConstraints)
        if overviewScrollView.superview == nil {
            mainContentContainer.addSubview(overviewScrollView)
        }
        overviewConstraints = [
            overviewScrollView.leadingAnchor.constraint(equalTo: mainContentContainer.leadingAnchor),
            overviewScrollView.trailingAnchor.constraint(equalTo: mainContentContainer.trailingAnchor),
            overviewScrollView.topAnchor.constraint(equalTo: mainContentContainer.topAnchor),
            overviewScrollView.bottomAnchor.constraint(equalTo: mainContentContainer.bottomAnchor),
        ]
        NSLayoutConstraint.activate(overviewConstraints)
    }

    private func installSettingsContent() {
        NSLayoutConstraint.deactivate(overviewConstraints)
        overviewScrollView.removeFromSuperview()
        guard currentSettingsController !== settingsViewController else { return }

        addChild(settingsViewController)
        settingsViewController.view.translatesAutoresizingMaskIntoConstraints = false
        settingsViewController.view.userInterfaceLayoutDirection = .leftToRight
        settingsViewController.view.wantsLayer = true
        settingsViewController.view.layer?.backgroundColor = DashboardPalette.appBackground.cgColor
        mainContentContainer.addSubview(settingsViewController.view)
        settingsConstraints = [
            settingsViewController.view.leadingAnchor.constraint(equalTo: mainContentContainer.leadingAnchor),
            settingsViewController.view.trailingAnchor.constraint(equalTo: mainContentContainer.trailingAnchor),
            settingsViewController.view.topAnchor.constraint(equalTo: mainContentContainer.topAnchor),
            settingsViewController.view.bottomAnchor.constraint(equalTo: mainContentContainer.bottomAnchor),
        ]
        NSLayoutConstraint.activate(settingsConstraints)
        currentSettingsController = settingsViewController
        enforceLeftAlignedContent(in: settingsViewController.view)
    }

    private func subscribe() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(providerStateDidChange(_:)),
            name: .providerStateDidChange,
            object: nil
        )
        languageSettingsObserverToken = languageSettings.observe { [weak self] in
            self?.render()
        }
    }

    @objc private func providerStateDidChange(_ note: Notification) {
        render()
    }

    @objc func refreshDashboard(_ sender: Any?) {
        setRefreshButtonLoading(true)
        Task { @MainActor [weak self] in
            guard let self else { return }
            await refreshAction()
            render()
        }
    }

    @objc private func rangeButtonClicked(_ sender: NSButton) {
        guard let range = DashboardRange.allCases.first(where: {
            sender.identifier?.rawValue == "DashboardRange.\($0.rawValue)"
        }) else { return }
        selectedRange = range
        selectedNavigationItem = .overview
        installOverviewContent()
        updateNavigationSelection()
        render()
    }

    @objc private func navigationButtonClicked(_ sender: NSButton) {
        guard let item = DashboardNavigationItem.allCases.first(where: {
            sender.identifier?.rawValue == "DashboardNav.\($0.rawValue)"
        }) else { return }

        selectedNavigationItem = item
        switch item {
        case .overview:
            selectedRange = .sevenDays
            installOverviewContent()
        case .timeline:
            selectedRange = .month
            installOverviewContent()
        case .sessions:
            selectedRange = .day
            installOverviewContent()
        case .models, .projects:
            selectedRange = .all
            installOverviewContent()
        case .settings:
            installSettingsContent()
        }
        updateNavigationSelection()
        render()
    }

    @MainActor
    private func render() {
        let states = stateProvider()
        let totalSnapshot = TotalStatsBuilder.build(states: states)
        let periodSnapshot = MonthlyTokenChartBuilder.build(
            states: states,
            period: selectedRange.period,
            now: nowProvider(),
            calendar: calendar,
            language: languageSettings.resolvedLanguage
        )
        let summary = selectedRange == .all
            ? DashboardUsageSummary.makeTotal(from: states)
            : DashboardUsageSummary.makePeriod(from: periodSnapshot)

        totalTokenValueLabel.stringValue = CompactNumberFormatter.formatMillions(summary.totalTokens)
        totalTokenDetailLabel.stringValue = "输入 \(CompactNumberFormatter.formatMillions(summary.inputTokens)) / 输出 \(CompactNumberFormatter.formatMillions(summary.outputTokens)) / 缓存命中率 \(formatCacheHitRate(summary))"
        totalCostValueLabel.stringValue = formatCurrency(summary.cost)
        totalCostDetailLabel.stringValue = "\(totalSnapshot.loadedProviderCount) 个来源已载入 / \(totalSnapshot.unauthorizedProviderCount) 个待授权 / \(totalSnapshot.loadingProviderCount) 个刷新中"
        sessionValueLabel.stringValue = formatInt(summary.entryCount)
        sessionDetailLabel.stringValue = "\(totalSnapshot.loadedProviderCount) 个来源，\(summary.projectCount) 个项目"
        scanStatusBodyLabel.stringValue = totalSnapshot.loadingProviderCount > 0
            ? "正在更新本地记录。不依赖任何网络 API。"
            : "本地记录已就绪。不依赖任何网络 API。"

        updateRangeButtons()
        updateNavigationSelection()
        setRefreshButtonLoading(states.values.contains { $0.isLoading })
        rebuildDataSourceRows(states: states)
        trendView.configure(buckets: periodSnapshot.monthBuckets)
        rebuildModelRows(totalSnapshot.modelRows)
        rebuildSourceLegend(periodSnapshot.toolShareSlices)
        sourceDonutView.configure(slices: periodSnapshot.toolShareSlices)
        rebuildProjectRows(summary.projects)
        rebuildDetailRows(summary.details)
        statusLabel.stringValue = statusText(
            totalSnapshot: totalSnapshot,
            periodSnapshot: periodSnapshot,
            totalProviderCount: states.count
        )
        statusLabel.isHidden = statusLabel.stringValue.isEmpty
        enforceLeftAlignedContent(in: view)
    }

    private func updateNavigationSelection() {
        for item in DashboardNavigationItem.allCases {
            guard let button = navButtons[item] else { continue }
            let isSelected = item == selectedNavigationItem
            button.layer?.backgroundColor = (isSelected ? NSColor(hex: 0x182235) : DashboardPalette.sidebarBackground).cgColor
            let tintColor = isSelected ? NSColor.white : DashboardPalette.secondaryText
            button.contentTintColor = tintColor
            (button as? DashboardNavigationButton)?.setVisualTint(tintColor)
        }
    }

    private func updateRangeButtons() {
        for range in DashboardRange.allCases {
            guard let button = rangeButtons[range] else { continue }
            let isSelected = range == selectedRange
            button.layer?.backgroundColor = (isSelected ? DashboardPalette.primaryText : DashboardPalette.panelBackground).cgColor
            button.layer?.borderColor = DashboardPalette.border.cgColor
            button.contentTintColor = isSelected ? DashboardPalette.appBackground : DashboardPalette.primaryText
        }
    }

    private func setRefreshButtonLoading(_ isLoading: Bool) {
        refreshButton.isEnabled = !isLoading
        refreshButton.title = "刷新"
        refreshButton.image = NSImage(
            systemSymbolName: isLoading ? "arrow.triangle.2.circlepath" : "arrow.clockwise",
            accessibilityDescription: refreshButton.title
        )
        refreshButton.image?.isTemplate = true
        refreshButton.contentTintColor = DashboardPalette.primaryText
    }

    private func rebuildDataSourceRows(states: [ProviderID: TokenStatsViewModel.ProviderState]) {
        clearStack(dataSourceRowsStack)
        for provider in ProviderRegistry.allProviders {
            let state = states[provider.id]
            let isAuthorized = state?.needsAuthorization == false
            addFullWidthArrangedSubview(makeSourceStatusRow(
                providerID: provider.id,
                title: provider.displayName,
                isAuthorized: isAuthorized
            ), to: dataSourceRowsStack)
        }
    }

    private func makeSourceStatusRow(providerID: ProviderID, title: String, isAuthorized: Bool) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12)
        label.textColor = DashboardPalette.secondaryText
        let dot = DashboardDotView(
            color: isAuthorized ? DashboardPalette.green : DashboardPalette.statusInactive,
            accessibilityIdentifier: "DashboardDataSourceStatus.\(providerID.rawValue)",
            accessibilityValue: isAuthorized ? "authorized" : "unauthorized"
        )
        let row = NSStackView(views: [label, NSView(), dot])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        return row
    }

    private func rebuildModelRows(_ rows: [TotalStatsModelRow]) {
        clearStack(modelRowsStack)
        emptyModelLabel.isHidden = !rows.isEmpty
        let visibleRows = Array(rows.prefix(5))
        let maxTokens = visibleRows.map(\.totalTokens).max() ?? 0
        for (index, row) in visibleRows.enumerated() {
            addFullWidthArrangedSubview(DashboardBarRowView(
                title: row.modelName,
                value: formatInt(row.totalTokens),
                fraction: fraction(row.totalTokens, max: maxTokens),
                color: DashboardColors.modelColor(at: index)
            ), to: modelRowsStack)
        }
    }

    private func rebuildSourceLegend(_ slices: [UsageShareSlice]) {
        clearStack(sourceLegendStack)
        let visible = Array(slices.prefix(4))
        if visible.isEmpty {
            let label = NSTextField(labelWithString: "暂无数据")
            label.font = .systemFont(ofSize: 12)
            label.textColor = DashboardPalette.secondaryText
            addFullWidthArrangedSubview(label, to: sourceLegendStack)
            return
        }
        for (index, slice) in visible.enumerated() {
            addFullWidthArrangedSubview(makeLegendRow(
                title: slice.label,
                value: formatPercentage(slice.percentage),
                color: DashboardColors.modelColor(at: index)
            ), to: sourceLegendStack)
        }
    }

    private func rebuildProjectRows(_ rows: [DashboardProjectRow]) {
        clearStack(projectRowsStack)
        if rows.isEmpty {
            let label = NSTextField(labelWithString: "暂无项目数据")
            label.font = .systemFont(ofSize: 12)
            label.textColor = DashboardPalette.secondaryText
            addFullWidthArrangedSubview(label, to: projectRowsStack)
            return
        }
        let maxTokens = rows.map(\.tokens).max() ?? 0
        for (index, row) in rows.prefix(4).enumerated() {
            addFullWidthArrangedSubview(DashboardBarRowView(
                title: row.name,
                value: formatInt(row.tokens),
                fraction: fraction(row.tokens, max: maxTokens),
                color: DashboardColors.modelColor(at: index + 2)
            ), to: projectRowsStack)
        }
    }

    private func rebuildDetailRows(_ rows: [DashboardDetailRow]) {
        clearStack(detailRowsStack)
        if rows.isEmpty {
            addFullWidthArrangedSubview(makeDetailRow(
                values: ["暂无数据", "-", "-", "-", "-", "-", "-"],
                isHeader: false
            ), to: detailRowsStack)
            return
        }
        for row in rows.prefix(5) {
            addFullWidthArrangedSubview(makeDetailRow(
                values: [
                    row.period,
                    row.source,
                    row.project,
                    row.model,
                    formatInt(row.tokens),
                    formatCurrency(row.cost),
                    formatPercentage(row.percentage),
                ],
                isHeader: false
            ), to: detailRowsStack)
        }
    }

    private func makeLegendRow(title: String, value: String, color: NSColor) -> NSView {
        let dot = DashboardDotView(color: color)
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12)
        titleLabel.textColor = DashboardPalette.primaryText
        titleLabel.lineBreakMode = .byTruncatingMiddle
        let valueLabel = NSTextField(labelWithString: value)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        valueLabel.textColor = DashboardPalette.secondaryText
        valueLabel.alignment = .right
        let row = NSStackView(views: [dot, titleLabel, valueLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 8
        return row
    }

    private func clearStack(_ stack: NSStackView) {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    private func addFullWidthArrangedSubview(_ subview: NSView, to stack: NSStackView) {
        subview.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(subview)
        subview.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func configureBodyStatusLabel(_ label: NSTextField) {
        label.font = .systemFont(ofSize: 12)
        label.textColor = DashboardPalette.secondaryText
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
    }

    private func enforceLeftAlignedContent(in root: NSView) {
        root.userInterfaceLayoutDirection = .leftToRight
        if let textField = root as? NSTextField,
           textField.accessibilityIdentifier() != "DashboardBrandMark" {
            textField.alignment = .left
        }
        if let button = root as? NSButton {
            button.alignment = .left
        }
        for subview in root.subviews {
            enforceLeftAlignedContent(in: subview)
        }
    }

    private func fraction(_ value: Int, max maxValue: Int) -> CGFloat {
        guard maxValue > 0 else { return 0.04 }
        return Swift.max(0.04, min(1, CGFloat(value) / CGFloat(maxValue)))
    }

    private func formatCacheHitRate(_ summary: DashboardUsageSummary) -> String {
        let cache = summary.cacheReadTokens + summary.cacheCreationTokens
        let base = summary.inputTokens + summary.outputTokens + summary.reasoningTokens + cache
        guard base > 0 else { return "0%" }
        return formatPercentage(Double(cache) / Double(base))
    }

    private func formatPercentage(_ value: Double) -> String {
        guard value.isFinite else { return "0%" }
        return String(format: "%.1f%%", value * 100)
    }

    private func formatCurrency(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    private func formatInt(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func statusText(
        totalSnapshot: TotalStatsSnapshot,
        periodSnapshot: MonthlyTokenChartSnapshot,
        totalProviderCount: Int
    ) -> String {
        if totalProviderCount > 0
            && totalSnapshot.loadingProviderCount == totalProviderCount
            && totalSnapshot.loadedProviderCount == 0 {
            return AppStrings.text(.statusLoadingUsage, language: languageSettings.resolvedLanguage)
        }
        if totalSnapshot.loadedProviderCount == 0 && totalSnapshot.unauthorizedProviderCount > 0 {
            return AppStrings.text(.statusNeedsHomeAuthorization, language: languageSettings.resolvedLanguage)
        }
        if let errorMessage = totalSnapshot.errorMessages.first ?? periodSnapshot.errorMessages.first {
            return errorMessage
        }
        if totalSnapshot.totalTokens == 0 {
            return AppStrings.text(.statusTotalNoTokenData, language: languageSettings.resolvedLanguage)
        }
        if totalSnapshot.loadingProviderCount > 0 {
            return AppStrings.text(.statusPartialLoading, language: languageSettings.resolvedLanguage)
        }
        return ""
    }
}

private enum DashboardNavigationItem: String, CaseIterable {
    case overview
    case timeline
    case sessions
    case models
    case projects
    case settings

    var title: String {
        switch self {
        case .overview: return "总览"
        case .timeline: return "时间线"
        case .sessions: return "会话"
        case .models: return "模型"
        case .projects: return "项目"
        case .settings: return "设置"
        }
    }

    var symbolName: String {
        switch self {
        case .overview: return "waveform.path.ecg"
        case .timeline: return "clock"
        case .sessions: return "message"
        case .models: return "cpu"
        case .projects: return "folder"
        case .settings: return "gearshape"
        }
    }
}

private enum DashboardRange: String, CaseIterable {
    case day
    case sevenDays
    case month
    case all

    var title: String {
        switch self {
        case .day: return "当天"
        case .sevenDays: return "7天"
        case .month: return "30天"
        case .all: return "全部"
        }
    }

    var period: UsageStatsPeriod {
        switch self {
        case .day:
            return .today
        case .sevenDays, .month:
            return .recent30Days
        case .all:
            return .recent12Months
        }
    }
}

private struct DashboardUsageSummary {
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
    let details: [DashboardDetailRow]

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
        var details: [DashboardDetailRow] = []

        for (providerID, state) in states {
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
            for (month, summary) in stats.byMonth.sorted(by: { $0.key > $1.key }).prefix(3) {
                details.append(DashboardDetailRow(
                    period: month,
                    source: providerName(providerID),
                    project: topProjectName(in: stats),
                    model: topModelName(in: summary),
                    tokens: summary.totalTokens,
                    cost: summary.cost,
                    percentage: totalTokens > 0 ? Double(summary.totalTokens) / Double(totalTokens) : 0
                ))
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
            projectCount: projects.filter { $0.value.totalTokens > 0 }.count,
            projects: makeProjectRows(projects),
            details: details.sorted { $0.period > $1.period }
        )
    }

    static func makePeriod(from snapshot: MonthlyTokenChartSnapshot) -> DashboardUsageSummary {
        let modelProjects = snapshot.modelShareSlices.map {
            DashboardProjectRow(name: $0.label, tokens: $0.totalTokens)
        }
        let details = snapshot.monthBuckets
            .filter { $0.totalTokens > 0 }
            .reversed()
            .prefix(5)
            .map { bucket in
                DashboardDetailRow(
                    period: bucket.monthLabel,
                    source: "汇总",
                    project: "全部项目",
                    model: bucket.modelSegments.first?.modelName ?? "全部模型",
                    tokens: bucket.totalTokens,
                    cost: bucket.totalCost,
                    percentage: snapshot.totalTokens > 0 ? Double(bucket.totalTokens) / Double(snapshot.totalTokens) : 0
                )
            }

        return DashboardUsageSummary(
            inputTokens: 0,
            outputTokens: 0,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            reasoningTokens: 0,
            totalTokens: snapshot.totalTokens,
            cost: snapshot.totalCost,
            entryCount: snapshot.monthBuckets.reduce(0) { $0 + ($1.totalTokens > 0 ? 1 : 0) },
            projectCount: modelProjects.count,
            projects: Array(modelProjects.prefix(4)),
            details: Array(details)
        )
    }

    private static func makeProjectRows(_ projects: [String: UsageSummary]) -> [DashboardProjectRow] {
        projects
            .filter { $0.value.totalTokens > 0 }
            .sorted { lhs, rhs in
                if lhs.value.totalTokens != rhs.value.totalTokens {
                    return lhs.value.totalTokens > rhs.value.totalTokens
                }
                return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
            }
            .prefix(4)
            .map { DashboardProjectRow(name: displayProjectName($0.key), tokens: $0.value.totalTokens) }
    }

    private static func providerName(_ id: ProviderID) -> String {
        ProviderRegistry.provider(for: id)?.displayName ?? id.rawValue
    }

    private static func displayProjectName(_ path: String) -> String {
        let components = path.split(separator: "/")
        return components.last.map(String.init) ?? path
    }

    private static func topProjectName(in stats: AggregatedStats) -> String {
        guard let project = stats.byProject.max(by: { $0.value.totalTokens < $1.value.totalTokens }) else {
            return "全部项目"
        }
        return displayProjectName(project.key)
    }

    private static func topModelName(in summary: UsageSummary) -> String {
        summary.modelBreakdown.max(by: { $0.value.totalTokens < $1.value.totalTokens })?.key ?? "全部模型"
    }
}

private struct DashboardProjectRow {
    let name: String
    let tokens: Int
}

private struct DashboardDetailRow {
    let period: String
    let source: String
    let project: String
    let model: String
    let tokens: Int
    let cost: Double
    let percentage: Double
}

private enum DashboardColors {
    static let palette = [
        DashboardPalette.accent,
        DashboardPalette.green,
        DashboardPalette.yellow,
        DashboardPalette.purple,
        NSColor(hex: 0x38BDF8),
        NSColor(hex: 0xFB7185),
    ]

    static func modelColor(at index: Int) -> NSColor {
        palette[index % palette.count]
    }
}

private final class DashboardRoundedView: NSView {
    init(
        backgroundColor: NSColor,
        cornerRadius: CGFloat,
        borderColor: NSColor? = nil,
        borderWidth: CGFloat = 0
    ) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = backgroundColor.cgColor
        layer?.cornerRadius = cornerRadius
        layer?.borderColor = borderColor?.cgColor
        layer?.borderWidth = borderWidth
    }

    required init?(coder: NSCoder) {
        fatalError("DashboardRoundedView 必须用 init(backgroundColor:cornerRadius:) 构造")
    }
}

private final class DashboardDotView: NSView {
    private let color: NSColor

    init(color: NSColor, accessibilityIdentifier: String? = nil, accessibilityValue: String? = nil) {
        self.color = color
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
        layer?.cornerRadius = 4
        if let accessibilityIdentifier {
            setAccessibilityIdentifier(accessibilityIdentifier)
        }
        if let accessibilityValue {
            setAccessibilityValue(accessibilityValue)
        }
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 8),
            heightAnchor.constraint(equalToConstant: 8),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("DashboardDotView 必须用 init(color:) 构造")
    }
}

private final class DashboardBarRowView: NSView {
    private let fraction: CGFloat
    private let color: NSColor

    init(title: String, value: String, fraction: CGFloat, color: NSColor) {
        self.fraction = fraction
        self.color = color
        super.init(frame: .zero)
        setup(title: title, value: value)
    }

    required init?(coder: NSCoder) {
        fatalError("DashboardBarRowView 必须用 init(title:value:fraction:color:) 构造")
    }

    private func setup(title: String, value: String) {
        let bar = DashboardRoundedView(
            backgroundColor: color.withAlphaComponent(0.55),
            cornerRadius: 4
        )
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = DashboardPalette.primaryText
        titleLabel.lineBreakMode = .byTruncatingMiddle

        let valueLabel = NSTextField(labelWithString: value)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        valueLabel.textColor = DashboardPalette.secondaryText
        valueLabel.alignment = .right

        addSubview(bar)
        addSubview(titleLabel)
        addSubview(valueLabel)
        bar.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),
            bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.topAnchor.constraint(equalTo: topAnchor),
            bar.bottomAnchor.constraint(equalTo: bottomAnchor),
            bar.widthAnchor.constraint(equalTo: widthAnchor, multiplier: fraction),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: valueLabel.leadingAnchor, constant: -12),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 76),
        ])
    }
}

private final class DashboardTrendView: NSView {
    private var buckets: [MonthlyTokenBucket] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(hex: 0x07101A).cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    func configure(buckets: [MonthlyTokenBucket]) {
        self.buckets = buckets
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !buckets.isEmpty, bounds.width > 28, bounds.height > 32 else { return }
        let drawingRect = bounds.insetBy(dx: 12, dy: 14)
        guard drawingRect.width.isFinite,
              drawingRect.height.isFinite,
              drawingRect.width > 0,
              drawingRect.height > 0 else { return }
        drawGrid(in: drawingRect)
        drawTrend(in: drawingRect)
    }

    private func drawGrid(in rect: NSRect) {
        DashboardPalette.subtleBorder.withAlphaComponent(0.55).setStroke()
        let path = NSBezierPath()
        for index in 0...3 {
            let y = rect.minY + rect.height * CGFloat(index) / 3
            path.move(to: NSPoint(x: rect.minX, y: y))
            path.line(to: NSPoint(x: rect.maxX, y: y))
        }
        path.lineWidth = 1
        path.stroke()
    }

    private func drawTrend(in rect: NSRect) {
        let maxTokens = max(1, buckets.map(\.totalTokens).max() ?? 0)
        let points = buckets.enumerated().map { index, bucket -> NSPoint in
            let x = rect.minX + rect.width * CGFloat(index) / CGFloat(max(1, buckets.count - 1))
            let normalized = CGFloat(bucket.totalTokens) / CGFloat(maxTokens)
            let y = rect.minY + rect.height * normalized
            return NSPoint(x: x, y: y)
        }

        let fillPath = NSBezierPath()
        if let first = points.first {
            fillPath.move(to: NSPoint(x: first.x, y: rect.minY))
            for point in points {
                fillPath.line(to: point)
            }
            if let last = points.last {
                fillPath.line(to: NSPoint(x: last.x, y: rect.minY))
            }
            fillPath.close()
            DashboardPalette.accent.withAlphaComponent(0.18).setFill()
            fillPath.fill()
        }

        let linePath = NSBezierPath()
        for (index, point) in points.enumerated() {
            index == 0 ? linePath.move(to: point) : linePath.line(to: point)
        }
        DashboardPalette.accent.setStroke()
        linePath.lineWidth = 2
        linePath.stroke()
    }
}

private final class DashboardDonutView: NSView {
    private var slices: [UsageShareSlice] = []

    func configure(slices: [UsageShareSlice]) {
        self.slices = slices.filter { $0.totalTokens > 0 }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let rect = bounds.insetBy(dx: 10, dy: 10)
        let total = slices.reduce(0) { $0 + $1.totalTokens }
        guard total > 0 else {
            DashboardPalette.subtleBorder.setStroke()
            NSBezierPath(ovalIn: rect).stroke()
            return
        }

        var startAngle: CGFloat = 90
        for (index, slice) in slices.enumerated() {
            let sweep = CGFloat(slice.totalTokens) / CGFloat(total) * 360
            let path = NSBezierPath()
            let center = NSPoint(x: rect.midX, y: rect.midY)
            path.move(to: center)
            path.appendArc(
                withCenter: center,
                radius: min(rect.width, rect.height) / 2,
                startAngle: startAngle,
                endAngle: startAngle - sweep,
                clockwise: true
            )
            path.close()
            DashboardColors.modelColor(at: index).setFill()
            path.fill()
            startAngle -= sweep
        }

        DashboardPalette.deepPanelBackground.setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: rect.width * 0.27, dy: rect.height * 0.27)).fill()
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
            modelBreakdown: modelBreakdown.merging(other.modelBreakdown) { $0.merged(with: $1) }
        )
    }
}

private extension NSColor {
    convenience init(hex: Int) {
        self.init(
            calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
