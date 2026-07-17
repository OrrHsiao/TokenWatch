//
//  AppDelegate.swift
//  TokenWatch
//
//  Created by OrrHsiao on 2026/6/13.
//

import Cocoa
import os.log

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    private static let openMainWindowOnLaunchKey = "TokenWatch.openMainWindowOnLaunch"

    static let supportURL = URL(
        string: "https://orrhsiao.github.io/TokenWatch/support/"
    )!

    /// ViewModel 实例,协调数据加载和统计计算
    /// `internal`: 让 ViewController 通过 `NSApp.delegate` 拿到同一实例,避免引入 DI 容器
    let viewModel = TokenStatsViewModel()

    /// 状态栏控制器,长驻 menu bar 显示当日 token 数
    /// 在 didFinishLaunching 时创建,terminate 时 stop() 释放 Timer + 摘掉 status item
    private var statusBarController: StatusBarController?
    private var mainMenuController: AppMainMenuController?
    private var mainWindowController: NSWindowController?

    private let languageSettings: AppLanguageSettings
    private let externalURLOpener: (URL) -> Bool
    private let initialDirectoryAuthorizationGuide: InitialDirectoryAuthorizationGuide
    private var isInitialDirectoryAuthorizationGuidePending = false
    private var isInitialDirectoryAuthorizationGuidePresentationScheduled = false

    override init() {
        self.languageSettings = .shared
        self.externalURLOpener = { NSWorkspace.shared.open($0) }
        self.initialDirectoryAuthorizationGuide = InitialDirectoryAuthorizationGuide()
        super.init()
    }

    init(
        languageSettings: AppLanguageSettings,
        externalURLOpener: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) {
        self.languageSettings = languageSettings
        self.externalURLOpener = externalURLOpener
        self.initialDirectoryAuthorizationGuide = InitialDirectoryAuthorizationGuide()
        super.init()
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        mainMenuController = AppMainMenuController(actionTarget: self, languageSettings: languageSettings)
        mainMenuController?.start()

        // 先建状态栏(订阅 ViewModel),再异步加载,确保首次 onStateChange 能被状态栏接到
        statusBarController = StatusBarController(viewModel: viewModel)

        if Self.shouldOpenMainWindowOnLaunch() {
            _ = presentMainWindow()
        }

        // 在启动加载前快照首次安装条件，避免失效 bookmark 清理后被误判为新安装。
        let shouldPresentInitialDirectoryAuthorizationGuide =
            initialDirectoryAuthorizationGuide.shouldPresent()
        let viewModel = self.viewModel

        // 引导与本地扫描互不依赖；应在应用启动事件结束后立即出现，避免大型本地数据延迟提示。
        if shouldPresentInitialDirectoryAuthorizationGuide {
            // 先结束应用启动事件，避免窗口置前请求被启动流程覆盖。
            DispatchQueue.main.async { [weak self] in
                self?.requestInitialDirectoryAuthorizationGuide()
            }
        }

        // 启动阶段不得触发目录面板；仅清理旧共享授权，再按 provider 独立状态加载。
        Task { @MainActor [viewModel] in
            let coordinator = AppLaunchDataCoordinator(
                clearLegacyAuthorization: {
                    LegacyAuthorizationCleaner.removeLegacyState(from: .standard)
                },
                loadAllStats: { [viewModel] in
                    await viewModel.loadAllStats()
                }
            )
            await coordinator.performStartupWork()
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // 关停状态栏:释放 Timer、移除 observer、摘掉 status item
        statusBarController?.stop()
        statusBarController = nil
        mainMenuController?.stop()
        mainMenuController = nil
        // 停止所有 provider 的 Security-Scoped 访问，释放资源
        SecurityScopedBookmarkManager.shared.stopAccessingAll()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    /// 打开主窗口,用于主菜单和其他全局入口复用。
    @objc func openMainWindow(_ sender: Any?) {
        _ = presentMainWindow()
    }

    /// 打开主窗口并切换到设置页。
    @objc func showSettings(_ sender: Any?) {
        presentMainWindow()?.showSettingsFromMainMenu(sender)
    }

    /// 请求首次无目录授权引导；确认后仅进入设置页，不请求任何文件夹权限。
    private func requestInitialDirectoryAuthorizationGuide() {
        guard !isInitialDirectoryAuthorizationGuidePending else { return }
        isInitialDirectoryAuthorizationGuidePending = true
        presentInitialDirectoryAuthorizationGuideWhenReady()
    }

    /// 在启动事件结束后的下一轮主线程显示引导，避免依赖主窗口的可见或焦点时序。
    private func presentInitialDirectoryAuthorizationGuideWhenReady() {
        guard !isInitialDirectoryAuthorizationGuidePresentationScheduled else { return }
        isInitialDirectoryAuthorizationGuidePresentationScheduled = true

        // 让 applicationDidFinishLaunching 的当前事件完整结束，再开启应用级标准提示框。
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isInitialDirectoryAuthorizationGuidePresentationScheduled = false
            guard self.isInitialDirectoryAuthorizationGuidePending else { return }

            self.showInitialDirectoryAuthorizationGuide()
            self.isInitialDirectoryAuthorizationGuidePending = false
        }
    }

    /// 显示首次目录设置引导。
    /// 使用应用级标准提示框，避免首次启动时主窗口尚未获取焦点而导致 sheet 不可见。
    private func showInitialDirectoryAuthorizationGuide() {
        let language = languageSettings.resolvedLanguage
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = AppStrings.text(
            .initialDirectoryAuthorizationGuideTitle,
            language: language
        )
        alert.informativeText = AppStrings.text(
            .initialDirectoryAuthorizationGuideMessage,
            language: language
        )
        alert.addButton(withTitle: AppStrings.text(
            .initialDirectoryAuthorizationGuideOpenSettings,
            language: language
        ))
        alert.addButton(withTitle: AppStrings.text(
            .initialDirectoryAuthorizationGuideLater,
            language: language
        ))

        // runModal 不依赖父窗口成为 key window，首次启动时也能稳定呈现。
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        initialDirectoryAuthorizationGuide.markPresented()
        if response == .alertFirstButtonReturn {
            showSettings(nil)
        }
    }

    /// 立即重新加载所有 provider 的统计数据。
    @objc func refreshNow(_ sender: Any?) {
        Task { await viewModel.loadAllStats() }
    }

    /// 使用默认浏览器打开公开支持页面。
    @objc func openSupport(_ sender: Any?) {
        guard externalURLOpener(Self.supportURL) else {
            NSLog("TokenWatch failed to open the support page")
            return
        }
    }

    private func presentMainWindow() -> ViewController? {
        let target = existingMainWindow() ?? instantiateMainWindow()
        guard let target else { return nil }

        for action in StatusMainWindowPresentation.actions(targetWindowExists: true) {
            switch action {
            case .activateApplication:
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
            case .makeWindowKeyAndOrderFront:
                target.makeKeyAndOrderFront(nil)
            case .orderWindowFrontRegardless:
                target.orderFrontRegardless()
            }
        }
        return target.contentViewController as? ViewController
    }

    private func existingMainWindow() -> NSWindow? {
        if let window = mainWindowController?.window {
            return window
        }

        if let mainWindow = NSApp.mainWindow,
           mainWindow.contentViewController is ViewController,
           mainWindow.isVisible || mainWindow.isMiniaturized {
            return mainWindow
        }

        return NSApp.windows.first {
            $0.contentViewController is ViewController && ($0.isVisible || $0.isMiniaturized)
        }
    }

    private func instantiateMainWindow() -> NSWindow? {
        let windowController = MainWindowFactory.makeWindowController(languageSettings: languageSettings)
        mainWindowController = windowController
        windowController.showWindow(nil)
        return windowController.window
    }

    private static func shouldOpenMainWindowOnLaunch() -> Bool {
        let defaults = UserDefaults.standard
        return MainWindowLaunchPolicy.shouldOpen(
            hasStoredPreference: defaults.object(forKey: openMainWindowOnLaunchKey) != nil,
            storedPreference: defaults.bool(forKey: openMainWindowOnLaunchKey)
        )
    }

}

