import AppKit
import Charts
import SwiftUI

enum DashboardPalette {
    static let appBackground = dynamicColor(light: 0xF4F6FA, dark: 0x0B0F14)
    static let sidebarBackground = dynamicColor(light: 0xFFFFFF, dark: 0x05070A)
    static let panelBackground = dynamicColor(light: 0xFFFFFF, dark: 0x151B23)
    static let deepPanelBackground = dynamicColor(light: 0xFFFFFF, dark: 0x05070A)
    static let scanCardBackground = dynamicColor(light: 0xF8FAFC, dark: 0x0D1117)
    static let border = dynamicColor(light: 0xD8DEE8, dark: 0x2B3440)
    static let subtleBorder = dynamicColor(light: 0xE5E7EB, dark: 0x223041)
    static let primaryText = dynamicColor(light: 0x111827, dark: 0xF5F7FA)
    static let secondaryText = dynamicColor(light: 0x6B7280, dark: 0x9CA3AF)
    static let mutedText = dynamicColor(light: 0x94A3B8, dark: 0x6B7280)
    static let accent = dynamicColor(light: 0x2563EB, dark: 0x5AA2FF)
    static let green = dynamicColor(light: 0x16A34A, dark: 0x5FE3A1)
    static let costLine = dynamicColor(light: 0x16A34A, dark: 0x39D353)
    static let statusInactive = dynamicColor(light: 0xDC2626, dark: 0x4B5563)
    static let yellow = dynamicColor(light: 0xF59E0B, dark: 0xF5C451)
    static let purple = dynamicColor(light: 0x8B5CF6, dark: 0xA78BFA)
    static let navigationSelectedBackground = dynamicColor(light: 0xEAF2FF, dark: 0x182235)
    static let navigationSelectedText = dynamicColor(light: 0x2563EB, dark: 0xFFFFFF)
    static let rangeSelectedBackground = dynamicColor(light: 0x2563EB, dark: 0xF5F7FA)
    static let rangeSelectedText = dynamicColor(light: 0xFFFFFF, dark: 0x0B0F14)
    static let rangeSelectedBorder = dynamicColor(light: 0x2563EB, dark: 0x2B3440)
    static let sessionTableHeaderBackground = dynamicColor(light: 0xF1F5F9, dark: 0x202936)
    static let sessionTableAlternateRowBackground = dynamicColor(light: 0xF8FAFC, dark: 0x111820)
    static let sessionDateBackground = dynamicColor(light: 0xFFFFFF, dark: 0x111827)
    static let sessionDateBorder = dynamicColor(light: 0xD8DEE8, dark: 0x263244)
    static let sessionCopyIcon = dynamicColor(light: 0x94A3B8, dark: 0x6B7280)
    static let sessionProviderBadgeBackground = dynamicColor(light: 0xF1F5F9, dark: 0x202936)
    static let sessionClaude = dynamicColor(light: 0x2563EB, dark: 0x5AA2FF)
    static let sessionCodex = dynamicColor(light: 0x16A34A, dark: 0x4ADE80)
    static let sessionOpenCode = dynamicColor(light: 0xD97706, dark: 0xFBBF24)

    private static func dynamicColor(light: Int, dark: Int) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        }
    }
}

@MainActor
private enum AppLogoImage {
    static let identifier = "AppLogo"

    static func make() -> NSImage? {
        guard let source = NSImage(named: NSImage.Name("AppIcon")) ?? NSApp.applicationIconImage else {
            return nil
        }
        guard let image = source.copy() as? NSImage else { return nil }
        image.isTemplate = false
        return image
    }
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
    private static let sessionTableColumnWidths: [CGFloat] = [150, 180, 86, 200, 150, 104, 84, 66]

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
    private let sessionScrollView = NSScrollView()
    private let sessionContentView = NSView()
    private let sessionStack = NSStackView()
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
    private let sessionTitleLabel = NSTextField(labelWithString: "会话")
    private let sessionSubtitleLabel = NSTextField(labelWithString: "按最近时间倒序查看会话聚合、成本与使用记录")
    private let sessionDateLabel = NSTextField(labelWithString: "")
    private let sessionCountValueLabel = NSTextField(labelWithString: "0")
    private let sessionTokenValueLabel = NSTextField(labelWithString: "0")
    private let sessionCostValueLabel = NSTextField(labelWithString: "$0.00")
    private let sessionRecordValueLabel = NSTextField(labelWithString: "0")
    private let sessionRowsStack = NSStackView()
    private let sessionStatusLabel = NSTextField(labelWithString: "")

