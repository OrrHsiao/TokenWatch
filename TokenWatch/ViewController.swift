//
//  ViewController.swift
//  TokenWatch
//
//  Created by OrrHsiao on 2026/6/13.
//

import Cocoa

/// 主视图控制器
///
/// MVP 状态视图(Phase 7 完整 UI 之前的最小可用形态):
/// - 未授权 → 显示提示文本 + 「授权访问 ~/.claude」按钮 → 弹 NSOpenPanel
/// - 加载中 → 显示进度提示
/// - 加载失败 → 显示错误信息 + 重试按钮
/// - 加载成功 → 显示统计概览(总记录数 / 总成本)
///
/// 暂以代码方式构建子视图,不动 storyboard,降低与未来 Phase 7 完整 UI 的合并冲突。
class ViewController: NSViewController {

    private let statusLabel = NSTextField(labelWithString: "")
    private let actionButton = NSButton(title: "", target: nil, action: nil)

    /// 通过 NSApp.delegate 获取与 AppDelegate 同一个 ViewModel 实例
    /// `applicationDidFinishLaunching` 已触发首次 loadStats,这里只负责订阅状态变更
    private var viewModel: TokenStatsViewModel? {
        (NSApp.delegate as? AppDelegate)?.viewModel
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
        // stats 渲染为多行块状文本(本日 / 累计),左对齐更整齐;
        // 加载/授权/错误等单行/短文本由文本本身居中性质决定视觉效果。
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
        viewModel?.onStateChange = { [weak self] _ in
            self?.render()
        }
    }

    /// 根据 ViewModel 当前状态刷新视图
    /// 状态优先级:loading > needsAuthorization > error > stats
    @MainActor
    private func render() {
        guard let vm = viewModel,
              let state = vm.states[.claude] else {
            statusLabel.stringValue = "ViewModel 未就绪"
            actionButton.isHidden = true
            return
        }

        if state.isLoading {
            statusLabel.stringValue = "正在加载用量数据…"
            actionButton.isHidden = true
            return
        }
        if state.needsAuthorization {
            statusLabel.stringValue = "TokenWatch 需要读取 ~/.claude 目录\n以统计 Token 用量"
            actionButton.title = "授权访问 ~/.claude"
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
        statusLabel.stringValue = "暂无数据"
        actionButton.title = "刷新"
        actionButton.isHidden = false
    }

    // MARK: - 交互

    @objc private func actionButtonClicked() {
        guard let vm = viewModel, let state = vm.states[.claude] else { return }
        Task { @MainActor in
            // 未授权 → 走授权流程(内含 loadStats);其余状态 → 直接重新加载
            if state.needsAuthorization {
                await vm.requestAuthorization(for: .claude)
            } else {
                await vm.loadStats(for: .claude)
            }
        }
    }

    // MARK: - 文案构造

    /// 拼装「本日 + 累计」两段式概览文本
    /// 设计原因:聚合层已生成 byDay 切片(key 与 UsageAggregator.dayKey 同源),
    /// UI 层只取今日 summary 即可;若今日无记录,以 .zero 兜底,避免界面空块。
    /// 注:byDay 不含 sessionID 维度,「本日会话数」无法在不新增聚合切片的情况下准确计算,
    /// 因此本日块暂只展示记录数;会话数仅在累计块出现。
    private func formatStatsText(_ stats: AggregatedStats) -> String {
        let todayKey = Self.todayKey()
        let today = stats.byDay[todayKey] ?? .zero
        let overall = stats.overall

        return """
        ── 本日 (\(todayKey)) ──
        总 Token: \(Self.formatInt(today.totalTokens))
          ├ Input:  \(Self.formatInt(today.inputTokens))
          ├ Output: \(Self.formatInt(today.outputTokens))
          └ Cache:  \(Self.formatInt(today.cacheReadTokens + today.cacheCreationTokens))
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

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }
}