/// 将持久化的启动偏好转换为窗口展示决策；未保存过偏好时保持默认打开。
enum MainWindowLaunchPolicy {
    static func shouldOpen(hasStoredPreference: Bool, storedPreference: Bool) -> Bool {
        hasStoredPreference ? storedPreference : true
    }
}

/// 构建主窗口。App 启动、主菜单和 UI 测试入口都走同一套窗口配置。
@MainActor
enum MainWindowFactory {
    static let contentSize = NSSize(width: 1180, height: 840)

    static func makeWindowController(
        languageSettings: AppLanguageSettings = .shared
    ) -> NSWindowController {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        let contentController = ViewController(languageSettings: languageSettings)
        window.title = "TokenWatch"
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.contentViewController = contentController
        window.initialFirstResponder = contentController.view
        window.setContentSize(contentSize)
        window.center()
        return NSWindowController(window: window)
    }
}

enum LegacyAuthorizationCleaner {
    static let homeBookmarkKey = "HomeDirectoryBookmark"
    static let initialPromptKey = "TokenWatch.didPromptInitialHomeAuthorization"
    private static let logger = Logger(
        subsystem: "com.xiaoao.TokenWatch",
        category: "LegacyAuthorizationCleaner"
    )

    /// 删除旧共享 Home 授权状态，不迁移也不触碰 provider 独立 bookmark。
    /// - Parameter defaults: 保存遗留键的偏好域。
    static func removeLegacyState(from defaults: UserDefaults) {
        let removedLegacyState = defaults.object(forKey: homeBookmarkKey) != nil
            || defaults.object(forKey: initialPromptKey) != nil
        defaults.removeObject(forKey: homeBookmarkKey)
        defaults.removeObject(forKey: initialPromptKey)
        if removedLegacyState {
            logger.info("已清理旧 Home 目录授权状态")
        }
    }
}

@MainActor
struct AppLaunchDataCoordinator {
    let clearLegacyAuthorization: () -> Void
    let loadAllStats: () async -> Void

    /// 执行无交互启动流程：先清理旧授权，再按现有 provider 状态加载。
    func performStartupWork() async {
        clearLegacyAuthorization()
        await loadAllStats()
    }
}
