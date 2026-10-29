import AppKit

/// 状态栏 popover 内容控制器,展示摘要统计与近 22 周跨 provider token 日历热力图。
///
/// 顶部为订阅剩余区，原有统计区作为整体位于其下方：原区域保持 370 × 355pt 与内部全部
/// 相对布局，只整体下移；弹窗总高度为两者之和，不压缩或缩放原控件。
@MainActor
final class StatusPopoverViewController: NSViewController {

    /// 原有统计区尺寸；内部控件布局全部相对该区域，不随新增区调整。
    nonisolated static let originalContentSize = NSSize(width: 370, height: 355)
    nonisolated static let contentSize = NSSize(
        width: originalContentSize.width,
        height: originalContentSize.height + SubscriptionQuotaSectionLayout.height
    )
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
    /// 订阅区与原区域内容边缘（热力图卡片）对齐。
    private static let quotaSectionHorizontalInset =
        (originalContentSize.width - collectionWidth) / 2 - heatmapCardHorizontalPadding
    private static let heatmapCardHorizontalPadding: CGFloat = 8
    /// 弹窗可见期间刷新倒计时与记录时间的间隔。
    private static let quotaPresentationTickInterval: TimeInterval = 60

    private let viewModel: TokenStatsViewModel
    private let quotaStore: SubscriptionQuotaStore
    private let quotaAccess: SubscriptionQuotaAccess
    private let nowProvider: () -> Date
    private let calendar: Calendar
    private let languageSettings: AppLanguageSettings
    private var observerToken: TokenStatsViewModel.ObservationToken?
    private var quotaObserverToken: SubscriptionQuotaStore.ObservationToken?
    private var quotaAccessObserverToken: SubscriptionQuotaAccess.ObservationToken?
    private var languageSettingsObserverToken: AppLanguageSettings.ObservationToken?
    private var quotaPresentationTimer: Timer?
    private var snapshot: CalendarHeatmapSnapshot?
    private var hoverText: String?
    private var currentTodayRefreshButtonSymbolName: String?

