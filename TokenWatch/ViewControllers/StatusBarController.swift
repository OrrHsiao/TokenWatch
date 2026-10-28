import AppKit
import Foundation
import os.log

/// macOS 状态栏控制器
///
/// 默认常驻原有的图标 + 今日 token 文本,其后是 Claude / Codex 订阅剩余额度圆环;
/// 可在右键菜单切换为只显示其中一种。订阅额度为付费功能:未解锁时只显示今日 token,
/// 各周期是否展示及简洁 / 详细样式在主界面设置页配置。
/// 按设置间隔拉刷新,左键弹出 popover,右键弹下拉菜单(打开主窗口 / 立即刷新 / 显示设置 / 退出)。
///
/// 设计原则:
/// - 不直接读 JSONL / 不做聚合,完全复用 TokenStatsViewModel.states.byDay 与 SubscriptionQuotaStore
/// - title 计算交给 StatusBarTitleBuilder / SubscriptionQuotaPresenter,本类只负责 AppKit 层装配
@MainActor
final class StatusBarController {

    private let viewModel: TokenStatsViewModel
    private let quotaStore: SubscriptionQuotaStore
    private let autoRefreshSettings: AutoRefreshSettings
    private let languageSettings: AppLanguageSettings
    private let displaySettings: StatusBarDisplaySettings
    private let quotaAccess: SubscriptionQuotaAccess
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let statusMenu = NSMenu()
    private let menuItems = StatusMenuItems()
    private var observerToken: TokenStatsViewModel.ObservationToken?
    private var quotaObserverToken: SubscriptionQuotaStore.ObservationToken?
    private var autoRefreshSettingsObserverToken: AutoRefreshSettings.ObservationToken?
    private var languageSettingsObserverToken: AppLanguageSettings.ObservationToken?
    private var displaySettingsObserverToken: StatusBarDisplaySettings.ObservationToken?
    private var quotaAccessObserverToken: SubscriptionQuotaAccess.ObservationToken?
    private var buttonAppearanceObserver: NSKeyValueObservation?
    /// 含额度的模式下刷新倒计时、旧记录与重置点状态;模型未变化时不重新赋值图像。
    private var quotaPresentationTimer: Timer?
    private var lastRenderedQuotaModel: StatusBarQuotaModel?
    /// 按钮当前承载的展示模式;NSStatusBarButton 会改写 imagePosition,不能回读它判断模式。
    private var renderedDisplayMode: StatusBarDisplayMode?
    /// 组合模式下绘制进图像的今日 token 文本;单独今日 token 模式使用原生标题,此值为 nil。
    private var lastRenderedTokenPrimary: String?
    /// 记录 Codex 目录授权状态,授权变化后立即重读额度。
    private var lastCodexDirectoryState: ProviderDirectoryState?
    private var popoverCloseObserver: NSObjectProtocol?
    private var applicationResignActiveObserver: NSObjectProtocol?
    private var appAppearanceObserver: NSKeyValueObservation?
    private var popoverLocalEventMonitor: Any?
    private var popoverKeyEventMonitor: Any?
    private var popoverGlobalEventMonitor: Any?
    private var popoverLifecycle = StatusPopoverLifecycle()
    private var isStatusMenuPresented = false
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
    private static let quotaPresentationTickInterval: TimeInterval = 60

    private let logger = Logger(subsystem: "com.xiaoao.TokenWatch", category: "StatusBarController")

