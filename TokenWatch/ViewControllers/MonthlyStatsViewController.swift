import AppKit

/// 跨 provider 的按月 token 消耗页面。
final class MonthlyStatsViewController: NSViewController {
    private let titleLabel = NSTextField(labelWithString: "按月")
    private let subtitleLabel = NSTextField(labelWithString: "过去 12 个月,跨 provider 汇总")
    private let totalLabel = NSTextField(labelWithString: "0 tokens")
    private let statusLabel = NSTextField(labelWithString: "")
    private let chartView = MonthlyTokenChartView()
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
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 0
        statusLabel.lineBreakMode = .byWordWrapping

        chartView.translatesAutoresizingMaskIntoConstraints = false

        let headerTextStack = NSStackView(views: [titleLabel, subtitleLabel])
        headerTextStack.orientation = .vertical
        headerTextStack.alignment = .leading
        headerTextStack.spacing = 4

        let headerStack = NSStackView(views: [headerTextStack, totalLabel])
        headerStack.orientation = .horizontal
        headerStack.alignment = .firstBaseline
        headerStack.distribution = .gravityAreas
        headerStack.spacing = 16

        let contentStack = NSStackView(views: [headerStack, chartView, statusLabel])
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 18

        view.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            contentStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 32),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -32),
            chartView.leadingAnchor.constraint(equalTo: contentStack.leadingAnchor),
            chartView.trailingAnchor.constraint(equalTo: contentStack.trailingAnchor),
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
        let snapshot = MonthlyTokenChartBuilder.build(
            states: stateProvider(),
            now: nowProvider(),
            calendar: calendar
        )
        chartView.configure(with: snapshot)
        totalLabel.stringValue = "\(CompactNumberFormatter.format(snapshot.totalTokens)) tokens"
        statusLabel.stringValue = statusText(for: snapshot)
        statusLabel.isHidden = statusLabel.stringValue.isEmpty
    }

    private func statusText(for snapshot: MonthlyTokenChartSnapshot) -> String {
        if snapshot.loadingProviderCount > 0 && snapshot.loadedProviderCount == 0 {
            return "正在加载用量数据..."
        }
        if snapshot.loadedProviderCount == 0 && snapshot.unauthorizedProviderCount > 0 {
            return "请先在设置中授权访问用户目录"
        }
        if snapshot.loadedProviderCount == 0, let errorMessage = snapshot.errorMessages.first {
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