    private var rangeButtons: [DashboardRange: NSButton] = [:]
    private var navButtons: [DashboardNavigationItem: NSButton] = [:]
    private var selectedRange: DashboardRange = .sevenDays
    private var selectedNavigationItem: DashboardNavigationItem = .overview
    private var currentSettingsController: NSViewController?
    private var overviewConstraints: [NSLayoutConstraint] = []
    private var sessionConstraints: [NSLayoutConstraint] = []
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
        overviewScrollView.scrollerStyle = .overlay
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
        setupSessionContent()
    }

    private func setupSessionContent() {
        sessionScrollView.userInterfaceLayoutDirection = .leftToRight
        sessionScrollView.drawsBackground = false
        sessionScrollView.borderType = .noBorder
        sessionScrollView.hasVerticalScroller = true
        sessionScrollView.autohidesScrollers = true
        sessionScrollView.scrollerStyle = .overlay
        sessionScrollView.translatesAutoresizingMaskIntoConstraints = false
        sessionScrollView.documentView = sessionContentView

        sessionContentView.userInterfaceLayoutDirection = .leftToRight
        sessionContentView.translatesAutoresizingMaskIntoConstraints = false
        sessionContentView.wantsLayer = true
        sessionContentView.layer?.backgroundColor = DashboardPalette.appBackground.cgColor

        sessionStack.translatesAutoresizingMaskIntoConstraints = false
        sessionStack.orientation = .vertical
        sessionStack.alignment = .leading
        sessionStack.spacing = Self.rowGap
        sessionStack.identifier = NSUserInterfaceItemIdentifier("DashboardSessionsPage")
        sessionStack.setAccessibilityIdentifier("DashboardSessionsPage")
        sessionContentView.addSubview(sessionStack)

        addFullWidthArrangedSubview(makeSessionHeaderView(), to: sessionStack)
        addFullWidthArrangedSubview(makeSessionMetricRow(), to: sessionStack)
        addFullWidthArrangedSubview(makeSessionTable(), to: sessionStack)
        addFullWidthArrangedSubview(sessionStatusLabel, to: sessionStack)
        configureBodyStatusLabel(sessionStatusLabel)

        NSLayoutConstraint.activate([
            sessionContentView.leadingAnchor.constraint(equalTo: sessionScrollView.contentView.leadingAnchor),
            sessionContentView.trailingAnchor.constraint(equalTo: sessionScrollView.contentView.trailingAnchor),
            sessionContentView.topAnchor.constraint(equalTo: sessionScrollView.contentView.topAnchor),
            sessionContentView.widthAnchor.constraint(equalTo: sessionScrollView.contentView.widthAnchor),
            sessionContentView.heightAnchor.constraint(greaterThanOrEqualTo: sessionScrollView.contentView.heightAnchor),
            sessionStack.leadingAnchor.constraint(equalTo: sessionContentView.leadingAnchor, constant: Self.pageInset),
            sessionStack.trailingAnchor.constraint(equalTo: sessionContentView.trailingAnchor, constant: -Self.pageInset),
            sessionStack.topAnchor.constraint(equalTo: sessionContentView.topAnchor, constant: Self.pageInset),
            sessionStack.bottomAnchor.constraint(lessThanOrEqualTo: sessionContentView.bottomAnchor, constant: -Self.pageInset),
            sessionStack.widthAnchor.constraint(greaterThanOrEqualToConstant: Self.minimumContentWidth),
        ])
    }

    private func makeBrandView() -> NSView {
        let logoView = NSImageView(frame: .zero)
        logoView.translatesAutoresizingMaskIntoConstraints = false
        logoView.image = AppLogoImage.make()
        logoView.imageScaling = .scaleProportionallyUpOrDown
        logoView.identifier = NSUserInterfaceItemIdentifier("DashboardBrandIcon.\(AppLogoImage.identifier)")
        logoView.setAccessibilityIdentifier("DashboardBrandIcon.\(AppLogoImage.identifier)")
        logoView.setAccessibilityLabel("TokenWatch")
        logoView.setContentHuggingPriority(.required, for: .horizontal)
        logoView.setContentCompressionResistancePriority(.required, for: .horizontal)

        let name = NSTextField(labelWithString: "TokenWatch")
        name.font = .systemFont(ofSize: 18, weight: .bold)
        name.textColor = DashboardPalette.primaryText
        let subtitle = NSTextField(labelWithString: AppStrings.text(
            .appTagline,
            language: languageSettings.resolvedLanguage
        ))
        subtitle.font = .systemFont(ofSize: 11, weight: .regular)
        subtitle.textColor = DashboardPalette.secondaryText

        let textStack = NSStackView(views: [name, subtitle])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        let row = NSStackView(views: [logoView, textStack])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        NSLayoutConstraint.activate([
            logoView.widthAnchor.constraint(equalToConstant: 34),
            logoView.heightAnchor.constraint(equalToConstant: 34),
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
        title.textColor = DashboardPalette.primaryText

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
        controlsStack.identifier = NSUserInterfaceItemIdentifier("DashboardHeaderControls")
        controlsStack.setAccessibilityIdentifier("DashboardHeaderControls")
        for range in DashboardRange.allCases {
            let button = makeRangeButton(range)
            rangeButtons[range] = button
            controlsStack.addArrangedSubview(button)
        }
        configureRefreshButton()
        controlsStack.addArrangedSubview(refreshButton)

        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(titleStack)
        header.addSubview(controlsStack)
        titleStack.translatesAutoresizingMaskIntoConstraints = false
        controlsStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            header.heightAnchor.constraint(greaterThanOrEqualToConstant: 64),
            titleStack.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            titleStack.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            titleStack.topAnchor.constraint(greaterThanOrEqualTo: header.topAnchor),
            titleStack.bottomAnchor.constraint(lessThanOrEqualTo: header.bottomAnchor),
            controlsStack.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            controlsStack.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            controlsStack.leadingAnchor.constraint(greaterThanOrEqualTo: titleStack.trailingAnchor, constant: 18),
        ])
        return header
    }

    private func makeSessionHeaderView() -> NSView {
        sessionTitleLabel.font = .systemFont(ofSize: 26, weight: .bold)
        sessionTitleLabel.textColor = DashboardPalette.primaryText
        sessionSubtitleLabel.font = .systemFont(ofSize: 12)
        sessionSubtitleLabel.textColor = DashboardPalette.secondaryText

        let titleStack = NSStackView(views: [sessionTitleLabel, sessionSubtitleLabel])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 1

        let header = NSView()
        let dateBadge = makeSessionDateBadge()
        header.addSubview(titleStack)
        header.addSubview(dateBadge)
        titleStack.translatesAutoresizingMaskIntoConstraints = false
        dateBadge.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            header.heightAnchor.constraint(greaterThanOrEqualToConstant: 64),
            titleStack.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            titleStack.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            titleStack.topAnchor.constraint(greaterThanOrEqualTo: header.topAnchor),
            titleStack.bottomAnchor.constraint(lessThanOrEqualTo: header.bottomAnchor),
            dateBadge.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            dateBadge.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            dateBadge.leadingAnchor.constraint(greaterThanOrEqualTo: titleStack.trailingAnchor, constant: 18),
        ])
        return header
    }

    private func makeSessionDateBadge() -> NSView {
        let iconView = NSImageView()
        iconView.image = NSImage(systemSymbolName: "calendar", accessibilityDescription: "日期")
        iconView.image?.isTemplate = true
        iconView.contentTintColor = DashboardPalette.secondaryText
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        sessionDateLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        sessionDateLabel.textColor = DashboardPalette.primaryText
        sessionDateLabel.lineBreakMode = .byTruncatingTail

        let stack = NSStackView(views: [iconView, sessionDateLabel])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8

        let badge = DashboardRoundedView(
            backgroundColor: DashboardPalette.sessionDateBackground,
            cornerRadius: 7,
            borderColor: DashboardPalette.sessionDateBorder,
            borderWidth: 1
        )
        badge.identifier = NSUserInterfaceItemIdentifier("DashboardSessionsDateBadge")
        badge.setAccessibilityIdentifier("DashboardSessionsDateBadge")
        badge.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            badge.heightAnchor.constraint(equalToConstant: 35),
            badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 126),
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),
            stack.leadingAnchor.constraint(equalTo: badge.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: badge.trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
        ])
        return badge
    }

    private func makeSessionMetricRow() -> NSView {
        let row = NSStackView(views: [
            makeSessionMetricCard(title: "会话数", valueLabel: sessionCountValueLabel),
            makeSessionMetricCard(title: "总 Token", valueLabel: sessionTokenValueLabel),
            makeSessionMetricCard(title: "成本", valueLabel: sessionCostValueLabel),
            makeSessionMetricCard(title: "记录数", valueLabel: sessionRecordValueLabel),
        ])
        row.orientation = .horizontal
        row.alignment = .height
        row.distribution = .fillEqually
        row.spacing = 14
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 104),
        ])
        return row
    }

    private func makeSessionMetricCard(title: String, valueLabel: NSTextField) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = DashboardPalette.secondaryText

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 26, weight: .bold)
        valueLabel.textColor = DashboardPalette.primaryText
        valueLabel.lineBreakMode = .byTruncatingTail

        let stack = NSStackView(views: [titleLabel, valueLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8

        let card = DashboardRoundedView(
            backgroundColor: DashboardPalette.panelBackground,
            cornerRadius: 8,
            borderColor: DashboardPalette.border,
            borderWidth: 1
        )
        card.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -18),
        ])
        return card
    }

    private func makeRangeButton(_ range: DashboardRange) -> NSButton {
        let button = NSButton(title: range.title, target: self, action: #selector(rangeButtonClicked(_:)))
        button.identifier = NSUserInterfaceItemIdentifier("DashboardRange.\(range.rawValue)")
        button.setAccessibilityIdentifier("DashboardRange.\(range.rawValue)")
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.font = .systemFont(ofSize: 12, weight: .semibold)
        button.alignment = .center
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.layer?.borderWidth = 1
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 35),
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 64),
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
        refreshButton.imageHugsTitle = true
        refreshButton.bezelStyle = .regularSquare
        refreshButton.isBordered = false
        refreshButton.font = .systemFont(ofSize: 12, weight: .semibold)
        refreshButton.alignment = .center
        refreshButton.contentTintColor = DashboardPalette.primaryText
        refreshButton.wantsLayer = true
        refreshButton.layer?.cornerRadius = 8
        refreshButton.layer?.borderWidth = 1
        refreshButton.layer?.borderColor = DashboardPalette.border.cgColor
        refreshButton.layer?.backgroundColor = DashboardPalette.panelBackground.cgColor
        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        refreshButton.setContentHuggingPriority(.required, for: .horizontal)
        refreshButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            refreshButton.heightAnchor.constraint(equalToConstant: 35),
            refreshButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 86),
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
            title: "趋势",
            subtitle: "展示 Token 消耗与费用变化",
            content: trendView,
            minimumHeight: 230,
            trailingHeaderContent: makeTrendLegendView()
        )
    }

    private func makeTrendLegendView() -> NSView {
        let row = NSStackView(views: [
            makeTrendLegendItem(
                title: DashboardTrendRendering.tokenLegendTitle,
                color: DashboardPalette.accent,
                identifier: "DashboardTrendLegend.token"
            ),
            makeTrendLegendItem(
                title: DashboardTrendRendering.costLegendTitle,
                color: DashboardPalette.costLine,
                identifier: "DashboardTrendLegend.cost"
            ),
        ])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 14
        row.setContentHuggingPriority(.required, for: .horizontal)
        row.setContentCompressionResistancePriority(.required, for: .horizontal)
        return row
    }

    private func makeTrendLegendItem(title: String, color: NSColor, identifier: String) -> NSView {
        let dot = DashboardDotView(color: color)

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = DashboardPalette.secondaryText
        label.alignment = .left
        label.lineBreakMode = .byTruncatingTail

        let item = NSStackView(views: [dot, label])
        item.orientation = .horizontal
        item.alignment = .centerY
        item.spacing = 7
        item.setAccessibilityIdentifier(identifier)
        item.setContentHuggingPriority(.required, for: .horizontal)
        item.setContentCompressionResistancePriority(.required, for: .horizontal)
        return item
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

    private func makePanel(
        title: String,
        subtitle: String?,
        content: NSView,
        minimumHeight: CGFloat,
        trailingHeaderContent: NSView? = nil
    ) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 16, weight: .bold)
        titleLabel.textColor = DashboardPalette.primaryText
        titleLabel.lineBreakMode = .byTruncatingTail

        var headerViews: [NSView] = [titleLabel]
        var trailingAlignmentView: NSView = titleLabel
        if let subtitle {
            let subtitleLabel = NSTextField(labelWithString: subtitle)
            subtitleLabel.font = .systemFont(ofSize: 12)
            subtitleLabel.textColor = DashboardPalette.secondaryText
            subtitleLabel.lineBreakMode = .byTruncatingTail
            headerViews.append(subtitleLabel)
            trailingAlignmentView = subtitleLabel
        }
        let headerStack = NSStackView(views: headerViews)
        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 3

        let headerView: NSView
        if let trailingHeaderContent {
            let headerContainer = NSView()
            headerContainer.addSubview(headerStack)
            headerContainer.addSubview(trailingHeaderContent)
            headerStack.translatesAutoresizingMaskIntoConstraints = false
            trailingHeaderContent.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                headerStack.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor),
                headerStack.topAnchor.constraint(equalTo: headerContainer.topAnchor),
                headerStack.bottomAnchor.constraint(equalTo: headerContainer.bottomAnchor),
                headerStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingHeaderContent.leadingAnchor, constant: -18),
                trailingHeaderContent.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor),
                trailingHeaderContent.centerYAnchor.constraint(equalTo: trailingAlignmentView.centerYAnchor),
            ])
            headerView = headerContainer
        } else {
            headerView = headerStack
        }

        let stack = NSStackView(views: [headerView, content])
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
            headerView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            content.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        return panel
    }

    private func makeDetailTable() -> NSView {
        let title = NSTextField(labelWithString: "最近明细")
        title.font = .systemFont(ofSize: 16, weight: .bold)
        title.textColor = DashboardPalette.primaryText

        let header = makeDetailRow(
            values: ["时间", "工具", "会话", "项目", "模型", "Token", "费用", "记录"],
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

    private func makeSessionTable() -> NSView {
        let header = makeSessionTableHeader()
        sessionRowsStack.orientation = .vertical
        sessionRowsStack.alignment = .width
        sessionRowsStack.spacing = 0

        let stack = NSStackView(views: [header, sessionRowsStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0

        let table = DashboardRoundedView(
            backgroundColor: DashboardPalette.panelBackground,
            cornerRadius: 8,
            borderColor: DashboardPalette.border,
            borderWidth: 1
        )
        table.identifier = NSUserInterfaceItemIdentifier("DashboardSessionsTable")
        table.setAccessibilityIdentifier("DashboardSessionsTable")
        table.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            table.heightAnchor.constraint(equalToConstant: 620),
            stack.leadingAnchor.constraint(equalTo: table.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: table.trailingAnchor),
            stack.topAnchor.constraint(equalTo: table.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: table.bottomAnchor),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            sessionRowsStack.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        return table
    }

    private func makeSessionTableHeader() -> NSView {
        makeSessionTableRowContainer(
            identifier: "DashboardSessionsTableHeader",
            backgroundColor: DashboardPalette.sessionTableHeaderBackground,
            height: 44,
            cells: zip(
                ["最近时间 ↓", "会话 ID", "工具", "项目", "主模型", "总 Token", "成本", "记录数"],
                Self.sessionTableColumnWidths
            ).map { title, width in
                makeSessionTextCell(
                    text: title,
                    width: width,
                    font: .systemFont(ofSize: 11, weight: .bold),
                    color: DashboardPalette.secondaryText
                )
            }
        )
    }

    private func makeSessionTableRow(_ row: RecentSessionRow, index: Int) -> NSView {
        makeSessionTableRowContainer(
            identifier: "DashboardSessionsRow.\(index)",
            backgroundColor: sessionTableRowBackground(at: index),
            height: 56,
            cells: [
                makeSessionTextCell(
                    text: DashboardRangeSnapshot.formatDetailDate(row.lastActiveAt),
                    width: Self.sessionTableColumnWidths[0],
                    font: .monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
                    color: DashboardPalette.primaryText
                ),
                makeSessionIDCell(row.sessionID, width: Self.sessionTableColumnWidths[1]),
                makeSessionProviderCell(row.provider, width: Self.sessionTableColumnWidths[2]),
                makeSessionTextCell(
                    text: row.projectPath.map(DashboardRangeSnapshot.displayProjectName) ?? "unknown",
                    width: Self.sessionTableColumnWidths[3],
                    font: .systemFont(ofSize: 12),
                    color: DashboardPalette.secondaryText
                ),
                makeSessionTextCell(
                    text: DashboardRangeSnapshot.modelText(for: row),
                    width: Self.sessionTableColumnWidths[4],
                    font: .systemFont(ofSize: 12, weight: .medium),
                    color: DashboardPalette.primaryText
                ),
                makeSessionTextCell(
                    text: CompactNumberFormatter.format(row.totalTokens),
                    width: Self.sessionTableColumnWidths[5],
                    font: .monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
                    color: DashboardPalette.secondaryText
                ),
                makeSessionTextCell(
                    text: formatCurrency(row.cost),
                    width: Self.sessionTableColumnWidths[6],
                    font: .monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
                    color: DashboardPalette.primaryText
                ),
                makeSessionTextCell(
                    text: formatInt(row.entryCount),
                    width: Self.sessionTableColumnWidths[7],
                    font: .monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
                    color: DashboardPalette.secondaryText
                ),
            ]
        )
    }

    private func makeEmptySessionTableRow() -> NSView {
        makeSessionTableRowContainer(
            identifier: "DashboardSessionsRow.0",
            backgroundColor: sessionTableRowBackground(at: 0),
            height: 56,
            cells: zip(
                ["暂无会话", "-", "-", "-", "-", "-", "-", "-"],
                Self.sessionTableColumnWidths
            ).map { value, width in
                makeSessionTextCell(
                    text: value,
                    width: width,
                    font: .systemFont(ofSize: 12),
                    color: DashboardPalette.secondaryText
                )
            }
        )
    }

    private func makeSessionTableRowContainer(
        identifier: String,
        backgroundColor: NSColor,
        height: CGFloat,
        cells: [NSView]
    ) -> NSView {
        let content = NSStackView(views: cells)
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = 8

        let row = DashboardRoundedView(backgroundColor: backgroundColor, cornerRadius: 0)
        row.identifier = NSUserInterfaceItemIdentifier(identifier)
        row.setAccessibilityIdentifier(identifier)
        row.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: height),
            content.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -16),
            content.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
        return row
    }

    private func makeSessionTextCell(text: String, width: CGFloat, font: NSFont, color: NSColor) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 1

        let cell = NSView()
        cell.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            cell.widthAnchor.constraint(equalToConstant: width),
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private func makeSessionIDCell(_ sessionID: String, width: CGFloat) -> NSView {
        let label = NSTextField(labelWithString: sessionID)
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        label.textColor = DashboardPalette.secondaryText
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 1
        label.toolTip = sessionID

        let iconView = NSImageView()
        iconView.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "复制完整 ID")
        iconView.image?.isTemplate = true
        iconView.contentTintColor = DashboardPalette.sessionCopyIcon
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [label, iconView])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8

        let cell = NSView()
        cell.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            cell.widthAnchor.constraint(equalToConstant: width),
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private func makeSessionProviderCell(_ provider: ProviderID, width: CGFloat) -> NSView {
        let dot = DashboardDotView(color: sessionProviderColor(provider))

        let label = NSTextField(labelWithString: sessionProviderName(provider))
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = DashboardPalette.primaryText

        let stack = NSStackView(views: [dot, label])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6

        let badge = DashboardRoundedView(
            backgroundColor: DashboardPalette.sessionProviderBadgeBackground,
            cornerRadius: 999,
            borderColor: DashboardPalette.border,
            borderWidth: 1
        )
        badge.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let cell = NSView()
        cell.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(badge)
        badge.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            cell.widthAnchor.constraint(equalToConstant: width),
            stack.leadingAnchor.constraint(equalTo: badge.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: badge.trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            badge.heightAnchor.constraint(equalToConstant: 26),
            badge.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
            badge.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            badge.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor),
        ])
        return cell
    }

    private func sessionTableRowBackground(at index: Int) -> NSColor {
        index.isMultiple(of: 2)
            ? DashboardPalette.panelBackground
            : DashboardPalette.sessionTableAlternateRowBackground
    }

    private func sessionProviderColor(_ provider: ProviderID) -> NSColor {
        switch provider {
        case .claude:
            return DashboardPalette.sessionClaude
        case .codex:
            return DashboardPalette.sessionCodex
        case .opencode:
            return DashboardPalette.sessionOpenCode
        }
    }

    private func sessionProviderName(_ provider: ProviderID) -> String {
        switch provider {
        case .claude:
            return "Claude"
        case .codex:
            return "Codex"
        case .opencode:
            return "opencode"
        }
    }

    private func makeDetailRow(values: [String], isHeader: Bool) -> NSView {
        let widths: [CGFloat] = [116, 58, 168, 150, 132, 82, 70, 48]
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
        NSLayoutConstraint.deactivate(overviewConstraints)
        NSLayoutConstraint.deactivate(sessionConstraints)
        NSLayoutConstraint.deactivate(settingsConstraints)
        sessionScrollView.removeFromSuperview()
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

    private func installSessionContent() {
        currentSettingsController?.view.removeFromSuperview()
        currentSettingsController?.removeFromParent()
        currentSettingsController = nil
        NSLayoutConstraint.deactivate(overviewConstraints)
        NSLayoutConstraint.deactivate(sessionConstraints)
        NSLayoutConstraint.deactivate(settingsConstraints)
        overviewScrollView.removeFromSuperview()
        if sessionScrollView.superview == nil {
            mainContentContainer.addSubview(sessionScrollView)
        }
        sessionConstraints = [
            sessionScrollView.leadingAnchor.constraint(equalTo: mainContentContainer.leadingAnchor),
            sessionScrollView.trailingAnchor.constraint(equalTo: mainContentContainer.trailingAnchor),
            sessionScrollView.topAnchor.constraint(equalTo: mainContentContainer.topAnchor),
            sessionScrollView.bottomAnchor.constraint(equalTo: mainContentContainer.bottomAnchor),
        ]
        NSLayoutConstraint.activate(sessionConstraints)
    }

    private func installSettingsContent() {
        NSLayoutConstraint.deactivate(overviewConstraints)
        NSLayoutConstraint.deactivate(sessionConstraints)
        overviewScrollView.removeFromSuperview()
        sessionScrollView.removeFromSuperview()
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
            installOverviewContent()
        case .sessions:
            installSessionContent()
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
        let rangeSnapshot = DashboardRangeSnapshot.build(
            states: states,
            range: selectedRange,
            now: nowProvider(),
            calendar: calendar,
            language: languageSettings.resolvedLanguage
        )
        let summary = rangeSnapshot.summary

        totalTokenValueLabel.stringValue = CompactNumberFormatter.formatMillions(summary.totalTokens)
        totalTokenDetailLabel.stringValue = "输入 \(CompactNumberFormatter.formatMillions(summary.inputTokens)) / 输出 \(CompactNumberFormatter.formatMillions(summary.outputTokens)) / 缓存命中率 \(formatCacheHitRate(summary))"
        totalCostValueLabel.stringValue = formatCurrency(summary.cost)
        totalCostDetailLabel.stringValue = formatCostBreakdown(summary)
        sessionValueLabel.stringValue = formatInt(summary.entryCount)
        sessionDetailLabel.stringValue = "\(totalSnapshot.loadedProviderCount) 个来源，\(summary.projectCount) 个项目"
        scanStatusBodyLabel.stringValue = scanStatusText(states: states)

        updateRangeButtons()
        updateNavigationSelection()
        setRefreshButtonLoading(states.values.contains { $0.isLoading })
        rebuildDataSourceRows(states: states)
        trendView.configure(
            buckets: rangeSnapshot.trendBuckets,
            language: languageSettings.resolvedLanguage
        )
        rebuildModelRows(totalSnapshot.modelRows)
        rebuildSourceLegend(rangeSnapshot.toolShareSlices)
        sourceDonutView.configure(slices: rangeSnapshot.toolShareSlices)
        rebuildProjectRows(summary.projects)
        rebuildDetailRows(summary.details)
        statusLabel.stringValue = statusText(
            totalSnapshot: totalSnapshot,
            rangeSnapshot: rangeSnapshot,
            totalProviderCount: states.count
        )
        statusLabel.isHidden = statusLabel.stringValue.isEmpty
        if selectedNavigationItem == .sessions {
            renderSessionPage(states: states)
        }
        enforceLeftAlignedContent(in: view)
    }

    private func renderSessionPage(states: [ProviderID: TokenStatsViewModel.ProviderState]) {
        let snapshot = RecentSessionDetailsBuilder.build(
            states: states,
            period: .recent7Days,
            now: nowProvider(),
            calendar: calendar
        )
        sessionDateLabel.stringValue = formatSessionDate(nowProvider())
        sessionCountValueLabel.stringValue = formatInt(snapshot.totalSessionCount)
        sessionTokenValueLabel.stringValue = CompactNumberFormatter.format(snapshot.totalTokens)
        sessionCostValueLabel.stringValue = formatCurrency(snapshot.totalCost)
        sessionRecordValueLabel.stringValue = formatInt(snapshot.rows.reduce(0) { $0 + $1.entryCount })
        rebuildSessionRows(snapshot.rows)
        sessionStatusLabel.stringValue = sessionStatusText(
            snapshot: snapshot,
            totalProviderCount: states.count
        )
        sessionStatusLabel.isHidden = sessionStatusLabel.stringValue.isEmpty
    }

    private func updateNavigationSelection() {
        for item in DashboardNavigationItem.allCases {
            guard let button = navButtons[item] else { continue }
            let isSelected = item == selectedNavigationItem
            button.layer?.backgroundColor = (
                isSelected ? DashboardPalette.navigationSelectedBackground : DashboardPalette.sidebarBackground
            ).cgColor
            let tintColor = isSelected ? DashboardPalette.navigationSelectedText : DashboardPalette.secondaryText
            button.contentTintColor = tintColor
            (button as? DashboardNavigationButton)?.setVisualTint(tintColor)
        }
    }

    private func updateRangeButtons() {
        for range in DashboardRange.allCases {
            guard let button = rangeButtons[range] else { continue }
            let isSelected = range == selectedRange
            button.layer?.backgroundColor = (
                isSelected ? DashboardPalette.rangeSelectedBackground : DashboardPalette.panelBackground
            ).cgColor
            button.layer?.borderColor = (isSelected ? DashboardPalette.rangeSelectedBorder : DashboardPalette.border).cgColor
            button.contentTintColor = isSelected ? DashboardPalette.rangeSelectedText : DashboardPalette.primaryText
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
        refreshButton.imageHugsTitle = true
        refreshButton.contentTintColor = DashboardPalette.primaryText
    }

    private func scanStatusText(states: [ProviderID: TokenStatsViewModel.ProviderState]) -> String {
        if states.values.contains(where: { $0.isLoading }) {
            return "正在更新本地记录。不依赖任何网络 API。"
        }
        guard let lastRefreshedAt = states.values.compactMap(\.lastRefreshedAt).max() else {
            return "尚未完成本地扫描。不依赖任何网络 API。"
        }
        return "\(relativeRefreshDescription(since: lastRefreshedAt, now: nowProvider()))更新。不依赖任何网络 API。"
    }

    private func relativeRefreshDescription(since date: Date, now: Date) -> String {
        let elapsedSeconds = max(0, now.timeIntervalSince(date))
        let minutes = Int(elapsedSeconds / 60)
        if minutes < 1 {
            return "刚刚"
        }
        if minutes < 60 {
            return "\(minutes) 分钟前"
        }
        return "\(max(1, Int(elapsedSeconds / 3_600))) 小时前"
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
        let statusText = isAuthorized ? "已授权" : "未授权"
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12)
        label.textColor = DashboardPalette.secondaryText
        label.toolTip = statusText
        let dot = DashboardDotView(
            color: isAuthorized ? DashboardPalette.green : DashboardPalette.statusInactive,
            accessibilityIdentifier: "DashboardDataSourceStatus.\(providerID.rawValue)",
            accessibilityValue: isAuthorized ? "authorized" : "unauthorized"
        )
        dot.toolTip = statusText
        let row = NSStackView(views: [label, NSView(), dot])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.identifier = NSUserInterfaceItemIdentifier("DashboardDataSourceRow.\(providerID.rawValue)")
        row.setAccessibilityIdentifier("DashboardDataSourceRow.\(providerID.rawValue)")
        row.toolTip = statusText
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
                values: ["暂无数据", "-", "-", "-", "-", "-", "-", "-"],
                isHeader: false
            ), to: detailRowsStack)
            return
        }
        for row in rows.prefix(5) {
            addFullWidthArrangedSubview(makeDetailRow(
                values: [
                    row.time,
                    row.tool,
                    row.session,
                    row.project,
                    row.model,
                    formatInt(row.tokens),
                    formatCurrency(row.cost),
                    formatInt(row.records),
                ],
                isHeader: false
            ), to: detailRowsStack)
        }
    }

    private func rebuildSessionRows(_ rows: [RecentSessionRow]) {
        clearStack(sessionRowsStack)
        let visibleRows = Array(rows.prefix(8))
        if visibleRows.isEmpty {
            addFullWidthArrangedSubview(makeEmptySessionTableRow(), to: sessionRowsStack)
            return
        }
        for (index, row) in visibleRows.enumerated() {
            addFullWidthArrangedSubview(makeSessionTableRow(row, index: index), to: sessionRowsStack)
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
        if let textField = root as? NSTextField {
            textField.alignment = .left
        }
        if let button = root as? NSButton {
            button.alignment = isHeaderControlButton(button) ? .center : .left
        }
        for subview in root.subviews {
            enforceLeftAlignedContent(in: subview)
        }
    }

    private func isHeaderControlButton(_ button: NSButton) -> Bool {
        let identifier = button.identifier?.rawValue ?? button.accessibilityIdentifier()
        return identifier.hasPrefix("DashboardRange.") || identifier == "DashboardRefreshButton"
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

    private func formatCostBreakdown(_ summary: DashboardUsageSummary) -> String {
        let inputBillableTokens = summary.inputTokens + summary.cacheReadTokens + summary.cacheCreationTokens
        let billableTokens = inputBillableTokens + summary.outputTokens + summary.reasoningTokens
        guard billableTokens > 0, summary.cost > 0 else {
            return "输入 $0.00 / 输出 $0.00 / 推理 $0.00"
        }

        let inputCost = summary.cost * Double(inputBillableTokens) / Double(billableTokens)
        let outputCost = summary.cost * Double(summary.outputTokens) / Double(billableTokens)
        let reasoningCost = summary.cost * Double(summary.reasoningTokens) / Double(billableTokens)
        return "输入 \(formatCurrency(inputCost)) / 输出 \(formatCurrency(outputCost)) / 推理 \(formatCurrency(reasoningCost))"
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

    private func formatSessionDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func sessionStatusText(
        snapshot: RecentSessionDetailsSnapshot,
        totalProviderCount: Int
    ) -> String {
        if totalProviderCount > 0
            && snapshot.loadingProviderCount == totalProviderCount
            && snapshot.loadedProviderCount == 0 {
            return AppStrings.text(.statusLoadingUsage, language: languageSettings.resolvedLanguage)
        }
        if snapshot.loadedProviderCount == 0 && snapshot.unauthorizedProviderCount > 0 {
            return AppStrings.text(.statusNeedsHomeAuthorization, language: languageSettings.resolvedLanguage)
        }
        if let errorMessage = snapshot.errorMessages.first {
            return errorMessage
        }
        if snapshot.rows.isEmpty {
            return "最近 7 天暂无会话记录"
        }
        if snapshot.loadingProviderCount > 0 {
            return AppStrings.text(.statusPartialLoading, language: languageSettings.resolvedLanguage)
        }
        return ""
    }

    private func statusText(
        totalSnapshot: TotalStatsSnapshot,
        rangeSnapshot: DashboardRangeSnapshot,
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
        if let errorMessage = totalSnapshot.errorMessages.first ?? rangeSnapshot.errorMessages.first {
            return errorMessage
        }
        if rangeSnapshot.totalTokens == 0 {
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
    case sessions
    case settings

    var title: String {
        switch self {
        case .overview: return "总览"
        case .sessions: return "会话"
        case .settings: return "设置"
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

private struct DashboardRangeSnapshot {
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
        let details = makeRecentSessionDetailRows(
            states: states,
            range: range,
            now: now,
            calendar: calendar
        )
        let summary = makeWindowSummary(
            orderedSummaries: orderedSummaries,
            projectTotals: projectTotals,
            details: details
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
        let details = makeDetailRows(from: RecentSessionDetailsBuilder.buildAll(states: states))
        let summary = DashboardUsageSummary.makeTotal(from: states, details: details)

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
        projectTotals: [String: Int],
        details: [DashboardDetailRow]
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
            projects: projects,
            details: details
        )
    }

    private static func makeRecentSessionDetailRows(
        states: [ProviderID: TokenStatsViewModel.ProviderState],
        range: DashboardRange,
        now: Date,
        calendar: Calendar
    ) -> [DashboardDetailRow] {
        let snapshot: RecentSessionDetailsSnapshot
        switch range {
        case .day:
            snapshot = RecentSessionDetailsBuilder.build(states: states, period: .today, now: now, calendar: calendar)
        case .sevenDays:
            snapshot = RecentSessionDetailsBuilder.build(states: states, period: .recent7Days, now: now, calendar: calendar)
        case .month:
            snapshot = RecentSessionDetailsBuilder.build(states: states, period: .recent30Days, now: now, calendar: calendar)
        case .all:
            snapshot = RecentSessionDetailsBuilder.buildAll(states: states)
        }

        return makeDetailRows(from: snapshot)
    }

    private static func makeDetailRows(from snapshot: RecentSessionDetailsSnapshot) -> [DashboardDetailRow] {
        snapshot.rows.prefix(5).map { row in
            DashboardDetailRow(
                time: formatDetailDate(row.lastActiveAt),
                tool: providerName(row.provider),
                session: row.sessionID,
                project: row.projectPath.map(displayProjectName) ?? "unknown",
                model: modelText(for: row),
                tokens: row.totalTokens,
                cost: row.cost,
                records: row.entryCount
            )
        }
    }

    fileprivate static func modelText(for row: RecentSessionRow) -> String {
        let model = row.primaryModel.isEmpty ? "-" : row.primaryModel
        guard row.additionalModelCount > 0 else { return model }
        return "\(model) +\(row.additionalModelCount)"
    }

    fileprivate static func formatDetailDate(_ date: Date?) -> String {
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

    fileprivate static func displayProjectName(_ path: String) -> String {
        DashboardProjectRows.displayName(for: path)
    }

    private static func providerName(_ id: ProviderID) -> String {
        ProviderRegistry.provider(for: id)?.displayName ?? id.rawValue
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

    static func makeTotal(
        from states: [ProviderID: TokenStatsViewModel.ProviderState],
        details: [DashboardDetailRow]
    ) -> DashboardUsageSummary {
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
            projects: makeProjectRows(projects),
            details: details
        )
    }

    private static func makeProjectRows(_ projects: [String: UsageSummary]) -> [DashboardProjectRow] {
        DashboardProjectRows.makeRows(fromSummaries: projects)
    }

}

private struct DashboardProjectRow {
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
        displayNameOrNil(for: path) ?? fallbackDisplayName(for: path)
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

private struct DashboardDetailRow {
    let time: String
    let tool: String
    let session: String
    let project: String
    let model: String
    let tokens: Int
    let cost: Double
    let records: Int
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

private enum DashboardTrendRendering {
    static let tokenSeriesName = "Token"
    static let costSeriesName = "Cost"
    static let seriesKeys = [tokenSeriesName, costSeriesName]
    static let tokenLegendTitle = "Token 消耗"
    static let costLegendTitle = "费用"
    static let trendLegendTitles = [tokenLegendTitle, costLegendTitle]
    static let trendLegendPlacementName = "subtitleHeaderTrailing"
    static let chartLegendVisibilityName = "hidden"
    static let areaStacking: MarkStackingMethod = .unstacked
    static let areaStackingModeName = "unstacked"
    static let areaLayerOrder = seriesKeys
    static let costLineDashPattern: [CGFloat] = []
    static let costYAxisPositionName = "trailing"
    private static let costScalePaddingMultiplier = 1.20

    static func costAxisLabel(forScaledValue value: Double, maxTokens: Double, maxCost: Double) -> String {
        guard value.isFinite, maxTokens > 0, maxCost > 0 else {
            return MonthlyBarChartStyle.costAxisLabel(for: 0)
        }

        let normalizedValue = clampedUnit(value / costPlotMaximum(maxTokens: maxTokens))
        return MonthlyBarChartStyle.costAxisLabel(for: normalizedValue * maxCost)
    }

    static func tokenAxisValues(maxTokens: Double) -> [Double] {
        [0, maxTokens * 0.5, maxTokens]
    }

    static func costAxisValues(maxTokens: Double) -> [Double] {
        let maximum = costPlotMaximum(maxTokens: maxTokens)
        return [0, maximum * 0.5, maximum]
    }

    static func costPlotY(forNormalizedCostHeight value: Double, maxTokens: Double) -> Double {
        clampedUnit(value) * costPlotMaximum(maxTokens: maxTokens)
    }

    static func chartYScaleUpperBound(maxTokens: Double) -> Double {
        costPlotMaximum(maxTokens: maxTokens)
    }

    private static func costPlotMaximum(maxTokens: Double) -> Double {
        guard maxTokens.isFinite, maxTokens > 0 else {
            return costScalePaddingMultiplier
        }
        return maxTokens * costScalePaddingMultiplier
    }

    private static func clampedUnit(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

struct DashboardTrendBucket: Sendable, Equatable, Identifiable {
    let id: String
    let key: String
    let label: String
    let totalTokens: Int
    let totalCost: Double
    let normalizedHeight: Double
    let normalizedCostHeight: Double
    let isCurrent: Bool
}

final class DashboardTrendView: NSView {
    private static let hoverLabelToChartSpacing: CGFloat = 1

    private let chartHost = NSHostingView(rootView: AnyView(DashboardTrendChartContent(
        buckets: [],
        language: .zhHans,
        axisKeys: [],
        onHoverBucketKeyChange: { _ in }
    )))
    private let hoverLabel = NSTextField(labelWithString: "")
    private var buckets: [DashboardTrendBucket] = []
    private var language: AppLanguage = .zhHans

    var debugBucketKeys: [String] {
        buckets.map(\.key)
    }

    var debugHoverText: String {
        hoverLabel.stringValue
    }

    var debugLineInterpolationMethodName: String {
        TodayHourlyLineChartRendering.interpolationMethodName
    }

    var debugAreaGradientScaleModeName: String {
        TodayHourlyLineChartRendering.areaGradientScaleModeName
    }

    var debugAreaStackingModeName: String {
        DashboardTrendRendering.areaStackingModeName
    }

    var debugAreaLayerOrder: [String] {
        DashboardTrendRendering.areaLayerOrder
    }

    var debugTrendSeriesKeys: [String] {
        DashboardTrendRendering.seriesKeys
    }

    var debugChartLegendVisibilityName: String {
        DashboardTrendRendering.chartLegendVisibilityName
    }

    var debugTrendLegendPlacementName: String {
        DashboardTrendRendering.trendLegendPlacementName
    }

    var debugTrendLegendTitles: [String] {
        DashboardTrendRendering.trendLegendTitles
    }

    var debugCostLineDashPattern: [CGFloat] {
        DashboardTrendRendering.costLineDashPattern
    }

    var debugCostYAxisPositionName: String {
        DashboardTrendRendering.costYAxisPositionName
    }

    func debugCostYAxisLabel(forScaledValue value: Double, maxTokens: Double, maxCost: Double) -> String {
        DashboardTrendRendering.costAxisLabel(
            forScaledValue: value,
            maxTokens: maxTokens,
            maxCost: maxCost
        )
    }

    func debugCostPlotY(forNormalizedCostHeight value: Double, maxTokens: Double) -> Double {
        DashboardTrendRendering.costPlotY(
            forNormalizedCostHeight: value,
            maxTokens: maxTokens
        )
    }

    func debugChartYScaleUpperBound(maxTokens: Double) -> Double {
        DashboardTrendRendering.chartYScaleUpperBound(maxTokens: maxTokens)
    }

    var debugTokenAreaGradientLightRGBAComponents: [CGFloat]? {
        Self.roundedRGBAComponents(for: DashboardPalette.accent, appearanceName: .aqua)
    }

    var debugCostAreaGradientLightRGBAComponents: [CGFloat]? {
        Self.roundedRGBAComponents(for: DashboardPalette.costLine, appearanceName: .aqua)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    /// 用所选 Dashboard 范围的趋势桶替换折线图内容。
    func configure(buckets: [DashboardTrendBucket], language: AppLanguage = .zhHans) {
        self.buckets = buckets
        self.language = language
        hoverLabel.stringValue = ""
        chartHost.rootView = AnyView(DashboardTrendChartContent(
            buckets: buckets,
            language: language,
            axisKeys: Self.axisKeys(for: buckets),
            onHoverBucketKeyChange: { [weak self] key in
                self?.updateHoverText(bucketKey: key)
            }
        ))
    }

    func debugSimulateHover(bucketKey: String?) {
        updateHoverText(bucketKey: bucketKey)
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        chartHost.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chartHost)

        hoverLabel.font = .systemFont(ofSize: 10, weight: .medium)
        hoverLabel.textColor = DashboardPalette.secondaryText
        hoverLabel.alignment = .right
        hoverLabel.lineBreakMode = .byTruncatingMiddle
        hoverLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        hoverLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hoverLabel)

        NSLayoutConstraint.activate([
            chartHost.leadingAnchor.constraint(equalTo: leadingAnchor),
            chartHost.trailingAnchor.constraint(equalTo: trailingAnchor),
            chartHost.topAnchor.constraint(equalTo: hoverLabel.bottomAnchor, constant: Self.hoverLabelToChartSpacing),
            chartHost.bottomAnchor.constraint(equalTo: bottomAnchor),
            hoverLabel.topAnchor.constraint(equalTo: topAnchor),
            hoverLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            hoverLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 176),
        ])
    }

    private func updateHoverText(bucketKey: String?) {
        guard let bucketKey,
              let bucket = buckets.first(where: { $0.key == bucketKey }) else {
            hoverLabel.stringValue = ""
            return
        }
        hoverLabel.stringValue = "\(bucket.label) · \(CompactNumberFormatter.formatHoverTokens(bucket.totalTokens)) · 费用 \(Self.costText(bucket.totalCost))"
    }

    private static func axisKeys(for buckets: [DashboardTrendBucket]) -> [String] {
        guard !buckets.isEmpty else { return [] }
        let preferredIndexes: [Int]
        switch buckets.count {
        case 1...6:
            preferredIndexes = Array(buckets.indices)
        case 7:
            preferredIndexes = [0, 3, 6]
        case 24:
            preferredIndexes = [0, 6, 12, 18, 23]
        case 30:
            preferredIndexes = [0, 6, 13, 20, 29]
        default:
            let lastIndex = buckets.count - 1
            let step = max(1, lastIndex / 5)
            preferredIndexes = stride(from: 0, through: lastIndex, by: step).map { $0 }
        }
        return preferredIndexes
            .filter { buckets.indices.contains($0) }
            .map { buckets[$0].key }
    }

    private static func costText(_ value: Double) -> String {
        guard value.isFinite else { return "$0.00" }
        return String(format: "$%.2f", max(0, value))
    }

    private static func roundedRGBAComponents(for color: NSColor, appearanceName: NSAppearance.Name) -> [CGFloat]? {
        guard let appearance = NSAppearance(named: appearanceName) else {
            return nil
        }

        var components: [CGFloat]?
        appearance.performAsCurrentDrawingAppearance {
            components = color.cgColor.components
        }
        return components?.map { ($0 * 1_000).rounded() / 1_000 }
    }
}

private struct DashboardTrendChartContent: View {
    let buckets: [DashboardTrendBucket]
    let language: AppLanguage
    let axisKeys: [String]
    let onHoverBucketKeyChange: (String?) -> Void

    private var maxTokens: Double {
        max(1, Double(buckets.map(\.totalTokens).max() ?? 0))
    }

    private var maxCost: Double {
        max(0, buckets.map(\.totalCost).max() ?? 0)
    }

    var body: some View {
        Chart {
            ForEach(buckets) { bucket in
                AreaMark(
                    x: .value(axisValueName, bucket.key),
                    y: .value("Tokens", Double(bucket.totalTokens)),
                    series: .value("Series", DashboardTrendRendering.tokenSeriesName),
                    stacking: DashboardTrendRendering.areaStacking
                )
                .interpolationMethod(TodayHourlyLineChartRendering.interpolationMethod)
                .foregroundStyle(tokenAreaGradient)

                AreaMark(
                    x: .value(axisValueName, bucket.key),
                    y: .value(
                        "Cost",
                        DashboardTrendRendering.costPlotY(
                            forNormalizedCostHeight: bucket.normalizedCostHeight,
                            maxTokens: maxTokens
                        )
                    ),
                    series: .value("Series", DashboardTrendRendering.costSeriesName),
                    stacking: DashboardTrendRendering.areaStacking
                )
                .interpolationMethod(TodayHourlyLineChartRendering.interpolationMethod)
                .foregroundStyle(costAreaGradient)
            }

            ForEach(buckets) { bucket in
                LineMark(
                    x: .value(axisValueName, bucket.key),
                    y: .value("Tokens", Double(bucket.totalTokens)),
                    series: .value("Series", DashboardTrendRendering.tokenSeriesName)
                )
                .interpolationMethod(TodayHourlyLineChartRendering.interpolationMethod)
                .foregroundStyle(by: .value("图例", DashboardTrendRendering.tokenLegendTitle))
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                LineMark(
                    x: .value(axisValueName, bucket.key),
                    y: .value(
                        "Cost",
                        DashboardTrendRendering.costPlotY(
                            forNormalizedCostHeight: bucket.normalizedCostHeight,
                            maxTokens: maxTokens
                        )
                    ),
                    series: .value("Series", DashboardTrendRendering.costSeriesName)
                )
                .interpolationMethod(TodayHourlyLineChartRendering.interpolationMethod)
                .foregroundStyle(by: .value("图例", DashboardTrendRendering.costLegendTitle))
                .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))

                if bucket.isCurrent {
                    PointMark(
                        x: .value(axisValueName, bucket.key),
                        y: .value("Tokens", Double(bucket.totalTokens))
                    )
                    .foregroundStyle(Color(nsColor: DashboardPalette.accent))
                    .symbolSize(22)

                    PointMark(
                        x: .value(axisValueName, bucket.key),
                        y: .value(
                            "Cost",
                            DashboardTrendRendering.costPlotY(
                                forNormalizedCostHeight: bucket.normalizedCostHeight,
                                maxTokens: maxTokens
                            )
                        )
                    )
                    .foregroundStyle(Color(nsColor: DashboardPalette.costLine))
                    .symbolSize(18)
                }
            }
        }
        .chartForegroundStyleScale([
            DashboardTrendRendering.tokenLegendTitle: Color(nsColor: DashboardPalette.accent),
            DashboardTrendRendering.costLegendTitle: Color(nsColor: DashboardPalette.costLine),
        ])
        .chartLegend(.hidden)
        .chartYScale(domain: 0...DashboardTrendRendering.chartYScaleUpperBound(maxTokens: maxTokens))
        .chartXAxis {
            AxisMarks(values: axisKeys) { value in
                AxisTick()
                AxisValueLabel {
                    if let key = value.as(String.self) {
                        Text(MonthlyBarChartStyle.monthAxisLabel(for: key, language: language))
                            .font(.system(size: 8))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: DashboardTrendRendering.tokenAxisValues(maxTokens: maxTokens)) { value in
                AxisGridLine()
                    .foregroundStyle(.secondary.opacity(0.16))
                AxisTick()
                if let tokens = value.as(Double.self) {
                    AxisValueLabel(MonthlyBarChartStyle.tokenAxisLabel(for: tokens))
                        .font(.system(size: 8))
                }
            }
            AxisMarks(position: .trailing, values: DashboardTrendRendering.costAxisValues(maxTokens: maxTokens)) { value in
                AxisTick()
                    .foregroundStyle(Color(nsColor: DashboardPalette.costLine).opacity(0.65))
                if let scaledValue = value.as(Double.self) {
                    AxisValueLabel(
                        DashboardTrendRendering.costAxisLabel(
                            forScaledValue: scaledValue,
                            maxTokens: maxTokens,
                            maxCost: maxCost
                        )
                    )
                    .font(.system(size: 8))
                    .foregroundStyle(Color(nsColor: DashboardPalette.costLine))
                }
            }
        }
        .chartOverlay { proxy in
            hoverOverlay(proxy: proxy)
        }
        .padding(.top, 4)
    }

    private var axisValueName: String {
        language.periodAxisValueName
    }

    private var tokenAreaGradient: LinearGradient {
        let color = Color(nsColor: DashboardPalette.accent)
        return LinearGradient(
            colors: [
                color.opacity(TodayHourlyLineChartRendering.areaGradientPeakOpacity),
                color.opacity(TodayHourlyLineChartRendering.areaGradientBaselineOpacity),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var costAreaGradient: LinearGradient {
        let color = Color(nsColor: DashboardPalette.costLine)
        return LinearGradient(
            colors: [
                color.opacity(TodayHourlyLineChartRendering.areaGradientPeakOpacity),
                color.opacity(TodayHourlyLineChartRendering.areaGradientBaselineOpacity),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func hoverOverlay(proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    guard let plotFrame = proxy.plotFrame else {
                        onHoverBucketKeyChange(nil)
                        return
                    }
                    let frame = geometry[plotFrame]
                    switch phase {
                    case .active(let location):
                        guard frame.contains(location) else {
                            onHoverBucketKeyChange(nil)
                            return
                        }
                        onHoverBucketKeyChange(proxy.value(atX: location.x - frame.origin.x, as: String.self))
                    case .ended:
                        onHoverBucketKeyChange(nil)
                    }
                }
        }
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
            modelBreakdown: modelBreakdown.merging(other.modelBreakdown) { $0.merged(with: $1) },
            projectBreakdown: projectBreakdown.merging(other.projectBreakdown) { $0.merged(with: $1) }
        )
    }
}

private extension NSColor {
    convenience init(hex: Int) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
