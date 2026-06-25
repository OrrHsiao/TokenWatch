import AppKit

/// 跨 provider 的时间窗口 token 消耗页面。
final class MonthlyStatsViewController: NSViewController {
    private static let compactBarChartWidth: CGFloat = 520
    private static let refreshButtonSize: CGFloat = 20
    private static let refreshButtonSpacing: CGFloat = 8
    private static let refreshButtonDefaultSymbolName = "arrow.clockwise"
    private static let refreshButtonLoadingSymbolName = "arrow.triangle.2.circlepath"

    private let titleLabel = NSTextField(labelWithString: "")
    private let totalLabel = NSTextField(labelWithString: "0.0M")
    private let costLabel = NSTextField(labelWithString: "$0.00")
    private let statusLabel = NSTextField(labelWithString: "")
    private let partialLoadingStatusLabel = NSTextField(labelWithString: "")
    private let tokenChartTitleLabel = NSTextField(labelWithString: "Token 用量")
    private let costChartTitleLabel = NSTextField(labelWithString: "费用")
    private let tokenChartHoverLabel = NSTextField(labelWithString: "")
    private let costChartHoverLabel = NSTextField(labelWithString: "")
    private let chartView = MonthlyTokenChartView()
    private let costChartView = MonthlyCostChartView()
    private let toolSharePieView = UsageSharePieChartView(title: "工具占比")
    private let modelSharePieView = UsageSharePieChartView(title: "模型占比")
    private let period: UsageStatsPeriod
    private let stateProvider: @MainActor () -> [ProviderID: TokenStatsViewModel.ProviderState]
    private let refreshAction: @MainActor () async -> Void
    private let languageSettings: AppLanguageSettings
    private let refreshButton = RefreshIconButton()
    private let nowProvider: () -> Date
    private let calendar: Calendar
    private var currentRefreshButtonSymbolName: String?
    private var languageSettingsObserverToken: AppLanguageSettings.ObservationToken?
    private var tokenHoverLabelTrailingConstraint: NSLayoutConstraint?
    private var tokenTitleRowTrailingConstraint: NSLayoutConstraint?
    private var costHoverLabelTrailingConstraint: NSLayoutConstraint?
    private var costTitleRowTrailingConstraint: NSLayoutConstraint?
    private var language: AppLanguage { languageSettings.resolvedLanguage }

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

    var debugTokenChartHoverText: String {
        tokenChartHoverLabel.stringValue
    }

    var debugCostChartHoverText: String {
        costChartHoverLabel.stringValue
    }

    var debugStatusText: String {
        if !partialLoadingStatusLabel.isHidden {
            return partialLoadingStatusLabel.stringValue
        }
        return statusLabel.stringValue
    }

    var debugRefreshButtonTitle: String {
        refreshButton.title
    }

    var debugRefreshButtonSymbolName: String? {
        refreshButton.image == nil ? nil : currentRefreshButtonSymbolName
    }

    var debugRefreshButtonUsesImageOnly: Bool {
        refreshButton.imagePosition == .imageOnly
    }

    var debugRefreshButtonToolTip: String? {
        refreshButton.toolTip
    }

    var debugRefreshButtonActionName: String? {
        refreshButton.action.map(NSStringFromSelector)
    }

    var debugRefreshButtonCornerRadius: CGFloat {
        refreshButton.debugCornerRadius
    }

    var debugRefreshButtonHasBackground: Bool {
        refreshButton.debugHasBackground
    }

    var debugRefreshButtonIsEnabled: Bool {
        refreshButton.isEnabled
    }

    var debugRefreshButtonFrameInView: NSRect {
        guard let superview = refreshButton.superview else {
            return .zero
        }
        return superview.convert(refreshButton.frame, to: view)
    }

    var debugTokenHoverLabelTrailingAlignsWithTokenChart: Bool {
        tokenHoverLabelTrailingConstraint?.isActive == true
            && tokenTitleRowTrailingConstraint?.isActive == true
    }

    var debugCostHoverLabelTrailingAlignsWithCostChart: Bool {
        costHoverLabelTrailingConstraint?.isActive == true
            && costTitleRowTrailingConstraint?.isActive == true
    }

    func debugSimulateTokenChartHover(monthKey: String?) {
        chartView.debugSimulateHover(monthKey: monthKey)
    }

    func debugSimulateCostChartHover(monthKey: String?) {
        costChartView.debugSimulateHover(monthKey: monthKey)
    }

    func debugSetRefreshButtonHovering(_ isHovering: Bool) {
        refreshButton.debugSetHovering(isHovering)
    }

    func debugClickRefreshButton() {
        refreshButton.performClick(nil)
    }