    var debugRefreshTimerInterval: TimeInterval? {
        refreshTimer?.timeInterval
    }
    var debugStatusMenuItemTitles: [String] {
        statusMenu.items.filter { !$0.isSeparatorItem && !$0.isHidden }.map(\.title)
    }
    var debugTitlePlainString: String {
        statusItem.button?.attributedTitle.string ?? ""
    }
    var debugStatusButtonToolTip: String? {
        statusItem.button?.toolTip
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
    var debugPopoverAppearance: NSAppearance? { popover.appearance }
    var debugStatusButtonImagePosition: NSControl.ImagePosition? { statusItem.button?.imagePosition }
    var debugRenderedDisplayMode: StatusBarDisplayMode? { renderedDisplayMode }
    var debugRenderedTokenPrimary: String? { lastRenderedTokenPrimary }
    var debugStatusButtonImageSize: NSSize? { statusItem.button?.image?.size }
    var debugLastRenderedQuotaModel: StatusBarQuotaModel? { lastRenderedQuotaModel }
    var debugQuotaPresentationTimerInterval: TimeInterval? { quotaPresentationTimer?.timeInterval }
    var debugDisplayModeMenuTitles: [String] {
        menuItems.displayModeMenuItem.submenu?.items.map(\.title) ?? []
    }
    var debugCheckedDisplayModeTitle: String? {
        menuItems.displayModeMenuItem.submenu?.items.first { $0.state == .on }?.title
    }
    func debugRenderTitle() {
        renderTitle()
    }

    init(
        viewModel: TokenStatsViewModel,
        quotaStore: SubscriptionQuotaStore = SubscriptionQuotaStore(),
        autoRefreshSettings: AutoRefreshSettings = .shared,
        languageSettings: AppLanguageSettings = .shared,
        displaySettings: StatusBarDisplaySettings = .shared,
        quotaAccess: SubscriptionQuotaAccess = SubscriptionQuotaAccess(isUnlocked: false)
    ) {
        self.viewModel = viewModel
        self.quotaStore = quotaStore
        self.autoRefreshSettings = autoRefreshSettings
        self.languageSettings = languageSettings
        self.displaySettings = displaySettings
        self.quotaAccess = quotaAccess
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusMenu.userInterfaceLayoutDirection = .leftToRight

        configureButton()
        configurePopover()
        installMenu()
        subscribeToViewModel()
        subscribeToQuotaStore()
        subscribeToAutoRefreshSettings()
        subscribeToLanguageSettings()
        subscribeToDisplaySettings()
        subscribeToQuotaAccess()
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
            quotaPresentationTimer?.invalidate()
            if let token = displaySettingsObserverToken {
                displaySettings.removeObserver(token)
            }
            if let token = quotaAccessObserverToken {
                quotaAccess.removeObserver(token)
            }
            if let token = quotaObserverToken {
                quotaStore.removeObserver(token)
            }
            if let token = popoverCloseObserver {
                NotificationCenter.default.removeObserver(token)
            }
            if let token = applicationResignActiveObserver {
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
        quotaPresentationTimer?.invalidate()
        quotaPresentationTimer = nil
        if let token = observerToken {
            viewModel.removeObserver(token)
            observerToken = nil
        }
        if let token = quotaObserverToken {
            quotaStore.removeObserver(token)
            quotaObserverToken = nil
        }
        if let token = displaySettingsObserverToken {
            displaySettings.removeObserver(token)
            displaySettingsObserverToken = nil
        }
        if let token = quotaAccessObserverToken {
            quotaAccess.removeObserver(token)
            quotaAccessObserverToken = nil
        }
        buttonAppearanceObserver?.invalidate()
        buttonAppearanceObserver = nil
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
        if let token = applicationResignActiveObserver {
            NotificationCenter.default.removeObserver(token)
            applicationResignActiveObserver = nil
        }
        if let token = appAppearanceObserver {
            token.invalidate()
            appAppearanceObserver = nil
        }
        popoverLifecycle.reset()
        isStatusMenuPresented = false
        removePopoverDismissMonitors()
        popover.close()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    // MARK: - Setup

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.userInterfaceLayoutDirection = .leftToRight
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
        // 额度图像在绘制时按按钮外观解析颜色;状态栏深浅变化时重建一次,避免沿用旧外观缓存。
        buttonAppearanceObserver = button.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self, self.effectiveDisplayMode.showsQuota else { return }
                self.renderTitle(forceImage: true)
            }
        }
    }

