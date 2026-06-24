import AppKit

/// 跨 provider 的全量 token 消耗总计页面。
final class TotalStatsViewController: NSViewController {
    private static let contentWidth: CGFloat = 520
    private static let horizontalInset: CGFloat = 32
    private static let refreshButtonSize: CGFloat = 20
    private static let refreshButtonSpacing: CGFloat = 8
    private static let refreshButtonDefaultSymbolName = "arrow.clockwise"
    private static let refreshButtonLoadingSymbolName = "arrow.triangle.2.circlepath"
    private static let partialLoadingStatusText = "部分数据仍在加载"

    private let titleLabel = NSTextField(labelWithString: "总计")
    private let subtitleLabel = NSTextField(labelWithString: "跨 provider 全量汇总")
    private let totalLabel = NSTextField(labelWithString: "0.0M")
    private let costLabel = NSTextField(labelWithString: "$0.00")
    private let modelSectionTitleLabel = NSTextField(labelWithString: "模型消耗")
    private let modelRowsStack = NSStackView()
    private let emptyModelLabel = NSTextField(labelWithString: "暂无模型数据")
    private let statusLabel = NSTextField(labelWithString: "")
    private let partialLoadingStatusLabel = NSTextField(labelWithString: "")
    private let stateProvider: @MainActor () -> [ProviderID: TokenStatsViewModel.ProviderState]
    private let refreshAction: @MainActor () async -> Void
    private let refreshButton = RefreshIconButton()
    private var currentRefreshButtonSymbolName: String?
    private var modelRowLabels: [String] = []
    private var modelRowValueTexts: [String] = []

    init(
        stateProvider: @escaping @MainActor () -> [ProviderID: TokenStatsViewModel.ProviderState] = {
            (NSApp.delegate as? AppDelegate)?.viewModel.states ?? [:]
        },
        refreshAction: @escaping @MainActor () async -> Void = {
            if let viewModel = (NSApp.delegate as? AppDelegate)?.viewModel {
                await viewModel.loadAllStats()
            }
        }
    ) {
        self.stateProvider = stateProvider
        self.refreshAction = refreshAction
        super.init(nibName: nil, bundle: nil)
        self.title = "总计"
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
        refreshButton.convert(refreshButton.bounds, to: view)
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
        NotificationCenter.default.removeObserver(self)
    }

    private func setupSubviews() {
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabelColor
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

        let headerTextStack = NSStackView(views: [titleLabel, subtitleLabel])
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
        modelRowsStack.spacing = 8
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
            summaryStack.leadingAnchor.constraint(equalTo: subtitleLabel.trailingAnchor, constant: 16),
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
        refreshButton.toolTip = "立即刷新"
        refreshButton.target = self
        refreshButton.action = #selector(refreshStats(_:))
        refreshButton.setButtonType(.momentaryChange)
        refreshButton.setContentHuggingPriority(.required, for: .horizontal)
        refreshButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        setRefreshButtonLoading(false)
    }

    private func bindNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(providerStateDidChange(_:)),
            name: .providerStateDidChange,
            object: nil
        )
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
        applyStatusText(statusText(for: snapshot, totalProviderCount: states.count))
        applyRefreshButtonLoadingState(states: states)
    }

    private func applyStatusText(_ text: String) {
        if text == Self.partialLoadingStatusText {
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
        setRefreshButtonSymbol(symbolName, accessibilityDescription: isLoading ? "正在刷新" : "立即刷新")

        refreshButton.isEnabled = !isLoading
        refreshButton.toolTip = isLoading ? "正在刷新" : "立即刷新"
        refreshButton.setAccessibilityLabel(isLoading ? "正在刷新总计数据" : "刷新总计数据")
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

        for (index, row) in rows.enumerated() {
            modelRowsStack.addArrangedSubview(makeModelRow(row, tokenText: modelRowValueTexts[index]))
        }
    }

    private func makeModelRow(_ row: TotalStatsModelRow, tokenText: String) -> NSView {
        let nameLabel = NSTextField(labelWithString: row.modelName)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .systemFont(ofSize: 12)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.maximumNumberOfLines = 1
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let tokenLabel = NSTextField(labelWithString: tokenText)
        tokenLabel.translatesAutoresizingMaskIntoConstraints = false
        tokenLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        tokenLabel.textColor = .secondaryLabelColor
        tokenLabel.alignment = .right
        tokenLabel.setContentHuggingPriority(.required, for: .horizontal)
        tokenLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let rowView = NSView()
        rowView.translatesAutoresizingMaskIntoConstraints = false
        rowView.addSubview(nameLabel)
        rowView.addSubview(tokenLabel)
        rowView.toolTip = "\(row.modelName) · \(tokenText)"

        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: rowView.leadingAnchor),
            nameLabel.topAnchor.constraint(equalTo: rowView.topAnchor),
            nameLabel.bottomAnchor.constraint(equalTo: rowView.bottomAnchor),
            tokenLabel.leadingAnchor.constraint(greaterThanOrEqualTo: nameLabel.trailingAnchor, constant: 12),
            tokenLabel.trailingAnchor.constraint(equalTo: rowView.trailingAnchor),
            tokenLabel.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            tokenLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 72),
        ])
        return rowView
    }

    private func formatCurrency(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    private func formatModelRowValue(_ row: TotalStatsModelRow) -> String {
        "\(formatModelTokens(row.totalTokens)) · \(formatCurrency(row.totalCost))"
    }

    private func formatModelTokens(_ value: Int) -> String {
        if value >= 100_000 {
            return CompactNumberFormatter.formatMillions(value)
        }
        return CompactNumberFormatter.format(value)
    }

    private func statusText(for snapshot: TotalStatsSnapshot, totalProviderCount: Int) -> String {
        if totalProviderCount > 0
            && snapshot.loadingProviderCount == totalProviderCount
            && snapshot.loadedProviderCount == 0 {
            return "正在加载用量数据..."
        }
        if snapshot.loadedProviderCount == 0 && snapshot.unauthorizedProviderCount > 0 {
            return "请先在设置中授权访问用户目录"
        }
        if snapshot.loadedProviderCount == 0, let errorMessage = snapshot.errorMessages.first {
            return errorMessage
        }
        if snapshot.totalTokens == 0 {
            return "总计暂无 token 数据"
        }
        if snapshot.loadingProviderCount > 0 {
            return Self.partialLoadingStatusText
        }
        if let errorMessage = snapshot.errorMessages.first {
            return errorMessage
        }
        return ""
    }
}
