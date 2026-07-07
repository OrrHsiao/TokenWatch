import AppKit
import Foundation
import os.log

/// macOS 状态栏控制器
///
/// 长驻一个图标 + 文本(今日所有 provider 累加 token 数),
/// 按设置间隔拉刷新,左键弹出 popover,右键弹下拉菜单(打开主窗口 / 立即刷新 / 退出)。
///
/// 设计原则:
/// - 不直接读 JSONL / 不做聚合,完全复用 TokenStatsViewModel.states.byDay
/// - title 计算交给 StatusBarTitleBuilder,本类只负责 AppKit 层装配
@MainActor
final class StatusBarController {

    private let viewModel: TokenStatsViewModel
    private let autoRefreshSettings: AutoRefreshSettings
    private let languageSettings: AppLanguageSettings
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let statusMenu = NSMenu()
    private var observerToken: TokenStatsViewModel.ObservationToken?
    private var autoRefreshSettingsObserverToken: AutoRefreshSettings.ObservationToken?
    private var languageSettingsObserverToken: AppLanguageSettings.ObservationToken?
    private var popoverCloseObserver: NSObjectProtocol?
    private var popoverLocalEventMonitor: Any?
    private var popoverGlobalEventMonitor: Any?
    private var refreshTimer: Timer?
    private var lastRenderedDayKey: String?
    /// 上次渲染的图标 symbol 名,用于在档位未变时跳过 image 赋值,避免触发状态栏重布局
    private var lastRenderedSymbolName: String?
    /// SF Symbol 配置统一管理,保证替换图标后 pointSize/weight 不丢失
    private let iconSymbolConfig = NSImage.SymbolConfiguration(
        pointSize: StatusBarIconLayout.pointSize,
        weight: .regular
    )
    private var loadingAnimationTimer: Timer?
    private var loadingAnimationFrameIndex = 0
    private static let loadingAnimationInterval: TimeInterval = 0.18

    private let logger = Logger(subsystem: "com.xiaoao.TokenWatch", category: "StatusBarController")

    var debugRefreshTimerInterval: TimeInterval? {
        refreshTimer?.timeInterval
    }
    var debugStatusMenuItemTitles: [String] {
        statusMenu.items.filter { !$0.isSeparatorItem }.map(\.title)
    }
    var debugTitlePlainString: String {
        statusItem.button?.attributedTitle.string ?? ""
    }
    var debugStatusButtonCustomSubviewCount: Int {
        statusItem.button?.subviews.filter {
            $0 is NSStackView || $0 is NSTextField || $0 is NSImageView
        }.count ?? 0
    }
    var debugStatusItemLength: CGFloat {
        statusItem.length
    }
    var debugStatusButtonUsesCustomCell: Bool {
        guard let cell = statusItem.button?.cell else { return false }
        return String(describing: type(of: cell)) == "StatusBarNativeButtonCell"
    }
    var debugTitleBaselineOffsets: [CGFloat] {
        guard let attributedTitle = statusItem.button?.attributedTitle else { return [] }
        let fullRange = NSRange(location: 0, length: attributedTitle.length)
        var offsets: [CGFloat] = []
        attributedTitle.enumerateAttribute(.baselineOffset, in: fullRange) { value, _, _ in
            if let value = value as? NSNumber {
                offsets.append(CGFloat(value.doubleValue))
            }
        }
        return offsets
    }