    private let quotaSectionView = SubscriptionQuotaSectionView(
        horizontalInset: StatusPopoverViewController.quotaSectionHorizontalInset
    )
    /// 原有统计区容器；原控件的约束全部相对它建立，以保证整体下移时内部布局不变。
    private let originalContentView = NSView()
    private let summaryStack = NSStackView()
    private var summaryCards: [SummaryMetricCardView] = []
    private let todayDescriptionRow = NSView()
    private let todayDescriptionLabel = NSTextField(labelWithString: "")
    private let todayRefreshButton = RefreshIconButton()
    private let hoverLabel = NSTextField(labelWithString: "")
    private let heatmapCard = DashboardRoundedView(
        backgroundColor: DashboardPalette.panelBackground,
        cornerRadius: 8,
        borderColor: DashboardPalette.border,
        borderWidth: 1
    )
    private let collectionView = NSCollectionView()
    private let hourlyLineChartView = TodayHourlyTokenLineChartView()
    private let loadingOverlay = LoadingOverlayView()

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
    var debugHeatmapCard: NSView? { heatmapCard }
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
        ) || (
            hasConstraint(
                firstItem: todayDescriptionRow,
                firstAttribute: .leading,
                secondItem: heatmapCard,
                secondAttribute: .leading,
                constant: 0
            ) && hasConstraint(
                firstItem: todayDescriptionRow,
                firstAttribute: .trailing,
                secondItem: heatmapCard,
                secondAttribute: .trailing,
                constant: 0
            )
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
        (hasConstraint(
            firstItem: hourlyLineChartView,
            firstAttribute: .leading,
            secondItem: heatmapCard,
            secondAttribute: .leading,
            constant: 0
        ) && hasConstraint(
            firstItem: hourlyLineChartView,
            firstAttribute: .trailing,
            secondItem: heatmapCard,
            secondAttribute: .trailing,
            constant: 0
        )) || hasConstraint(
            firstItem: hourlyLineChartView,
            firstAttribute: .width,
            secondItem: heatmapCard,
            secondAttribute: .width,
            constant: 0
        ) || hasConstraint(
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
    var debugLoadingOverlayIsVisible: Bool { !loadingOverlay.isHidden }
    var debugLoadingOverlayMessage: String { loadingOverlay.debugMessage }
    var debugLoadingOverlaySymbolName: String? { loadingOverlay.debugSymbolName }
    var debugLoadingOverlayUsesGlassMaterial: Bool {
        loadingOverlay.material == .hudWindow
            && loadingOverlay.blendingMode == .withinWindow
            && loadingOverlay.state == .active
    }
    /// 统计加载遮罩只覆盖原统计区，不遮挡新增订阅区。
    var debugLoadingOverlayCoversOriginalContent: Bool {
        hasConstraint(
            firstItem: loadingOverlay,
            firstAttribute: .leading,
            secondItem: originalContentView,
            secondAttribute: .leading,
            constant: 0
        ) && hasConstraint(
            firstItem: loadingOverlay,
            firstAttribute: .trailing,
            secondItem: originalContentView,
            secondAttribute: .trailing,
            constant: 0
        ) && hasConstraint(
            firstItem: loadingOverlay,
            firstAttribute: .top,
            secondItem: originalContentView,
            secondAttribute: .top,
            constant: 0
        ) && hasConstraint(
            firstItem: loadingOverlay,
            firstAttribute: .bottom,
            secondItem: originalContentView,
            secondAttribute: .bottom,
            constant: 0
        )
    }
    var debugQuotaSectionView: SubscriptionQuotaSectionView { quotaSectionView }
    /// 原统计区在根视图中的 frame（非 flipped 坐标）。
    var debugOriginalContentFrame: NSRect {
        originalContentView.convert(originalContentView.bounds, to: view)
    }
    /// 新增订阅区在根视图中的 frame（非 flipped 坐标）。
    var debugQuotaSectionFrame: NSRect {
        quotaSectionView.convert(quotaSectionView.bounds, to: view)
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
    func debugSetLoadingOverlayVisible(_ isVisible: Bool) {
        loadingOverlay.setLoading(isVisible)
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

    /// 未购买时用户点击订阅区解锁入口；由状态栏控制器负责关闭弹窗并打开设置页。
    var onRequestQuotaUnlock: (() -> Void)?

    init(
        viewModel: TokenStatsViewModel,
        quotaStore: SubscriptionQuotaStore = SubscriptionQuotaStore(),
        nowProvider: @escaping () -> Date = Date.init,
        calendar: Calendar = .current,
        languageSettings: AppLanguageSettings = .shared,
        quotaAccess: SubscriptionQuotaAccess = SubscriptionQuotaAccess(isUnlocked: false)
    ) {
        self.viewModel = viewModel
        self.quotaStore = quotaStore
        self.quotaAccess = quotaAccess
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
        let root = DashboardGlassBackgroundView(
            frame: NSRect(origin: .zero, size: Self.contentSize),
            acceptsFirstResponder: true
        )
        root.userInterfaceLayoutDirection = .leftToRight
        view = root
        setupSubviews()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        render()
        renderQuota()
        observerToken = viewModel.observe { [weak self] _ in
            self?.render()
        }
        quotaObserverToken = quotaStore.observe { [weak self] in
            self?.renderQuota()
        }
        quotaAccessObserverToken = quotaAccess.observe { [weak self] in
            self?.renderQuota()
        }
        languageSettingsObserverToken = languageSettings.observe { [weak self] in
            self?.render()
            self?.renderQuota()
        }
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        DashboardAppearanceRefresh.refresh(in: view)
        renderQuota()
        startQuotaPresentationTimer()
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        stopQuotaPresentationTimer()
        quotaSectionView.closeInfoPopover()
    }

    /// 判断窗口是否属于本弹窗派生的说明气泡；状态栏控制器据此不把气泡内点击当作外部点击。
    /// - Parameter windowNumber: 鼠标事件所在窗口编号。
    /// - Returns: 是订阅区说明气泡的窗口时为 true。
    func ownsAuxiliaryWindow(withNumber windowNumber: Int) -> Bool {
        quotaSectionView.infoPopoverWindowNumber == windowNumber
    }

    deinit {
        MainActor.assumeIsolated {
            quotaPresentationTimer?.invalidate()
            if let observerToken {
                viewModel.removeObserver(observerToken)
            }
            if let quotaObserverToken {
                quotaStore.removeObserver(quotaObserverToken)
            }
            if let quotaAccessObserverToken {
                quotaAccess.removeObserver(quotaAccessObserverToken)
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
        todayDescriptionLabel.textColor = DashboardPalette.primaryText
        todayDescriptionLabel.alignment = .left
        todayDescriptionLabel.lineBreakMode = .byTruncatingTail
        todayDescriptionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        todayDescriptionLabel.translatesAutoresizingMaskIntoConstraints = false

        configureTodayRefreshButton()

        hoverLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        hoverLabel.textColor = DashboardPalette.secondaryText
        hoverLabel.alignment = .right
        hoverLabel.lineBreakMode = .byTruncatingMiddle
        hoverLabel.translatesAutoresizingMaskIntoConstraints = false

        heatmapCard.translatesAutoresizingMaskIntoConstraints = false

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

        quotaSectionView.onAction = { [weak self] action in
            self?.performQuotaAction(action)
        }
        quotaSectionView.onUnlock = { [weak self] in
            self?.onRequestQuotaUnlock?()
        }
        originalContentView.translatesAutoresizingMaskIntoConstraints = false
        addToRootGlass(quotaSectionView)
        addToRootGlass(originalContentView)

        todayDescriptionRow.addSubview(todayDescriptionLabel)
        todayDescriptionRow.addSubview(todayRefreshButton)
        originalContentView.addSubview(todayDescriptionRow)
        originalContentView.addSubview(summaryStack)
        originalContentView.addSubview(heatmapCard)
        originalContentView.addSubview(hoverLabel)
        originalContentView.addSubview(collectionView)
        originalContentView.addSubview(hourlyLineChartView)
        originalContentView.addSubview(loadingOverlay)

        NSLayoutConstraint.activate([
            quotaSectionView.topAnchor.constraint(equalTo: view.topAnchor),
            quotaSectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            quotaSectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            originalContentView.topAnchor.constraint(equalTo: quotaSectionView.bottomAnchor),
            originalContentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            originalContentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            originalContentView.heightAnchor.constraint(equalToConstant: Self.originalContentSize.height),
            originalContentView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            todayDescriptionRow.topAnchor.constraint(equalTo: originalContentView.topAnchor, constant: Self.outerMargin),
            todayDescriptionRow.leadingAnchor.constraint(equalTo: heatmapCard.leadingAnchor),
            todayDescriptionRow.trailingAnchor.constraint(equalTo: heatmapCard.trailingAnchor),
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
            summaryStack.leadingAnchor.constraint(equalTo: heatmapCard.leadingAnchor),
            summaryStack.trailingAnchor.constraint(equalTo: heatmapCard.trailingAnchor),
            summaryStack.heightAnchor.constraint(equalToConstant: Self.summaryCardHeight),

            heatmapCard.leadingAnchor.constraint(
                equalTo: collectionView.leadingAnchor,
                constant: -Self.heatmapCardHorizontalPadding
            ),
            heatmapCard.trailingAnchor.constraint(
                equalTo: collectionView.trailingAnchor,
                constant: Self.heatmapCardHorizontalPadding
            ),
            heatmapCard.topAnchor.constraint(equalTo: summaryStack.bottomAnchor, constant: 6),
            heatmapCard.bottomAnchor.constraint(equalTo: collectionView.bottomAnchor, constant: 8),

            hoverLabel.leadingAnchor.constraint(equalTo: collectionView.leadingAnchor),
            hoverLabel.trailingAnchor.constraint(equalTo: collectionView.trailingAnchor),
            hoverLabel.bottomAnchor.constraint(equalTo: collectionView.topAnchor, constant: -1),

            collectionView.topAnchor.constraint(equalTo: summaryStack.bottomAnchor, constant: 21),
            collectionView.centerXAnchor.constraint(equalTo: originalContentView.centerXAnchor),
            collectionView.widthAnchor.constraint(equalToConstant: Self.collectionWidth),
            collectionView.heightAnchor.constraint(equalToConstant: Self.collectionHeight),
            collectionView.bottomAnchor.constraint(
                lessThanOrEqualTo: originalContentView.bottomAnchor,
                constant: -Self.outerMargin
            ),

            hourlyLineChartView.topAnchor.constraint(
                equalTo: collectionView.bottomAnchor,
                constant: Self.hourlyLineChartTopSpacing
            ),
            hourlyLineChartView.leadingAnchor.constraint(equalTo: heatmapCard.leadingAnchor),
            hourlyLineChartView.trailingAnchor.constraint(equalTo: heatmapCard.trailingAnchor),
            hourlyLineChartView.heightAnchor.constraint(equalToConstant: Self.hourlyLineChartHeight),
            hourlyLineChartView.bottomAnchor.constraint(
                lessThanOrEqualTo: originalContentView.bottomAnchor,
                constant: -Self.outerMargin
            ),

            loadingOverlay.leadingAnchor.constraint(equalTo: originalContentView.leadingAnchor),
            loadingOverlay.trailingAnchor.constraint(equalTo: originalContentView.trailingAnchor),
            loadingOverlay.topAnchor.constraint(equalTo: originalContentView.topAnchor),
            loadingOverlay.bottomAnchor.constraint(equalTo: originalContentView.bottomAnchor),
        ])
    }

    /// 将弹窗内容添加到与主界面一致的玻璃 contentView，避免内容覆盖原生玻璃效果。
    private func addToRootGlass(_ subview: NSView) {
        if let rootView = view as? DashboardGlassBackgroundView {
            rootView.addContentSubview(subview)
        } else {
            view.addSubview(subview)
        }
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
        todayRefreshButton.contentTintColor = DashboardPalette.secondaryText
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
        // 原刷新入口追加本地额度读取；额度未解锁时不读取。按钮样式与统计刷新行为保持不变。
        if quotaAccess.isUnlocked {
            let quotaStore = self.quotaStore
            Task { @MainActor in
                await quotaStore.refresh()
            }
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await viewModel.loadAllStats()
            applyRefreshButtonLoadingState()
        }
    }

    /// 处理订阅区的授权入口；另一个工具的展示不受影响。
    private func performQuotaAction(_ action: SubscriptionQuotaProviderPresentation.Action) {
        let quotaStore = self.quotaStore
        let viewModel = self.viewModel
        switch action {
        case .chooseClaudeFile:
            Task { @MainActor in
                await quotaStore.requestClaudeFileAuthorization()
            }
        case .authorizeCodexDirectory:
            Task { @MainActor in
                guard await viewModel.requestAuthorization(for: .codex) else { return }
                await quotaStore.refresh()
            }
        }
    }

    /// 只重绘订阅区；统计数据失败或加载不会覆盖该区域，反之亦然。
    private func renderQuota() {
        let now = nowProvider()
        let language = languageSettings.resolvedLanguage
        quotaSectionView.applyInfo(
            text: [
                AppStrings.text(.quotaDataSourceInfo, language: language),
                SubscriptionQuotaPresenter.resetInferredNote(language: language),
            ].joined(separator: "\n\n"),
            accessibilityLabel: AppStrings.text(.quotaSectionTitle, language: language)
        )
        guard quotaAccess.isUnlocked else {
            quotaSectionView.applyLocked(
                title: AppStrings.text(.quotaSectionTitle, language: language),
                message: AppStrings.text(.quotaPremiumLockedMessage, language: language),
                unlockTitle: AppStrings.text(.quotaUnlockAction, language: language)
            )
            return
        }
        let presentations = SubscriptionQuotaProvider.allCases.map { provider in
            SubscriptionQuotaPresenter.make(
                provider: provider,
                state: quotaStore.state(for: provider),
                now: now,
                language: language
            )
        }
        quotaSectionView.apply(
            title: AppStrings.text(.quotaSectionTitle, language: language),
            presentations: presentations
        )
    }

    private func startQuotaPresentationTimer() {
        guard quotaPresentationTimer == nil else { return }
        let timer = Timer(timeInterval: Self.quotaPresentationTickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.renderQuota()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        quotaPresentationTimer = timer
    }

    private func stopQuotaPresentationTimer() {
        quotaPresentationTimer?.invalidate()
        quotaPresentationTimer = nil
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
        loadingOverlay.update(language: language)
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
        loadingOverlay.setLoading(viewModel.states.values.contains { $0.isLoading })
        DashboardAppearanceRefresh.refresh(in: view)
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
        let rate = TokenBurnRateCalculator.calculateRate(
            states: viewModel.states,
            now: nowProvider()
        )
        let baseText = StatusPopoverDailyTokenDescription.text(
            forTodayTokens: todayTokens,
            language: language
        )
        todayDescriptionLabel.stringValue = TokenBurnRateCalculator.descriptionText(
            baseText: baseText,
            todayTokens: todayTokens,
            rate: rate,
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
    let borderColor: NSColor
    let borderWidth: CGFloat
    let cornerRadius: CGFloat

    static let neutral = SummaryMetricCardStyle(
        name: "neutral",
        backgroundColor: DashboardPalette.panelBackground,
        borderColor: DashboardPalette.border,
        borderWidth: 1,
        cornerRadius: 8
    )
}

private final class SummaryMetricCardView: NSView, DashboardAppearanceRefreshable {
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
        titleLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        titleLabel.textColor = DashboardPalette.secondaryText
        titleLabel.lineBreakMode = .byTruncatingTail

        valueLabel.alignment = .center
        valueLabel.font = .systemFont(ofSize: 16, weight: .bold)
        valueLabel.textColor = DashboardPalette.primaryText
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
        refreshDashboardAppearance()
    }

    func refreshDashboardAppearance() {
        updateCardColors()
    }

    func configure(title: String, value: String, tokenUnit: String) {
        titleLabel.stringValue = title
        valueLabel.stringValue = value
        toolTip = "\(titleLabel.stringValue) \(value) \(tokenUnit)"
    }

    private func updateCardColors() {
        layer?.cornerRadius = style.cornerRadius
        layer?.backgroundColor = DashboardLayerColor.cgColor(style.backgroundColor, for: self)
        layer?.borderColor = DashboardLayerColor.cgColor(style.borderColor, for: self)
        layer?.borderWidth = style.borderWidth
    }
}

/// 覆盖状态栏弹窗和主界面内容区的加载层。
///
/// 使用系统 `NSVisualEffectView` 材质形成液态玻璃效果，并复用状态栏的 SF Symbol
/// 动画帧，使首次扫描期间的反馈与菜单栏图标保持一致。
@MainActor
final class LoadingOverlayView: NSVisualEffectView {
    private let imageView = NSImageView()
    private let messageLabel = NSTextField(labelWithString: "")
    private var animationTimer: Timer?
    private var animationFrameIndex = 0
    private var isLoading = false
    private(set) var debugSymbolName: String?
    var debugMessage: String { messageLabel.stringValue }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        isEmphasized = true
        isHidden = true
        translatesAutoresizingMaskIntoConstraints = false
        update(language: .en)

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false

        messageLabel.font = .systemFont(ofSize: 13, weight: .medium)
        messageLabel.textColor = .labelColor
        messageLabel.alignment = .center
        messageLabel.lineBreakMode = .byTruncatingTail
        messageLabel.translatesAutoresizingMaskIntoConstraints = false

        let contentStack = NSStackView(views: [imageView, messageLabel])
        contentStack.orientation = .vertical
        contentStack.alignment = .centerX
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)

        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 48),
            imageView.heightAnchor.constraint(equalToConstant: 48),
            contentStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            messageLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
            messageLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("LoadingOverlayView 不支持 storyboard 初始化")
    }

    deinit {
        MainActor.assumeIsolated {
            animationTimer?.invalidate()
        }
    }

    /// 切换遮罩可见状态，并同步启停图标动画以避免在隐藏时持续重绘。
    func setLoading(_ isLoading: Bool) {
        guard self.isLoading != isLoading else { return }

        self.isLoading = isLoading
        isHidden = !isLoading
        if isLoading {
            startAnimation()
        } else {
            stopAnimation()
        }
    }

    /// Updates visible and accessibility copy for the selected app language.
    func update(language: AppLanguage) {
        let message = AppStrings.text(.statusLoadingUsage, language: language)
        messageLabel.stringValue = message
        setAccessibilityLabel(message)
        if isLoading {
            renderAnimationFrame()
        }
    }

    private func startAnimation() {
        guard animationTimer == nil else { return }

        animationFrameIndex = 0
        renderAnimationFrame()
        let timer = Timer(timeInterval: StatusBarLoadingAnimation.frameInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advanceAnimationFrame()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        animationFrameIndex = 0
    }

    private func advanceAnimationFrame() {
        animationFrameIndex = StatusBarLoadingAnimation.nextFrameIndex(after: animationFrameIndex)
        renderAnimationFrame()
    }

    private func renderAnimationFrame() {
        let symbolName = StatusBarLoadingAnimation.symbolNames[animationFrameIndex]
        let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: messageLabel.stringValue
        )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 42, weight: .regular))
        image?.isTemplate = true
        imageView.image = image
        debugSymbolName = image == nil ? nil : symbolName
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
        heatmapItem.configure(
            with: cell,
            language: languageSettings.resolvedLanguage,
            calendar: calendar
        )
        return heatmapItem
    }
}
