import AppKit

/// 跨 provider 的全量 token 消耗总计页面。
final class TotalStatsViewController: NSViewController {
    private static let contentWidth: CGFloat = 520
    private static let horizontalInset: CGFloat = 32
    private static let refreshButtonSize: CGFloat = 20
    private static let refreshButtonSpacing: CGFloat = 8
    private static let refreshButtonDefaultSymbolName = "arrow.clockwise"
    private static let refreshButtonLoadingSymbolName = "arrow.triangle.2.circlepath"
    private static let modelRankRowHeight: CGFloat = 28
    private static let modelRankBarVerticalInset: CGFloat = 0
    private static let modelRankTextInset: CGFloat = 12
    private static let modelRankValueSpacing: CGFloat = 18
    private static let modelRankValueColumnWidth: CGFloat = 96
    private static let modelRankBarCornerRadius: CGFloat = 4
    private static let modelRankMinimumBarFraction: CGFloat = 0.02
    private static let modelRankBarAlpha: CGFloat = 0.55
    private static let modelRankBarColors: [NSColor] = [
        NSColor(calibratedRed: 0.72, green: 0.96, blue: 0.78, alpha: modelRankBarAlpha),
        NSColor(calibratedRed: 1.00, green: 0.90, blue: 0.64, alpha: modelRankBarAlpha),
        NSColor(calibratedRed: 1.00, green: 0.78, blue: 0.66, alpha: modelRankBarAlpha),
        NSColor(calibratedRed: 0.86, green: 0.70, blue: 0.98, alpha: modelRankBarAlpha),
        NSColor(calibratedRed: 0.80, green: 0.68, blue: 0.96, alpha: modelRankBarAlpha),
        NSColor(calibratedRed: 0.68, green: 0.82, blue: 0.98, alpha: modelRankBarAlpha),
    ]

    private let titleLabel = NSTextField(labelWithString: "")
    private let totalLabel = NSTextField(labelWithString: "0.0M")
    private let costLabel = NSTextField(labelWithString: "$0.00")
    private let modelSectionTitleLabel = NSTextField(labelWithString: "")
    private let modelRowsStack = NSStackView()
    private let emptyModelLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let partialLoadingStatusLabel = NSTextField(labelWithString: "")
    private let stateProvider: @MainActor () -> [ProviderID: TokenStatsViewModel.ProviderState]
    private let refreshAction: @MainActor () async -> Void
    private let languageSettings: AppLanguageSettings
    private let refreshButton = RefreshIconButton()
    private var currentRefreshButtonSymbolName: String?
    private var languageSettingsObserverToken: AppLanguageSettings.ObservationToken?
    private var modelRowLabels: [String] = []
    private var modelRowValueTexts: [String] = []
    private var language: AppLanguage { languageSettings.resolvedLanguage }

    init(
        stateProvider: @escaping @MainActor () -> [ProviderID: TokenStatsViewModel.ProviderState] = {
            (NSApp.delegate as? AppDelegate)?.viewModel.states ?? [:]
        },
        refreshAction: @escaping @MainActor () async -> Void = {
            if let viewModel = (NSApp.delegate as? AppDelegate)?.viewModel {
                await viewModel.loadAllStats()
            }
        },
        languageSettings: AppLanguageSettings = .shared
    ) {
        self.stateProvider = stateProvider
        self.refreshAction = refreshAction
        self.languageSettings = languageSettings
        super.init(nibName: nil, bundle: nil)
        self.title = AppStrings.text(.sidebarTotal, language: languageSettings.resolvedLanguage)
    }