    init(
        viewModel: TokenStatsViewModel,
        autoRefreshSettings: AutoRefreshSettings = .shared,
        languageSettings: AppLanguageSettings = .shared
    ) {
        self.viewModel = viewModel
        self.autoRefreshSettings = autoRefreshSettings
        self.languageSettings = languageSettings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        configureButton()
        configurePopover()
        installMenu()
        subscribeToViewModel()
        subscribeToAutoRefreshSettings()
        subscribeToLanguageSettings()
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
            if let token = popoverCloseObserver {
                NotificationCenter.default.removeObserver(token)
            }
            if let token = autoRefreshSettingsObserverToken {
                autoRefreshSettings.removeObserver(token)
            }
            if let token = languageSettingsObserverToken {
                languageSettings.removeObserver(token)
            }
            removePopoverDismissMonitors()
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
        if let token = autoRefreshSettingsObserverToken {
            autoRefreshSettings.removeObserver(token)
            autoRefreshSettingsObserverToken = nil
        }
        if let token = languageSettingsObserverToken {
            languageSettings.removeObserver(token)
            languageSettingsObserverToken = nil
        }
        if let token = popoverCloseObserver {
            NotificationCenter.default.removeObserver(token)
            popoverCloseObserver = nil
        }
        removePopoverDismissMonitors()
        popover.performClose(nil)
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    // MARK: - Setup

    private func configureButton() {
        guard let button = statusItem.button else { return }
        // 用 NSStatusBarButton 原生 image + attributedTitle 渲染图标与双行文字。
        // 自定义 NSStackView 子视图会进入 macOS 26 的 NSStatusItemScene 布局管线,
        // 与状态栏自适应宽度互相 invalidation,空闲时也可能持续重绘。
        // 保留系统状态栏 cell,由它负责状态栏图标和标题整体垂直位置。
        button.target = self
        button.action = #selector(handleStatusItemClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageLeft
        button.imageScaling = .scaleProportionallyDown
        // attributedTitle 双行渲染(数字 + 单位)需要 cell 开启换行。
        if let cell = button.cell as? NSButtonCell {
            cell.wraps = true
            cell.truncatesLastVisibleLine = false
        }
    }

    private func configurePopover() {
        let contentViewController = StatusPopoverViewController(
            viewModel: viewModel,
            languageSettings: languageSettings
        )
        contentViewController.preferredContentSize = StatusBarPopoverLayout.contentSize

        popover.behavior = .transient
        popover.contentSize = StatusBarPopoverLayout.contentSize
        popover.contentViewController = contentViewController
        popoverCloseObserver = NotificationCenter.default.addObserver(
            forName: NSPopover.didCloseNotification,
            object: popover,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.removePopoverDismissMonitors()
                self?.setStatusButtonHighlighted(popoverIsShown: false)
            }
        }
    }

