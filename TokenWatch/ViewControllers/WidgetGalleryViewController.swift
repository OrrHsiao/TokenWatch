import AppKit
import Charts
import SwiftUI

private final class WidgetPurchaseStatusTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let contentRect = super.drawingRect(forBounds: rect)
        guard let font else { return contentRect }

        // AppKit keeps the native label baseline when the badge stretches to 24pt,
        // so constrain the single text line around the badge's vertical midpoint.
        let lineHeight = min(
            ceil(font.ascender - font.descender + font.leading),
            contentRect.height
        )
        return NSRect(
            x: contentRect.minX,
            y: floor(contentRect.midY - lineHeight / 2),
            width: contentRect.width,
            height: lineHeight
        )
    }
}

private final class WidgetPurchaseStatusTextField: NSTextField {
    override class var cellClass: AnyClass? {
        get { WidgetPurchaseStatusTextFieldCell.self }
        set {}
    }
}

/// 展示当前桌面小组件的固定示例，便于在应用内查看可用样式。
@MainActor
final class WidgetGalleryViewController: NSViewController {
    private static let pageInset: CGFloat = 28
    private static let rowGap: CGFloat = 18
    private static let minimumContentWidth: CGFloat = 860

    /// WidgetKit 可因展示上下文调整实际尺寸；此值是图库使用的 macOS 中号小组件参考画布。
    static let systemMediumPreviewSize = CGSize(width: 329, height: 155)
    static let systemSmallPreviewSize = CGSize(width: 155, height: 155)

    private let scrollView = NSScrollView()
    private let contentView = NSView()
    private let contentStack = NSStackView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let purchaseCard = DashboardGlassCardView(cornerRadius: 16)
    private let purchaseTitleLabel = NSTextField(labelWithString: "")
    private let purchaseDescriptionLabel = NSTextField(labelWithString: "")
    private let purchaseStatusLabel = WidgetPurchaseStatusTextField(labelWithString: "")
    private let purchaseMessageLabel = NSTextField(labelWithString: "")
    private let purchaseButton = DashboardRangeButton(title: "", target: nil, action: nil)
    private let restoreButton = DashboardRangeButton(title: "", target: nil, action: nil)
    private let purchaseProgressIndicator = NSProgressIndicator()
    private let heatmapSectionTitleLabel = NSTextField(labelWithString: "")
    private let hourlyLineSectionTitleLabel = NSTextField(labelWithString: "")
    private let weeklySummarySectionTitleLabel = NSTextField(labelWithString: "")
    private let todayAnomalySectionTitleLabel = NSTextField(labelWithString: "")
    private let monthlyBudgetSectionTitleLabel = NSTextField(labelWithString: "")
    private let projectFocusSectionTitleLabel = NSTextField(labelWithString: "")
    private let modelFocusSectionTitleLabel = NSTextField(labelWithString: "")
    private let heatmapPreviewHost = NSHostingView(rootView: AnyView(EmptyView()))
    private let hourlyLinePreviewHost = NSHostingView(rootView: AnyView(EmptyView()))
    private let weeklySmallPreviewHost = NSHostingView(rootView: AnyView(EmptyView()))
    private let weeklyMediumPreviewHost = NSHostingView(rootView: AnyView(EmptyView()))
    private let monthlyBudgetPreviewHost = NSHostingView(rootView: AnyView(EmptyView()))
    private let todayAnomalySmallPreviewHost = NSHostingView(rootView: AnyView(EmptyView()))
    private let todayAnomalyMediumPreviewHost = NSHostingView(rootView: AnyView(EmptyView()))
    private let projectFocusPreviewHost = NSHostingView(rootView: AnyView(EmptyView()))
    private let modelFocusPreviewHost = NSHostingView(rootView: AnyView(EmptyView()))
    private let heatmapPreviewContainer = NSView()
    private let hourlyLinePreviewContainer = NSView()
    private let weeklySmallPreviewContainer = NSView()
    private let weeklyMediumPreviewContainer = NSView()
    private let monthlyBudgetPreviewContainer = NSView()
    private let todayAnomalySmallPreviewContainer = NSView()
    private let todayAnomalyMediumPreviewContainer = NSView()
    private let projectFocusPreviewContainer = NSView()
    private let modelFocusPreviewContainer = NSView()

    private let purchaseController: WidgetPurchaseController?
    private var purchaseObservationToken: WidgetPurchaseController.ObservationToken?
    private var renderedLanguage: AppLanguage = .en

    init(purchaseController: WidgetPurchaseController? = nil) {
        self.purchaseController = purchaseController
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("WidgetGalleryViewController 必须使用代码 initializer 构造")
    }

    override func loadView() {
        let root = NSView()
        root.userInterfaceLayoutDirection = .leftToRight
        root.identifier = NSUserInterfaceItemIdentifier("DashboardWidgetsPage")
        root.setAccessibilityIdentifier("DashboardWidgetsPage")
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupLayout()
        subscribeToPurchaseState()
    }

    deinit {
        MainActor.assumeIsolated {
            if let purchaseObservationToken {
                purchaseController?.removeObserver(purchaseObservationToken)
            }
        }
    }