    private func configurePopover() {
        let contentViewController = StatusPopoverViewController(
            viewModel: viewModel,
            quotaStore: quotaStore,
            languageSettings: languageSettings,
            quotaAccess: quotaAccess
        )
        contentViewController.preferredContentSize = StatusBarPopoverLayout.contentSize
        contentViewController.onRequestQuotaUnlock = { [weak self] in
            self?.openQuotaPurchaseSettings()
        }

        // 外部点击由带 presentation generation 的 monitor 统一处理。
        // 若同时使用 transient，AppKit 可能在 mouseDown 先关闭，随后 mouseUp action 又重新打开。
        popover.behavior = StatusBarPopoverPolicy.behavior
        popover.contentSize = StatusBarPopoverLayout.contentSize
        popover.contentViewController = contentViewController
        syncPopoverAppearance()
        appAppearanceObserver = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.syncPopoverAppearance()
            }
        }
        popoverCloseObserver = NotificationCenter.default.addObserver(
            forName: NSPopover.didCloseNotification,
            object: popover,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handlePopoverDidClose()
            }
        }
        applicationResignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.dismissCurrentPopover()
            }
        }
    }

    /// 拼装两行富文本:数字加粗,单位字号小一号
    /// 两行 paragraphStyle 设置 maximumLineHeight 把行高压紧,使两行总高接近图标高度(18pt)
    /// - Parameter includesBaselineOffset: 原生标题需要 baseline 偏移修正 cell 绘制偏上;
    ///   组合模式自行在图像中居中绘制,不需要该偏移。
    private func makeAttributedTitle(primary: String, includesBaselineOffset: Bool = true) -> NSAttributedString {
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
                .baselineOffset: includesBaselineOffset ? StatusBarTitleTextLayout.baselineOffset : 0,
            ]
        )
        result.append(NSAttributedString(
            string: "\n\(unit)",
            attributes: [
                .font: NSFont.systemFont(ofSize: 7),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: secondaryParagraph,
                .baselineOffset: includesBaselineOffset ? StatusBarTitleTextLayout.baselineOffset : 0,
            ]
        ))
        return result
    }

    private func installMenu() {
        menuItems.openItem.action = #selector(openMainWindow)
        menuItems.openItem.keyEquivalent = "0"
        menuItems.openItem.target = self
        statusMenu.addItem(menuItems.openItem)

        menuItems.refreshItem.action = #selector(refreshNow)
        menuItems.refreshItem.keyEquivalent = "r"
        menuItems.refreshItem.target = self
        statusMenu.addItem(menuItems.refreshItem)

        statusMenu.addItem(NSMenuItem.separator())

        // 右键菜单承载状态栏显示模式;各额度周期的展示与样式在主界面设置页配置。
        let displayModeMenu = NSMenu()
        for mode in StatusBarDisplayMode.allCases {
            let item = NSMenuItem(title: "", action: #selector(selectDisplayMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            displayModeMenu.addItem(item)
        }
        menuItems.displayModeMenuItem.submenu = displayModeMenu
        statusMenu.addItem(menuItems.displayModeMenuItem)

        menuItems.chooseClaudeQuotaFileItem.action = #selector(chooseClaudeQuotaFile)
        menuItems.chooseClaudeQuotaFileItem.target = self
        statusMenu.addItem(menuItems.chooseClaudeQuotaFileItem)

        statusMenu.addItem(NSMenuItem.separator())

        menuItems.quitItem.action = #selector(quitApp)
        menuItems.quitItem.keyEquivalent = "q"
        menuItems.quitItem.target = self
        statusMenu.addItem(menuItems.quitItem)

        updateMenuTitles()
    }

    private func subscribeToViewModel() {
        observerToken = viewModel.observe { [weak self] providerID in
            guard let self else { return }
            if providerID == .codex {
                self.refreshQuotaIfCodexDirectoryChanged()
            }
            // 等所有 provider 都不再 loading 才重绘,避免 loadAllStats 并发跑时
            // 状态栏数字在中间态多次跳变(800k → 1.2M → 1.25M)。
            // 单 provider 完成时其它仍 isLoading,这里挡掉;最后一个完成时 allSatisfy 才通过。
            self.syncLoadingAnimationState()
            guard self.viewModel.states.values.allSatisfy({ !$0.isLoading }) else { return }
            self.renderTitle()
        }
    }

    private func subscribeToQuotaStore() {
        quotaObserverToken = quotaStore.observe { [weak self] in
            guard let self, self.effectiveDisplayMode.showsQuota else { return }
            self.renderTitle()
        }
    }

    private func subscribeToDisplaySettings() {
        displaySettingsObserverToken = displaySettings.observe { [weak self] in
            guard let self else { return }
            self.updateMenuTitles()
            self.syncLoadingAnimationState()
            self.renderTitle()
        }
    }

    /// 购买或恢复后立即读取额度并重绘;退款撤销后同步隐藏额度与相关菜单项。
    private func subscribeToQuotaAccess() {
        quotaAccessObserverToken = quotaAccess.observe { [weak self] in
            guard let self else { return }
            self.updateMenuTitles()
            self.syncLoadingAnimationState()
            self.renderTitle()
            self.refreshQuotaIfUnlocked()
        }
    }

    /// Codex 额度复用 Codex 数据目录授权;授权状态变化(例如在设置页重新授权)后立即重读。
    private func refreshQuotaIfCodexDirectoryChanged() {
        let directoryState = viewModel.states[.codex]?.directoryState
        guard directoryState != lastCodexDirectoryState else { return }
        lastCodexDirectoryState = directoryState
        refreshQuotaIfUnlocked()
    }

    /// 额度为付费功能,未解锁时不读取本地额度记录。
    private func refreshQuotaIfUnlocked() {
        guard quotaAccess.isUnlocked else { return }
        let quotaStore = self.quotaStore
        Task { @MainActor in
            await quotaStore.refresh()
        }
    }

    /// 实际生效的展示模式。
    ///
    /// 额度未解锁,或设置页把两个 Agent 的所有周期都关闭时,含额度的模式退回只显示今日 token,
    /// 保证状态栏始终有可点击的内容;用户选择的模式本身保持不变,解锁或重新开启后自动恢复。
    private var effectiveDisplayMode: StatusBarDisplayMode {
        let mode = displaySettings.mode
        guard mode.showsQuota else { return mode }
        guard quotaAccess.isUnlocked, displaySettings.hasVisibleQuotaWindow else { return .todayTokens }
        return mode
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
        menuItems.openItem.title = AppStrings.text(.statusMenuOpen, language: language)
        menuItems.refreshItem.title = AppStrings.text(.refreshNow, language: language)
        menuItems.displayModeMenuItem.title = AppStrings.text(.statusMenuDisplayMode, language: language)
        menuItems.chooseClaudeQuotaFileItem.title = AppStrings.text(
            .statusMenuChooseClaudeQuotaFile,
            language: language
        )
        menuItems.quitItem.title = AppStrings.text(.statusMenuQuit, language: language)
        // 未解锁时额度不可见,显示模式与额度文件入口没有意义,一并隐藏。
        menuItems.displayModeMenuItem.isHidden = !quotaAccess.isUnlocked
        menuItems.chooseClaudeQuotaFileItem.isHidden = !quotaAccess.isUnlocked

        let selectedMode = displaySettings.mode
        for item in menuItems.displayModeMenuItem.submenu?.items ?? [] {
            guard let mode = (item.representedObject as? String).flatMap(StatusBarDisplayMode.init(rawValue:)) else {
                continue
            }
            item.title = mode.title(language: language)
            item.state = mode == selectedMode ? .on : .off
        }
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
        refreshQuotaIfUnlocked()
        Task { await viewModel.loadAllStats(mode: .silentIfUnchanged) }
    }

    // MARK: - Render

    private func syncLoadingAnimationState() {
        // 只有包含今日 token 的模式承载原有仪表盘加载动画;纯额度模式不跑动画。
        if effectiveDisplayMode.showsTodayTokens,
           viewModel.states.values.contains(where: { $0.isLoading }) {
            startLoadingAnimation()
        } else {
            stopLoadingAnimation()
        }
    }

    private func startLoadingAnimation() {
        guard loadingAnimationTimer == nil else { return }
        loadingAnimationFrameIndex = 0
        renderLoadingAnimationFrame()

        let timer = Timer(timeInterval: StatusBarLoadingAnimation.frameInterval, repeats: true) { [weak self] _ in
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
        applyButtonImage(
            symbolName: symbolName,
            tokenPrimary: lastRenderedTokenPrimary,
            quotaModel: lastRenderedQuotaModel,
            force: false
        )
    }

    private func makeSymbolImage(symbolName: String) -> NSImage? {
        let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: "AI Token Watch"
        )?.withSymbolConfiguration(iconSymbolConfig)
        // 状态栏图标做成 template 由系统按主题自动反色
        image?.isTemplate = true
        return image
    }

    /// 按当前模式组装按钮图像。
    ///
    /// 单独今日 token 模式沿用原生 image + attributedTitle；含额度的模式使用 image-only，
    /// 组合模式把档位图标、今日 token 文本与额度圆环按顺序绘制进同一张图。
    /// 输入都未变化时不重新赋值，避免状态栏重新布局。
    /// - Parameters:
    ///   - symbolName: 今日 token 档位图标；纯额度模式传 nil。
    ///   - tokenPrimary: 组合模式绘制进图像的今日 token 数字；其他模式传 nil。
    ///   - quotaModel: 额度圆环模型；纯今日 token 模式传 nil。
    ///   - force: 外观变化时即使输入相同也重建图像。
    private func applyButtonImage(
        symbolName: String?,
        tokenPrimary: String?,
        quotaModel: StatusBarQuotaModel?,
        force: Bool
    ) {
        guard let button = statusItem.button else { return }
        let mode = effectiveDisplayMode
        guard force
            || mode != renderedDisplayMode
            || symbolName != lastRenderedSymbolName
            || tokenPrimary != lastRenderedTokenPrimary
            || quotaModel != lastRenderedQuotaModel else {
            return
        }

        let symbolImage = symbolName.flatMap(makeSymbolImage(symbolName:))
        let image: NSImage?
        if let quotaModel, let symbolImage, let tokenPrimary {
            image = StatusBarQuotaImageRenderer.makeImage(
                for: quotaModel,
                leadingSymbol: symbolImage,
                leadingTitle: makeAttributedTitle(primary: tokenPrimary, includesBaselineOffset: false)
            )
        } else if let quotaModel {
            image = StatusBarQuotaImageRenderer.makeImage(for: quotaModel)
        } else {
            image = symbolImage.map(StatusBarIconLayout.imageWithTrailingSpacing)
        }

        if mode != renderedDisplayMode {
            // 只有单独今日 token 模式使用原生标题；组合模式的文本已在图像中。
            button.imagePosition = mode == .todayTokens ? .imageLeft : .imageOnly
            if mode != .todayTokens {
                button.attributedTitle = NSAttributedString(string: "")
            }
            renderedDisplayMode = mode
            logger.info("状态栏显示模式已应用: \(mode.rawValue, privacy: .public)")
        }
        button.image = image
        lastRenderedSymbolName = symbolName
        lastRenderedTokenPrimary = tokenPrimary
        lastRenderedQuotaModel = quotaModel
    }

    /// 按显示模式重绘状态栏：原有图标 + 今日 token 文本在前，额度圆环在后。
    /// - Parameter forceImage: 外观变化时即使内容相同也重建图像。
    private func renderTitle(forceImage: Bool = false) {
        guard let button = statusItem.button else { return }
        let mode = effectiveDisplayMode
        let language = languageSettings.resolvedLanguage
        var toolTipSections: [String] = []

        var symbolName: String?
        var tokenPrimary: String?
        if mode.showsTodayTokens {
            let todayKey = Self.todayKey()
            let primary = StatusBarTitleBuilder.build(states: viewModel.states, todayKey: todayKey)
            if mode == .todayTokens {
                let attributedTitle = makeAttributedTitle(primary: primary)
                if button.attributedTitle != attributedTitle {
                    button.attributedTitle = attributedTitle
                }
            } else {
                tokenPrimary = primary
            }
            // 图标分档:用与文本相同的累加口径,避免文字和图标显示出处不一致
            let total = StatusBarTitleBuilder.totalTokens(states: viewModel.states, todayKey: todayKey)
            symbolName = StatusBarTitleBuilder.symbolName(forTotalTokens: total)
            toolTipSections.append(todayTokensToolTip(primary: primary))
            lastRenderedDayKey = todayKey
        }

        var quotaModel: StatusBarQuotaModel?
        if mode.showsQuota {
            startQuotaPresentationTimer()
            let now = Date()
            let presentations = SubscriptionQuotaProvider.allCases.map { provider in
                SubscriptionQuotaPresenter.make(
                    provider: provider,
                    state: quotaStore.state(for: provider),
                    now: now,
                    language: language
                )
            }
            let displaySettings = self.displaySettings
            quotaModel = StatusBarQuotaModel.make(
                presentations: presentations,
                configuration: { displaySettings.quotaWindowConfiguration(provider: $0, kind: $1) },
                ringDiameter: StatusBarQuotaLayout.ringDiameter(
                    forStatusBarThickness: NSStatusBar.system.thickness
                )
            )
            // 悬停说明只列出状态栏中实际展示的 Agent,简洁模式下仍可在此查看百分比。
            let visibleProviders = Set(quotaModel?.groups.map(\.provider) ?? [])
            toolTipSections.append(SubscriptionQuotaPresenter.toolTip(
                for: presentations.filter { visibleProviders.contains($0.provider) },
                language: language
            ))
        } else {
            stopQuotaPresentationTimer()
        }

        applyButtonImage(
            symbolName: symbolName,
            tokenPrimary: tokenPrimary,
            quotaModel: quotaModel,
            force: forceImage
        )

        let toolTip = toolTipSections.joined(separator: "\n\n")
        if button.toolTip != toolTip {
            button.toolTip = toolTip
        }
        // 含额度的图像没有原生文字可供读屏，使用与悬停说明一致的辅助功能文案。
        button.setAccessibilityLabel(mode.showsQuota ? toolTip.replacingOccurrences(of: "\n", with: ", ") : nil)
    }

    private func todayTokensToolTip(primary: String) -> String {
        let rate = TokenBurnRateCalculator.calculateRate(states: viewModel.states, now: Date())
        let isChinese = languageSettings.resolvedLanguage.baseLanguageCode == "zh"
        guard rate.activeTokensPerSecond > 0 else {
            return "TokenWatch · \(primary) Tokens"
        }
        let rateLabel = isChinese ? "燃烧速率" : "Burn Rate"
        let rateText = TokenBurnRateCalculator.formatRate(rate.activeTokensPerSecond)
        if rate.costPerHour >= 0.01 {
            let costText = TokenBurnRateCalculator.formatCostPerHour(rate.costPerHour)
            return "TokenWatch · \(primary) Tokens\n\(rateLabel): \(rateText) (\(costText))"
        }
        return "TokenWatch · \(primary) Tokens\n\(rateLabel): \(rateText)"
    }

    private func startQuotaPresentationTimer() {
        guard quotaPresentationTimer == nil else { return }
        let timer = Timer(timeInterval: Self.quotaPresentationTickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.effectiveDisplayMode.showsQuota else { return }
                self.renderTitle()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        quotaPresentationTimer = timer
    }

    private func stopQuotaPresentationTimer() {
        quotaPresentationTimer?.invalidate()
        quotaPresentationTimer = nil
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
        performPopoverLifecycleAction(popoverLifecycle.toggle())
    }

    private func showStatusMenu() {
        // NSMenu 会进入嵌套 tracking run loop，popover 的 didClose 可能在 presenter
        // 返回前到达。单独记录菜单展示期，避免迟到的 popover 回调清掉菜单高亮。
        isStatusMenuPresented = true
        defer {
            isStatusMenuPresented = false
            setStatusButtonHighlighted(popoverIsShown: false)
        }

        performPopoverLifecycleAction(popoverLifecycle.dismiss())
        setStatusButtonHighlighted(popoverIsShown: false)
        switch StatusBarMenuPresentation.presenter() {
        case .statusItemMenu(let selectorName):
            // 左键需要自定义 popover,所以不能常驻设置 statusItem.menu;
            // 右键这里直接走 NSStatusItem 的菜单 presenter,由 AppKit 负责状态栏定位。
            let selector = NSSelectorFromString(selectorName)
            guard statusItem.responds(to: selector) else {
                logger.error("状态栏菜单 presenter 不可用: \(selectorName, privacy: .public)")
                return
            }
            _ = statusItem.perform(selector, with: statusMenu)
        }
    }

    private func performPopoverLifecycleAction(_ action: StatusPopoverLifecycle.Action) {
        switch action {
        case .none:
            break
        case .show(let generation):
            showPopover(generation: generation)
        case .close(let generation):
            closePopover(generation: generation)
        }
    }

    private func showPopover(generation: StatusPopoverLifecycle.Generation) {
        guard popoverLifecycle.ownsShownPresentation(generation) else { return }
        guard let button = statusItem.button else {
            popoverLifecycle.showFailed(generation: generation)
            return
        }

        // 每一轮 presentation 都重新绑定 monitor；上一轮已排队的异步回调会被
        // generation guard 拒绝，不能关闭或改亮新弹窗。
        removePopoverDismissMonitors()
        syncPopoverAppearance()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        guard popover.isShown else {
            popoverLifecycle.showFailed(generation: generation)
            setStatusButtonHighlighted(popoverIsShown: false)
            return
        }

        installPopoverDismissMonitors(generation: generation)
        activatePopoverAfterShowing(generation: generation)
        setStatusButtonHighlighted(popoverIsShown: true, generation: generation)
    }

    private func closePopover(generation: StatusPopoverLifecycle.Generation) {
        guard popoverLifecycle.phase == .closing(generation) else { return }
        setStatusButtonHighlighted(popoverIsShown: false)
        // close() 强制结束本轮 presentation；didClose 是唯一完成 closing 状态并
        // 执行待定 reopen 的位置，避免关闭动画中复用同一个 NSPopover。
        // monitor 保留到 didClose，使关闭期间的背景点击 / Escape 仍能取消待定 reopen。
        popover.close()
    }

    private func dismissCurrentPopover() {
        performPopoverLifecycleAction(popoverLifecycle.dismiss())
    }

    private func handlePopoverDidClose() {
        // 极端情况下旧 didClose 可能排到新一轮 show 之后；物理弹窗仍显示时忽略它。
        guard !popover.isShown else { return }

        removePopoverDismissMonitors()
        let nextAction = popoverLifecycle.didClose()
        if !isStatusMenuPresented {
            setStatusButtonHighlighted(popoverIsShown: false)
        }
        performPopoverLifecycleAction(nextAction)
    }

    private func setStatusButtonHighlighted(
        popoverIsShown: Bool,
        generation: StatusPopoverLifecycle.Generation? = nil
    ) {
        let isHighlighted = StatusBarButtonHighlight.isHighlighted(popoverIsShown: popoverIsShown)
        switch StatusBarButtonHighlight.applicationTiming(popoverIsShown: popoverIsShown) {
        case .immediate:
            applyStatusButtonHighlight(isHighlighted)
        case .afterCurrentEvent:
            Task { @MainActor [weak self] in
                guard let self,
                      let generation,
                      self.popoverLifecycle.ownsShownPresentation(generation),
                      self.popover.isShown else { return }
                self.applyStatusButtonHighlight(isHighlighted)
            }
        }
    }

    private func applyStatusButtonHighlight(_ isHighlighted: Bool) {
        guard let button = statusItem.button else { return }
        button.highlight(isHighlighted)
        button.needsDisplay = true
    }

    private func activatePopoverAfterShowing(generation: StatusPopoverLifecycle.Generation) {
        Task { @MainActor [weak self] in
            guard let self,
                  self.popoverLifecycle.ownsShownPresentation(generation),
                  self.popover.isShown else { return }
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

    /// 将 popover 外观与系统/应用当前 effectiveAppearance 保持同步。
    ///
    /// 解决在非暗黑模式下，因 status item 所在状态栏窗口默认具有 vibrantDark 外观，
    /// 导致 NSPopover 默认继承暗色外观并使内部卡片、热力图和折线图错误显示为暗黑背景的问题。
    private func syncPopoverAppearance() {
        popover.appearance = NSApp.effectiveAppearance
        if let view = popover.contentViewController?.view {
            DashboardAppearanceRefresh.refresh(in: view)
        }
    }

    private func installPopoverDismissMonitors(generation: StatusPopoverLifecycle.Generation) {
        let mouseDownEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if popoverLocalEventMonitor == nil {
            popoverLocalEventMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseDownEvents) { [weak self] event in
                MainActor.assumeIsolated {
                    self?.handleLocalPopoverMouseDown(event, generation: generation)
                }
                return event
            }
            if popoverLocalEventMonitor == nil {
                logger.error("无法安装 popover 本地鼠标监听器")
            }
        }

        if popoverKeyEventMonitor == nil {
            popoverKeyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let didHandle = MainActor.assumeIsolated {
                    self?.handleLocalPopoverKeyDown(event, generation: generation) ?? false
                }
                return didHandle ? nil : event
            }
            if popoverKeyEventMonitor == nil {
                logger.error("无法安装 popover 键盘监听器")
            }
        }

        if popoverGlobalEventMonitor == nil {
            popoverGlobalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseDownEvents) { [weak self] _ in
                // AppKit 在主线程调用 event monitor；这里同步更新 desiredVisible，
                // 避免额外 hop 排到 didClose/reopen 之后才执行。
                MainActor.assumeIsolated {
                    self?.dismissPopoverPresentation(generation: generation)
                }
            }
            if popoverGlobalEventMonitor == nil {
                logger.error("无法安装 popover 全局鼠标监听器")
            }
        }
    }

    private func removePopoverDismissMonitors() {
        if let monitor = popoverLocalEventMonitor {
            NSEvent.removeMonitor(monitor)
            popoverLocalEventMonitor = nil
        }
        if let monitor = popoverKeyEventMonitor {
            NSEvent.removeMonitor(monitor)
            popoverKeyEventMonitor = nil
        }
        if let monitor = popoverGlobalEventMonitor {
            NSEvent.removeMonitor(monitor)
            popoverGlobalEventMonitor = nil
        }
    }

    private func handleLocalPopoverMouseDown(
        _ event: NSEvent,
        generation: StatusPopoverLifecycle.Generation
    ) {
        guard popoverLifecycle.ownsPresentation(generation) else { return }
        let eventTarget = popoverEventTarget(for: event)
        switch StatusPopoverOutsideClick.resolve(
            isPopoverShown: popoverLifecycle.ownsPresentation(generation),
            eventTarget: eventTarget
        ) {
        case .closePopover:
            dismissPopoverPresentation(generation: generation)
        case .keepPopover:
            break
        }
    }

    private func handleLocalPopoverKeyDown(
        _ event: NSEvent,
        generation: StatusPopoverLifecycle.Generation
    ) -> Bool {
        guard event.keyCode == StatusPopoverKeyboard.escapeKeyCode,
              popoverLifecycle.ownsPresentation(generation) else { return false }
        dismissPopoverPresentation(generation: generation)
        return true
    }

    private func dismissPopoverPresentation(generation: StatusPopoverLifecycle.Generation) {
        performPopoverLifecycleAction(popoverLifecycle.dismiss(generation: generation))
    }

    private func popoverEventTarget(for event: NSEvent) -> StatusPopoverOutsideClick.EventTarget {
        if let button = statusItem.button, eventHitsView(event, view: button) {
            return .statusButton
        }
        if let contentView = popover.contentViewController?.view, eventHitsView(event, view: contentView) {
            return .popover
        }
        // 订阅区说明气泡是独立窗口,其中的点击属于弹窗内部交互,不应关闭弹窗。
        if let contentController = popover.contentViewController as? StatusPopoverViewController,
           contentController.ownsAuxiliaryWindow(withNumber: event.windowNumber) {
            return .popover
        }
        return .background
    }

    private func eventHitsView(_ event: NSEvent, view: NSView) -> Bool {
        guard let viewWindow = view.window else { return false }

        // NSEvent.window 的对象身份在状态栏内部窗口切换时并不稳定；windowNumber
        // 才是同一原生窗口的可靠标识。
        if event.windowNumber == viewWindow.windowNumber {
            let pointInView = view.convert(event.locationInWindow, from: nil)
            return view.bounds.contains(pointInView)
        }

        let screenPoint = event.window.map {
            $0.convertPoint(toScreen: event.locationInWindow)
        } ?? NSEvent.mouseLocation
        let viewRectInWindow = view.convert(view.bounds, to: nil)
        let viewRectOnScreen = viewWindow.convertToScreen(viewRectInWindow)
        return viewRectOnScreen.contains(screenPoint)
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
        refreshQuotaIfUnlocked()
        Task { await viewModel.loadAllStats() }
    }

    @objc private func selectDisplayMode(_ sender: NSMenuItem) {
        guard let mode = (sender.representedObject as? String).flatMap(StatusBarDisplayMode.init(rawValue:)) else {
            return
        }
        logger.info("状态栏显示切换为 \(mode.rawValue, privacy: .public)")
        displaySettings.mode = mode
    }

    /// 弹窗订阅区的解锁入口:关闭弹窗后打开主界面设置页的订阅额度区块,由其承载购买与恢复。
    private func openQuotaPurchaseSettings() {
        logger.info("从状态栏弹窗打开订阅额度解锁入口")
        dismissCurrentPopover()
        Task { @MainActor in
            (NSApp.delegate as? AppDelegate)?.showStatusBarQuotaSettings()
        }
    }

    @objc private func chooseClaudeQuotaFile() {
        let quotaStore = self.quotaStore
        // 菜单 action 执行时仍在 tracking;延后到下一轮主线程再弹出文件面板。
        Task { @MainActor in
            await quotaStore.requestClaudeFileAuthorization()
        }
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

/// 状态栏右键菜单项;按引用更新文案,避免依赖菜单项的位置索引。
@MainActor
private final class StatusMenuItems {
    let openItem = NSMenuItem()
    let refreshItem = NSMenuItem()
    let displayModeMenuItem = NSMenuItem()
    let chooseClaudeQuotaFileItem = NSMenuItem()
    let quitItem = NSMenuItem()
}

/// 状态栏 popover 固定布局参数。
enum StatusBarPopoverLayout {
    static var contentSize: NSSize { StatusPopoverViewController.contentSize }
}

/// Popover 关闭策略。
///
/// `.transient` 会让 AppKit 在 mouseDown 自动关闭；而状态栏按钮的 action 在
/// mouseUp 才执行，两条路径叠加会把一次“关闭”误判成下一次“打开”。
enum StatusBarPopoverPolicy {
    static let behavior: NSPopover.Behavior = .applicationDefined
}

/// 状态栏 popover 的逻辑生命周期。
///
/// `NSPopover.isShown` 在关闭动画和 didClose 之间不能表达用户的最终意图，因此
/// 这里同时维护物理阶段和 desiredVisible。每轮展示分配 generation，让已经排队的
/// monitor / Task 只能操作创建它们的那一轮 presentation。
struct StatusPopoverLifecycle {
    typealias Generation = UInt64

    enum Phase: Equatable {
        case hidden
        case shown(Generation)
        case closing(Generation)
    }

    enum Action: Equatable {
        case none
        case show(Generation)
        case close(Generation)
    }

    private(set) var phase: Phase = .hidden
    private(set) var desiredVisible = false
    private var nextGeneration: Generation = 0

    mutating func toggle() -> Action {
        switch phase {
        case .hidden:
            desiredVisible = true
            return beginShowing()
        case .shown(let generation):
            desiredVisible = false
            phase = .closing(generation)
            return .close(generation)
        case .closing:
            // 关闭动画不可安全取消；只记录动画结束后是否需要重新打开。
            desiredVisible.toggle()
            return .none
        }
    }

    mutating func dismiss() -> Action {
        desiredVisible = false
        guard case .shown(let generation) = phase else { return .none }
        phase = .closing(generation)
        return .close(generation)
    }

    mutating func dismiss(generation: Generation) -> Action {
        guard ownsPresentation(generation) else { return .none }
        return dismiss()
    }

    mutating func didClose() -> Action {
        switch phase {
        case .hidden:
            desiredVisible = false
            return .none
        case .shown:
            // applicationDefined 之外仍可能因窗口销毁等原因被 AppKit 关闭。
            phase = .hidden
            desiredVisible = false
            return .none
        case .closing:
            phase = .hidden
            guard desiredVisible else { return .none }
            return beginShowing()
        }
    }

    mutating func showFailed(generation: Generation) {
        guard phase == .shown(generation) else { return }
        phase = .hidden
        desiredVisible = false
    }

    mutating func reset() {
        phase = .hidden
        desiredVisible = false
    }

    func ownsShownPresentation(_ generation: Generation) -> Bool {
        phase == .shown(generation)
    }

    func ownsPresentation(_ generation: Generation) -> Bool {
        phase == .shown(generation) || phase == .closing(generation)
    }

    private mutating func beginShowing() -> Action {
        nextGeneration &+= 1
        phase = .shown(nextGeneration)
        return .show(nextGeneration)
    }
}

/// `.applicationDefined` popover 不会替我们处理 Escape，统一在本地 key monitor 关闭。
enum StatusPopoverKeyboard {
    static let escapeKeyCode: UInt16 = 53
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
/// 关闭后保留的窗口必须先恢复可见,再激活应用,让系统能够切换到窗口所属的 Space。
/// 已在屏幕上的主窗口若被其它 app 盖住,仅 makeKeyAndOrderFront 不够,需要 orderFrontRegardless。
enum StatusMainWindowPresentation {
    enum Timing: Equatable {
        case afterCurrentEvent
    }

    enum Action: Equatable {
        case restoreWindow
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
            .restoreWindow,
            .activateApplication,
            .makeWindowKeyAndOrderFront,
            .orderWindowFrontRegardless,
        ]
    }

    /// 恢复并置前同一个主窗口,在应用激活前确保它已重新进入窗口列表。
    /// - Parameters:
    ///   - window: 已有或新建的主窗口。
    ///   - activateApplication: 窗口恢复后执行的应用激活操作。
    @MainActor
    static func present(_ window: NSWindow, activateApplication: () -> Void) {
        for action in actions(targetWindowExists: true) {
            switch action {
            case .restoreWindow:
                if window.isMiniaturized {
                    window.deminiaturize(nil)
                }
                // 先仅恢复可见性,激活后再设置 key window,保留正常的焦点通知顺序。
                window.orderFront(nil)
            case .activateApplication:
                activateApplication()
            case .makeWindowKeyAndOrderFront:
                window.makeKeyAndOrderFront(nil)
            case .orderWindowFrontRegardless:
                window.orderFrontRegardless()
            }
        }
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