    /// 拼装两行富文本:数字加粗,单位字号小一号
    /// 两行 paragraphStyle 设置 maximumLineHeight 把行高压紧,使两行总高接近图标高度(18pt)
    private func makeAttributedTitle(primary: String) -> NSAttributedString {
        let language = languageSettings.resolvedLanguage
        let unit = AppStrings.text(.statusBarTokenUnit, language: language)
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
                .baselineOffset: StatusBarTitleTextLayout.baselineOffset,
            ]
        )
        result.append(NSAttributedString(
            string: "\n\(unit)",
            attributes: [
                .font: NSFont.systemFont(ofSize: 7),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: secondaryParagraph,
                .baselineOffset: StatusBarTitleTextLayout.baselineOffset,
            ]
        ))
        return result
    }

    private func installMenu() {
        let language = languageSettings.resolvedLanguage
        let openItem = NSMenuItem(
            title: AppStrings.text(.statusMenuOpen, language: language),
            action: #selector(openMainWindow),
            keyEquivalent: "0"
        )
        openItem.target = self
        statusMenu.addItem(openItem)

        let refreshItem = NSMenuItem(
            title: AppStrings.text(.refreshNow, language: language),
            action: #selector(refreshNow),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        statusMenu.addItem(refreshItem)

        statusMenu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: AppStrings.text(.statusMenuQuit, language: language),
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

    private func subscribeToAutoRefreshSettings() {
        autoRefreshSettingsObserverToken = autoRefreshSettings.observe { [weak self] in
            self?.restartRefreshTimer()
        }
    }

    private func subscribeToLanguageSettings() {
        languageSettingsObserverToken = languageSettings.observe { [weak self] in
            self?.updateLocalizedText()
        }
    }

    private func updateLocalizedText() {
        updateMenuTitles()
        renderTitle()
    }

    private func updateMenuTitles() {
        let language = languageSettings.resolvedLanguage
        let nonSeparatorItems = statusMenu.items.filter { !$0.isSeparatorItem }
        guard nonSeparatorItems.count >= 3 else { return }

        nonSeparatorItems[0].title = AppStrings.text(.statusMenuOpen, language: language)
        nonSeparatorItems[1].title = AppStrings.text(.refreshNow, language: language)
        nonSeparatorItems[2].title = AppStrings.text(.statusMenuQuit, language: language)
    }

    private func startRefreshTimer() {
        guard let interval = autoRefreshSettings.selectedOption.interval else { return }

        // 用 RunLoop.common 而非默认 mode,避免菜单展开时 Timer 被冻结
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.handleScheduledRefresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func restartRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        startRefreshTimer()
    }

    // MARK: - Refresh

    private func handleScheduledRefresh() {
        // 跨日检测:即便数据没变也强制重绘文本,避免 0 点跨过去仍显示昨天
        let todayKey = Self.todayKey()
        if lastRenderedDayKey != todayKey {
            renderTitle()
        }
        Task { await viewModel.loadAllStats(mode: .silentIfUnchanged) }
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
        let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: "TokenWatch"
        )?.withSymbolConfiguration(iconSymbolConfig)
        // 状态栏图标做成 template 由系统按主题自动反色
        image?.isTemplate = true
        statusItem.button?.image = image.map(StatusBarIconLayout.imageWithTrailingSpacing)
        lastRenderedSymbolName = symbolName
    }

    private func renderTitle() {
        let todayKey = Self.todayKey()
        let primary = StatusBarTitleBuilder.build(states: viewModel.states, todayKey: todayKey)
        statusItem.button?.attributedTitle = makeAttributedTitle(primary: primary)

        // 图标分档:用与文本相同的累加口径,避免文字和图标显示出处不一致
        let total = StatusBarTitleBuilder.totalTokens(states: viewModel.states, todayKey: todayKey)
        let symbolName = StatusBarTitleBuilder.symbolName(forTotalTokens: total)
        // 仅在档位变化时换图,减少 image 赋值引发的状态栏重新布局
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
            removePopoverDismissMonitors()
            setStatusButtonHighlighted(popoverIsShown: false)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            installPopoverDismissMonitors()
            activatePopoverAfterShowing()
            setStatusButtonHighlighted(popoverIsShown: true)
        }
    }

    private func showStatusMenu() {
        popover.performClose(nil)
        removePopoverDismissMonitors()
        setStatusButtonHighlighted(popoverIsShown: false)
        switch StatusBarMenuPresentation.presenter() {
        case .statusItemMenu(let selectorName):
            // 左键需要自定义 popover,所以不能常驻设置 statusItem.menu;
            // 右键这里直接走 NSStatusItem 的菜单 presenter,由 AppKit 负责状态栏定位。
            _ = statusItem.perform(NSSelectorFromString(selectorName), with: statusMenu)
        }
    }

    private func setStatusButtonHighlighted(popoverIsShown: Bool) {
        let isHighlighted = StatusBarButtonHighlight.isHighlighted(popoverIsShown: popoverIsShown)
        switch StatusBarButtonHighlight.applicationTiming(popoverIsShown: popoverIsShown) {
        case .immediate:
            applyStatusButtonHighlight(isHighlighted)
        case .afterCurrentEvent:
            Task { @MainActor [weak self] in
                guard let self, self.popover.isShown == popoverIsShown else { return }
                self.applyStatusButtonHighlight(isHighlighted)
            }
        }
    }

    private func applyStatusButtonHighlight(_ isHighlighted: Bool) {
        guard let button = statusItem.button else { return }
        button.highlight(isHighlighted)
        button.needsDisplay = true
    }

    private func activatePopoverAfterShowing() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let contentView = self.popover.contentViewController?.view
            let popoverWindow = contentView?.window

            for action in StatusPopoverActivation.actions(isPopoverShown: self.popover.isShown) {
                switch action {
                case .activateApplication:
                    NSApp.activate(ignoringOtherApps: true)
                case .makePopoverWindowKey:
                    popoverWindow?.makeKey()
                case .makeContentFirstResponder:
                    guard let contentView else { continue }
                    _ = popoverWindow?.makeFirstResponder(contentView)
                }
            }
        }
    }

    private func installPopoverDismissMonitors() {
        guard popoverLocalEventMonitor == nil, popoverGlobalEventMonitor == nil else { return }

        let mouseDownEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        popoverLocalEventMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseDownEvents) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleLocalPopoverMouseDown(event)
            }
            return event
        }
        popoverGlobalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseDownEvents) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.dismissPopoverForBackgroundClick()
            }
        }
    }

    private func removePopoverDismissMonitors() {
        if let monitor = popoverLocalEventMonitor {
            NSEvent.removeMonitor(monitor)
            popoverLocalEventMonitor = nil
        }
        if let monitor = popoverGlobalEventMonitor {
            NSEvent.removeMonitor(monitor)
            popoverGlobalEventMonitor = nil
        }
    }

    private func handleLocalPopoverMouseDown(_ event: NSEvent) {
        let eventTarget = popoverEventTarget(for: event)
        switch StatusPopoverOutsideClick.resolve(isPopoverShown: popover.isShown, eventTarget: eventTarget) {
        case .closePopover:
            dismissPopoverForBackgroundClick()
        case .keepPopover:
            break
        }
    }

    private func dismissPopoverForBackgroundClick() {
        guard popover.isShown else {
            removePopoverDismissMonitors()
            return
        }
        popover.performClose(nil)
        removePopoverDismissMonitors()
        setStatusButtonHighlighted(popoverIsShown: false)
    }

    private func popoverEventTarget(for event: NSEvent) -> StatusPopoverOutsideClick.EventTarget {
        if let button = statusItem.button, eventHitsView(event, view: button) {
            return .statusButton
        }
        if let contentView = popover.contentViewController?.view, eventHitsView(event, view: contentView) {
            return .popover
        }
        return .background
    }

    private func eventHitsView(_ event: NSEvent, view: NSView) -> Bool {
        guard let eventWindow = event.window, let viewWindow = view.window, eventWindow === viewWindow else {
            return false
        }
        let pointInView = view.convert(event.locationInWindow, from: nil)
        return view.bounds.contains(pointInView)
    }

    @objc private func openMainWindow() {
        switch StatusMainWindowPresentation.timing() {
        case .afterCurrentEvent:
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let appDelegate = NSApp.delegate as? AppDelegate else {
                    logger.info("openMainWindow: 找不到 AppDelegate,跳过")
                    return
                }
                appDelegate.openMainWindow(nil)
            }
        }
    }

    @objc private func refreshNow() {
        Task { await viewModel.loadAllStats() }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

/// 自动刷新间隔选项,用于设置页展示并驱动状态栏定时器。
enum AutoRefreshIntervalOption: String, CaseIterable {
    case seconds30
    case minute1
    case minutes5
    case minutes15
    case disabled

    var title: String {
        title(language: .zhHans)
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .seconds30:
            return AppStrings.text(.autoRefreshSeconds30, language: language)
        case .minute1:
            return AppStrings.text(.autoRefreshMinute1, language: language)
        case .minutes5:
            return AppStrings.text(.autoRefreshMinutes5, language: language)
        case .minutes15:
            return AppStrings.text(.autoRefreshMinutes15, language: language)
        case .disabled:
            return AppStrings.text(.autoRefreshDisabled, language: language)
        }
    }

    var interval: TimeInterval? {
        switch self {
        case .seconds30:
            return 30
        case .minute1:
            return 60
        case .minutes5:
            return 300
        case .minutes15:
            return 900
        case .disabled:
            return nil
        }
    }

    static var defaultOption: AutoRefreshIntervalOption {
        .minutes5
    }

    static func option(titled title: String) -> AutoRefreshIntervalOption? {
        allCases.first { $0.title == title }
    }
}

