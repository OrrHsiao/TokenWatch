import AppKit

/// 状态栏 popover 内容控制器,展示摘要统计与近 22 周跨 provider token 日历热力图。
@MainActor
final class StatusPopoverViewController: NSViewController {

    nonisolated static let contentSize = NSSize(width: 370, height: 355)
    private static let outerMargin: CGFloat = 14
    private static let tileSpacing: CGFloat = 3
    private static let todayDescriptionHeight: CGFloat = 20
    private static let todayDescriptionToSummarySpacing: CGFloat = 8
    private static let todayRefreshButtonSize: CGFloat = 20
    private static let todayRefreshButtonSpacing: CGFloat = 6
    private static let todayRefreshButtonDefaultSymbolName = "arrow.clockwise"
    private static let todayRefreshButtonLoadingSymbolName = "arrow.triangle.2.circlepath"
    private static let summaryCardHeight: CGFloat = 50
    private static let gridColumnCount = 22
    private static let gridRowCount = 7
    private static let collectionHeight =
        CalendarHeatmapCollectionViewItem.tileSize.height * CGFloat(gridRowCount)
        + tileSpacing * CGFloat(gridRowCount - 1)
    private static let collectionWidth =
        CalendarHeatmapCollectionViewItem.tileSize.width * CGFloat(gridColumnCount)
        + tileSpacing * CGFloat(gridColumnCount - 1)
    private static let hourlyLineChartTopSpacing: CGFloat = 14
    private static let hourlyLineChartHeight: CGFloat = 111

    private let viewModel: TokenStatsViewModel
    private let nowProvider: () -> Date
    private let calendar: Calendar
    private let languageSettings: AppLanguageSettings
    private var observerToken: TokenStatsViewModel.ObservationToken?
    private var languageSettingsObserverToken: AppLanguageSettings.ObservationToken?
    private var snapshot: CalendarHeatmapSnapshot?
    private var hoverText: String?
    private var currentTodayRefreshButtonSymbolName: String?

    private let summaryStack = NSStackView()
    private var summaryCards: [SummaryMetricCardView] = []
    private let todayDescriptionRow = NSView()
    private let todayDescriptionLabel = NSTextField(labelWithString: "")
    private let todayRefreshButton = RefreshIconButton()
    private let hoverLabel = NSTextField(labelWithString: "")
    private let collectionView = NSCollectionView()
    private let hourlyLineChartView = TodayHourlyTokenLineChartView()

    struct DebugSummaryCard: Equatable {
        let title: String
        let value: String
        let toolTip: String?
        let styleName: String
        let hasBackgroundColor: Bool
        let hasBorder: Bool
        let cornerRadius: CGFloat
    }