    required init?(coder: NSCoder) {
        fatalError("MonthlyStatsViewController 必须用 init(stateProvider:nowProvider:calendar:) 构造")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 420))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupSubviews()
        bindNotifications()
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

    private func setupSubviews() {
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        totalLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .medium)
        costLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .medium)
        costLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 0
        statusLabel.lineBreakMode = .byWordWrapping
        partialLoadingStatusLabel.font = .systemFont(ofSize: 12)
        partialLoadingStatusLabel.textColor = .secondaryLabelColor
        partialLoadingStatusLabel.alignment = .right
        partialLoadingStatusLabel.maximumNumberOfLines = 1
        partialLoadingStatusLabel.lineBreakMode = .byTruncatingTail
        partialLoadingStatusLabel.isHidden = true
        partialLoadingStatusLabel.setContentHuggingPriority(.required, for: .horizontal)
        partialLoadingStatusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        partialLoadingStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        configureChartTitle(tokenChartTitleLabel)
        configureChartTitle(costChartTitleLabel)
        configureChartHoverLabel(tokenChartHoverLabel)
        configureChartHoverLabel(costChartHoverLabel)

        tokenChartTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        costChartTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        tokenChartHoverLabel.translatesAutoresizingMaskIntoConstraints = false
        costChartHoverLabel.translatesAutoresizingMaskIntoConstraints = false
        chartView.translatesAutoresizingMaskIntoConstraints = false
        costChartView.translatesAutoresizingMaskIntoConstraints = false
        toolSharePieView.translatesAutoresizingMaskIntoConstraints = false
        modelSharePieView.translatesAutoresizingMaskIntoConstraints = false
        chartView.setContentHuggingPriority(.required, for: .horizontal)
        costChartView.setContentHuggingPriority(.required, for: .horizontal)
        chartView.onHoverTextChange = { [weak self] text in
            self?.updateTokenChartHoverText(text)
        }
        costChartView.onHoverTextChange = { [weak self] text in
            self?.updateCostChartHoverText(text)
        }

        let headerTextStack = NSStackView(views: [titleLabel])
        headerTextStack.orientation = .vertical
        headerTextStack.alignment = .leading
        headerTextStack.spacing = 4

        let summaryStack = NSStackView(views: [totalLabel, costLabel])
        summaryStack.orientation = .vertical
        summaryStack.alignment = .trailing
        summaryStack.spacing = 4

        let headerStack = NSStackView(views: [headerTextStack, summaryStack])
        headerStack.orientation = .horizontal
        headerStack.alignment = .firstBaseline
        headerStack.distribution = .gravityAreas
        headerStack.spacing = 16
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        configureRefreshButton()

        let headerView = NSView()
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(headerStack)
        headerView.addSubview(refreshButton)
        headerView.addSubview(partialLoadingStatusLabel)

        let tokenChartSection = makeChartSection(
            titleLabel: tokenChartTitleLabel,
            hoverLabel: tokenChartHoverLabel,
            chartView: chartView
        )
        tokenHoverLabelTrailingConstraint = tokenChartSection.hoverLabelTrailingConstraint
        tokenTitleRowTrailingConstraint = tokenChartSection.titleRowTrailingConstraint
        let costChartSection = makeChartSection(
            titleLabel: costChartTitleLabel,
            hoverLabel: costChartHoverLabel,
            chartView: costChartView
        )
        costHoverLabelTrailingConstraint = costChartSection.hoverLabelTrailingConstraint
        costTitleRowTrailingConstraint = costChartSection.titleRowTrailingConstraint

        let pieChartsStack = NSStackView(views: [toolSharePieView, modelSharePieView])
        pieChartsStack.translatesAutoresizingMaskIntoConstraints = false
        pieChartsStack.orientation = .vertical
        pieChartsStack.alignment = .width
        pieChartsStack.distribution = .fill
        pieChartsStack.spacing = 18
        pieChartsStack.setContentHuggingPriority(.required, for: .horizontal)

        let contentStack = NSStackView(views: [headerView, tokenChartSection.stack, costChartSection.stack, pieChartsStack, statusLabel])
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 18

        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(contentStack)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.documentView = contentView

        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            contentStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 32),
            contentStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -32),
            contentStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 32),
            contentStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -32),
            headerView.leadingAnchor.constraint(equalTo: contentStack.leadingAnchor),
            headerView.widthAnchor.constraint(equalToConstant: Self.compactBarChartWidth),
            headerStack.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            headerStack.topAnchor.constraint(equalTo: headerView.topAnchor),
            headerStack.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),
            headerStack.trailingAnchor.constraint(
                lessThanOrEqualTo: refreshButton.leadingAnchor,
                constant: -Self.refreshButtonSpacing
            ),
            refreshButton.topAnchor.constraint(equalTo: headerView.topAnchor),
            refreshButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            refreshButton.widthAnchor.constraint(equalToConstant: Self.refreshButtonSize),
            refreshButton.heightAnchor.constraint(equalToConstant: Self.refreshButtonSize),
            partialLoadingStatusLabel.topAnchor.constraint(equalTo: refreshButton.bottomAnchor, constant: 6),
            partialLoadingStatusLabel.trailingAnchor.constraint(equalTo: refreshButton.trailingAnchor),
            partialLoadingStatusLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: headerStack.trailingAnchor,
                constant: Self.refreshButtonSpacing
            ),
            partialLoadingStatusLabel.bottomAnchor.constraint(lessThanOrEqualTo: headerView.bottomAnchor),
            tokenChartSection.stack.leadingAnchor.constraint(equalTo: contentStack.leadingAnchor),
            tokenChartSection.stack.widthAnchor.constraint(equalToConstant: Self.compactBarChartWidth),
            chartView.widthAnchor.constraint(equalToConstant: Self.compactBarChartWidth),
            costChartSection.stack.leadingAnchor.constraint(equalTo: contentStack.leadingAnchor),
            costChartSection.stack.widthAnchor.constraint(equalToConstant: Self.compactBarChartWidth),
            costChartView.widthAnchor.constraint(equalToConstant: Self.compactBarChartWidth),
            pieChartsStack.leadingAnchor.constraint(equalTo: contentStack.leadingAnchor),
            pieChartsStack.trailingAnchor.constraint(lessThanOrEqualTo: contentStack.trailingAnchor),
            pieChartsStack.widthAnchor.constraint(equalToConstant: Self.compactBarChartWidth),
            toolSharePieView.widthAnchor.constraint(equalToConstant: Self.compactBarChartWidth),
            modelSharePieView.widthAnchor.constraint(equalToConstant: Self.compactBarChartWidth),
            statusLabel.widthAnchor.constraint(lessThanOrEqualTo: contentStack.widthAnchor),
        ])
    }

    private func configureRefreshButton() {
        refreshButton.title = ""
        refreshButton.imagePosition = .imageOnly
        refreshButton.imageScaling = .scaleProportionallyDown
        refreshButton.isBordered = false
        refreshButton.bezelStyle = .smallSquare
        refreshButton.contentTintColor = .secondaryLabelColor
        refreshButton.target = self
        refreshButton.action = #selector(refreshStats(_:))
        refreshButton.setButtonType(.momentaryChange)
        refreshButton.setContentHuggingPriority(.required, for: .horizontal)
        refreshButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        setRefreshButtonLoading(false)
    }

    private func configureChartTitle(_ label: NSTextField) {
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .labelColor
        label.alignment = .left
    }

    private func configureChartHoverLabel(_ label: NSTextField) {
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        label.lineBreakMode = .byTruncatingMiddle
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    private func makeChartSection(
        titleLabel: NSTextField,
        hoverLabel: NSTextField,
        chartView: NSView
    ) -> ChartSectionLayout {
        let titleRow = NSView()
        titleRow.translatesAutoresizingMaskIntoConstraints = false
        titleRow.addSubview(titleLabel)
        titleRow.addSubview(hoverLabel)

        let stack = NSStackView(views: [titleRow, chartView])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setContentHuggingPriority(.required, for: .horizontal)

        let hoverLabelTrailingConstraint = hoverLabel.trailingAnchor.constraint(equalTo: titleRow.trailingAnchor)
        let titleRowTrailingConstraint = titleRow.trailingAnchor.constraint(equalTo: chartView.trailingAnchor)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: titleRow.leadingAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: hoverLabel.leadingAnchor, constant: -12),
            titleLabel.topAnchor.constraint(equalTo: titleRow.topAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: titleRow.bottomAnchor),
            hoverLabelTrailingConstraint,
            hoverLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            titleRow.leadingAnchor.constraint(equalTo: chartView.leadingAnchor),
            titleRowTrailingConstraint,
        ])
        return ChartSectionLayout(
            stack: stack,
            hoverLabelTrailingConstraint: hoverLabelTrailingConstraint,
            titleRowTrailingConstraint: titleRowTrailingConstraint
        )
    }

    private func bindNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(providerStateDidChange(_:)),
            name: .providerStateDidChange,
            object: nil
        )
        languageSettingsObserverToken = languageSettings.observe { [weak self] in
            self?.applyLocalizedText()
            self?.render()
        }
    }

    @objc private func providerStateDidChange(_ note: Notification) {
        render()
    }

    @MainActor
    private func render() {
        applyLocalizedText()
        let states = stateProvider()
        let snapshot = MonthlyTokenChartBuilder.build(
            states: states,
            period: period,
            now: nowProvider(),
            calendar: calendar,
            language: language
        )
        chartView.configure(with: snapshot, period: period, language: language)
        costChartView.configure(with: snapshot, period: period, language: language)
        toolSharePieView.configure(slices: snapshot.toolShareSlices, language: language)
        modelSharePieView.configure(slices: snapshot.modelShareSlices, language: language)
        totalLabel.stringValue = CompactNumberFormatter.formatMillions(snapshot.totalTokens)
        costLabel.stringValue = formatCurrency(snapshot.totalCost)
        let status = statusText(for: snapshot, totalProviderCount: states.count)
        applyStatusText(status.text, isPartialLoading: status.isPartialLoading)
        applyRefreshButtonLoadingState(states: states)
    }

    private func applyLocalizedText() {
        title = period.title(language: language)
        titleLabel.stringValue = period.title(language: language)
        tokenChartTitleLabel.stringValue = AppStrings.text(.chartTokenUsage, language: language)
        costChartTitleLabel.stringValue = AppStrings.text(.chartCost, language: language)
        toolSharePieView.setTitle(AppStrings.text(.shareTool, language: language))
        modelSharePieView.setTitle(AppStrings.text(.shareModel, language: language))
        setRefreshButtonLoading(!refreshButton.isEnabled)
    }

    private func applyStatusText(_ text: String, isPartialLoading: Bool) {
        if isPartialLoading {
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

    @objc private func refreshStats(_ sender: Any?) {
        setRefreshButtonLoading(true)
        Task { @MainActor [weak self] in
            guard let self else { return }
            await refreshAction()
            applyRefreshButtonLoadingState(states: stateProvider())
        }
    }

    private func applyRefreshButtonLoadingState(states: [ProviderID: TokenStatsViewModel.ProviderState]) {
        setRefreshButtonLoading(states.values.contains { $0.isLoading })
    }

    private func setRefreshButtonLoading(_ isLoading: Bool) {
        let symbolName = isLoading
            ? Self.refreshButtonLoadingSymbolName
            : Self.refreshButtonDefaultSymbolName
        setRefreshButtonSymbol(
            symbolName,
            accessibilityDescription: isLoading
                ? AppStrings.text(.refreshInProgress, language: language)
                : AppStrings.text(.refreshNow, language: language)
        )

        refreshButton.isEnabled = !isLoading
        refreshButton.toolTip = isLoading
            ? AppStrings.text(.refreshInProgress, language: language)
            : AppStrings.text(.refreshNow, language: language)
        refreshButton.setAccessibilityLabel(refreshButtonAccessibilityLabel(isLoading: isLoading))
    }

    private func setRefreshButtonSymbol(_ symbolName: String, accessibilityDescription: String) {
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: accessibilityDescription
        )?.withSymbolConfiguration(symbolConfig)
        image?.isTemplate = true

        refreshButton.image = image
        currentRefreshButtonSymbolName = image == nil ? nil : symbolName
    }

    private func updateTokenChartHoverText(_ text: String?) {
        tokenChartHoverLabel.stringValue = text ?? ""
    }

    private func updateCostChartHoverText(_ text: String?) {
        costChartHoverLabel.stringValue = text ?? ""
    }

    private func formatCurrency(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    private func statusText(
        for snapshot: MonthlyTokenChartSnapshot,
        totalProviderCount: Int
    ) -> (text: String, isPartialLoading: Bool) {
        if totalProviderCount > 0
            && snapshot.loadingProviderCount == totalProviderCount
            && snapshot.loadedProviderCount == 0 {
            return (AppStrings.text(.statusLoadingUsage, language: language), false)
        }
        if snapshot.loadedProviderCount == 0 && snapshot.unauthorizedProviderCount > 0 {
            return (AppStrings.text(.statusNeedsHomeAuthorization, language: language), false)
        }
        if let errorMessage = snapshot.errorMessages.first {
            return (errorMessage, false)
        }
        if snapshot.totalTokens == 0 {
            return (period.emptyDataText(language: language), false)
        }
        if snapshot.loadingProviderCount > 0 {
            return (AppStrings.text(.statusPartialLoading, language: language), true)
        }
        if let errorMessage = snapshot.errorMessages.first {
            return (errorMessage, false)
        }
        return ("", false)
    }

    private func refreshButtonAccessibilityLabel(isLoading: Bool) -> String {
        switch (period, isLoading) {
        case (.today, true):
            return AppStrings.text(.refreshingTodayAccessibility, language: language)
        case (.today, false):
            return AppStrings.text(.refreshTodayAccessibility, language: language)
        case (_, true):
            return AppStrings.text(.refreshingUsageAccessibility, language: language)
        case (_, false):
            return AppStrings.text(.refreshUsageAccessibility, language: language)
        }
    }
}

private struct ChartSectionLayout {
    let stack: NSStackView
    let hoverLabelTrailingConstraint: NSLayoutConstraint
    let titleRowTrailingConstraint: NSLayoutConstraint
}