    /// 用当前语言生成固定示例快照并更新所有小组件预览。
    /// - Parameters:
    ///   - now: 用于突出示例中的当前小时并生成本地日期文案。
    ///   - calendar: 定义示例日期和当前小时的本地日历。
    ///   - language: 主应用当前使用的文案语言。
    func render(now: Date, calendar: Calendar, language: AppLanguage) {
        guard isViewLoaded else { return }

        renderedLanguage = language

        titleLabel.stringValue = AppStrings.text(.dashboardWidgetsTitle, language: language)
        subtitleLabel.stringValue = AppStrings.text(.dashboardWidgetsSubtitle, language: language)
        renderPurchaseState()

        let state = WidgetUsageEntryState.placeholder(
            WidgetGallerySampleSnapshotFactory.make(
                now: now,
                calendar: calendar,
                language: language
            )
        )
        let heatmap = WidgetChartPresentationBuilder.heatmap(for: state)
        let hourlyLine = WidgetChartPresentationBuilder.hourlyLine(for: state)
        let weeklySummary = WidgetChartPresentationBuilder.weeklySummary(for: state)
        let monthlyBudget = WidgetChartPresentationBuilder.monthlyBudget(for: state)
        let todayAnomaly = WidgetChartPresentationBuilder.todayAnomaly(for: state)
        let projectFocus = WidgetChartPresentationBuilder.projectFocus(for: state)
        let modelFocus = WidgetChartPresentationBuilder.modelFocus(for: state)
        heatmapSectionTitleLabel.stringValue = heatmap.title
        hourlyLineSectionTitleLabel.stringValue = AppStrings.text(
            .dashboardTrendTitle,
            language: language
        )
        weeklySummarySectionTitleLabel.stringValue = weeklySummary.title
        todayAnomalySectionTitleLabel.stringValue = todayAnomaly.title
        monthlyBudgetSectionTitleLabel.stringValue = monthlyBudget.title
        projectFocusSectionTitleLabel.stringValue = projectFocus.title
        modelFocusSectionTitleLabel.stringValue = modelFocus.title
        heatmapPreviewContainer.setAccessibilityLabel(heatmap.title)
        hourlyLinePreviewContainer.setAccessibilityLabel(hourlyLine.title)
        weeklySmallPreviewContainer.setAccessibilityLabel(weeklySummary.title)
        weeklyMediumPreviewContainer.setAccessibilityLabel(weeklySummary.title)
        monthlyBudgetPreviewContainer.setAccessibilityLabel(monthlyBudget.title)
        todayAnomalySmallPreviewContainer.setAccessibilityLabel(todayAnomaly.title)
        todayAnomalyMediumPreviewContainer.setAccessibilityLabel(todayAnomaly.title)
        projectFocusPreviewContainer.setAccessibilityLabel(projectFocus.title)
        modelFocusPreviewContainer.setAccessibilityLabel(modelFocus.title)
        heatmapPreviewHost.rootView = AnyView(
            WidgetGalleryPreviewSurface {
                WidgetGalleryHeatmapPreview(presentation: heatmap)
            }
        )
        hourlyLinePreviewHost.rootView = AnyView(
            WidgetGalleryPreviewSurface {
                WidgetGalleryHourlyLinePreview(presentation: hourlyLine, language: language)
            }
        )
        weeklySmallPreviewHost.rootView = AnyView(
            WidgetGalleryPreviewSurface {
                WidgetGalleryWeeklySummaryPreview(
                    presentation: weeklySummary,
                    language: language,
                    isCompact: true
                )
            }
        )
        weeklyMediumPreviewHost.rootView = AnyView(
            WidgetGalleryPreviewSurface {
                WidgetGalleryWeeklySummaryPreview(
                    presentation: weeklySummary,
                    language: language,
                    isCompact: false
                )
            }
        )
        monthlyBudgetPreviewHost.rootView = AnyView(
            WidgetGalleryPreviewSurface {
                WidgetGalleryMonthlyBudgetPreview(presentation: monthlyBudget)
            }
        )
        todayAnomalySmallPreviewHost.rootView = AnyView(
            WidgetGalleryPreviewSurface {
                WidgetGalleryTodayAnomalyPreview(
                    presentation: todayAnomaly,
                    showsChart: false,
                    language: language
                )
            }
        )
        todayAnomalyMediumPreviewHost.rootView = AnyView(
            WidgetGalleryPreviewSurface {
                WidgetGalleryTodayAnomalyPreview(
                    presentation: todayAnomaly,
                    showsChart: true,
                    language: language
                )
            }
        )
        projectFocusPreviewHost.rootView = AnyView(
            WidgetGalleryPreviewSurface {
                WidgetGalleryProjectFocusPreview(presentation: projectFocus)
            }
        )
        modelFocusPreviewHost.rootView = AnyView(
            WidgetGalleryPreviewSurface {
                WidgetGalleryModelFocusPreview(presentation: modelFocus)
            }
        )
    }