    var debugSummaryCards: [DebugSummaryCard] {
        summaryCards.map {
            DebugSummaryCard(
                title: $0.debugTitle,
                value: $0.debugValue,
                toolTip: $0.debugToolTip,
                styleName: $0.debugStyleName,
                hasBackgroundColor: $0.debugHasBackgroundColor,
                hasBorder: $0.debugHasBorder,
                cornerRadius: $0.debugCornerRadius
            )
        }
    }
    var debugTodayDescriptionText: String { todayDescriptionLabel.stringValue }
    var debugTodayDescriptionAlignment: NSTextAlignment { todayDescriptionLabel.alignment }
    var debugRefreshButtonTitle: String { todayRefreshButton.title }
    var debugRefreshButtonSymbolName: String? {
        todayRefreshButton.image == nil ? nil : currentTodayRefreshButtonSymbolName
    }
    var debugRefreshButtonUsesImageOnly: Bool {
        todayRefreshButton.imagePosition == .imageOnly
    }
    var debugRefreshButtonToolTip: String? { todayRefreshButton.toolTip }
    var debugRefreshButtonAccessibilityLabel: String? { todayRefreshButton.accessibilityLabel() }
    var debugRefreshButtonImageAccessibilityDescription: String? {
        todayRefreshButton.image?.accessibilityDescription
    }
    var debugRefreshButtonActionName: String? {
        todayRefreshButton.action.map(NSStringFromSelector)
    }
    var debugRefreshButtonCornerRadius: CGFloat { todayRefreshButton.debugCornerRadius }
    var debugRefreshButtonHasBackground: Bool { todayRefreshButton.debugHasBackground }
    var debugRefreshButtonIsEnabled: Bool { todayRefreshButton.isEnabled }
    var debugHoverText: String { hoverLabel.stringValue }
    var debugCollectionView: NSCollectionView? { collectionView }
    var debugHourlyLineChartView: TodayHourlyTokenLineChartView? { hourlyLineChartView }
    var debugHourlyLineChartPointCount: Int { hourlyLineChartView.debugPointCount }
    var debugHourlyLineChartXAxisLabels: [String] { hourlyLineChartView.debugXAxisLabels }
    var debugHourlyLineChartHoverText: String { hourlyLineChartView.debugHoverText }
    var debugHourlyLineChartHoverLabelTopAlignsWithLineChart: Bool {
        hourlyLineChartView.debugHoverLabelTopAlignsWithChartView
    }
    var debugHourlyLineChartHoverLabelTrailingAlignsWithLineChart: Bool {
        hourlyLineChartView.debugHoverLabelTrailingAlignsWithChartView
    }
    var debugWeekdayLabelCount: Int { 0 }
    var debugCollectionItemCount: Int { snapshot?.cells.count ?? 0 }
    var debugCollectionHeight: CGFloat { Self.collectionHeight }
    static var debugExpectedCollectionHeight: CGFloat { collectionHeight }
    var debugTodayDescriptionRowCenteredInRoot: Bool {
        hasConstraint(
            firstItem: todayDescriptionRow,
            firstAttribute: .centerX,
            secondItem: view,
            secondAttribute: .centerX,
            constant: 0
        )
    }
    var debugTodayDescriptionLabelSitsAboveSummary: Bool {
        hasConstraint(
            firstItem: summaryStack,
            firstAttribute: .top,
            secondItem: todayDescriptionRow,
            secondAttribute: .bottom,
            constant: Self.todayDescriptionToSummarySpacing
        )
    }
    var debugRefreshButtonSitsRightOfDescriptionLabel: Bool {
        hasConstraint(
            firstItem: todayRefreshButton,
            firstAttribute: .leading,
            secondItem: todayDescriptionLabel,
            secondAttribute: .trailing,
            constant: Self.todayRefreshButtonSpacing
        )
    }
    var debugRefreshButtonTrailingAlignsWithDescriptionRow: Bool {
        hasConstraint(
            firstItem: todayRefreshButton,
            firstAttribute: .trailing,
            secondItem: todayDescriptionRow,
            secondAttribute: .trailing,
            constant: 0
        )
    }
    var debugHoverLabelTrailingAlignsWithCollectionView: Bool {
        hasConstraint(
            firstItem: hoverLabel,
            firstAttribute: .trailing,
            secondItem: collectionView,
            secondAttribute: .trailing,
            constant: 0
        )
    }
    var debugHoverLabelLeadingAlignsWithCollectionView: Bool {
        hasConstraint(
            firstItem: hoverLabel,
            firstAttribute: .leading,
            secondItem: collectionView,
            secondAttribute: .leading,
            constant: 0
        )
    }
    var debugHoverLabelSitsJustAboveCollectionView: Bool {
        hasConstraint(
            firstItem: hoverLabel,
            firstAttribute: .bottom,
            secondItem: collectionView,
            secondAttribute: .top,
            constant: -1
        )
    }
    var debugCollectionViewBottomFitsInRootBounds: Bool {
        let frameInRoot = collectionView.convert(collectionView.bounds, to: view)
        return frameInRoot.minY >= Self.outerMargin
            && frameInRoot.maxY <= view.bounds.maxY - Self.outerMargin
    }
    var debugHourlyLineChartSitsBelowCollectionView: Bool {
        hasConstraint(
            firstItem: hourlyLineChartView,
            firstAttribute: .top,
            secondItem: collectionView,
            secondAttribute: .bottom,
            constant: Self.hourlyLineChartTopSpacing
        )
    }
    var debugHourlyLineChartWidthMatchesCollectionView: Bool {
        hasConstraint(
            firstItem: hourlyLineChartView,
            firstAttribute: .width,
            secondItem: collectionView,
            secondAttribute: .width,
            constant: 0
        )
    }
    var debugHourlyLineChartBottomFitsInRootBounds: Bool {
        let frameInRoot = hourlyLineChartView.convert(hourlyLineChartView.bounds, to: view)
        return frameInRoot.minY >= Self.outerMargin
            && frameInRoot.maxY <= view.bounds.maxY - Self.outerMargin
    }
    func debugHasCell(at item: Int) -> Bool { cell(at: item) != nil }
    func debugUpdateHoverText(_ text: String?) { updateHoverText(text) }
    func debugSimulateHourlyLineChartHover(monthKey: String?) {
        hourlyLineChartView.debugSimulateHover(monthKey: monthKey)
    }
    func debugSetRefreshButtonHovering(_ isHovering: Bool) {
        todayRefreshButton.debugSetHovering(isHovering)
    }
    func debugSetRefreshButtonLoading(_ isLoading: Bool) {
        setRefreshButtonLoading(isLoading)
    }

