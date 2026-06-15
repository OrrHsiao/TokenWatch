import AppKit
import Foundation
import os.log

/// 垂直居中绘制文字的 NSTextFieldCell
///
/// macOS 的 NSTextFieldCell 默认从 frame 顶部开始绘制文字,
/// 导致在固定高度 label 中文字视觉偏上;
/// 重写 drawingRect(forBounds:) 让绘制区域在 frame 内垂直居中。
private final class VerticallyCenteredTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let actualRect = super.drawingRect(forBounds: rect)
        let preferredSize = cellSize(forBounds: rect)
        let yOffset = max(0, (actualRect.height - preferredSize.height) / 2.0)
        return NSRect(
            x: actualRect.origin.x,
            y: actualRect.origin.y + yOffset,
            width: actualRect.width,
            height: preferredSize.height
        )
    }
}

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
    private static let iconAssetName = "StatusBarIcon"

    private let viewModel: TokenStatsViewModel
    private let statusItem: NSStatusItem
    private var observerToken: TokenStatsViewModel.ObservationToken?
    private var refreshTimer: Timer?
    private var lastRenderedDayKey: String?

    /// 自定义状态栏内容视图所用的 label
    /// 使用 VerticallyCenteredTextFieldCell 使文字在 frame 内垂直居中,
    /// 解决 macOS 默认从顶部绘制文字导致视觉偏上的问题
    private let primaryLabel: NSTextField = {
        let field = NSTextField(labelWithString: "")
        field.cell = VerticallyCenteredTextFieldCell()
        return field
    }()

    private let secondaryLabel: NSTextField = {
        let field = NSTextField(labelWithString: "Tokens")
        field.cell = VerticallyCenteredTextFieldCell()
        return field
    }()

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
        iconView.image = NSImage(named: Self.iconAssetName)
        // 状态栏图标做成 template 由系统按主题自动反色
        iconView.image?.isTemplate = true
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
        ])

        configureLabel(primaryLabel, font: .boldSystemFont(ofSize: 10))
        configureLabel(secondaryLabel, font: .systemFont(ofSize: 6))
        applyAttributed(primaryLabel, text: "", font: .boldSystemFont(ofSize: 10))
        applyAttributed(secondaryLabel, text: "Tokens", font: .systemFont(ofSize: 6))

        // 布局规则:
        //   primaryLabel  顶边 = 图标顶边,高度 = 图标的 3/5
        //   secondaryLabel 底边 = 图标底边,高度 = 图标的 2/5
        let textContainer = NSView()
        textContainer.translatesAutoresizingMaskIntoConstraints = false
        textContainer.addSubview(primaryLabel)
        textContainer.addSubview(secondaryLabel)

        let rootStack = NSStackView(views: [iconView, textContainer])
        rootStack.orientation = .horizontal
        rootStack.alignment = .centerY
        rootStack.spacing = 4
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        button.addSubview(rootStack)
        NSLayoutConstraint.activate([
            // rootStack 填满 button,驱动 button 宽度自适应
            rootStack.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 4),
            rootStack.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -4),
            rootStack.centerYAnchor.constraint(equalTo: button.centerYAnchor),

            // textContainer 内部:两个 label 宽度撑满容器
            primaryLabel.leadingAnchor.constraint(equalTo: textContainer.leadingAnchor),
            primaryLabel.trailingAnchor.constraint(equalTo: textContainer.trailingAnchor),
            secondaryLabel.leadingAnchor.constraint(equalTo: textContainer.leadingAnchor),
            secondaryLabel.trailingAnchor.constraint(equalTo: textContainer.trailingAnchor),

            // primaryLabel: 顶边 = 图标顶边,高度 = 图标 3/5
            primaryLabel.topAnchor.constraint(equalTo: iconView.topAnchor),
            primaryLabel.heightAnchor.constraint(equalTo: iconView.heightAnchor, multiplier: 3.0 / 5.0),

            // secondaryLabel: 底边 = 图标底边,高度 = 图标 2/5
            secondaryLabel.bottomAnchor.constraint(equalTo: iconView.bottomAnchor),
            secondaryLabel.heightAnchor.constraint(equalTo: iconView.heightAnchor, multiplier: 2.0 / 5.0),

            // textContainer 上下边由 label 撑开
            textContainer.topAnchor.constraint(equalTo: primaryLabel.topAnchor),
            textContainer.bottomAnchor.constraint(equalTo: secondaryLabel.bottomAnchor),
        ])
    }

    /// label 的通用样式(颜色 / 居中 / 不换行)
    private func configureLabel(_ label: NSTextField, font: NSFont) {
        label.font = font
        label.alignment = .center
        label.textColor = .labelColor
        label.wantsLayer = true
        label.lineBreakMode = .byClipping
        label.translatesAutoresizingMaskIntoConstraints = false
    }

    /// 设置 label 的内容,不强制行高,让 label 按 font 自然 intrinsicContentSize 撑高
    /// 配合 VerticallyCenteredTextFieldCell 使文字垂直居中于 frame
    private func applyAttributed(_ label: NSTextField, text: String, font: NSFont) {
        label.attributedStringValue = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.labelColor,
            ]
        )
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
        // 重渲染只刷数字那行,Tokens 行在 configureButton 时一次性设过
        applyAttributed(primaryLabel, text: primary, font: .boldSystemFont(ofSize: 10))
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