    private func setupLayout() {
        scrollView.identifier = NSUserInterfaceItemIdentifier("DashboardWidgetsScrollView")
        scrollView.setAccessibilityIdentifier("DashboardWidgetsScrollView")
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = contentView

        contentView.userInterfaceLayoutDirection = .leftToRight
        contentView.translatesAutoresizingMaskIntoConstraints = false

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = Self.rowGap
        contentStack.identifier = NSUserInterfaceItemIdentifier("DashboardWidgetsSection")
        contentStack.setAccessibilityIdentifier("DashboardWidgetsSection")
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(contentStack)

        addFullWidthArrangedSubview(makeHeaderView(), to: contentStack)
        if purchaseController != nil {
            addFullWidthArrangedSubview(makePurchaseCard(), to: contentStack)
        }
        addFullWidthArrangedSubview(
            makeWidgetSection(
                identifier: "heatmap",
                titleLabel: heatmapSectionTitleLabel,
                previewRow: makeHeatmapPreviewRow()
            ),
            to: contentStack
        )
        addFullWidthArrangedSubview(
            makeWidgetSection(
                identifier: "hourlyLine",
                titleLabel: hourlyLineSectionTitleLabel,
                previewRow: makeHourlyLinePreviewRow()
            ),
            to: contentStack
        )
        addFullWidthArrangedSubview(
            makeWidgetSection(
                identifier: "weeklySummary",
                titleLabel: weeklySummarySectionTitleLabel,
                previewRow: makeWeeklySummaryPreviewRow()
            ),
            to: contentStack
        )
        addFullWidthArrangedSubview(
            makeWidgetSection(
                identifier: "todayAnomaly",
                titleLabel: todayAnomalySectionTitleLabel,
                previewRow: makeTodayAnomalyPreviewRow()
            ),
            to: contentStack
        )
        addFullWidthArrangedSubview(
            makeWidgetSection(
                identifier: "monthlyBudget",
                titleLabel: monthlyBudgetSectionTitleLabel,
                previewRow: makeMonthlyBudgetPreviewRow()
            ),
            to: contentStack
        )
        addFullWidthArrangedSubview(
            makeWidgetSection(
                identifier: "projectFocus",
                titleLabel: projectFocusSectionTitleLabel,
                previewRow: makeProjectFocusPreviewRow()
            ),
            to: contentStack
        )
        addFullWidthArrangedSubview(
            makeWidgetSection(
                identifier: "modelFocus",
                titleLabel: modelFocusSectionTitleLabel,
                previewRow: makeModelFocusPreviewRow()
            ),
            to: contentStack
        )

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
            contentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor),
            contentStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Self.pageInset),
            contentStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Self.pageInset),
            contentStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Self.pageInset),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -Self.pageInset),
            contentStack.widthAnchor.constraint(greaterThanOrEqualToConstant: Self.minimumContentWidth),
        ])
    }

    private func makeHeaderView() -> NSView {
        titleLabel.font = .systemFont(ofSize: 26, weight: .bold)
        titleLabel.textColor = DashboardPalette.primaryText
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = DashboardPalette.secondaryText

        let stack = NSStackView(views: [titleLabel, subtitleLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        NSLayoutConstraint.activate([
            stack.heightAnchor.constraint(greaterThanOrEqualToConstant: 64),
        ])
        return stack
    }

    /// Builds the commerce card once; later StoreKit state changes only update its contents.
    private func makePurchaseCard() -> NSView {
        purchaseCard.identifier = NSUserInterfaceItemIdentifier("WidgetPurchaseCard")
        purchaseCard.setAccessibilityIdentifier("WidgetPurchaseCard")
        purchaseCard.setAccessibilityElement(true)
        purchaseCard.setAccessibilityRole(.group)
        purchaseCard.translatesAutoresizingMaskIntoConstraints = false

        purchaseTitleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        purchaseTitleLabel.textColor = DashboardPalette.primaryText
        purchaseTitleLabel.lineBreakMode = .byTruncatingTail
        purchaseTitleLabel.identifier = NSUserInterfaceItemIdentifier("WidgetPurchaseTitle")
        purchaseTitleLabel.setAccessibilityIdentifier("WidgetPurchaseTitle")

        purchaseDescriptionLabel.font = .systemFont(ofSize: 12)
        purchaseDescriptionLabel.textColor = DashboardPalette.secondaryText
        purchaseDescriptionLabel.lineBreakMode = .byWordWrapping
        purchaseDescriptionLabel.maximumNumberOfLines = 2
        purchaseDescriptionLabel.identifier = NSUserInterfaceItemIdentifier(
            "WidgetPurchaseDescription"
        )
        purchaseDescriptionLabel.setAccessibilityIdentifier("WidgetPurchaseDescription")

        purchaseStatusLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        purchaseStatusLabel.alignment = .center
        purchaseStatusLabel.wantsLayer = true
        purchaseStatusLabel.layer?.cornerRadius = 8
        purchaseStatusLabel.identifier = NSUserInterfaceItemIdentifier("WidgetPurchaseStatus")
        purchaseStatusLabel.setAccessibilityIdentifier("WidgetPurchaseStatus")

        purchaseMessageLabel.font = .systemFont(ofSize: 11)
        purchaseMessageLabel.textColor = DashboardPalette.secondaryText
        purchaseMessageLabel.lineBreakMode = .byWordWrapping
        purchaseMessageLabel.maximumNumberOfLines = 2
        purchaseMessageLabel.identifier = NSUserInterfaceItemIdentifier("WidgetPurchaseMessage")
        purchaseMessageLabel.setAccessibilityIdentifier("WidgetPurchaseMessage")

        configurePurchaseButton(purchaseButton, identifier: "WidgetPurchaseButton")
        purchaseButton.target = self
        purchaseButton.action = #selector(purchaseButtonClicked(_:))
        configurePurchaseButton(restoreButton, identifier: "WidgetRestorePurchaseButton")
        restoreButton.target = self
        restoreButton.action = #selector(restoreButtonClicked(_:))

        purchaseProgressIndicator.style = .spinning
        purchaseProgressIndicator.controlSize = .small
        purchaseProgressIndicator.isDisplayedWhenStopped = false
        purchaseProgressIndicator.identifier = NSUserInterfaceItemIdentifier(
            "WidgetPurchaseProgress"
        )
        purchaseProgressIndicator.setAccessibilityIdentifier("WidgetPurchaseProgress")

        let headingSpacer = NSView()
        headingSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        headingSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let headingRow = NSStackView(views: [
            purchaseTitleLabel,
            headingSpacer,
            purchaseStatusLabel,
        ])
        headingRow.orientation = .horizontal
        headingRow.alignment = .centerY
        headingRow.spacing = 12
        purchaseTitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        purchaseTitleLabel.setContentHuggingPriority(.required, for: .horizontal)
        purchaseStatusLabel.setContentHuggingPriority(.required, for: .horizontal)

        let actions = NSStackView(views: [
            purchaseProgressIndicator,
            purchaseButton,
            restoreButton,
        ])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 10
        actions.setContentHuggingPriority(.required, for: .horizontal)
        actions.setContentCompressionResistancePriority(.required, for: .horizontal)

        let detailRow = NSStackView(views: [purchaseDescriptionLabel, actions])
        detailRow.orientation = .horizontal
        detailRow.alignment = .centerY
        detailRow.spacing = 18
        purchaseDescriptionLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        purchaseDescriptionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let cardContent = NSStackView(views: [headingRow, detailRow, purchaseMessageLabel])
        cardContent.orientation = .vertical
        cardContent.alignment = .leading
        cardContent.spacing = 8
        cardContent.translatesAutoresizingMaskIntoConstraints = false
        purchaseCard.addContentSubview(cardContent)

        NSLayoutConstraint.activate([
            cardContent.leadingAnchor.constraint(equalTo: purchaseCard.leadingAnchor, constant: 18),
            cardContent.trailingAnchor.constraint(equalTo: purchaseCard.trailingAnchor, constant: -18),
            cardContent.topAnchor.constraint(equalTo: purchaseCard.topAnchor, constant: 16),
            cardContent.bottomAnchor.constraint(equalTo: purchaseCard.bottomAnchor, constant: -16),
            headingRow.widthAnchor.constraint(equalTo: cardContent.widthAnchor),
            detailRow.widthAnchor.constraint(equalTo: cardContent.widthAnchor),
            purchaseMessageLabel.widthAnchor.constraint(equalTo: cardContent.widthAnchor),
            purchaseStatusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 72),
            purchaseStatusLabel.heightAnchor.constraint(equalToConstant: 24),
            purchaseButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 164),
            restoreButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 132),
        ])
        return purchaseCard
    }

    private func configurePurchaseButton(
        _ button: DashboardRangeButton,
        identifier: String
    ) {
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.alignment = .center
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.layer?.borderWidth = 1
        button.translatesAutoresizingMaskIntoConstraints = false
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
        button.setAccessibilityIdentifier(identifier)
        button.heightAnchor.constraint(equalToConstant: 36).isActive = true
    }

    private func subscribeToPurchaseState() {
        guard let purchaseController else { return }
        purchaseObservationToken = purchaseController.observe { [weak self] _ in
            self?.renderPurchaseState()
        }
        purchaseController.start()
    }

    /// Maps StoreKit state to a stable, reviewable purchase card without displaying raw errors.
    private func renderPurchaseState() {
        guard let purchaseController, isViewLoaded else { return }
        let state = purchaseController.state
        let copy = WidgetPurchaseCopy.make(language: renderedLanguage)
        let isBusy: Bool
        let message: String

        switch state.operation {
        case .loading:
            isBusy = true
            message = copy.loadingMessage
        case .purchasing:
            isBusy = true
            message = copy.purchasingMessage
        case .restoring:
            isBusy = true
            message = copy.restoringMessage
        case .purchasePending:
            isBusy = false
            message = copy.pendingMessage
        case .noPurchasesToRestore:
            isBusy = false
            message = copy.noPurchaseMessage
        case .failed(let failure):
            isBusy = false
            message = purchaseFailureMessage(failure, copy: copy)
        case .idle, .purchaseCompleted, .restoreCompleted:
            isBusy = false
            message = ""
        }

        purchaseTitleLabel.stringValue = state.isUnlocked
            ? copy.unlockedTitle
            : copy.lockedTitle
        purchaseDescriptionLabel.stringValue = state.isUnlocked
            ? copy.unlockedDescription
            : copy.lockedDescription
        purchaseStatusLabel.stringValue = state.isUnlocked
            ? copy.unlockedStatus
            : copy.lockedStatus
        purchaseStatusLabel.textColor = state.isUnlocked
            ? DashboardPalette.green
            : DashboardPalette.yellow
        DashboardLayerColor.applyBackground(
            (state.isUnlocked ? DashboardPalette.green : DashboardPalette.yellow)
                .withAlphaComponent(0.14),
            to: purchaseStatusLabel
        )
        purchaseMessageLabel.stringValue = message
        purchaseMessageLabel.isHidden = message.isEmpty

        if isBusy {
            purchaseProgressIndicator.startAnimation(nil)
        } else {
            purchaseProgressIndicator.stopAnimation(nil)
        }

        purchaseButton.title = state.product.map {
            copy.purchaseTitle(displayPrice: $0.displayPrice)
        } ?? copy.purchaseUnavailableTitle
        purchaseButton.setAccessibilityLabel(purchaseButton.title)
        restoreButton.title = copy.restoreTitle
        restoreButton.setAccessibilityLabel(copy.restoreTitle)
        purchaseButton.isHidden = state.isUnlocked
        restoreButton.isHidden = state.isUnlocked
        purchaseButton.isEnabled = !isBusy && state.product != nil
        restoreButton.isEnabled = !isBusy
        applyPurchaseButtonStyles()
        purchaseCard.setAccessibilityLabel(
            "\(purchaseTitleLabel.stringValue). \(purchaseDescriptionLabel.stringValue)"
        )
    }

    private func purchaseFailureMessage(
        _ failure: WidgetPurchaseFailure,
        copy: WidgetPurchaseCopy
    ) -> String {
        switch failure {
        case .productUnavailable, .productLoadFailed:
            return copy.unavailableMessage
        case .purchaseVerificationFailed:
            return copy.verificationFailedMessage
        case .purchaseFailed, .restoreFailed:
            return copy.failedMessage
        case .entitlementPersistenceFailed:
            return copy.entitlementPersistenceFailedMessage
        }
    }

    private func applyPurchaseButtonStyles() {
        applyPurchaseButtonStyle(
            purchaseButton,
            backgroundColor: DashboardPalette.rangeSelectedBackground,
            borderColor: DashboardPalette.rangeSelectedBorder,
            textColor: DashboardPalette.rangeSelectedText
        )
        applyPurchaseButtonStyle(
            restoreButton,
            backgroundColor: .clear,
            borderColor: DashboardPalette.glassControlBorder,
            textColor: DashboardPalette.primaryText
        )
    }

    private func applyPurchaseButtonStyle(
        _ button: DashboardRangeButton,
        backgroundColor: NSColor,
        borderColor: NSColor,
        textColor: NSColor
    ) {
        let isEnabled = button.isEnabled
        button.setDashboardLayerColors(
            backgroundColor: backgroundColor,
            borderColor: borderColor
        )
        button.alphaValue = isEnabled ? 1 : 0.55
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        button.attributedTitle = NSAttributedString(
            string: button.title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: isEnabled ? textColor : DashboardPalette.secondaryText,
                .paragraphStyle: paragraph,
            ]
        )
    }

    @objc private func purchaseButtonClicked(_ sender: Any?) {
        guard let purchaseController, let window = view.window else { return }
        Task { @MainActor in
            await purchaseController.purchase(in: window)
        }
    }

    @objc private func restoreButtonClicked(_ sender: Any?) {
        guard let purchaseController else { return }
        Task { @MainActor in
            await purchaseController.restorePurchases()
        }
    }

    private func makeHeatmapPreviewRow() -> NSView {
        configurePreviewContainer(
            heatmapPreviewContainer,
            hostingView: heatmapPreviewHost,
            identifier: "DashboardWidgetPreview.heatmap"
        )
        return makeSinglePreviewRow(heatmapPreviewContainer)
    }

    private func makeHourlyLinePreviewRow() -> NSView {
        configurePreviewContainer(
            hourlyLinePreviewContainer,
            hostingView: hourlyLinePreviewHost,
            identifier: "DashboardWidgetPreview.hourlyLine"
        )
        return makeSinglePreviewRow(hourlyLinePreviewContainer)
    }

    private func makeSinglePreviewRow(_ previewContainer: NSView) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(previewContainer)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: Self.systemMediumPreviewSize.height),
            previewContainer.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            previewContainer.topAnchor.constraint(equalTo: row.topAnchor),
        ])
        return row
    }

    private func makeWeeklySummaryPreviewRow() -> NSView {
        configurePreviewContainer(
            weeklySmallPreviewContainer,
            hostingView: weeklySmallPreviewHost,
            identifier: "DashboardWidgetPreview.weeklySummary.small",
            size: Self.systemSmallPreviewSize
        )
        configurePreviewContainer(
            weeklyMediumPreviewContainer,
            hostingView: weeklyMediumPreviewHost,
            identifier: "DashboardWidgetPreview.weeklySummary.medium"
        )

        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(weeklySmallPreviewContainer)
        row.addSubview(weeklyMediumPreviewContainer)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: Self.systemMediumPreviewSize.height),
            weeklySmallPreviewContainer.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            weeklySmallPreviewContainer.topAnchor.constraint(equalTo: row.topAnchor),
            weeklyMediumPreviewContainer.leadingAnchor.constraint(
                equalTo: weeklySmallPreviewContainer.trailingAnchor,
                constant: 16
            ),
            weeklyMediumPreviewContainer.topAnchor.constraint(equalTo: row.topAnchor),
        ])
        return row
    }

    private func makeTodayAnomalyPreviewRow() -> NSView {
        configurePreviewContainer(
            todayAnomalySmallPreviewContainer,
            hostingView: todayAnomalySmallPreviewHost,
            identifier: "DashboardWidgetPreview.todayAnomaly.small",
            size: Self.systemSmallPreviewSize
        )
        configurePreviewContainer(
            todayAnomalyMediumPreviewContainer,
            hostingView: todayAnomalyMediumPreviewHost,
            identifier: "DashboardWidgetPreview.todayAnomaly.medium"
        )

        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(todayAnomalySmallPreviewContainer)
        row.addSubview(todayAnomalyMediumPreviewContainer)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: Self.systemMediumPreviewSize.height),
            todayAnomalySmallPreviewContainer.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            todayAnomalySmallPreviewContainer.topAnchor.constraint(equalTo: row.topAnchor),
            todayAnomalyMediumPreviewContainer.leadingAnchor.constraint(
                equalTo: todayAnomalySmallPreviewContainer.trailingAnchor,
                constant: 16
            ),
            todayAnomalyMediumPreviewContainer.topAnchor.constraint(equalTo: row.topAnchor),
        ])
        return row
    }

    private func makeMonthlyBudgetPreviewRow() -> NSView {
        configurePreviewContainer(
            monthlyBudgetPreviewContainer,
            hostingView: monthlyBudgetPreviewHost,
            identifier: "DashboardWidgetPreview.monthlyBudget"
        )

        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(monthlyBudgetPreviewContainer)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: Self.systemMediumPreviewSize.height),
            monthlyBudgetPreviewContainer.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            monthlyBudgetPreviewContainer.topAnchor.constraint(equalTo: row.topAnchor),
        ])
        return row
    }

    private func makeProjectFocusPreviewRow() -> NSView {
        configurePreviewContainer(
            projectFocusPreviewContainer,
            hostingView: projectFocusPreviewHost,
            identifier: "DashboardWidgetPreview.projectFocus"
        )
        return makeSinglePreviewRow(projectFocusPreviewContainer)
    }

    private func makeModelFocusPreviewRow() -> NSView {
        configurePreviewContainer(
            modelFocusPreviewContainer,
            hostingView: modelFocusPreviewHost,
            identifier: "DashboardWidgetPreview.modelFocus"
        )
        return makeSinglePreviewRow(modelFocusPreviewContainer)
    }

    private func configurePreviewContainer(
        _ container: NSView,
        hostingView: NSHostingView<AnyView>,
        identifier: String,
        size: CGSize? = nil
    ) {
        let previewSize = size ?? Self.systemMediumPreviewSize
        container.identifier = NSUserInterfaceItemIdentifier(identifier)
        container.setAccessibilityIdentifier(identifier)
        container.setAccessibilityElement(true)
        container.setAccessibilityRole(.group)
        container.translatesAutoresizingMaskIntoConstraints = false
        container.setContentHuggingPriority(.required, for: .horizontal)
        container.setContentCompressionResistancePriority(.required, for: .horizontal)
        container.addSubview(hostingView)
        hostingView.identifier = NSUserInterfaceItemIdentifier("\(identifier).content")
        hostingView.setAccessibilityIdentifier("\(identifier).content")
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: previewSize.width),
            container.heightAnchor.constraint(equalToConstant: previewSize.height),
            hostingView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: container.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    /// 将同一种小组件的标题和预览行封装为独立分区，保持图库的扫描顺序清晰。
    private func makeWidgetSection(
        identifier: String,
        titleLabel: NSTextField,
        previewRow: NSView
    ) -> NSStackView {
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = DashboardPalette.primaryText
        titleLabel.identifier = NSUserInterfaceItemIdentifier(
            "DashboardWidgetSectionTitle.\(identifier)"
        )
        titleLabel.setAccessibilityIdentifier(
            "DashboardWidgetSectionTitle.\(identifier)"
        )

        let section = NSStackView(views: [titleLabel, previewRow])
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 8
        section.identifier = NSUserInterfaceItemIdentifier("DashboardWidgetSection.\(identifier)")
        section.setAccessibilityIdentifier("DashboardWidgetSection.\(identifier)")
        section.setAccessibilityElement(true)
        section.setAccessibilityRole(.group)
        section.translatesAutoresizingMaskIntoConstraints = false
        previewRow.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        return section
    }

    private func addFullWidthArrangedSubview(_ view: NSView, to stack: NSStackView) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
}