    private func isConstraintItem(_ item: Any?, identicalTo target: NSView) -> Bool {
        guard let item = item as AnyObject? else { return false }
        return item === target
    }

    private func allConstraints(in root: NSView) -> [NSLayoutConstraint] {
        root.constraints + root.subviews.flatMap(allConstraints)
    }

    private func hasConstraint(
        firstItem: NSView,
        firstAttribute: NSLayoutConstraint.Attribute,
        secondItem: NSView,
        secondAttribute: NSLayoutConstraint.Attribute,
        constant: CGFloat
    ) -> Bool {
        allConstraints(in: view).contains { constraint in
            guard constraint.isActive,
                  constraint.firstAttribute == firstAttribute,
                  constraint.secondAttribute == secondAttribute,
                  constraint.multiplier == 1,
                  constraint.constant == constant else {
                return false
            }

            return isConstraintItem(constraint.firstItem, identicalTo: firstItem)
                && isConstraintItem(constraint.secondItem, identicalTo: secondItem)
        }
    }

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

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("StatusPopoverViewController 必须用指定初始化方法构造")
    }

    override func loadView() {
        view = StatusPopoverRootView(frame: NSRect(origin: .zero, size: Self.contentSize))
        setupSubviews()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        render()
        observerToken = viewModel.observe { [weak self] _ in
            self?.render()
        }
        languageSettingsObserverToken = languageSettings.observe { [weak self] in
            self?.render()
        }
    }

    deinit {
        MainActor.assumeIsolated {
            if let observerToken {
                viewModel.removeObserver(observerToken)
            }
            if let languageSettingsObserverToken {
                languageSettings.removeObserver(languageSettingsObserverToken)
            }
        }
    }

    private func setupSubviews() {
        summaryStack.orientation = .horizontal
        summaryStack.alignment = .centerY
        summaryStack.distribution = .fillEqually
        summaryStack.spacing = 7
        summaryStack.translatesAutoresizingMaskIntoConstraints = false
        setupSummaryCards()

        todayDescriptionRow.translatesAutoresizingMaskIntoConstraints = false

        todayDescriptionLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        todayDescriptionLabel.textColor = .labelColor
        todayDescriptionLabel.alignment = .left
        todayDescriptionLabel.lineBreakMode = .byTruncatingTail
        todayDescriptionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        todayDescriptionLabel.translatesAutoresizingMaskIntoConstraints = false

        configureTodayRefreshButton()

        hoverLabel.font = .systemFont(ofSize: 12, weight: .medium)
        hoverLabel.textColor = .secondaryLabelColor
        hoverLabel.alignment = .right
        hoverLabel.lineBreakMode = .byTruncatingMiddle
        hoverLabel.translatesAutoresizingMaskIntoConstraints = false

        let layout = NSCollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumInteritemSpacing = Self.tileSpacing
        layout.minimumLineSpacing = Self.tileSpacing
        layout.itemSize = CalendarHeatmapCollectionViewItem.tileSize
        layout.sectionInset = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

        collectionView.collectionViewLayout = layout
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = false
        collectionView.dataSource = self
        collectionView.register(
            CalendarHeatmapCollectionViewItem.self,
            forItemWithIdentifier: CalendarHeatmapCollectionViewItem.reuseIdentifier
        )
        collectionView.translatesAutoresizingMaskIntoConstraints = false

        hourlyLineChartView.translatesAutoresizingMaskIntoConstraints = false

        todayDescriptionRow.addSubview(todayDescriptionLabel)
        todayDescriptionRow.addSubview(todayRefreshButton)
        view.addSubview(todayDescriptionRow)
        view.addSubview(summaryStack)
        view.addSubview(hoverLabel)
        view.addSubview(collectionView)
        view.addSubview(hourlyLineChartView)

        NSLayoutConstraint.activate([
            todayDescriptionRow.topAnchor.constraint(equalTo: view.topAnchor, constant: Self.outerMargin),
            todayDescriptionRow.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            todayDescriptionRow.widthAnchor.constraint(equalToConstant: Self.collectionWidth),
            todayDescriptionRow.heightAnchor.constraint(equalToConstant: Self.todayDescriptionHeight),

            todayDescriptionLabel.leadingAnchor.constraint(equalTo: todayDescriptionRow.leadingAnchor),
            todayDescriptionLabel.topAnchor.constraint(equalTo: todayDescriptionRow.topAnchor),
            todayDescriptionLabel.bottomAnchor.constraint(equalTo: todayDescriptionRow.bottomAnchor),

            todayRefreshButton.leadingAnchor.constraint(
                equalTo: todayDescriptionLabel.trailingAnchor,
                constant: Self.todayRefreshButtonSpacing
            ),
            todayRefreshButton.trailingAnchor.constraint(equalTo: todayDescriptionRow.trailingAnchor),
            todayRefreshButton.centerYAnchor.constraint(equalTo: todayDescriptionRow.centerYAnchor),
            todayRefreshButton.widthAnchor.constraint(equalToConstant: Self.todayRefreshButtonSize),
            todayRefreshButton.heightAnchor.constraint(equalToConstant: Self.todayRefreshButtonSize),

            summaryStack.topAnchor.constraint(
                equalTo: todayDescriptionRow.bottomAnchor,
                constant: Self.todayDescriptionToSummarySpacing
            ),
            summaryStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            summaryStack.widthAnchor.constraint(equalToConstant: Self.collectionWidth),
            summaryStack.heightAnchor.constraint(equalToConstant: Self.summaryCardHeight),

            hoverLabel.leadingAnchor.constraint(equalTo: collectionView.leadingAnchor),
            hoverLabel.trailingAnchor.constraint(equalTo: collectionView.trailingAnchor),
            hoverLabel.bottomAnchor.constraint(equalTo: collectionView.topAnchor, constant: -1),

            collectionView.topAnchor.constraint(equalTo: summaryStack.bottomAnchor, constant: 21),
            collectionView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            collectionView.widthAnchor.constraint(equalToConstant: Self.collectionWidth),
            collectionView.heightAnchor.constraint(equalToConstant: Self.collectionHeight),
            collectionView.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -Self.outerMargin),

            hourlyLineChartView.topAnchor.constraint(
                equalTo: collectionView.bottomAnchor,
                constant: Self.hourlyLineChartTopSpacing
            ),
            hourlyLineChartView.centerXAnchor.constraint(equalTo: collectionView.centerXAnchor),
            hourlyLineChartView.widthAnchor.constraint(equalTo: collectionView.widthAnchor),
            hourlyLineChartView.heightAnchor.constraint(equalToConstant: Self.hourlyLineChartHeight),
            hourlyLineChartView.bottomAnchor.constraint(
                lessThanOrEqualTo: view.bottomAnchor,
                constant: -Self.outerMargin
            ),
        ])
    }

    private func setupSummaryCards() {
        let cards = summaryTitles().map { title in
            SummaryMetricCardView(title: title, style: .neutral)
        }
        summaryCards = cards
        for card in cards {
            summaryStack.addArrangedSubview(card)
        }
    }

    private func configureTodayRefreshButton() {
        todayRefreshButton.title = ""
        todayRefreshButton.imagePosition = .imageOnly
        todayRefreshButton.imageScaling = .scaleProportionallyDown
        todayRefreshButton.isBordered = false
        todayRefreshButton.bezelStyle = .smallSquare
        todayRefreshButton.contentTintColor = .secondaryLabelColor
        todayRefreshButton.toolTip = AppStrings.text(.refreshNow, language: languageSettings.resolvedLanguage)
        todayRefreshButton.target = self
        todayRefreshButton.action = #selector(refreshTodayStats(_:))
        todayRefreshButton.setButtonType(.momentaryChange)
        todayRefreshButton.setContentHuggingPriority(.required, for: .horizontal)
        todayRefreshButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        todayRefreshButton.translatesAutoresizingMaskIntoConstraints = false
        setRefreshButtonLoading(false)
    }

    @objc private func refreshTodayStats(_ sender: Any?) {
        setRefreshButtonLoading(true)
        Task { @MainActor [weak self] in
            guard let self else { return }
            await viewModel.loadAllStats()
            applyRefreshButtonLoadingState()
        }
    }

    private func applyRefreshButtonLoadingState() {
        setRefreshButtonLoading(viewModel.states.values.contains { $0.isLoading })
    }

    private func setRefreshButtonLoading(_ isLoading: Bool) {
        let language = languageSettings.resolvedLanguage
        let symbolName = isLoading
            ? Self.todayRefreshButtonLoadingSymbolName
            : Self.todayRefreshButtonDefaultSymbolName
        setRefreshButtonSymbol(
            symbolName,
            accessibilityDescription: isLoading
                ? AppStrings.text(.refreshInProgress, language: language)
                : AppStrings.text(.refreshNow, language: language)
        )

        todayRefreshButton.isEnabled = !isLoading
        todayRefreshButton.toolTip = isLoading
            ? AppStrings.text(.refreshInProgress, language: language)
            : AppStrings.text(.refreshNow, language: language)
        todayRefreshButton.setAccessibilityLabel(isLoading
            ? AppStrings.text(.refreshingTodayAccessibility, language: language)
            : AppStrings.text(.refreshTodayAccessibility, language: language))
    }

    private func setRefreshButtonSymbol(_ symbolName: String, accessibilityDescription: String) {
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: accessibilityDescription
        )?.withSymbolConfiguration(symbolConfig)
        image?.isTemplate = true

        todayRefreshButton.image = image
        currentTodayRefreshButtonSymbolName = image == nil ? nil : symbolName
    }

    private func render() {
        let now = nowProvider()
        let language = languageSettings.resolvedLanguage
        let snapshot = CalendarHeatmapBuilder.build(
            states: viewModel.states,
            month: now,
            now: now,
            calendar: calendar,
            language: language
        )
        self.snapshot = snapshot
        let hourlySnapshot = MonthlyTokenChartBuilder.build(
            states: viewModel.states,
            period: .today,
            now: now,
            calendar: calendar,
            language: language
        )
        hourlyLineChartView.configure(with: hourlySnapshot, language: language)

        applySummary(snapshot.summary, language: language)
        applyTodayDescription(todayTokens: snapshot.summary.todayTokens, language: language)
        applyHoverText()
        applyRefreshButtonLoadingState()
        collectionView.reloadData()
    }

    private func updateHoverText(_ text: String?) {
        hoverText = text
        applyHoverText()
    }

    private func summaryTitles() -> [String] {
        let language = languageSettings.resolvedLanguage
        return [
            AppStrings.text(.popoverMonth, language: language),
            AppStrings.text(.popoverWeek, language: language),
            AppStrings.text(.popoverToday, language: language),
            AppStrings.text(.popoverDailyAverage, language: language),
        ]
    }

    private func applySummary(_ summary: CalendarHeatmapSummary, language: AppLanguage) {
        let titles = [
            AppStrings.text(.popoverMonth, language: language),
            AppStrings.text(.popoverWeek, language: language),
            AppStrings.text(.popoverToday, language: language),
            AppStrings.text(.popoverDailyAverage, language: language),
        ]
        let values = [
            summary.monthTokens,
            summary.weekTokens,
            summary.todayTokens,
            summary.averageDailyTokens,
        ].map(CompactNumberFormatter.format)

        let tokenUnit = AppStrings.text(.statusBarTokenUnit, language: language)
        for (card, titleAndValue) in zip(summaryCards, zip(titles, values)) {
            card.configure(title: titleAndValue.0, value: titleAndValue.1, tokenUnit: tokenUnit)
        }
    }

    private func applyTodayDescription(todayTokens: Int, language: AppLanguage) {
        todayDescriptionLabel.stringValue = StatusPopoverDailyTokenDescription.text(
            forTodayTokens: todayTokens,
            language: language
        )
    }

    private func applyHoverText() {
        hoverLabel.stringValue = hoverText ?? ""
    }

    private func cell(at item: Int) -> CalendarHeatmapCell? {
        guard let cells = snapshot?.cells,
              cells.indices.contains(item) else {
            return nil
        }

        return cells[item]
    }
}

