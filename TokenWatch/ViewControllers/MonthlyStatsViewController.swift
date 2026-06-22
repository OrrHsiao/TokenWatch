import AppKit

/// 跨 provider 的按月 token 消耗页面。
final class MonthlyStatsViewController: NSViewController {
    private static let compactBarChartWidth: CGFloat = 520

    private let titleLabel = NSTextField(labelWithString: "按月")
    private let subtitleLabel = NSTextField(labelWithString: "过去 12 个月,跨 provider 汇总")
    private let totalLabel = NSTextField(labelWithString: "0 tokens")
    private let costLabel = NSTextField(labelWithString: "$0.00")
    private let statusLabel = NSTextField(labelWithString: "")
    private let tokenChartTitleLabel = NSTextField(labelWithString: "Token 用量")
    private let costChartTitleLabel = NSTextField(labelWithString: "费用")
    private let chartView = MonthlyTokenChartView()
    private let costChartView = MonthlyCostChartView()
    private let toolSharePieView = UsageSharePieChartView(title: "工具占比")
    private let modelSharePieView = UsageSharePieChartView(title: "模型占比")
    private let stateProvider: @MainActor () -> [ProviderID: TokenStatsViewModel.ProviderState]
    private let nowProvider: () -> Date
    private let calendar: Calendar

    init(
        stateProvider: @escaping @MainActor () -> [ProviderID: TokenStatsViewModel.ProviderState] = {
            (NSApp.delegate as? AppDelegate)?.viewModel.states ?? [:]
        },
        nowProvider: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.stateProvider = stateProvider
        self.nowProvider = nowProvider
        self.calendar = calendar
        super.init(nibName: nil, bundle: nil)
        self.title = "按月"
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
        NotificationCenter.default.removeObserver(self)
    }

    private func setupSubviews() {
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabelColor
        totalLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .medium)
        costLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .medium)
        costLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 0
        statusLabel.lineBreakMode = .byWordWrapping
        configureChartTitle(tokenChartTitleLabel)
        configureChartTitle(costChartTitleLabel)

        tokenChartTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        costChartTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        chartView.translatesAutoresizingMaskIntoConstraints = false
        costChartView.translatesAutoresizingMaskIntoConstraints = false
        toolSharePieView.translatesAutoresizingMaskIntoConstraints = false
        modelSharePieView.translatesAutoresizingMaskIntoConstraints = false
        chartView.setContentHuggingPriority(.required, for: .horizontal)
        costChartView.setContentHuggingPriority(.required, for: .horizontal)

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

        let tokenChartSection = makeChartSection(titleLabel: tokenChartTitleLabel, chartView: chartView)
        let costChartSection = makeChartSection(titleLabel: costChartTitleLabel, chartView: costChartView)

        let pieChartsStack = NSStackView(views: [toolSharePieView, modelSharePieView])
        pieChartsStack.translatesAutoresizingMaskIntoConstraints = false
        pieChartsStack.orientation = .vertical
        pieChartsStack.alignment = .width
        pieChartsStack.distribution = .fill
        pieChartsStack.spacing = 18
        pieChartsStack.setContentHuggingPriority(.required, for: .horizontal)

        let contentStack = NSStackView(views: [headerStack, tokenChartSection, costChartSection, pieChartsStack, statusLabel])
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
            tokenChartSection.leadingAnchor.constraint(equalTo: contentStack.leadingAnchor),
            tokenChartSection.widthAnchor.constraint(equalToConstant: Self.compactBarChartWidth),
            chartView.widthAnchor.constraint(equalToConstant: Self.compactBarChartWidth),
            costChartSection.leadingAnchor.constraint(equalTo: contentStack.leadingAnchor),
            costChartSection.widthAnchor.constraint(equalToConstant: Self.compactBarChartWidth),
            costChartView.widthAnchor.constraint(equalToConstant: Self.compactBarChartWidth),
            pieChartsStack.leadingAnchor.constraint(equalTo: contentStack.leadingAnchor),
            pieChartsStack.trailingAnchor.constraint(lessThanOrEqualTo: contentStack.trailingAnchor),
            pieChartsStack.widthAnchor.constraint(equalToConstant: Self.compactBarChartWidth),
            toolSharePieView.widthAnchor.constraint(equalToConstant: Self.compactBarChartWidth),
            modelSharePieView.widthAnchor.constraint(equalToConstant: Self.compactBarChartWidth),
            statusLabel.widthAnchor.constraint(lessThanOrEqualTo: contentStack.widthAnchor),
        ])
    }

    private func configureChartTitle(_ label: NSTextField) {
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .labelColor
        label.alignment = .left
    }

    private func makeChartSection(titleLabel: NSTextField, chartView: NSView) -> NSStackView {
        let stack = NSStackView(views: [titleLabel, chartView])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setContentHuggingPriority(.required, for: .horizontal)
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
        let snapshot = MonthlyTokenChartBuilder.build(
            states: states,
            now: nowProvider(),
            calendar: calendar
        )
        chartView.configure(with: snapshot)
        costChartView.configure(with: snapshot)
        toolSharePieView.configure(slices: snapshot.toolShareSlices)
        modelSharePieView.configure(slices: snapshot.modelShareSlices)
        totalLabel.stringValue = "\(CompactNumberFormatter.format(snapshot.totalTokens)) tokens"
        costLabel.stringValue = formatCurrency(snapshot.totalCost)
        statusLabel.stringValue = statusText(for: snapshot, totalProviderCount: states.count)
        statusLabel.isHidden = statusLabel.stringValue.isEmpty
    }

    private func formatCurrency(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    private func statusText(for snapshot: MonthlyTokenChartSnapshot, totalProviderCount: Int) -> String {
        if totalProviderCount > 0
            && snapshot.loadingProviderCount == totalProviderCount
            && snapshot.loadedProviderCount == 0 {
            return "正在加载用量数据..."
        }
        if snapshot.loadedProviderCount == 0 && snapshot.unauthorizedProviderCount > 0 {
            return "请先在设置中授权访问用户目录"
        }
        if let errorMessage = snapshot.errorMessages.first {
            return errorMessage
        }
        if snapshot.totalTokens == 0 {
            return "过去 12 个月暂无 token 数据"
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
