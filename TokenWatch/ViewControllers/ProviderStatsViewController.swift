import Cocoa

/// 单个 provider 的用量展示 ViewController
/// 由 ViewController(NSTabViewController)装入每个 Tab，通过初始化参数区分 provider
final class ProviderStatsViewController: NSViewController {

    private let provider: any UsageProvider
    private let statusLabel = NSTextField(labelWithString: "")
    private let actionButton = NSButton(title: "", target: nil, action: nil)

    /// 通过 NSApp.delegate 获取与 AppDelegate 同一个 ViewModel 实例
    private var viewModel: TokenStatsViewModel? {
        (NSApp.delegate as? AppDelegate)?.viewModel
    }

    /// 通过 provider 显式注入，避免依赖外部状态
    init(provider: any UsageProvider) {
        self.provider = provider
        super.init(nibName: nil, bundle: nil)
        self.title = provider.displayName
    }

    required init?(coder: NSCoder) {
        fatalError("ProviderStatsViewController 必须用 init(provider:) 构造")
    }

    /// NSTabViewController 装载子 VC 时若没显式 view，会触发 loadView，我们手动建一个
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 280))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupSubviews()
        bindViewModel()
        render()
    }

    // MARK: - 视图

    private func setupSubviews() {
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.alignment = .left
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 0
        statusLabel.font = .systemFont(ofSize: 13)

        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.bezelStyle = .rounded
        actionButton.target = self
        actionButton.action = #selector(actionButtonClicked)

        view.addSubview(statusLabel)
        view.addSubview(actionButton)

        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -16),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),

            actionButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            actionButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 16),
        ])
    }

    // MARK: - 绑定

    private func bindViewModel() {
        // 顶层 ViewController 已绑过 onStateChange,这里订阅同一个回调
        // 设计:让 ViewController 把回调多路复用到所有 Tab,各 Tab 只关心自己 provider id
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(stateDidChange(_:)),
            name: .providerStateDidChange,
            object: nil
        )
    }

    @objc private func stateDidChange(_ note: Notification) {
        guard let id = note.userInfo?["providerID"] as? ProviderID, id == provider.id else { return }
        render()
    }

    // MARK: - 渲染

    /// 根据 ViewModel 当前状态刷新视图
    /// 状态优先级:loading > needsAuthorization > error > stats
    @MainActor
    private func render() {
        guard let state = viewModel?.states[provider.id] else {
            statusLabel.stringValue = "ViewModel 未就绪"
            actionButton.isHidden = true
            return
        }

        if state.isLoading {
            statusLabel.stringValue = "正在加载 \(provider.displayName) 用量数据…"
            actionButton.isHidden = true
            return
        }
        if state.needsAuthorization {
            statusLabel.stringValue = "TokenWatch 需要读取 \(provider.defaultDirectoryPath) 目录\n以统计 \(provider.displayName) Token 用量"
            actionButton.title = "授权访问 \(provider.defaultDirectoryPath)"
            actionButton.isHidden = false
            return
        }
        if let error = state.errorMessage {
            statusLabel.stringValue = error
            actionButton.title = "重试"
            actionButton.isHidden = false
            return
        }
        if let stats = state.stats {
            statusLabel.stringValue = formatStatsText(stats)
            actionButton.title = "刷新"
            actionButton.isHidden = false
            return
        }
        statusLabel.stringValue = "暂无 \(provider.displayName) 数据"
        actionButton.title = "刷新"
        actionButton.isHidden = false
    }

    // MARK: - 交互

    @objc private func actionButtonClicked() {
        guard let vm = viewModel, let state = vm.states[provider.id] else { return }
        let id = provider.id
        Task { @MainActor in
            // 未授权 → 走授权流程(内含 loadStats);其余状态 → 直接重新加载
            if state.needsAuthorization {
                await vm.requestAuthorization(for: id)
            } else {
                await vm.loadStats(for: id)
            }
        }
    }

    // MARK: - 文案构造

    /// 拼装「本日 + 累计」概览。Codex provider 的 cache 行替换为 Cached Input
    private func formatStatsText(_ stats: AggregatedStats) -> String {
        let todayKey = Self.todayKey()
        let today = stats.byDay[todayKey] ?? .zero
        let overall = stats.overall

        let cacheLineToday: String
        if provider.hasCacheWriteDimension {
            cacheLineToday = "  └ Cache:  \(Self.formatInt(today.cacheReadTokens + today.cacheCreationTokens))"
        } else {
            // Codex:只有 cache_read,没有 5m/1h write
            cacheLineToday = "  └ Cached: \(Self.formatInt(today.cacheReadTokens))"
        }

        return """
        ── 本日 (\(todayKey)) ──
        总 Token: \(Self.formatInt(today.totalTokens))
          ├ Input:  \(Self.formatInt(today.inputTokens))
          ├ Output: \(Self.formatInt(today.outputTokens))
        \(cacheLineToday)
        成本: $\(String(format: "%.4f", today.cost))
        记录: \(today.entryCount)

        ── 累计 ──
        总 Token: \(Self.formatInt(overall.totalTokens))
        成本: $\(String(format: "%.4f", overall.cost))
        记录: \(overall.entryCount)  会话: \(stats.bySession.count)
        """
    }

    /// 生成今日 key,格式 "yyyy-MM-dd"
    /// 与 UsageAggregator.dayKey 保持完全一致的算法 / 时区,保证能正确命中 byDay
    private static func todayKey() -> String {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month, .day], from: Date())
        guard let y = comps.year, let m = comps.month, let d = comps.day else {
            return "unknown"
        }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    /// 千位分隔符格式化整数(本地化)
    private static func formatInt(_ value: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }
}

extension Notification.Name {
    /// provider 状态变更通知,userInfo["providerID"] = ProviderID
    static let providerStateDidChange = Notification.Name("com.xiaoao.TokenWatch.providerStateDidChange")
}
