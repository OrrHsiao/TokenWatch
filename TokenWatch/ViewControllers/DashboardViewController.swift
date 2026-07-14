import AppKit

private final class DashboardSessionTableDocumentView: DashboardRoundedView {
    /// AppKit 在 document 小于 overlay clip 时默认底部对齐；翻转坐标确保动态 gutter 留在底部而不裁表头。
    override var isFlipped: Bool { true }
}

/// Pencil 设计稿中的 AI Token Watch 深色总览 Dashboard。
final class DashboardViewController: NSViewController {
    private static let sidebarWidth: CGFloat = 244
    private static let pageInset: CGFloat = 28
    private static let rowGap: CGFloat = 18
    private static let sessionVerticalInset: CGFloat = 20
    private static let sessionRowGap: CGFloat = 14
    private static let minimumContentWidth: CGFloat = 860
    private static let sessionTableColumnWidths: [CGFloat] = [120, 150, 84, 132, 116, 86, 76, 68]
    private static let sessionTableMinimumWidth: CGFloat = 880
    private static let sessionTableColumnSpacing: CGFloat = 4
    private static let sessionTableHorizontalPadding: CGFloat = 10
    private static let sessionPageSize = 10
    private static let sessionTableHeaderHeight: CGFloat = 44
    private static let sessionTableRowHeight: CGFloat = 48
    private static let sessionPaginationHeight: CGFloat = 44
    private static let sessionTableContentHeight = sessionTableHeaderHeight
        + CGFloat(sessionPageSize) * sessionTableRowHeight
        + sessionPaginationHeight
    // 按 overlay/legacy regular scroller 最大高度仅为滚动外壳底部预留 gutter，不计入 document。
    private static let sessionTableScrollerGutter = max(
        NSScroller.scrollerWidth(for: .regular, scrollerStyle: .overlay),
        NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
    )
    private static let sessionTableHeight = sessionTableContentHeight
        + sessionTableScrollerGutter
    private static let sourceLegendValueWidth: CGFloat = 52
    private static let privacyPolicyURL = URL(string: "https://orrhsiao.github.io/TokenWatch/privacy/")!

    private let settingsViewController: SettingsViewController
    private let stateProvider: @MainActor () -> [ProviderID: TokenStatsViewModel.ProviderState]
    private let refreshAction: @MainActor () async -> Void
    private let languageSettings: AppLanguageSettings
    private let nowProvider: () -> Date
    private let calendar: Calendar

    private let sidebarView = DashboardBackgroundView(backgroundColor: DashboardPalette.sidebarBackground)
    private let mainContentContainer = DashboardBackgroundView(backgroundColor: DashboardPalette.appBackground)
    private let overviewScrollView = NSScrollView()
    private let overviewContentView = DashboardBackgroundView(backgroundColor: DashboardPalette.appBackground)
    private let overviewStack = NSStackView()
    private let sessionScrollView = NSScrollView()
    private let sessionTableScrollView = NSScrollView()
    private let sessionContentView = DashboardBackgroundView(backgroundColor: DashboardPalette.appBackground)
    private let sessionStack = NSStackView()
    private let navButtonsStack = NSStackView()
    private let dataSourceRowsStack = NSStackView()
    private let scanStatusBodyLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let refreshButton = DashboardRangeButton(title: "", target: nil, action: nil)
    private let totalTokenValueLabel = NSTextField(labelWithString: "0")
    private let totalTokenDetailLabel = NSTextField(labelWithString: "")
    private let totalCostValueLabel = NSTextField(labelWithString: "$0.00")
    private let totalCostDetailLabel = NSTextField(labelWithString: "")
    private let sessionValueLabel = NSTextField(labelWithString: "0")
    private let sessionDetailLabel = NSTextField(labelWithString: "")
    private let trendView = DashboardTrendView()
    private let modelRowsStack = NSStackView()
    private let emptyModelLabel = NSTextField(labelWithString: "")
    private let sourceDonutView = DashboardDonutView()
    private let sourceLegendStack = NSStackView()
    private let projectRowsStack = NSStackView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let sessionTitleLabel = NSTextField(labelWithString: "")
    private let sessionSubtitleLabel = NSTextField(labelWithString: "")
    private let sessionDateLabel = NSTextField(labelWithString: "")
    private let sessionCountValueLabel = NSTextField(labelWithString: "0")
    private let sessionTokenValueLabel = NSTextField(labelWithString: "0")
    private let sessionCostValueLabel = NSTextField(labelWithString: "$0.00")
    private let sessionRecordValueLabel = NSTextField(labelWithString: "0")
    private let sessionRowsStack = NSStackView()
    private let sessionPaginationRangeLabel = NSTextField(labelWithString: "")
    private let sessionPaginationControlsStack = NSStackView()
    private let sessionStatusLabel = NSTextField(labelWithString: "")

    private var rangeButtons: [DashboardRange: NSButton] = [:]
    private var navButtons: [DashboardNavigationItem: NSButton] = [:]
    private var privacyPolicyButton: DashboardNavigationButton?
    private var selectedRange: DashboardRange = .sevenDays
    private var selectedNavigationItem: DashboardNavigationItem = .overview
    private var currentSessionPage = 1
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

    private var language: AppLanguage {
        languageSettings.resolvedLanguage
    }