/// 状态栏弹窗顶部的本日 token 消耗文案。
enum StatusPopoverDailyTokenDescription {
    /// 按状态栏图标相同阈值生成一句轻量描述。
    /// - Parameter total: 本日跨 provider token 总量,负数会按 0 处理。
    /// - Returns: 可直接展示在 popover 顶部的本地化文案。
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
}

private struct SummaryMetricCardStyle {
    let name: String
    let backgroundColor: NSColor
    let cornerRadius: CGFloat

    static let neutral = SummaryMetricCardStyle(
        name: "neutral",
        backgroundColor: dynamicColor(
            light: color(red: 252, green: 252, blue: 252),
            dark: color(red: 33, green: 34, blue: 37)
        ),
        cornerRadius: 8
    )

    private static func dynamicColor(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    private static func color(red: CGFloat, green: CGFloat, blue: CGFloat) -> NSColor {
        NSColor(calibratedRed: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
    }
}

private final class SummaryMetricCardView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    private let style: SummaryMetricCardStyle

    var debugTitle: String { titleLabel.stringValue }
    var debugValue: String { valueLabel.stringValue }
    var debugToolTip: String? { toolTip }
    var debugStyleName: String { style.name }
    var debugHasBackgroundColor: Bool { layer?.backgroundColor != nil }
    var debugHasBorder: Bool { (layer?.borderWidth ?? 0) > 0 && layer?.borderColor != nil }
    var debugCornerRadius: CGFloat { layer?.cornerRadius ?? 0 }

    init(title: String, style: SummaryMetricCardStyle) {
        self.style = style
        super.init(frame: .zero)

        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.stringValue = title
        titleLabel.alignment = .center
        titleLabel.font = .systemFont(ofSize: 10, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail

        valueLabel.alignment = .center
        valueLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        valueLabel.textColor = .labelColor
        valueLabel.lineBreakMode = .byTruncatingTail

        let contentStack = NSStackView(views: [titleLabel, valueLabel])
        contentStack.orientation = .vertical
        contentStack.alignment = .centerX
        contentStack.spacing = 3
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        updateCardColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SummaryMetricCardView 不支持 storyboard 初始化")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateCardColors()
    }

    func configure(title: String, value: String, tokenUnit: String) {
        titleLabel.stringValue = title
        valueLabel.stringValue = value
        toolTip = "\(titleLabel.stringValue) \(value) \(tokenUnit)"
    }

    private func updateCardColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.cornerRadius = style.cornerRadius
            layer?.backgroundColor = style.backgroundColor.cgColor
            layer?.borderColor = nil
            layer?.borderWidth = 0
        }
    }
}

/// 跟随系统外观刷新 popover 背景色。
final class StatusPopoverRootView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        updateBackgroundColor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("StatusPopoverRootView 不支持 storyboard 初始化")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackgroundColor()
    }

    private func updateBackgroundColor() {
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }
}

extension StatusPopoverViewController: NSCollectionViewDataSource {
    func collectionView(
        _ collectionView: NSCollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        snapshot?.cells.count ?? 0
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        let item = collectionView.makeItem(
            withIdentifier: CalendarHeatmapCollectionViewItem.reuseIdentifier,
            for: indexPath
        )
        guard let heatmapItem = item as? CalendarHeatmapCollectionViewItem,
              let cell = cell(at: indexPath.item) else {
            return item
        }

        heatmapItem.onHoverTextChange = { [weak self] text in
            self?.updateHoverText(text)
        }
        heatmapItem.configure(with: cell, language: languageSettings.resolvedLanguage)
        return heatmapItem
    }
}
