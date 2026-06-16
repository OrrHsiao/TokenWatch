import AppKit
import Foundation
import os.log

/// macOS 状态栏控制器
///
/// 长驻一个图标 + 文本(今日所有 provider 累加 token 数),
/// 定时(30s)拉刷新,点击弹下拉菜单(打开主窗口 / 立即刷新 / 退出)。
///
/// 设计原则:
/// - 不直接读 JSONL / 不做聚合,完全复用 TokenStatsViewModel.states.byDay
/// - title 计算交给 StatusBarTitleBuilder,本类只负责 AppKit 层装配
@MainActor
final class StatusBarController {

    private static let refreshInterval: TimeInterval = 30

    private let viewModel: TokenStatsViewModel
    private let statusItem: NSStatusItem
    private var observerToken: TokenStatsViewModel.ObservationToken?
    private var refreshTimer: Timer?
    private var lastRenderedDayKey: String?

    /// 单 label 双行展示:富文本第一行=数字(Bold 10pt),第二行="Tokens"(6pt)
    /// 用 paragraphStyle 控制行高,避免行间距过大撑高整体
    private let titleLabel = NSTextField(labelWithString: "")

    private let logger = Logger(subsystem: "com.xiaoao.TokenWatch", category: "StatusBarController")

    init(viewModel: TokenStatsViewModel) {
        self.viewModel = viewModel
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        configureButton()
        installMenu()
        subscribeToViewModel()
        startRefreshTimer()
        // 立即按当前 ViewModel 状态画一次,避免空标题闪现
        renderTitle()
    }

    deinit {
        // 仅作 Timer 兜底:正常终止路径走 stop() 完成所有释放;
        // status item 不在此处 remove,避免与 stop() 重复(AppKit 容忍但语义不洁)。
        // 进程异常退出时 status item 会被系统回收,无需 deinit 显式处理。
        // 用 assumeIsolated 是为了满足 Swift 6 隔离检查(Timer? 非 Sendable),
        // deinit 走 main actor 调度路径,这里同步执行不会重入。
        MainActor.assumeIsolated {
            refreshTimer?.invalidate()
        }
    }

    /// 应用退出时显式关停,确保 Timer 不再持有 self、status item 从 menu bar 摘除
    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        if let token = observerToken {
            viewModel.removeObserver(token)
            observerToken = nil
        }
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    // MARK: - Setup

    private func configureButton() {
        guard let button = statusItem.button else { return }
        // 关掉 button 自带的 image / title 渲染,统一用自定义布局
        button.image = nil
        button.title = ""

        let iconView = NSImageView()
        // SF Symbol 默认渲染较小,用 symbolConfiguration 指定 pointSize=18 使图标与之前自定义图片等大
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        iconView.image = NSImage(
            systemSymbolName: "gauge.with.dots.needle.bottom.50percent",
            accessibilityDescription: "TokenWatch"
        )?.withSymbolConfiguration(symbolConfig)
        // 状态栏图标做成 template 由系统按主题自动反色
        iconView.image?.isTemplate = true
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),
        ])

        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byClipping
        titleLabel.maximumNumberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let rootStack = NSStackView(views: [iconView, titleLabel])
        rootStack.orientation = .horizontal
        // 整体垂直居中,让图标中线和两行文字的整体中线对齐
        rootStack.alignment = .centerY
        rootStack.spacing = 4
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        button.addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 4),
            rootStack.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -4),
            rootStack.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        ])
    }

    /// 拼装两行富文本:数字加粗,"Tokens" 字号小一号
    /// 两行 paragraphStyle 设置 maximumLineHeight 把行高压紧,使两行总高接近图标高度(18pt)
    private func makeAttributedTitle(primary: String) -> NSAttributedString {
        let primaryParagraph = NSMutableParagraphStyle()
        primaryParagraph.alignment = .center
        primaryParagraph.maximumLineHeight = 10
        primaryParagraph.minimumLineHeight = 10

        let secondaryParagraph = NSMutableParagraphStyle()
        secondaryParagraph.alignment = .center
        secondaryParagraph.maximumLineHeight = 8
        secondaryParagraph.minimumLineHeight = 8

        let result = NSMutableAttributedString(
            string: primary,
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: 9),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: primaryParagraph,
            ]
        )
        result.append(NSAttributedString(
            string: "\nTokens",
            attributes: [
                .font: NSFont.systemFont(ofSize: 7),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: secondaryParagraph,
            ]
        ))
        return result
    }

    private func installMenu() {
        let menu = NSMenu()

        let openItem = NSMenuItem(
            title: "打开 TokenWatch",
            action: #selector(openMainWindow),
            keyEquivalent: "0"
        )
        openItem.target = self
        menu.addItem(openItem)

        let refreshItem = NSMenuItem(
            title: "立即刷新",
            action: #selector(refreshNow),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "退出 TokenWatch",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func subscribeToViewModel() {
        observerToken = viewModel.observe { [weak self] _ in
            guard let self else { return }
            // 等所有 provider 都不再 loading 才重绘,避免 loadAllStats 并发跑时
            // 状态栏数字在中间态多次跳变(800k → 1.2M → 1.25M)。
            // 单 provider 完成时其它仍 isLoading,这里挡掉;最后一个完成时 allSatisfy 才通过。
            guard self.viewModel.states.values.allSatisfy({ !$0.isLoading }) else { return }
            self.renderTitle()
        }
    }

    private func startRefreshTimer() {
        // 用 RunLoop.common 而非默认 mode,避免菜单展开时 Timer 被冻结
        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.handleScheduledRefresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    // MARK: - Refresh

    private func handleScheduledRefresh() {
        // 跨日检测:即便数据没变也强制重绘文本,避免 0 点跨过去仍显示昨天
        let todayKey = Self.todayKey()
        if lastRenderedDayKey != todayKey {
            renderTitle()
        }
        Task { await viewModel.loadAllStats() }
    }

    // MARK: - Render

    private func renderTitle() {
        let todayKey = Self.todayKey()
        let primary = StatusBarTitleBuilder.build(states: viewModel.states, todayKey: todayKey)
        titleLabel.attributedStringValue = makeAttributedTitle(primary: primary)
        lastRenderedDayKey = todayKey
    }

    /// 与 UsageAggregator.dayKey 保持一致:本地 Calendar + "yyyy-MM-dd"
    static func todayKey(now: Date = Date(), calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: now)
        guard let y = comps.year, let m = comps.month, let d = comps.day else {
            return "unknown"
        }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    // MARK: - Actions

    @objc private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        // 主窗口在 storyboard 中已设 releasedWhenClosed="NO",
        // 用户点红叉关闭后 window 对象仍在 NSApp.windows 里,可直接 makeKeyAndOrderFront 恢复。
        // 优先按 contentVC 类型匹配 ViewController 窗口,fallback 到 NSApp.mainWindow
        let target = NSApp.windows.first(where: { $0.contentViewController is ViewController })
            ?? NSApp.mainWindow
        target?.makeKeyAndOrderFront(nil)
        if target == nil {
            logger.info("openMainWindow: 找不到 ViewController 窗口,跳过(后续版本再处理重建)")
        }
    }

    @objc private func refreshNow() {
        Task { await viewModel.loadAllStats() }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