/// 持久化自动刷新设置,并同步通知状态栏重建 Timer。
@MainActor
final class AutoRefreshSettings {
    struct ObservationToken: Hashable {
        let id: UUID
    }

    static let shared = AutoRefreshSettings(defaults: .standard)
    static let storageKey = "TokenWatch.autoRefreshInterval"

    private let defaults: UserDefaults
    private var observers: [ObservationToken: @MainActor () -> Void] = [:]

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    var selectedOption: AutoRefreshIntervalOption {
        get {
            defaults.string(forKey: Self.storageKey)
                .flatMap(AutoRefreshIntervalOption.init(rawValue:))
                ?? AutoRefreshIntervalOption.defaultOption
        }
        set {
            guard selectedOption != newValue else { return }
            defaults.set(newValue.rawValue, forKey: Self.storageKey)
            notifyChange()
        }
    }

    @discardableResult
    func observe(_ handler: @escaping @MainActor () -> Void) -> ObservationToken {
        let token = ObservationToken(id: UUID())
        observers[token] = handler
        return token
    }

    func removeObserver(_ token: ObservationToken) {
        observers.removeValue(forKey: token)
    }

    private func notifyChange() {
        for handler in Array(observers.values) {
            handler()
        }
    }
}

/// 状态栏 popover 固定布局参数。
enum StatusBarPopoverLayout {
    static var contentSize: NSSize { StatusPopoverViewController.contentSize }
}

/// 状态栏 popover 展开后的激活动作。
///
/// 状态栏点击不会稳定激活应用;展开后需要显式让 popover window 接入响应链。
enum StatusPopoverActivation {
    enum Action: Equatable {
        case activateApplication
        case makePopoverWindowKey
        case makeContentFirstResponder
    }