/// 预览使用固定的、与用户数据无关的样例，以确保首次打开也能看清全部组件样式。
enum WidgetGallerySampleSnapshotFactory {
    /// 构建满足 Widget 固定网格和小时形状约束的本地化示例快照。
    static func make(
        now: Date,
        calendar: Calendar,
        language: AppLanguage
    ) -> WidgetUsageSnapshot {
        let cellCount = WidgetChartVisualStyle.heatmapColumns
            * WidgetChartVisualStyle.heatmapRows
        let cells = (0..<cellCount)
            .map { index in
                let cellDate = calendar.date(
                    byAdding: .day,
                    value: index - (cellCount - 1),
                    to: now
                ) ?? now
                let intensity = sampleHeatmapIntensity(
                    for: cellDate,
                    calendar: calendar
                )
                return WidgetHeatmapCell(
                    dateKey: dayKey(cellDate, calendar: calendar),
                    totalTokens: intensity * 100_000,
                    intensity: intensity,
                    isPlaceholder: false,
                    weekdayLabel: weekdayLabel(
                        for: cellDate,
                        calendar: calendar,
                        language: language
                    )
                )
            }
        let currentHour = calendar.component(.hour, from: now)
        let points = (0...23).map { hour in
            let total = max(0, 18 - abs(14 - hour) * 2) * 100_000
            return WidgetHourlyPoint(
                hour: hour,
                hourKey: "widget-preview-hour-\(hour)",
                hourLabel: "\(hour)",
                totalTokens: total,
                isCurrentHour: hour == currentHour
            )
        }
        let dateText = localizedMonthDay(now, calendar: calendar, language: language)
        let localDayKey = dayKey(now, calendar: calendar)
        let windowStart = calendar.date(byAdding: .day, value: -6, to: now) ?? now
        let windowStartDayKey = dayKey(windowStart, calendar: calendar)
        let monthlyBudgetCopy = MonthlyBudgetCopy.make(language: language)

        return WidgetUsageSnapshot(
            schemaVersion: WidgetSharedConfiguration.schemaVersion,
            generatedAt: now,
            localDayKey: localDayKey,
            localizedText: WidgetLocalizedText(
                heatmapTitle: AppStrings.text(.widgetHeatmapTitle, language: language),
                todayUsageTitle: AppStrings.text(.widgetTodayUsageTitle, language: language),
                datedUsageTitle: String(
                    format: AppStrings.text(.widgetDatedUsageTitleFormat, language: language),
                    dateText
                ),
                updatedThroughTitle: String(
                    format: AppStrings.text(.widgetUpdatedThroughTitleFormat, language: language),
                    dateText
                ),
                notReadyMessage: AppStrings.text(.widgetNotReadyMessage, language: language),
                monthlyBudgetTitle: monthlyBudgetCopy.title,
                monthlyBudgetUnconfiguredMessage: monthlyBudgetCopy.unconfiguredMessage,
                weeklySummaryTitle: UsageStatsPeriod.recent7Days.title(language: language),
                projectFocusTitle: AppStrings.text(.dashboardProjectUsageTitle, language: language),
                projectFocusNoDataMessage: AppStrings.text(.dashboardNoProjectData, language: language),
                modelFocusTitle: AppStrings.text(.dashboardPrimaryModel, language: language),
                modelFocusNoDataMessage: AppStrings.text(.totalEmptyModels, language: language),
                dailyAverageTitle: AppStrings.text(.popoverDailyAverage, language: language),
                shareTitle: AppStrings.text(.dashboardSourceShareTitle, language: language)
            ),
            heatmap: WidgetHeatmapSnapshot(
                totalTokens: cells.reduce(0) { $0 + $1.totalTokens },
                maxDailyTokens: cells.map(\.totalTokens).max() ?? 0,
                cells: cells
            ),
            hourlyLine: WidgetHourlyLineSnapshot(
                dayKey: localDayKey,
                totalTokens: points.reduce(0) { $0 + $1.totalTokens },
                maxHourlyTokens: points.map(\.totalTokens).max() ?? 0,
                points: points
            ),
            monthlyBudget: makeMonthlyBudget(copy: monthlyBudgetCopy),
            projectFocus: WidgetProjectFocusSnapshot(
                windowStartDayKey: windowStartDayKey,
                windowEndDayKey: localDayKey,
                windowTotalTokens: 4_000_000,
                topProjectName: "TokenWatch",
                topProjectTokens: 2_500_000
            ),
            modelFocus: WidgetModelFocusSnapshot(
                windowStartDayKey: windowStartDayKey,
                windowEndDayKey: localDayKey,
                windowTotalTokens: 4_000_000,
                providerName: "Claude",
                modelName: "claude-sonnet-4",
                modelTokens: 2_100_000
            )
        )
    }