    var debugTotalText: String {
        totalLabel.stringValue
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

    func debugSetRefreshButtonHovering(_ isHovering: Bool) {
        refreshButton.debugSetHovering(isHovering)
    }

    func debugClickRefreshButton() {
        refreshButton.performClick(nil)
    }

    var debugModelRowLabels: [String] {
        modelRowLabels
    }

    var debugModelRowValueTexts: [String] {
        modelRowValueTexts
    }

    required init?(coder: NSCoder) {
        fatalError("TotalStatsViewController 必须用 init(stateProvider:) 构造")
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
        totalLabel.alignment = .natural
        costLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .medium)
        costLabel.textColor = .secondaryLabelColor
        costLabel.alignment = .natural
        modelSectionTitleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        modelSectionTitleLabel.alignment = .left
        emptyModelLabel.font = .systemFont(ofSize: 12)
        emptyModelLabel.textColor = .secondaryLabelColor
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

        let headerTextStack = NSStackView(views: [titleLabel])
        headerTextStack.orientation = .vertical
        headerTextStack.alignment = .leading
        headerTextStack.spacing = 4
        headerTextStack.translatesAutoresizingMaskIntoConstraints = false

        let summaryStack = NSStackView(views: [totalLabel, costLabel])
        summaryStack.orientation = .vertical
        summaryStack.alignment = .leading
        summaryStack.distribution = .fill
        summaryStack.spacing = 4
        summaryStack.setContentHuggingPriority(.required, for: .horizontal)
        summaryStack.translatesAutoresizingMaskIntoConstraints = false

        configureRefreshButton()

        let headerView = NSView()
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(headerTextStack)
        headerView.addSubview(summaryStack)
        headerView.addSubview(refreshButton)
        headerView.addSubview(partialLoadingStatusLabel)

        modelRowsStack.orientation = .vertical
        modelRowsStack.alignment = .width
        modelRowsStack.spacing = 4
        modelRowsStack.translatesAutoresizingMaskIntoConstraints = false
        modelSectionTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyModelLabel.translatesAutoresizingMaskIntoConstraints = false

        let modelSectionStack = NSStackView(views: [modelSectionTitleLabel, modelRowsStack, emptyModelLabel])
        modelSectionStack.orientation = .vertical
        modelSectionStack.alignment = .leading
        modelSectionStack.spacing = 10

        let contentStack = NSStackView(views: [headerView, modelSectionStack, statusLabel])
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.distribution = .fill
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
            contentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor),

            contentStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Self.horizontalInset),
            contentStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Self.horizontalInset),
            contentStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Self.horizontalInset),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -Self.horizontalInset),
            headerView.leadingAnchor.constraint(equalTo: contentStack.leadingAnchor),
            headerView.widthAnchor.constraint(equalToConstant: Self.contentWidth),
            headerTextStack.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            headerTextStack.topAnchor.constraint(equalTo: headerView.topAnchor),
            headerTextStack.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),
            summaryStack.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 16),
            summaryStack.topAnchor.constraint(equalTo: headerView.topAnchor),
            refreshButton.topAnchor.constraint(equalTo: headerView.topAnchor),
            refreshButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            refreshButton.leadingAnchor.constraint(
                greaterThanOrEqualTo: summaryStack.trailingAnchor,
                constant: Self.refreshButtonSpacing
            ),
            refreshButton.widthAnchor.constraint(equalToConstant: Self.refreshButtonSize),
            refreshButton.heightAnchor.constraint(equalToConstant: Self.refreshButtonSize),
            partialLoadingStatusLabel.topAnchor.constraint(equalTo: refreshButton.bottomAnchor, constant: 6),
            partialLoadingStatusLabel.trailingAnchor.constraint(equalTo: refreshButton.trailingAnchor),
            partialLoadingStatusLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: summaryStack.trailingAnchor,
                constant: Self.refreshButtonSpacing
            ),
            partialLoadingStatusLabel.bottomAnchor.constraint(lessThanOrEqualTo: headerView.bottomAnchor),
            modelSectionStack.leadingAnchor.constraint(equalTo: contentStack.leadingAnchor),
            modelSectionStack.widthAnchor.constraint(equalToConstant: Self.contentWidth),
            modelSectionTitleLabel.leadingAnchor.constraint(equalTo: modelSectionStack.leadingAnchor),
            modelRowsStack.leadingAnchor.constraint(equalTo: modelSectionStack.leadingAnchor),
            modelRowsStack.widthAnchor.constraint(equalTo: modelSectionStack.widthAnchor),
            emptyModelLabel.leadingAnchor.constraint(equalTo: modelSectionStack.leadingAnchor),
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
        applyLocalizedText()
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
        let states = stateProvider()
        let snapshot = TotalStatsBuilder.build(states: states)
        totalLabel.stringValue = CompactNumberFormatter.formatMillions(snapshot.totalTokens)
        costLabel.stringValue = formatCurrency(snapshot.totalCost)
        rebuildModelRows(snapshot.modelRows)
        let status = statusText(for: snapshot, totalProviderCount: states.count)
        applyStatusText(status.text, isPartialLoading: status.isPartialLoading)
        applyRefreshButtonLoadingState(states: states)
    }

    private func applyLocalizedText() {
        title = AppStrings.text(.sidebarTotal, language: language)
        titleLabel.stringValue = AppStrings.text(.sidebarTotal, language: language)
        modelSectionTitleLabel.stringValue = AppStrings.text(.totalModelUsage, language: language)
        emptyModelLabel.stringValue = AppStrings.text(.totalEmptyModels, language: language)
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
        refreshButton.setAccessibilityLabel(
            isLoading
                ? AppStrings.text(.refreshingTotalAccessibility, language: language)
                : AppStrings.text(.refreshTotalAccessibility, language: language)
        )
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

    private func rebuildModelRows(_ rows: [TotalStatsModelRow]) {
        for view in modelRowsStack.arrangedSubviews {
            modelRowsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        modelRowLabels = rows.map(\.modelName)
        modelRowValueTexts = rows.map { formatModelRowValue($0) }
        emptyModelLabel.isHidden = !rows.isEmpty
        modelRowsStack.isHidden = rows.isEmpty

        let maxTokens = rows.map(\.totalTokens).max() ?? 0
        let totalModelTokens = rows.reduce(0) { $0 + $1.totalTokens }
        for (index, row) in rows.enumerated() {
            modelRowsStack.addArrangedSubview(
                makeModelRow(
                    row,
                    tokenText: modelRowValueTexts[index],
                    index: index,
                    maxTokens: maxTokens,
                    totalModelTokens: totalModelTokens
                )
            )
        }
    }

    private func makeModelRow(
        _ row: TotalStatsModelRow,
        tokenText: String,
        index: Int,
        maxTokens: Int,
        totalModelTokens: Int
    ) -> NSView {
        let barContainerView = NSView()
        barContainerView.translatesAutoresizingMaskIntoConstraints = false
        let percentageText = formatModelPercentage(tokens: row.totalTokens, totalTokens: totalModelTokens)

        let barView = NSView()
        barView.translatesAutoresizingMaskIntoConstraints = false
        barView.wantsLayer = true
        barView.layer?.cornerRadius = Self.modelRankBarCornerRadius
        barView.layer?.backgroundColor = Self.modelRankBarColor(at: index).cgColor
        barView.setAccessibilityIdentifier("TotalModelRankBar.\(index)")

        let nameLabel = NSTextField(labelWithString: row.modelName)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.maximumNumberOfLines = 1
        nameLabel.textColor = .labelColor
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.setAccessibilityIdentifier("TotalModelRankName.\(index)")

        let tokenLabel = NSTextField(labelWithString: tokenText)
        tokenLabel.translatesAutoresizingMaskIntoConstraints = false
        tokenLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        tokenLabel.textColor = .labelColor
        tokenLabel.alignment = .right
        tokenLabel.setContentHuggingPriority(.required, for: .horizontal)
        tokenLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        tokenLabel.setAccessibilityIdentifier("TotalModelRankValue.\(index)")

        let percentLabel = NSTextField(labelWithString: percentageText)
        percentLabel.translatesAutoresizingMaskIntoConstraints = false
        percentLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        percentLabel.textColor = .secondaryLabelColor
        percentLabel.alignment = .right
        percentLabel.setContentHuggingPriority(.required, for: .horizontal)
        percentLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        percentLabel.setAccessibilityIdentifier("TotalModelRankPercent.\(index)")

        let valueStack = NSStackView(views: [tokenLabel, percentLabel])
        valueStack.translatesAutoresizingMaskIntoConstraints = false
        valueStack.orientation = .vertical
        valueStack.alignment = .trailing
        valueStack.distribution = .fill
        valueStack.spacing = 1
        valueStack.setContentHuggingPriority(.required, for: .horizontal)
        valueStack.setContentCompressionResistancePriority(.required, for: .horizontal)

        let rowView = NSView()
        rowView.translatesAutoresizingMaskIntoConstraints = false
        rowView.setAccessibilityIdentifier("TotalModelRankRow.\(index)")
        rowView.addSubview(barContainerView)
        rowView.addSubview(valueStack)
        rowView.toolTip = "\(row.modelName) · \(tokenText) · \(formatCurrency(row.totalCost))"

        barContainerView.addSubview(barView)
        barContainerView.addSubview(nameLabel)

        NSLayoutConstraint.activate([
            rowView.heightAnchor.constraint(equalToConstant: Self.modelRankRowHeight),
            barContainerView.leadingAnchor.constraint(equalTo: rowView.leadingAnchor),
            barContainerView.topAnchor.constraint(equalTo: rowView.topAnchor),
            barContainerView.bottomAnchor.constraint(equalTo: rowView.bottomAnchor),
            barContainerView.trailingAnchor.constraint(
                equalTo: valueStack.leadingAnchor,
                constant: -Self.modelRankValueSpacing
            ),
            barView.leadingAnchor.constraint(equalTo: barContainerView.leadingAnchor),
            barView.topAnchor.constraint(equalTo: barContainerView.topAnchor, constant: Self.modelRankBarVerticalInset),
            barView.bottomAnchor.constraint(equalTo: barContainerView.bottomAnchor, constant: -Self.modelRankBarVerticalInset),
            barView.widthAnchor.constraint(
                equalTo: barContainerView.widthAnchor,
                multiplier: modelRankBarFraction(tokens: row.totalTokens, maxTokens: maxTokens)
            ),
            nameLabel.leadingAnchor.constraint(
                equalTo: barContainerView.leadingAnchor,
                constant: Self.modelRankTextInset
            ),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: barContainerView.trailingAnchor),
            nameLabel.centerYAnchor.constraint(equalTo: barContainerView.centerYAnchor),
            valueStack.trailingAnchor.constraint(equalTo: rowView.trailingAnchor),
            valueStack.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
            valueStack.widthAnchor.constraint(greaterThanOrEqualToConstant: Self.modelRankValueColumnWidth),
        ])
        return rowView
    }

    private static func modelRankBarColor(at index: Int) -> NSColor {
        modelRankBarColors[index % modelRankBarColors.count]
    }

    private func modelRankBarFraction(tokens: Int, maxTokens: Int) -> CGFloat {
        guard maxTokens > 0 else { return Self.modelRankMinimumBarFraction }
        return max(Self.modelRankMinimumBarFraction, min(1, CGFloat(tokens) / CGFloat(maxTokens)))
    }

    private func formatCurrency(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    private func formatModelRowValue(_ row: TotalStatsModelRow) -> String {
        formatModelTokens(row.totalTokens)
    }

    private func formatModelPercentage(tokens: Int, totalTokens: Int) -> String {
        guard totalTokens > 0 else { return "0%" }
        let percentage = Double(tokens) / Double(totalTokens) * 100
        if tokens > 0 && percentage < 0.1 {
            return "<0.1%"
        }
        let rounded = (percentage * 10).rounded() / 10
        if rounded.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f%%", rounded)
        }
        return String(format: "%.1f%%", rounded)
    }

    private func formatModelTokens(_ value: Int) -> String {
        let digits = String(value)
        guard digits.count > 3 else { return digits }

        var chunks: [String] = []
        var end = digits.endIndex
        while end > digits.startIndex {
            let start = digits.index(end, offsetBy: -3, limitedBy: digits.startIndex) ?? digits.startIndex
            chunks.append(String(digits[start..<end]))
            end = start
        }
        return chunks.reversed().joined(separator: ",")
    }

    private func statusText(for snapshot: TotalStatsSnapshot, totalProviderCount: Int) -> (text: String, isPartialLoading: Bool) {
        if totalProviderCount > 0
            && snapshot.loadingProviderCount == totalProviderCount
            && snapshot.loadedProviderCount == 0 {
            return (AppStrings.text(.statusLoadingUsage, language: language), false)
        }
        if snapshot.loadedProviderCount == 0 && snapshot.unauthorizedProviderCount > 0 {
            return (AppStrings.text(.statusNeedsHomeAuthorization, language: language), false)
        }
        if snapshot.loadedProviderCount == 0, let errorMessage = snapshot.errorMessages.first {
            return (errorMessage, false)
        }
        if snapshot.totalTokens == 0 {
            return (AppStrings.text(.statusTotalNoTokenData, language: language), false)
        }
        if snapshot.loadingProviderCount > 0 {
            return (AppStrings.text(.statusPartialLoading, language: language), true)
        }
        if let errorMessage = snapshot.errorMessages.first {
            return (errorMessage, false)
        }
        return ("", false)
    }
}