    private func localized(_ key: AppStringKey) -> String {
        AppStrings.text(key, language: language)
    }

    private func localizedLabel(_ key: AppStringKey) -> NSTextField {
        let label = NSTextField(labelWithString: localized(key))
        setLocalizedKey(key, for: label)
        return label
    }

    private func setLocalizedKey(_ key: AppStringKey, for label: NSTextField) {
        label.identifier = NSUserInterfaceItemIdentifier(localizedIdentifier(for: key))
        label.stringValue = localized(key)
    }

    private func refreshLocalizedTextFields(in root: NSView) {
        if let textField = root as? NSTextField,
           let key = localizedKey(for: textField.identifier?.rawValue) {
            textField.stringValue = localized(key)
        }
        for subview in root.subviews {
            refreshLocalizedTextFields(in: subview)
        }
    }

    private func localizedIdentifier(for key: AppStringKey) -> String {
        "AppStringKey.\(String(describing: key))"
    }

    private func localizedKey(for identifier: String?) -> AppStringKey? {
        guard let identifier,
              identifier.hasPrefix("AppStringKey.")
        else {
            return nil
        }
        let name = String(identifier.dropFirst("AppStringKey.".count))
        return AppStringKey.allCases.first { String(describing: $0) == name }
    }

    override func loadView() {
        view = DashboardBackgroundView(
            frame: NSRect(origin: .zero, size: MainWindowFactory.contentSize),
            backgroundColor: DashboardPalette.appBackground
        )
        view.userInterfaceLayoutDirection = .leftToRight
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

        let privacyPolicyButton = makePrivacyPolicyButton()
        self.privacyPolicyButton = privacyPolicyButton

        sidebarView.addSubview(rootStack)
        sidebarView.addSubview(privacyPolicyButton)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: sidebarView.leadingAnchor, constant: 20),
            rootStack.trailingAnchor.constraint(equalTo: sidebarView.trailingAnchor, constant: -20),
            rootStack.topAnchor.constraint(equalTo: sidebarView.topAnchor, constant: Self.pageInset),
            rootStack.bottomAnchor.constraint(lessThanOrEqualTo: privacyPolicyButton.topAnchor, constant: -20),
            privacyPolicyButton.leadingAnchor.constraint(equalTo: sidebarView.leadingAnchor, constant: 20),
            privacyPolicyButton.trailingAnchor.constraint(equalTo: sidebarView.trailingAnchor, constant: -20),
            privacyPolicyButton.bottomAnchor.constraint(equalTo: sidebarView.bottomAnchor, constant: -Self.pageInset),
            privacyPolicyButton.heightAnchor.constraint(equalToConstant: 39),
        ])
        updateNavigationSelection()
    }

    private func setupMainContent() {
        mainContentContainer.userInterfaceLayoutDirection = .leftToRight
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

        overviewStack.translatesAutoresizingMaskIntoConstraints = false
        overviewStack.orientation = .vertical
        overviewStack.alignment = .leading
        overviewStack.spacing = Self.rowGap
        overviewContentView.addSubview(overviewStack)

        addFullWidthArrangedSubview(makeHeaderView(), to: overviewStack)
        addFullWidthArrangedSubview(makeMetricRow(), to: overviewStack)
        addFullWidthArrangedSubview(makeAnalysisSection(), to: overviewStack)
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
        sessionScrollView.identifier = NSUserInterfaceItemIdentifier("DashboardSessionsPageScrollView")
        sessionScrollView.setAccessibilityIdentifier("DashboardSessionsPageScrollView")
        sessionScrollView.drawsBackground = false
        sessionScrollView.borderType = .noBorder
        sessionScrollView.hasVerticalScroller = true
        sessionScrollView.hasHorizontalScroller = false
        sessionScrollView.autohidesScrollers = true
        sessionScrollView.scrollerStyle = .overlay
        sessionScrollView.translatesAutoresizingMaskIntoConstraints = false
        sessionScrollView.documentView = sessionContentView

        sessionContentView.userInterfaceLayoutDirection = .leftToRight
        sessionContentView.translatesAutoresizingMaskIntoConstraints = false

        sessionStack.translatesAutoresizingMaskIntoConstraints = false
        sessionStack.orientation = .vertical
        sessionStack.alignment = .leading
        sessionStack.spacing = Self.sessionRowGap
        sessionStack.identifier = NSUserInterfaceItemIdentifier("DashboardSessionsPage")
        sessionStack.setAccessibilityIdentifier("DashboardSessionsPage")
        sessionContentView.addSubview(sessionStack)

        addFullWidthArrangedSubview(makeSessionHeaderView(), to: sessionStack)
        addFullWidthArrangedSubview(makeSessionMetricRow(), to: sessionStack)
        addFullWidthArrangedSubview(makeSessionTableScrollView(), to: sessionStack)
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
            sessionStack.topAnchor.constraint(equalTo: sessionContentView.topAnchor, constant: Self.sessionVerticalInset),
            sessionStack.bottomAnchor.constraint(
                lessThanOrEqualTo: sessionContentView.bottomAnchor,
                constant: -Self.sessionVerticalInset
            ),
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
        logoView.setAccessibilityLabel("AI Token Watch")
        logoView.setContentHuggingPriority(.required, for: .horizontal)
        logoView.setContentCompressionResistancePriority(.required, for: .horizontal)

        let name = NSTextField(labelWithString: "AI Token Watch")
        name.font = .systemFont(ofSize: 18, weight: .bold)
        name.textColor = DashboardPalette.primaryText
        let subtitle = localizedLabel(.appTagline)
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
            title: item.title(language: language),
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

    private func makePrivacyPolicyButton() -> DashboardNavigationButton {
        DashboardNavigationButton(
            title: localized(.privacyPolicy),
            symbolName: "hand.raised",
            identifier: "DashboardPrivacyPolicyButton",
            target: self,
            action: #selector(openPrivacyPolicy(_:))
        )
    }

    private func makeDataSourcesView() -> NSView {
        let title = localizedLabel(.dashboardDataSources)
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
        let title = localizedLabel(.dashboardLastLocalScan)
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
        setLocalizedKey(.dashboardOverviewTitle, for: titleLabel)
        titleLabel.font = .systemFont(ofSize: 26, weight: .bold)
        titleLabel.textColor = DashboardPalette.primaryText
        setLocalizedKey(.dashboardOverviewSubtitle, for: subtitleLabel)
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
        setLocalizedKey(.dashboardSessionsTitle, for: sessionTitleLabel)
        sessionTitleLabel.font = .systemFont(ofSize: 26, weight: .bold)
        sessionTitleLabel.textColor = DashboardPalette.primaryText
        setLocalizedKey(.dashboardSessionsSubtitle, for: sessionSubtitleLabel)
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
        iconView.image = NSImage(systemSymbolName: "calendar", accessibilityDescription: localized(.recentDetailsTime))
        iconView.image?.isTemplate = true
        iconView.contentTintColor = DashboardPalette.sessionDateIcon
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
            makeSessionMetricCard(titleKey: .dashboardMetricSessions, valueLabel: sessionCountValueLabel),
            makeSessionMetricCard(titleKey: .dashboardMetricTotalTokens, valueLabel: sessionTokenValueLabel),
            makeSessionMetricCard(titleKey: .recentDetailsCost, valueLabel: sessionCostValueLabel),
            makeSessionMetricCard(titleKey: .dashboardMetricRecords, valueLabel: sessionRecordValueLabel),
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

    private func makeSessionMetricCard(titleKey: AppStringKey, valueLabel: NSTextField) -> NSView {
        let titleLabel = localizedLabel(titleKey)
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
        let button = DashboardRangeButton(title: range.title(language: language), target: self, action: #selector(rangeButtonClicked(_:)))
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
        refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: localized(.refreshNow))
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
        refreshButton.setDashboardLayerColors(
            backgroundColor: DashboardPalette.panelBackground,
            borderColor: DashboardPalette.border
        )
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
            titleKey: .dashboardMetricTotalTokens,
            valueLabel: totalTokenValueLabel,
            detailLabel: totalTokenDetailLabel
        )
        let costCard = makeMetricCard(
            titleKey: .dashboardMetricTotalCost,
            valueLabel: totalCostValueLabel,
            detailLabel: totalCostDetailLabel
        )
        let sessionCard = makeMetricCard(
            titleKey: .dashboardMetricSessions,
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

    private func makeMetricCard(titleKey: AppStringKey, valueLabel: NSTextField, detailLabel: NSTextField) -> NSView {
        let titleLabel = localizedLabel(titleKey)
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
            titleKey: .dashboardTrendTitle,
            subtitleKey: .dashboardTrendSubtitle,
            content: trendView,
            minimumHeight: 230,
            trailingHeaderContent: makeTrendLegendView()
        )
    }

    private func makeTrendLegendView() -> NSView {
        let row = NSStackView(views: [
            makeTrendLegendItem(
                titleKey: .dashboardTrendTokenLegend,
                color: DashboardPalette.accent,
                identifier: "DashboardTrendLegend.token"
            ),
            makeTrendLegendItem(
                titleKey: .chartCost,
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

    private func makeTrendLegendItem(titleKey: AppStringKey, color: NSColor, identifier: String) -> NSView {
        let dot = DashboardDotView(color: color)

        let label = localizedLabel(titleKey)
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
        setLocalizedKey(.totalEmptyModels, for: emptyModelLabel)
        emptyModelLabel.font = .systemFont(ofSize: 12)
        emptyModelLabel.textColor = DashboardPalette.secondaryText

        let stack = NSStackView(views: [modelRowsStack, emptyModelLabel])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 8
        return makePanel(
            titleKey: .dashboardModelRankTitle,
            subtitleKey: nil,
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
        body.alignment = .top
        body.spacing = 16
        NSLayoutConstraint.activate([
            sourceDonutView.widthAnchor.constraint(equalToConstant: 132),
            sourceDonutView.heightAnchor.constraint(equalToConstant: 132),
        ])
        return makePanel(titleKey: .dashboardSourceShareTitle, subtitleKey: nil, content: body, minimumHeight: 230)
    }

    private func makeProjectPanel() -> NSView {
        projectRowsStack.orientation = .vertical
        projectRowsStack.alignment = .width
        projectRowsStack.spacing = 10
        return makePanel(titleKey: .dashboardProjectUsageTitle, subtitleKey: nil, content: projectRowsStack, minimumHeight: 232)
    }

    private func makePanel(
        titleKey: AppStringKey,
        subtitleKey: AppStringKey?,
        content: NSView,
        minimumHeight: CGFloat,
        trailingHeaderContent: NSView? = nil
    ) -> NSView {
        let titleLabel = localizedLabel(titleKey)
        titleLabel.font = .systemFont(ofSize: 16, weight: .bold)
        titleLabel.textColor = DashboardPalette.primaryText
        titleLabel.lineBreakMode = .byTruncatingTail

        var headerViews: [NSView] = [titleLabel]
        var trailingAlignmentView: NSView = titleLabel
        if let subtitleKey {
            let subtitleLabel = localizedLabel(subtitleKey)
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

        let panel = DashboardRoundedView(
            backgroundColor: DashboardPalette.panelBackground,
            cornerRadius: 8,
            borderColor: DashboardPalette.border,
            borderWidth: 1
        )
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

    private func makeSessionTableScrollView() -> NSScrollView {
        let table = makeSessionTable()
        let clipView = sessionTableScrollView.contentView

        sessionTableScrollView.identifier = NSUserInterfaceItemIdentifier("DashboardSessionsTableScrollView")
        sessionTableScrollView.setAccessibilityIdentifier("DashboardSessionsTableScrollView")
        sessionTableScrollView.drawsBackground = false
        sessionTableScrollView.borderType = .noBorder
        sessionTableScrollView.hasHorizontalScroller = true
        sessionTableScrollView.hasVerticalScroller = false
        sessionTableScrollView.autohidesScrollers = true
        sessionTableScrollView.scrollerStyle = .overlay
        sessionTableScrollView.documentView = table

        table.translatesAutoresizingMaskIntoConstraints = false
        let coverViewportWidth = table.widthAnchor.constraint(greaterThanOrEqualTo: clipView.widthAnchor)

        NSLayoutConstraint.activate([
            sessionTableScrollView.heightAnchor.constraint(equalToConstant: Self.sessionTableHeight),
            table.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            table.topAnchor.constraint(equalTo: clipView.topAnchor),
            table.widthAnchor.constraint(greaterThanOrEqualToConstant: Self.sessionTableMinimumWidth),
            table.heightAnchor.constraint(equalToConstant: Self.sessionTableContentHeight),
            coverViewportWidth,
        ])
        return sessionTableScrollView
    }

    private func makeSessionTable() -> NSView {
        let header = makeSessionTableHeader()
        let pagination = makeSessionPaginationView()
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        sessionRowsStack.orientation = .vertical
        sessionRowsStack.alignment = .width
        sessionRowsStack.spacing = 0

        let stack = NSStackView(views: [header, sessionRowsStack, spacer, pagination])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0

        let table = DashboardSessionTableDocumentView(
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
            table.heightAnchor.constraint(equalToConstant: Self.sessionTableContentHeight),
            stack.leadingAnchor.constraint(equalTo: table.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: table.trailingAnchor),
            stack.topAnchor.constraint(equalTo: table.topAnchor),
            stack.bottomAnchor.constraint(equalTo: table.bottomAnchor),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            sessionRowsStack.widthAnchor.constraint(equalTo: stack.widthAnchor),
            spacer.widthAnchor.constraint(equalTo: stack.widthAnchor),
            pagination.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        return table
    }

    private func makeSessionPaginationView() -> NSView {
        sessionPaginationRangeLabel.font = .systemFont(ofSize: 12, weight: .medium)
        sessionPaginationRangeLabel.textColor = DashboardPalette.secondaryText
        sessionPaginationRangeLabel.lineBreakMode = .byTruncatingTail
        sessionPaginationRangeLabel.identifier = NSUserInterfaceItemIdentifier("DashboardSessionsPaginationRange")
        sessionPaginationRangeLabel.setAccessibilityIdentifier("DashboardSessionsPaginationRange")

        sessionPaginationControlsStack.orientation = .horizontal
        sessionPaginationControlsStack.alignment = .centerY
        sessionPaginationControlsStack.spacing = 6
        sessionPaginationControlsStack.identifier = NSUserInterfaceItemIdentifier("DashboardSessionsPaginationControls")
        sessionPaginationControlsStack.setAccessibilityIdentifier("DashboardSessionsPaginationControls")

        let view = DashboardBackgroundView(backgroundColor: DashboardPalette.appBackground)
        view.identifier = NSUserInterfaceItemIdentifier("DashboardSessionsPagination")
        view.setAccessibilityIdentifier("DashboardSessionsPagination")
        view.addSubview(sessionPaginationRangeLabel)
        view.addSubview(sessionPaginationControlsStack)
        sessionPaginationRangeLabel.translatesAutoresizingMaskIntoConstraints = false
        sessionPaginationControlsStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(equalToConstant: Self.sessionPaginationHeight),
            sessionPaginationRangeLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            sessionPaginationRangeLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            sessionPaginationRangeLabel.trailingAnchor.constraint(lessThanOrEqualTo: sessionPaginationControlsStack.leadingAnchor, constant: -18),
            sessionPaginationControlsStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            sessionPaginationControlsStack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        return view
    }

    private func rebuildSessionPaginationControls(_ pagination: RecentSessionPagination) {
        clearStack(sessionPaginationControlsStack)
        sessionPaginationRangeLabel.stringValue = pagination.displayRangeText(language: language)

        sessionPaginationControlsStack.addArrangedSubview(makeSessionPaginationButton(
            title: localized(.dashboardPreviousPage),
            identifier: "DashboardSessionsPagination.previous",
            width: 64,
            page: max(1, pagination.currentPage - 1),
            isSelected: false,
            isEnabled: pagination.canGoPrevious
        ))

        for item in pagination.items {
            switch item {
            case .page(let page):
                sessionPaginationControlsStack.addArrangedSubview(makeSessionPaginationButton(
                    title: "\(page)",
                    identifier: "DashboardSessionsPagination.page.\(page)",
                    width: page >= 100 ? 40 : 32,
                    page: page,
                    isSelected: page == pagination.currentPage,
                    isEnabled: page != pagination.currentPage
                ))
            case .ellipsis:
                sessionPaginationControlsStack.addArrangedSubview(makeSessionPaginationEllipsisLabel())
            }
        }

        sessionPaginationControlsStack.addArrangedSubview(makeSessionPaginationButton(
            title: localized(.dashboardNextPage),
            identifier: "DashboardSessionsPagination.next",
            width: 64,
            page: min(pagination.totalPages, pagination.currentPage + 1),
            isSelected: false,
            isEnabled: pagination.canGoNext
        ))
    }

    private func makeSessionPaginationButton(
        title: String,
        identifier: String,
        width: CGFloat,
        page: Int,
        isSelected: Bool,
        isEnabled: Bool
    ) -> NSButton {
        let button = DashboardSessionButton(
            title: title,
            target: self,
            action: #selector(sessionPaginationButtonClicked(_:)),
            contentAlignment: .center
        )
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
        button.setAccessibilityIdentifier(identifier)
        button.setAccessibilityLabel(title)
        button.tag = page
        button.alignment = .center
        button.isEnabled = isEnabled
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: width),
            button.heightAnchor.constraint(equalToConstant: 32),
        ])
        applySessionPaginationButtonStyle(button, title: title, isSelected: isSelected, isEnabled: isEnabled)
        return button
    }

    private func applySessionPaginationButtonStyle(
        _ button: DashboardSessionButton,
        title: String,
        isSelected: Bool,
        isEnabled: Bool
    ) {
        let backgroundColor = isSelected ? DashboardPalette.accent : DashboardPalette.sessionDateBackground
        let borderColor = isSelected ? DashboardPalette.accent : DashboardPalette.sessionDateBorder
        let textColor: NSColor
        if isSelected {
            textColor = DashboardPalette.rangeSelectedText
        } else {
            textColor = isEnabled ? DashboardPalette.primaryText : DashboardPalette.secondaryText
        }
        button.setDashboardTitle(title)
        button.setDashboardStyle(
            backgroundColor: backgroundColor,
            borderColor: borderColor,
            borderWidth: 1,
            cornerRadius: 7,
            titleColor: textColor,
            font: .systemFont(ofSize: 12, weight: .semibold)
        )
    }

    private func makeSessionPaginationEllipsisLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "...")
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = DashboardPalette.secondaryText
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.widthAnchor.constraint(equalToConstant: 12),
            label.heightAnchor.constraint(equalToConstant: 32),
        ])
        return label
    }

    private func makeSessionTableHeader() -> NSView {
        makeSessionTableRowContainer(
            identifier: "DashboardSessionsTableHeader",
            backgroundColor: DashboardPalette.sessionTableHeaderBackground,
            height: Self.sessionTableHeaderHeight,
            cells: zip(
                [
                    .dashboardLatestTime,
                    .dashboardSessionID,
                    .recentDetailsTool,
                    .recentDetailsProject,
                    .dashboardPrimaryModel,
                    .dashboardMetricTotalTokens,
                    .recentDetailsCost,
                    .dashboardMetricRecords,
                ],
                Self.sessionTableColumnWidths
            ).map { key, width in
                makeSessionLocalizedTextCell(
                    key: key,
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
            height: Self.sessionTableRowHeight,
            cells: [
                makeSessionTextCell(
                    text: DashboardRangeSnapshot.formatDetailDate(row.lastActiveAt),
                    width: Self.sessionTableColumnWidths[0],
                    font: .monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
                    color: DashboardPalette.primaryText
                ),
                makeSessionIDCell(row.sessionID, rowIndex: index, width: Self.sessionTableColumnWidths[1]),
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
                    color: DashboardPalette.secondaryText
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
                    color: DashboardPalette.secondaryText
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
            height: Self.sessionTableRowHeight,
            cells: zip(
                [localized(.dashboardNoSessions), "-", "-", "-", "-", "-", "-", "-"],
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
        content.spacing = Self.sessionTableColumnSpacing

        let row = DashboardRoundedView(backgroundColor: backgroundColor, cornerRadius: 0)
        row.identifier = NSUserInterfaceItemIdentifier(identifier)
        row.setAccessibilityIdentifier(identifier)
        row.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: height),
            content.leadingAnchor.constraint(
                equalTo: row.leadingAnchor,
                constant: Self.sessionTableHorizontalPadding
            ),
            content.trailingAnchor.constraint(
                lessThanOrEqualTo: row.trailingAnchor,
                constant: -Self.sessionTableHorizontalPadding
            ),
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

    private func makeSessionLocalizedTextCell(key: AppStringKey, width: CGFloat, font: NSFont, color: NSColor) -> NSView {
        let label = localizedLabel(key)
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

    private func makeSessionIDCell(_ sessionID: String, rowIndex: Int, width: CGFloat) -> NSView {
        let copyButton = DashboardSessionButton(
            title: compactSessionID(sessionID),
            target: self,
            action: #selector(copySessionIDButtonClicked(_:)),
            contentAlignment: .leading,
            image: NSImage(
                systemSymbolName: "doc.on.doc",
                accessibilityDescription: localized(.dashboardCopyIDAccessibilityDescription)
            )
        )
        copyButton.identifier = NSUserInterfaceItemIdentifier("DashboardSessionsCopy.\(rowIndex)")
        copyButton.setAccessibilityIdentifier("DashboardSessionsCopy.\(rowIndex)")
        copyButton.setAccessibilityLabel(localized(.dashboardCopySessionIDAccessibility))
        copyButton.toolTip = sessionID
        copyButton.alignment = .left
        copyButton.setDashboardStyle(
            backgroundColor: .clear,
            borderColor: .clear,
            borderWidth: 0,
            cornerRadius: 4,
            titleColor: DashboardPalette.primaryText,
            font: .monospacedDigitSystemFont(ofSize: 12, weight: .bold)
        )
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.setContentHuggingPriority(.defaultLow, for: .horizontal)
        copyButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let cell = NSView()
        cell.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(copyButton)
        NSLayoutConstraint.activate([
            cell.widthAnchor.constraint(equalToConstant: width),
            copyButton.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
            copyButton.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
            copyButton.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            copyButton.heightAnchor.constraint(equalToConstant: 24),
        ])
        return cell
    }

    private func compactSessionID(_ sessionID: String) -> String {
        guard sessionID.count > 18 else { return sessionID }
        return "\(sessionID.prefix(8))...\(sessionID.suffix(7))"
    }

    private func makeSessionProviderCell(_ provider: ProviderID, width: CGFloat) -> NSView {
        let toolName = sessionProviderName(provider)
        let label = NSTextField(labelWithString: toolName)
        label.font = .systemFont(ofSize: 11, weight: .bold)
        label.textColor = DashboardPalette.accent
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.toolTip = toolName
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

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

    private func sessionTableRowBackground(at index: Int) -> NSColor {
        index.isMultiple(of: 2)
            ? DashboardPalette.panelBackground
            : DashboardPalette.sessionTableAlternateRowBackground
    }

    private func sessionProviderName(_ provider: ProviderID) -> String {
        ProviderRegistry.provider(for: provider)?.displayName ?? provider.rawValue
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
        DashboardAppearanceRefresh.refresh(in: overviewScrollView)
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
        DashboardAppearanceRefresh.refresh(in: sessionScrollView)
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
        mainContentContainer.addSubview(settingsViewController.view)
        DashboardLayerColor.applyBackground(DashboardPalette.appBackground, to: settingsViewController.view)
        settingsConstraints = [
            settingsViewController.view.leadingAnchor.constraint(equalTo: mainContentContainer.leadingAnchor),
            settingsViewController.view.trailingAnchor.constraint(equalTo: mainContentContainer.trailingAnchor),
            settingsViewController.view.topAnchor.constraint(equalTo: mainContentContainer.topAnchor),
            settingsViewController.view.bottomAnchor.constraint(equalTo: mainContentContainer.bottomAnchor),
        ]
        NSLayoutConstraint.activate(settingsConstraints)
        currentSettingsController = settingsViewController
        enforceLeftAlignedContent(in: settingsViewController.view)
        DashboardAppearanceRefresh.refresh(in: settingsViewController.view)
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

    @objc private func openPrivacyPolicy(_ sender: Any?) {
        NSWorkspace.shared.open(Self.privacyPolicyURL)
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

    @objc private func sessionPaginationButtonClicked(_ sender: NSButton) {
        guard sender.tag > 0 else { return }
        currentSessionPage = sender.tag
        render()
    }

    @objc private func copySessionIDButtonClicked(_ sender: NSButton) {
        guard let sessionID = sender.toolTip, !sessionID.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(sessionID, forType: .string)
    }

    @MainActor
    private func render() {
        applyLocalizedText()

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
        totalTokenDetailLabel.stringValue = formatTokenBreakdown(summary)
        totalCostValueLabel.stringValue = formatCurrency(summary.cost)
        totalCostDetailLabel.stringValue = formatCostBreakdown(summary)
        sessionValueLabel.stringValue = formatInt(summary.entryCount)
        sessionDetailLabel.stringValue = String(
            format: localized(.dashboardTotalSourcesProjectsFormat),
            totalSnapshot.loadedProviderCount,
            summary.projectCount
        )
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

    private func applyLocalizedText() {
        refreshLocalizedTextFields(in: view)
        updateNavigationTitles()
        updatePrivacyPolicyTitle()
        updateRangeButtonTitles()
    }

    private func updateNavigationTitles() {
        for item in DashboardNavigationItem.allCases {
            guard let button = navButtons[item] else { continue }
            let title = item.title(language: language)
            button.title = title
            button.setAccessibilityLabel(title)
            (button as? DashboardNavigationButton)?.updateTitle(title)
        }
    }

    private func updateRangeButtonTitles() {
        for range in DashboardRange.allCases {
            guard let button = rangeButtons[range] else { continue }
            button.title = range.title(language: language)
        }
    }

    private func updatePrivacyPolicyTitle() {
        guard let button = privacyPolicyButton else { return }
        let title = localized(.privacyPolicy)
        button.title = title
        button.setAccessibilityLabel(title)
        button.updateTitle(title)
    }

    private func renderSessionPage(states: [ProviderID: TokenStatsViewModel.ProviderState]) {
        let selectedDate = nowProvider()
        let snapshot = RecentSessionDetailsBuilder.build(
            states: states,
            period: .today,
            now: selectedDate,
            calendar: calendar
        )
        sessionDateLabel.stringValue = formatSessionDate(selectedDate)
        sessionCountValueLabel.stringValue = formatInt(snapshot.totalSessionCount)
        sessionTokenValueLabel.stringValue = CompactNumberFormatter.format(snapshot.totalTokens)
        sessionCostValueLabel.stringValue = formatCurrency(snapshot.totalCost)
        sessionRecordValueLabel.stringValue = formatInt(snapshot.rows.reduce(0) { $0 + $1.entryCount })
        rebuildSessionRows(snapshot.rows)
        sessionStatusLabel.stringValue = sessionStatusText(
            snapshot: snapshot,
            totalProviderCount: states.count
        )
        // 加载反馈已由侧边栏提供；避免额外状态行撑高默认视口并级联压窄表格。
        let hasLoadingProvider = snapshot.loadingProviderCount > 0
        sessionStatusLabel.isHidden = hasLoadingProvider || sessionStatusLabel.stringValue.isEmpty
    }

    private func updateNavigationSelection() {
        for item in DashboardNavigationItem.allCases {
            guard let button = navButtons[item] else { continue }
            let isSelected = item == selectedNavigationItem
            let backgroundColor = isSelected ? DashboardPalette.navigationSelectedBackground : DashboardPalette.sidebarBackground
            (button as? DashboardNavigationButton)?.setDashboardBackgroundColor(backgroundColor)
            let tintColor = isSelected ? DashboardPalette.navigationSelectedText : DashboardPalette.secondaryText
            button.contentTintColor = tintColor
            (button as? DashboardNavigationButton)?.setVisualTint(tintColor)
        }
        privacyPolicyButton?.setDashboardBackgroundColor(DashboardPalette.sidebarBackground)
        privacyPolicyButton?.contentTintColor = DashboardPalette.secondaryText
        privacyPolicyButton?.setVisualTint(DashboardPalette.secondaryText)
    }

    private func updateRangeButtons() {
        for range in DashboardRange.allCases {
            guard let button = rangeButtons[range] else { continue }
            let isSelected = range == selectedRange
            (button as? DashboardRangeButton)?.setDashboardLayerColors(
                backgroundColor: isSelected ? DashboardPalette.rangeSelectedBackground : DashboardPalette.panelBackground,
                borderColor: isSelected ? DashboardPalette.rangeSelectedBorder : DashboardPalette.border
            )
            button.contentTintColor = isSelected ? DashboardPalette.rangeSelectedText : DashboardPalette.primaryText
        }
    }

    private func setRefreshButtonLoading(_ isLoading: Bool) {
        refreshButton.isEnabled = !isLoading
        refreshButton.title = localized(.refreshNow)
        refreshButton.image = NSImage(
            systemSymbolName: isLoading ? "arrow.triangle.2.circlepath" : "arrow.clockwise",
            accessibilityDescription: isLoading ? localized(.refreshInProgress) : refreshButton.title
        )
        refreshButton.image?.isTemplate = true
        refreshButton.imageHugsTitle = true
        refreshButton.contentTintColor = DashboardPalette.primaryText
    }

    private func scanStatusText(states: [ProviderID: TokenStatsViewModel.ProviderState]) -> String {
        if states.values.contains(where: { $0.isLoading }) {
            return localized(.dashboardScanUpdating)
        }
        guard let lastRefreshedAt = states.values.compactMap(\.lastRefreshedAt).max() else {
            return localized(.dashboardScanPending)
        }
        return String(
            format: localized(.dashboardScanUpdatedFormat),
            relativeRefreshDescription(since: lastRefreshedAt, now: nowProvider())
        )
    }

    private func relativeRefreshDescription(since date: Date, now: Date) -> String {
        let elapsedSeconds = max(0, now.timeIntervalSince(date))
        let minutes = Int(elapsedSeconds / 60)
        if minutes < 1 {
            return localized(.dashboardJustNow)
        }
        if minutes < 60 {
            return String(format: localized(.dashboardMinutesAgoFormat), minutes)
        }
        return String(format: localized(.dashboardHoursAgoFormat), max(1, Int(elapsedSeconds / 3_600)))
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
        let statusText = isAuthorized ? localized(.settingsAuthorized) : localized(.dashboardUnauthorized)
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
            let label = NSTextField(labelWithString: localized(.shareEmpty))
            label.font = .systemFont(ofSize: 12)
            label.textColor = DashboardPalette.secondaryText
            addFullWidthArrangedSubview(label, to: sourceLegendStack)
            return
        }
        for (index, slice) in visible.enumerated() {
            addFullWidthArrangedSubview(makeLegendRow(
                title: slice.label,
                value: formatPercentage(slice.percentage),
                color: DashboardColors.modelColor(at: index),
                dotIdentifier: "DashboardSourceLegendDot.\(index)"
            ), to: sourceLegendStack)
        }
    }

    private func rebuildProjectRows(_ rows: [DashboardProjectRow]) {
        clearStack(projectRowsStack)
        if rows.isEmpty {
            let label = NSTextField(labelWithString: localized(.dashboardNoProjectData))
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

    private func rebuildSessionRows(_ rows: [RecentSessionRow]) {
        clearStack(sessionRowsStack)
        let pagination = RecentSessionPagination(
            totalCount: rows.count,
            pageSize: Self.sessionPageSize,
            currentPage: currentSessionPage
        )
        currentSessionPage = pagination.currentPage
        rebuildSessionPaginationControls(pagination)

        let visibleRows = Array(rows[pagination.rowRange])
        if visibleRows.isEmpty {
            addFullWidthArrangedSubview(makeEmptySessionTableRow(), to: sessionRowsStack)
        } else {
            for (index, row) in visibleRows.enumerated() {
                addFullWidthArrangedSubview(makeSessionTableRow(row, index: index), to: sessionRowsStack)
            }
        }
        DashboardAppearanceRefresh.refresh(in: sessionRowsStack)
        DashboardAppearanceRefresh.refresh(in: sessionPaginationControlsStack)
    }

    private func makeLegendRow(title: String, value: String, color: NSColor, dotIdentifier: String? = nil) -> NSView {
        let dot = DashboardDotView(color: color, accessibilityIdentifier: dotIdentifier)
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12)
        titleLabel.textColor = DashboardPalette.primaryText
        titleLabel.lineBreakMode = .byTruncatingMiddle
        let valueLabel = NSTextField(labelWithString: value)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        valueLabel.textColor = DashboardPalette.secondaryText
        valueLabel.alignment = .right
        valueLabel.lineBreakMode = .byTruncatingTail
        let row = NSStackView(views: [dot, titleLabel, valueLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 8
        valueLabel.widthAnchor.constraint(equalToConstant: Self.sourceLegendValueWidth).isActive = true
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
        return identifier.hasPrefix("DashboardRange.")
            || identifier.hasPrefix("DashboardSessionsPagination.")
            || identifier == "DashboardRefreshButton"
    }

    private func fraction(_ value: Int, max maxValue: Int) -> CGFloat {
        guard maxValue > 0 else { return 0.04 }
        return Swift.max(0.04, min(1, CGFloat(value) / CGFloat(maxValue)))
    }

    private func formatTokenBreakdown(_ summary: DashboardUsageSummary) -> String {
        var parts = [
            "\(localized(.dashboardInput)) \(CompactNumberFormatter.formatMillions(summary.inputTokens))",
            "\(localized(.dashboardOutput)) \(CompactNumberFormatter.formatMillions(summary.outputTokens))",
        ]
        let cacheTokens = summary.cacheReadTokens.addingSaturated(summary.cacheCreationTokens)
        let cacheText = CompactNumberFormatter.formatMillions(cacheTokens)
        let cacheHitRateText = localizedParenthetical(formatCacheHitRate(summary))
        parts.append("\(localized(.dashboardCache)) \(cacheText)\(cacheHitRateText)")
        if summary.reasoningTokens > 0 {
            parts.append("\(localized(.dashboardReasoning)) \(CompactNumberFormatter.formatMillions(summary.reasoningTokens))")
        }
        return parts.joined(separator: " / ")
    }

    private func localizedParenthetical(_ value: String) -> String {
        switch language {
        case .zhHans, .zhHant:
            return "（\(value)）"
        default:
            return " (\(value))"
        }
    }

    private func formatCacheHitRate(_ summary: DashboardUsageSummary) -> String {
        // 比例使用 Double 汇总，展示用 Int 饱和不能作为分母，否则极值会产生超过 100% 的占比。
        let cacheTokens = Double(summary.cacheReadTokens) + Double(summary.cacheCreationTokens)
        let base = Double(summary.inputTokens)
            + Double(summary.outputTokens)
            + Double(summary.reasoningTokens)
            + cacheTokens
        guard base > 0 else { return "0%" }
        return formatPercentage(cacheTokens / base)
    }

    private func formatCostBreakdown(_ summary: DashboardUsageSummary) -> String {
        let inputBillableTokens = Double(summary.inputTokens)
            + Double(summary.cacheReadTokens)
            + Double(summary.cacheCreationTokens)
        let outputTokens = Double(summary.outputTokens)
        let reasoningTokens = Double(summary.reasoningTokens)
        let billableTokens = inputBillableTokens + outputTokens + reasoningTokens
        guard billableTokens > 0, summary.cost > 0 else {
            return "\(localized(.dashboardInput)) $0.00 / \(localized(.dashboardOutput)) $0.00 / \(localized(.dashboardReasoning)) $0.00"
        }

        let inputCost = summary.cost * (inputBillableTokens / billableTokens)
        let outputCost = summary.cost * (outputTokens / billableTokens)
        let reasoningCost = summary.cost * (reasoningTokens / billableTokens)
        return "\(localized(.dashboardInput)) \(formatCurrency(inputCost)) / \(localized(.dashboardOutput)) \(formatCurrency(outputCost)) / \(localized(.dashboardReasoning)) \(formatCurrency(reasoningCost))"
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
            return localized(.dashboardSessionsEmptyToday)
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
