import AppKit
import Foundation
import os.log

/// macOS 状态栏控制器
///
/// 长驻一个图标 + 文本(今日所有 provider 累加 token 数),
/// 定时(30s)拉刷新,左键弹出 popover,右键弹下拉菜单(打开主窗口 / 立即刷新 / 退出)。
///
/// 设计原则:
/// - 不直接读 JSONL / 不做聚合,完全复用 TokenStatsViewModel.states.byDay
/// - title 计算交给 StatusBarTitleBuilder,本类只负责 AppKit 层装配
@MainActor
final class StatusBarController {

    private static let refreshInterval: TimeInterval = 30

    private let viewModel: TokenStatsViewModel
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let statusMenu = NSMenu()
    private var observerToken: TokenStatsViewModel.ObservationToken?
    private var refreshTimer: Timer?
    private var lastRenderedDayKey: String?

    /// 单 label 双行展示:富文本第一行=数字(Bold 10pt),第二行="Tokens"(6pt)
    /// 用 paragraphStyle 控制行高,避免行间距过大撑高整体
    private let titleLabel = NSTextField(labelWithString: "")

    /// 状态栏左侧仪表盘图标,按当日 token 总量分档替换 SF Symbol;持有引用以便 renderTitle 时更新
    private let iconView = NSImageView()
    /// SF Symbol 配置统一管理,保证替换图标后 pointSize/weight 不丢失
    private let iconSymbolConfig = NSImage.SymbolConfiguration(pointSize: 20, weight: .regular)
    private var lastRenderedSymbolName: String?
    private var loadingAnimationTimer: Timer?
    private var loadingAnimationFrameIndex = 0
    private static let loadingAnimationInterval: TimeInterval = 0.18

    private let logger = Logger(subsystem: "com.xiaoao.TokenWatch", category: "StatusBarController")

    init(viewModel: TokenStatsViewModel) {
        self.viewModel = viewModel
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        configureButton()
        configurePopover()
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
            loadingAnimationTimer?.invalidate()
        }
    }

    /// 应用退出时显式关停,确保 Timer 不再持有 self、status item 从 menu bar 摘除
    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        loadingAnimationTimer?.invalidate()
        loadingAnimationTimer = nil
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
        button.target = self
        button.action = #selector(handleStatusItemClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        // 图标内容由 renderTitle() 根据当日 token 量动态切换,这里只设公共属性。
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

    private func configurePopover() {
        let contentSize = NSSize(width: 280, height: 180)
        let contentViewController = NSViewController()
        contentViewController.view = EmptyStatusPopoverView(frame: NSRect(origin: .zero, size: contentSize))
        contentViewController.preferredContentSize = contentSize

        popover.behavior = .transient
        popover.contentSize = contentSize
        popover.contentViewController = contentViewController
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
        let openItem = NSMenuItem(
            title: "打开 TokenWatch",
            action: #selector(openMainWindow),
            keyEquivalent: "0"
        )
        openItem.target = self
        statusMenu.addItem(openItem)

        let refreshItem = NSMenuItem(
            title: "立即刷新",
            action: #selector(refreshNow),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        statusMenu.addItem(refreshItem)

        statusMenu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "退出 TokenWatch",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        statusMenu.addItem(quitItem)
    }

    private func subscribeToViewModel() {
        observerToken = viewModel.observe { [weak self] _ in
            guard let self else { return }
            // 等所有 provider 都不再 loading 才重绘,避免 loadAllStats 并发跑时
            // 状态栏数字在中间态多次跳变(800k → 1.2M → 1.25M)。
            // 单 provider 完成时其它仍 isLoading,这里挡掉;最后一个完成时 allSatisfy 才通过。
            self.syncLoadingAnimationState()
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

    private func syncLoadingAnimationState() {
        if viewModel.states.values.contains(where: { $0.isLoading }) {
            startLoadingAnimation()
        } else {
            stopLoadingAnimation()
        }
    }

    private func startLoadingAnimation() {
        guard loadingAnimationTimer == nil else { return }
        loadingAnimationFrameIndex = 0
        renderLoadingAnimationFrame()

        let timer = Timer(timeInterval: Self.loadingAnimationInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advanceLoadingAnimationFrame()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        loadingAnimationTimer = timer
    }

    private func stopLoadingAnimation() {
        loadingAnimationTimer?.invalidate()
        loadingAnimationTimer = nil
        loadingAnimationFrameIndex = 0
    }

    private func advanceLoadingAnimationFrame() {
        loadingAnimationFrameIndex = StatusBarLoadingAnimation.nextFrameIndex(after: loadingAnimationFrameIndex)
        renderLoadingAnimationFrame()
    }

    private func renderLoadingAnimationFrame() {
        let symbolName = StatusBarLoadingAnimation.symbolNames[loadingAnimationFrameIndex]
        setIcon(symbolName: symbolName)
    }

    private func setIcon(symbolName: String) {
        iconView.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: "TokenWatch"
        )?.withSymbolConfiguration(iconSymbolConfig)
        iconView.image?.isTemplate = true
        lastRenderedSymbolName = symbolName
    }

    private func renderTitle() {
        let todayKey = Self.todayKey()
        let primary = StatusBarTitleBuilder.build(states: viewModel.states, todayKey: todayKey)
        titleLabel.attributedStringValue = makeAttributedTitle(primary: primary)

        // 图标分档:用与文本相同的累加口径,避免文字和图标显示出处不一致
        let total = StatusBarTitleBuilder.totalTokens(states: viewModel.states, todayKey: todayKey)
        let symbolName = StatusBarTitleBuilder.symbolName(forTotalTokens: total)
        // 仅在档位变化时换图,减少 NSImageView.image set 引发的状态栏重新布局
        if symbolName != lastRenderedSymbolName {
            setIcon(symbolName: symbolName)
        }

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

    @objc private func handleStatusItemClick() {
        guard let event = NSApp.currentEvent else {
            togglePopover()
            return
        }

        switch StatusBarClickAction.resolve(
            eventType: event.type,
            modifierFlags: event.modifierFlags
        ) {
        case .togglePopover:
            togglePopover()
        case .showMenu:
            showStatusMenu()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func showStatusMenu() {
        guard let button = statusItem.button else { return }
        popover.performClose(nil)
        statusMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
    }

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

/// 状态栏按钮点击后的交互意图。
///
/// 抽成纯 helper,避免单元测试依赖真实 `NSStatusItem` 或鼠标事件对象。
enum StatusBarClickAction {
    case togglePopover
    case showMenu

    static func resolve(
        eventType: NSEvent.EventType,
        modifierFlags: NSEvent.ModifierFlags
    ) -> StatusBarClickAction {
        if eventType == .rightMouseUp || modifierFlags.contains(.control) {
            return .showMenu
        }
        return .togglePopover
    }
}

/// 空状态栏 popover 根视图。
///
/// 使用系统窗口背景色,让浅色和暗黑模式都由 AppKit 自动适配。
final class EmptyStatusPopoverView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("EmptyStatusPopoverView 不支持 storyboard 初始化")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }
}