    /// 以日期生成稳定但不重复的用量档位，并降低周末活跃度以贴近日常使用分布。
    private static func sampleHeatmapIntensity(
        for date: Date,
        calendar: Calendar
    ) -> Int {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let dateCode = UInt64(
            (components.year ?? 0) * 10_000
                + (components.month ?? 0) * 100
                + (components.day ?? 0)
        )

        // 固定散列让同一日期始终呈现相同档位，避免每次 render 时预览闪动。
        var sample = dateCode &+ 0x9E37_79B9_7F4A_7C15
        sample = (sample ^ (sample >> 30)) &* 0xBF58_476D_1CE4_E5B9
        sample = (sample ^ (sample >> 27)) &* 0x94D0_49BB_1331_11EB
        sample ^= sample >> 31

        let weekendAdjustment = calendar.isDateInWeekend(date) ? 20 : 0
        let activityScore = Int(sample % 100) - weekendAdjustment
        switch activityScore {
        case ..<30: return 0
        case ..<55: return 1
        case ..<75: return 2
        case ..<90: return 3
        default: return WidgetChartVisualStyle.heatmapMaximumIntensity
        }
    }

    private static func makeMonthlyBudget(
        copy: MonthlyBudgetCopy
    ) -> WidgetMonthlyBudgetSnapshot {
        return WidgetMonthlyBudgetSnapshot(
            monthKey: "2026-08",
            spentUSD: 42.75,
            budgetUSD: 100,
            forecastUSD: 86.50,
            title: copy.title,
            forecastTitle: copy.forecastTitle,
            unconfiguredMessage: copy.unconfiguredMessage,
            forecastOverBudgetMessage: copy.forecastOverBudgetMessage
        )
    }

