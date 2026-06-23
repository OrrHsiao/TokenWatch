import AppKit

/// 跨 provider 的全量 token 消耗总计页面。
final class TotalStatsViewController: NSViewController {
    private static let contentWidth: CGFloat = 520

    private let titleLabel = NSTextField(labelWithString: "总计")
    private let subtitleLabel = NSTextField(labelWithString: "跨 provider 全量汇总")
    private let totalLabel = NSTextField(labelWithString: "0.0M")
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
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabelColor
        totalLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .medium)
        costLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .medium)
        costLabel.textColor = .secondaryLabelColor
        modelSectionTitleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        emptyModelLabel.font = .systemFont(ofSize: 12)
        emptyModelLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 0
        statusLabel.lineBreakMode = .byWordWrapping

        let headerTextStack = NSStackView(views: [titleLabel, subtitleLabel])
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

        modelRowsStack.orientation = .vertical
        modelRowsStack.alignment = .width
        modelRowsStack.spacing = 8

        let modelSectionStack = NSStackView(views: [modelSectionTitleLabel, modelRowsStack, emptyModelLabel])
        modelSectionStack.orientation = .vertical
        modelSectionStack.alignment = .width
        modelSectionStack.spacing = 10

        let contentStack = NSStackView(views: [headerStack, modelSectionStack, statusLabel])
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
            headerStack.widthAnchor.constraint(equalToConstant: Self.contentWidth),
            modelSectionStack.widthAnchor.constraint(equalToConstant: Self.contentWidth),
            statusLabel.widthAnchor.constraint(lessThanOrEqualTo: contentStack.widthAnchor),
        ])
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
        nameLabel.font = .systemFont(ofSize: 12)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.maximumNumberOfLines = 1
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let tokenLabel = NSTextField(labelWithString: tokenText)
        tokenLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        tokenLabel.textColor = .secondaryLabelColor
        tokenLabel.alignment = .right
        tokenLabel.setContentHuggingPriority(.required, for: .horizontal)
        tokenLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let rowStack = NSStackView(views: [nameLabel, tokenLabel])
        rowStack.orientation = .horizontal
        rowStack.alignment = .centerY
        rowStack.distribution = .fill
        rowStack.spacing = 12
        rowStack.toolTip = "\(row.modelName) · \(tokenText)"

        NSLayoutConstraint.activate([
            tokenLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 72),
        ])
        return rowStack
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