    static func actions(isPopoverShown: Bool) -> [Action] {
        guard isPopoverShown else { return [] }
        return [
            .activateApplication,
            .makePopoverWindowKey,
            .makeContentFirstResponder,
        ]
    }
}

/// 状态栏菜单打开主窗口的置前策略。
///
/// NSMenu action 执行时菜单仍在 tracking;延后一轮主线程再处理,避免菜单关闭流程覆盖窗口激活。
/// 已在屏幕上的主窗口若被其它 app 盖住,仅 makeKeyAndOrderFront 不够,需要 orderFrontRegardless。
enum StatusMainWindowPresentation {
    enum Timing: Equatable {
        case afterCurrentEvent
    }

    enum Action: Equatable {
        case activateApplication
        case makeWindowKeyAndOrderFront
        case orderWindowFrontRegardless
    }

    static func timing() -> Timing {
        .afterCurrentEvent
    }

    static func actions(targetWindowExists: Bool) -> [Action] {
        guard targetWindowExists else { return [] }
        return [
            .activateApplication,
            .makeWindowKeyAndOrderFront,
            .orderWindowFrontRegardless,
        ]
    }
}

/// 状态栏 popover 外部点击处理策略。
///
/// 只让真实背景点击关闭 popover;状态栏按钮点击保留给按钮 action 处理,避免关闭后又被重新打开。
enum StatusPopoverOutsideClick {
    enum EventTarget {
        case background
        case statusButton
        case popover
    }

    enum Action: Equatable {
        case closePopover
        case keepPopover
    }

    static func resolve(isPopoverShown: Bool, eventTarget: EventTarget) -> Action {
        guard isPopoverShown, eventTarget == .background else {
            return .keepPopover
        }
        return .closePopover
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

/// 状态栏按钮高亮规则。
///
/// Popover 不是 `statusItem.menu` 的系统菜单路径,需要显式让按钮保持菜单栏选中背景。
enum StatusBarButtonHighlight {
    enum ApplicationTiming: Equatable {
        case immediate
        case afterCurrentEvent
    }

    static func isHighlighted(popoverIsShown: Bool) -> Bool {
        popoverIsShown
    }

    static func applicationTiming(popoverIsShown: Bool) -> ApplicationTiming {
        popoverIsShown ? .afterCurrentEvent : .immediate
    }
}

/// 状态栏双行标题的富文本布局参数。
///
/// 保留系统 NSStatusBarButton cell 负责状态栏整体垂直定位,只用 baseline offset
/// 把两行文字在行框内轻微下移,修正 attributedTitle 多行绘制偏上的视觉问题。
enum StatusBarTitleTextLayout {
    static let baselineOffset: CGFloat = -3.5
}

/// 状态栏图标布局参数。
///
/// AppKit 没有可设具体数值的 image-title spacing API。这里扩展图标画布右侧透明区域,
/// 继续交给原生 NSStatusBarButton cell 绘制 image + attributedTitle,避免标题字符串塞空格。
enum StatusBarIconLayout {
    static let pointSize: CGFloat = 18
    static let imageTitleSpacing: CGFloat = 4

    static func canvasSize(for imageSize: NSSize) -> NSSize {
        NSSize(width: imageSize.width + imageTitleSpacing, height: imageSize.height)
    }

    static func imageWithTrailingSpacing(_ image: NSImage) -> NSImage {
        guard imageTitleSpacing > 0, image.size.width > 0, image.size.height > 0 else {
            return image
        }

        let imageSize = image.size
        let paddedImage = NSImage(size: canvasSize(for: imageSize), flipped: false) { _ in
            image.draw(
                in: NSRect(origin: .zero, size: imageSize),
                from: NSRect(origin: .zero, size: imageSize),
                operation: .sourceOver,
                fraction: 1
            )
            return true
        }
        paddedImage.isTemplate = image.isTemplate
        return paddedImage
    }
}

/// 状态栏右键菜单展示方式。
///
/// 右键菜单必须使用状态栏项的菜单 presenter,普通 view 坐标弹窗会覆盖状态栏图标。
enum StatusBarMenuPresentation: Equatable {
    case statusItemMenu(selectorName: String)

    static func presenter() -> StatusBarMenuPresentation {
        .statusItemMenu(selectorName: "popUpStatusItemMenu:")
    }
}

/// 空状态栏 popover 根视图。
///
/// 使用系统窗口背景色,让浅色和暗黑模式都由 AppKit 自动适配。
final class EmptyStatusPopoverView: NSView {
    override var acceptsFirstResponder: Bool {
        true
    }

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