    private static func localizedMonthDay(
        _ date: Date,
        calendar: Calendar,
        language: AppLanguage
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: language.localeIdentifier)
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return formatter.string(from: date)
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private static func weekdayLabel(
        for date: Date,
        calendar: Calendar,
        language: AppLanguage
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: language.localeIdentifier)
        let symbols = language.usesCompactCJKFormatting
            ? formatter.veryShortStandaloneWeekdaySymbols
            : formatter.shortStandaloneWeekdaySymbols
        let index = calendar.component(.weekday, from: date) - 1
        guard let symbols, symbols.indices.contains(index) else {
            return "\(calendar.component(.day, from: date))"
        }
        return symbols[index]
    }
}

private struct WidgetGalleryPreviewSurface<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(WidgetGalleryPreviewAppearance.contentInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                .background,
                in: RoundedRectangle(
                    cornerRadius: WidgetGalleryPreviewAppearance.cornerRadius,
                    style: .continuous
                )
            )
    }
}

private enum WidgetGalleryPreviewAppearance {
    static let contentInset: CGFloat = 16
    static let cornerRadius: CGFloat = 20
}

private struct WidgetGalleryPreviewHeader: View {
    let title: String
    let subtitle: String?
    let total: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Text(total)
                .font(.headline)
                .fontWeight(.semibold)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

private struct WidgetGalleryHeatmapPreview: View {
    let presentation: WidgetHeatmapPresentation
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 8) {
            WidgetGalleryPreviewHeader(
                title: presentation.title,
                subtitle: presentation.subtitle,
                total: presentation.totalText
            )
            ZStack {
                GeometryReader { proxy in
                    let side = CGFloat(WidgetChartVisualStyle.heatmapTileSide(
                        availableWidth: Double(proxy.size.width),
                        availableHeight: Double(proxy.size.height)
                    ))
                    let spacing = CGFloat(WidgetChartVisualStyle.heatmapSpacing)
                    let radius = CGFloat(WidgetChartVisualStyle.heatmapCornerRadius)

                    HStack(spacing: spacing) {
                        ForEach(0..<WidgetChartVisualStyle.heatmapColumns, id: \.self) { column in
                            VStack(spacing: spacing) {
                                ForEach(0..<WidgetChartVisualStyle.heatmapRows, id: \.self) { row in
                                    let index = WidgetChartVisualStyle.heatmapIndex(
                                        column: column,
                                        row: row
                                    )
                                    RoundedRectangle(cornerRadius: radius)
                                        .fill(color(for: presentation.cells[index]))
                                        .frame(width: side, height: side)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    private func color(for cell: WidgetHeatmapPresentationCell) -> Color {
        guard cell.isVisible else { return .clear }
        let rgba = WidgetChartVisualStyle.heatmapRGBA(
            intensity: cell.intensity,
            isDark: colorScheme == .dark
        )
        return Color(
            .sRGB,
            red: rgba.red,
            green: rgba.green,
            blue: rgba.blue,
            opacity: rgba.alpha
        )
    }
}

private struct WidgetGalleryHourlyLinePreview: View {
    let presentation: WidgetHourlyLinePresentation
    let language: AppLanguage
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 8) {
            WidgetGalleryPreviewHeader(
                title: presentation.title,
                subtitle: nil,
                total: presentation.totalText
            )
            Chart {
                ForEach(presentation.points) { point in
                    AreaMark(
                        x: .value(hourAxisValueName, point.hour),
                        y: .value(tokenAxisValueName, point.totalTokens)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(areaGradient)
                }
                ForEach(presentation.points) { point in
                    LineMark(
                        x: .value(hourAxisValueName, point.hour),
                        y: .value(tokenAxisValueName, point.totalTokens)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(
                        lineWidth: CGFloat(WidgetChartVisualStyle.lineWidth),
                        lineCap: .round,
                        lineJoin: .round
                    ))
                }
                if let point = presentation.currentPoint {
                    PointMark(
                        x: .value(hourAxisValueName, point.hour),
                        y: .value(tokenAxisValueName, point.totalTokens)
                    )
                    .foregroundStyle(Color.accentColor)
                    .symbolSize(CGFloat(WidgetChartVisualStyle.currentPointSize))
                }
            }
            .chartLegend(.hidden)
            .chartXScale(domain: 0...23)
            .chartYScale(domain: 0...presentation.maximumY)
            .chartXAxis {
                AxisMarks(values: WidgetChartVisualStyle.hourAxisValues) { value in
                    AxisTick()
                    AxisValueLabel {
                        if let hour = value.as(Int.self) {
                            Text(verbatim: "\(hour)").font(.system(size: 8))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine()
                        .foregroundStyle(.secondary.opacity(WidgetChartVisualStyle.gridOpacity))
                    AxisTick()
                    AxisValueLabel {
                        if let tokens = value.as(Double.self) {
                            Text(WidgetChartNumberFormatter.axis(tokens))
                                .font(.system(size: 8))
                        }
                    }
                }
            }
            .padding(.top, 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    private var areaGradient: LinearGradient {
        let rgba = WidgetChartVisualStyle.heatmapRGBA(
            intensity: WidgetChartVisualStyle.heatmapMaximumIntensity,
            isDark: colorScheme == .dark
        )
        let green = Color(
            .sRGB,
            red: rgba.red,
            green: rgba.green,
            blue: rgba.blue,
            opacity: rgba.alpha
        )
        return LinearGradient(
            colors: [
                green.opacity(WidgetChartVisualStyle.areaPeakOpacity),
                green.opacity(WidgetChartVisualStyle.areaBaselineOpacity),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var hourAxisValueName: String {
        AppStrings.text(.recentDetailsTime, language: language)
    }

    private var tokenAxisValueName: String {
        AppStrings.text(.recentDetailsTokens, language: language)
    }
}

private struct WidgetGalleryWeeklySummaryPreview: View {
    let presentation: WidgetWeeklySummaryPresentation
    let language: AppLanguage
    let isCompact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 4 : 7) {
            if isCompact {
                Text(presentation.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(presentation.totalText)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            } else {
                WidgetGalleryPreviewHeader(
                    title: presentation.title,
                    subtitle: presentation.subtitle,
                    total: presentation.totalText
                )
            }

            if let message = presentation.message {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                weeklyChart
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    @ViewBuilder
    private var weeklyChart: some View {
        if isCompact {
            baseChart
                .chartXAxis(.hidden)
        } else {
            baseChart
                .chartXAxis {
                    AxisMarks(values: presentation.points.map(\.position)) { value in
                        AxisValueLabel {
                            if let position = value.as(Int.self),
                               let point = presentation.points.first(
                                   where: { $0.position == position }
                               ) {
                                Text(point.dayLabel)
                                    .font(.system(size: 9))
                                    .fontWeight(
                                        point.isCurrentDay ? .semibold : .regular
                                    )
                                    .foregroundStyle(
                                        point.isCurrentDay
                                            ? WidgetGalleryMetricPalette.usage
                                            : .secondary
                                    )
                            }
                        }
                    }
                }
        }
    }

    private var baseChart: some View {
        Chart(presentation.points) { point in
            BarMark(
                x: .value(
                    AppStrings.text(.dashboardRangeDay, language: language),
                    point.position
                ),
                y: .value(
                    AppStrings.text(.recentDetailsTokens, language: language),
                    point.totalTokens
                ),
                width: .fixed(isCompact ? 10 : 14)
            )
            .foregroundStyle(
                point.isCurrentDay
                    ? WidgetGalleryMetricPalette.usage
                    : WidgetGalleryMetricPalette.usage.opacity(0.7)
            )
            .clipShape(RoundedRectangle(cornerRadius: 2))
        }
        .chartLegend(.hidden)
        .chartXScale(domain: -0.5...6.5)
        .chartYScale(domain: 0...presentation.maximumY)
        .chartYAxis(.hidden)
        .frame(maxHeight: .infinity)
    }
}

private struct WidgetGalleryMonthlyBudgetPreview: View {
    let presentation: WidgetMonthlyBudgetPresentation
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            WidgetGalleryPreviewHeader(
                title: presentation.title,
                subtitle: presentation.subtitle,
                total: presentation.spentText
            )

            if let budgetText = presentation.budgetText,
               let progress = presentation.progress {
                Text(presentation.spentText)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(2)

                HStack(spacing: 6) {
                    Text(budgetText)
                        .monospacedDigit()
                    if let subtitle = presentation.subtitle {
                        Text(verbatim: "·")
                        Text(subtitle)
                            .lineLimit(1)
                    }
                }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .center, spacing: 10) {
                    progressBar(
                        progress: progress,
                        forecastProgress: presentation.forecastProgress
                    )

                    if let forecastText = presentation.forecastText {
                        Text(forecastText)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(forecastColor)
                            .monospacedDigit()
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 96, alignment: .trailing)
                    }
                }
                .frame(height: 24)
                .layoutPriority(1)
            }

            if let message = presentation.message {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(
                        presentation.isForecastOverBudget ? .red : .secondary
                    )
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    private var forecastColor: Color {
        WidgetGalleryMetricPalette.forecast
    }

    private func progressBar(
        progress: Double,
        forecastProgress: Double?
    ) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width * min(max(progress, 0), 1)
            let markerProgress = forecastProgress.map { min(max($0, 0), 1) }
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.primary.opacity(0.1))
                    .frame(height: 8)
                Capsule()
                    .fill(WidgetGalleryMetricPalette.usage)
                    .frame(width: width, height: 8)

                if let markerProgress {
                    let leadingMarkerX = min(
                        max(proxy.size.width * markerProgress, 1),
                        max(proxy.size.width - 1, 1)
                    )
                    let markerX = layoutDirection == .rightToLeft
                        ? proxy.size.width - leadingMarkerX
                        : leadingMarkerX
                    Path { path in
                        path.move(to: CGPoint(x: markerX, y: 0))
                        path.addLine(
                            to: CGPoint(x: markerX, y: proxy.size.height)
                        )
                    }
                    .stroke(
                        forecastColor,
                        style: StrokeStyle(
                            lineWidth: 2,
                            lineCap: .round,
                            dash: [4, 4]
                        )
                    )
                }
            }
        }
        .frame(height: 24)
    }
}

private struct WidgetGalleryTodayAnomalyPreview: View {
    let presentation: WidgetTodayAnomalyPresentation
    let showsChart: Bool
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(presentation.title)
                .font(.headline)
                .lineLimit(1)
            if let message = presentation.message {
                Spacer(minLength: 0)
                Text(message)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else if showsChart {
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        anomalyTotal
                        differenceIndicator
                        Spacer(minLength: 2)
                        baselineSummary
                    }
                    .frame(width: 102, alignment: .leading)

                    anomalyChart
                }
            } else {
                anomalyTotal
                differenceIndicator
                Spacer(minLength: 2)
                baselineSummary
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    private var anomalyTotal: some View {
        Text(presentation.totalText)
            .font(.system(
                size: showsChart ? 25 : 28,
                weight: .bold,
                design: .rounded
            ))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    @ViewBuilder
    private var differenceIndicator: some View {
        if let difference = presentation.differenceText
            ?? presentation.multiplierText {
            HStack(spacing: 4) {
                Image(systemName: statusSymbol)
                    .font(.caption)
                Text(difference)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            .foregroundStyle(statusColor)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        } else {
            Text(verbatim: "—")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var baselineSummary: some View {
        if let baseline = presentation.baselineText {
            if let baselineTitle = presentation.baselineTitle {
                Text(baselineTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(baseline)
                .font(.title3)
                .fontWeight(.semibold)
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    private var anomalyChart: some View {
        Chart(presentation.points) { point in
                BarMark(
                    x: .value(
                        AppStrings.text(.dashboardRangeDay, language: language),
                        point.position
                    ),
                    y: .value(
                        AppStrings.text(.recentDetailsTokens, language: language),
                        point.totalTokens
                    ),
                    width: .fixed(13)
                )
                .foregroundStyle(color(for: point))
                .clipShape(RoundedRectangle(cornerRadius: 2))
        }
        .chartLegend(.hidden)
        .chartXScale(domain: -0.5...7.5)
        .chartYScale(domain: 0...presentation.maximumY)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(maxHeight: .infinity)
        .chartOverlay { chartProxy in
            if let baselineValue = presentation.baselineValue {
                GeometryReader { geometry in
                    if let plotFrame = chartProxy.plotFrame,
                       let y = chartProxy.position(forY: baselineValue) {
                        let frame = geometry[plotFrame]
                        Path { path in
                            path.move(
                                to: CGPoint(x: frame.minX, y: frame.minY + y)
                            )
                            path.addLine(
                                to: CGPoint(x: frame.maxX, y: frame.minY + y)
                            )
                        }
                        .stroke(
                            Color.primary.opacity(0.65),
                            style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])
                        )
                    }
                }
                .allowsHitTesting(false)
            }
        }
    }

    private var statusColor: Color {
        if presentation.isElevated {
            return .red
        }
        return presentation.differenceText?.hasPrefix("-") == true
            ? .green
            : WidgetGalleryMetricPalette.usage
    }

    private var statusSymbol: String {
        if presentation.isElevated {
            return "arrow.up"
        }
        return presentation.hasComparableBaseline
            ? "checkmark"
            : "circle.dashed"
    }

    private func color(for point: WidgetTodayAnomalyPoint) -> Color {
        guard point.isToday else {
            return WidgetGalleryMetricPalette.usage.opacity(0.7)
        }
        return presentation.isElevated
            ? .red
            : WidgetGalleryMetricPalette.usage
    }
}

private struct WidgetGalleryProjectFocusPreview: View {
    let presentation: WidgetProjectFocusPresentation

    var body: some View {
        WidgetGalleryFocusPreview(
            title: presentation.title,
            subtitle: presentation.subtitle,
            primaryName: presentation.projectName,
            secondaryName: nil,
            total: presentation.totalText,
            shareTitle: presentation.shareTitle,
            share: presentation.shareText,
            progress: presentation.progress,
            accentColor: WidgetGalleryMetricPalette.project,
            message: presentation.message,
            accessibilityLabel: presentation.accessibilityLabel
        )
    }
}

private struct WidgetGalleryModelFocusPreview: View {
    let presentation: WidgetModelFocusPresentation

    var body: some View {
        WidgetGalleryFocusPreview(
            title: presentation.title,
            subtitle: presentation.subtitle,
            primaryName: presentation.modelName,
            secondaryName: presentation.providerName,
            total: presentation.totalText,
            shareTitle: presentation.shareTitle,
            share: presentation.shareText,
            progress: presentation.progress,
            accentColor: WidgetGalleryMetricPalette.model,
            message: presentation.message,
            accessibilityLabel: presentation.accessibilityLabel
        )
    }
}

private struct WidgetGalleryFocusPreview: View {
    let title: String
    let subtitle: String?
    let primaryName: String?
    let secondaryName: String?
    let total: String
    let shareTitle: String?
    let share: String?
    let progress: Double
    let accentColor: Color
    let message: String?
    let accessibilityLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(total)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            if let primaryName {
                Text(primaryName)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let secondaryName {
                    Text(secondaryName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                focusShareSummary
                GeometryReader { proxy in
                    let width = proxy.size.width * min(max(progress, 0), 1)
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.primary.opacity(0.1))
                        Capsule()
                            .fill(accentColor)
                            .frame(width: width)
                    }
                }
                .frame(height: 8)
            } else if let message {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var focusShareSummary: some View {
        if let share {
            HStack(spacing: 4) {
                if let subtitle {
                    Text(subtitle)
                        .lineLimit(1)
                    Text(verbatim: "·")
                }
                if let shareTitle {
                    Text(shareTitle)
                }
                Text(share)
                    .monospacedDigit()
                Spacer(minLength: 0)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
    }
}

private enum WidgetGalleryMetricPalette {
    static let usage = adaptive(
        name: "WidgetGallery.usage",
        light: NSColor(
            srgbRed: 37.0 / 255.0,
            green: 99.0 / 255.0,
            blue: 235.0 / 255.0,
            alpha: 1
        ),
        dark: NSColor(
            srgbRed: 90.0 / 255.0,
            green: 162.0 / 255.0,
            blue: 1,
            alpha: 1
        )
    )
    static let forecast = adaptive(
        name: "WidgetGallery.forecast",
        light: NSColor(
            srgbRed: 154.0 / 255.0,
            green: 87.0 / 255.0,
            blue: 0,
            alpha: 1
        ),
        dark: NSColor(
            srgbRed: 245.0 / 255.0,
            green: 196.0 / 255.0,
            blue: 81.0 / 255.0,
            alpha: 1
        )
    )
    static let project = adaptive(
        name: "WidgetGallery.project",
        light: NSColor(
            srgbRed: 124.0 / 255.0,
            green: 58.0 / 255.0,
            blue: 237.0 / 255.0,
            alpha: 1
        ),
        dark: NSColor(
            srgbRed: 167.0 / 255.0,
            green: 139.0 / 255.0,
            blue: 250.0 / 255.0,
            alpha: 1
        )
    )
    static let model = adaptive(
        name: "WidgetGallery.model",
        light: NSColor(
            srgbRed: 14.0 / 255.0,
            green: 116.0 / 255.0,
            blue: 144.0 / 255.0,
            alpha: 1
        ),
        dark: NSColor(
            srgbRed: 54.0 / 255.0,
            green: 198.0 / 255.0,
            blue: 217.0 / 255.0,
            alpha: 1
        )
    )

    private static func adaptive(
        name: NSColor.Name,
        light: NSColor,
        dark: NSColor
    ) -> Color {
        Color(nsColor: NSColor(name: name) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? dark
                : light
        })
    }
}
