import AppKit

/// 跨 provider 的全量 token 消耗总计页面。
final class TotalStatsViewController: NSViewController {
    private static let contentWidth: CGFloat = 520

    private let totalTitleLabel = NSTextField(labelWithString: "总 token")
    private let totalLabel = NSTextField(labelWithString: "0.0M")
    private let costTitleLabel = NSTextField(labelWithString: "总费用")
    private let costLabel = NSTextField(labelWithString: "$0.00")
    private let modelSectionTitleLabel = NSTextField(labelWithString: "模型消耗")
    private let modelRowsStack = NSStackView()
    private let emptyModelLabel = NSTextField(labelWithString: "暂无模型数据")
    private let statusLabel = NSTextField(labelWithString: "")
    private let stateProvider: @MainActor () -> [ProviderID: TokenStatsViewModel.ProviderState]
    private var modelRowLabels: [String] = []
    private var modelRowTokenTexts: [String] = []

    init(
        stateProvider: @escaping @MainActor () -> [ProviderID: TokenStatsViewModel.ProviderState] = {
            (NSApp.delegate as? AppDelegate)?.viewModel.states ?? [:]
        }
    ) {
        self.stateProvider = stateProvider
        super.init(nibName: nil, bundle: nil)
        self.title = "总计"
    }

    var debugTotalText: String {
        totalLabel.stringValue
    }

    var debugStatusText: String {
        statusLabel.stringValue
    }

    var debugModelRowLabels: [String] {
        modelRowLabels
    }

    var debugModelRowTokenTexts: [String] {
        modelRowTokenTexts
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
        configureMetricTitle(totalTitleLabel)
        configureMetricTitle(costTitleLabel)
        totalLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .medium)
        totalLabel.alignment = .left
        costLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .medium)
        costLabel.textColor = .secondaryLabelColor
        costLabel.alignment = .left
        modelSectionTitleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        modelSectionTitleLabel.alignment = .left
        emptyModelLabel.font = .systemFont(ofSize: 12)
        emptyModelLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 0
        statusLabel.lineBreakMode = .byWordWrapping

        let totalMetricStack = makeMetricStack(titleLabel: totalTitleLabel, valueLabel: totalLabel)
        let costMetricStack = makeMetricStack(titleLabel: costTitleLabel, valueLabel: costLabel)
        let summaryStack = NSStackView(views: [totalMetricStack, costMetricStack])
        summaryStack.orientation = .vertical
        summaryStack.alignment = .leading
        summaryStack.spacing = 10

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

        let contentStack = NSStackView(views: [summaryStack, modelSectionStack, statusLabel])
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
            contentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor),

            contentStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            summaryStack.leadingAnchor.constraint(equalTo: contentStack.leadingAnchor),
            summaryStack.widthAnchor.constraint(lessThanOrEqualTo: contentStack.widthAnchor),
            modelSectionStack.leadingAnchor.constraint(equalTo: contentStack.leadingAnchor),
            modelSectionStack.widthAnchor.constraint(equalToConstant: Self.contentWidth),
            modelSectionTitleLabel.leadingAnchor.constraint(equalTo: modelSectionStack.leadingAnchor),
            modelRowsStack.leadingAnchor.constraint(equalTo: modelSectionStack.leadingAnchor),
            modelRowsStack.widthAnchor.constraint(equalTo: modelSectionStack.widthAnchor),
            emptyModelLabel.leadingAnchor.constraint(equalTo: modelSectionStack.leadingAnchor),
            statusLabel.widthAnchor.constraint(lessThanOrEqualTo: contentStack.widthAnchor),
        ])
    }

    private func configureMetricTitle(_ label: NSTextField) {
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .left
    }

    private func makeMetricStack(titleLabel: NSTextField, valueLabel: NSTextField) -> NSStackView {
        let stack = NSStackView(views: [titleLabel, valueLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        return stack
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
        statusLabel.stringValue = statusText(for: snapshot, totalProviderCount: states.count)
        statusLabel.isHidden = statusLabel.stringValue.isEmpty
    }

    private func rebuildModelRows(_ rows: [TotalStatsModelRow]) {
        for view in modelRowsStack.arrangedSubviews {
            modelRowsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        modelRowLabels = rows.map(\.modelName)
        modelRowTokenTexts = rows.map { CompactNumberFormatter.formatMillions($0.totalTokens) }
        emptyModelLabel.isHidden = !rows.isEmpty
        modelRowsStack.isHidden = rows.isEmpty

        for (index, row) in rows.enumerated() {
            modelRowsStack.addArrangedSubview(makeModelRow(row, tokenText: modelRowTokenTexts[index]))
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
            return "部分数据仍在加载"
        }
        if let errorMessage = snapshot.errorMessages.first {
            return errorMessage
        }
        return ""
    }
}
