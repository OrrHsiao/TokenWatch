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
        statusLabel.alignment = .center
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
        viewModel?.onStateChange = { [weak self] in
            self?.render()
        }
    }

    /// 根据 ViewModel 当前状态刷新视图
    /// 状态优先级:loading > needsAuthorization > error > stats
    @MainActor
    private func render() {
        guard let vm = viewModel else {
            statusLabel.stringValue = "ViewModel 未就绪"
            actionButton.isHidden = true
            return
        }

        if vm.isLoading {
            statusLabel.stringValue = "正在加载用量数据…"
            actionButton.isHidden = true
            return
        }

        if vm.needsAuthorization {
            statusLabel.stringValue = "TokenWatch 需要读取 ~/.claude 目录\n以统计 Token 用量"
            actionButton.title = "授权访问 ~/.claude"
            actionButton.isHidden = false
            return
        }

        if let error = vm.errorMessage {
            statusLabel.stringValue = error
            actionButton.title = "重试"
            actionButton.isHidden = false
            return
        }

        if let stats = vm.stats {
            // 简单总览;完整 UI 在 Phase 7 实现
            let total = stats.overall
            statusLabel.stringValue = """
            已加载 \(total.entryCount) 条记录
            总成本: $\(String(format: "%.4f", total.cost))
            模型数: \(stats.byModel.count)  会话数: \(stats.bySession.count)
            """
            actionButton.title = "刷新"
            actionButton.isHidden = false
            return
        }

        // 兜底:理论不应到达(loadStats 后必然走入上面某分支)
        statusLabel.stringValue = "暂无数据"
        actionButton.title = "刷新"
        actionButton.isHidden = false
    }

    // MARK: - 交互

    @objc private func actionButtonClicked() {
        guard let vm = viewModel else { return }
        Task { @MainActor in
            // 未授权 → 走授权流程(内含 loadStats);其余状态 → 直接重新加载
            if vm.needsAuthorization {
                await vm.requestAuthorization()
            } else {
                await vm.loadStats()
            }
        }
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }
}
