//
//  AppDelegate.swift
//  TokenWatch
//
//  Created by OrrHsiao on 2026/6/13.
//

import Cocoa

@main
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    private static let initialAuthorizationPromptedKey = "TokenWatch.didPromptInitialHomeAuthorization"
    private static let openMainWindowOnLaunchKey = "TokenWatch.openMainWindowOnLaunch"

    /// ViewModel 实例,协调数据加载和统计计算
    /// `internal`: 让 ViewController 通过 `NSApp.delegate` 拿到同一实例,避免引入 DI 容器
    let viewModel = TokenStatsViewModel()

    /// 状态栏控制器,长驻 menu bar 显示当日 token 数
    /// 在 didFinishLaunching 时创建,terminate 时 stop() 释放 Timer + 摘掉 status item
    private var statusBarController: StatusBarController?
    private var mainMenuController: AppMainMenuController?
    private var mainWindowController: NSWindowController?

    private let languageSettings: AppLanguageSettings

    override init() {
        self.languageSettings = .shared
        super.init()
    }

    init(languageSettings: AppLanguageSettings) {
        self.languageSettings = languageSettings
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

        // 首次无授权时主动弹出用户目录授权;其余启动路径保持原有自动加载行为。
        Task { @MainActor in
            let coordinator = AppLaunchAuthorizationCoordinator(
                hasBookmark: {
                    SecurityScopedBookmarkManager.shared.hasBookmark(forKey: ProviderAuthorization.homeBookmarkKey)
                },
                hasPromptedInitialAuthorization: {
                    Self.hasPromptedInitialAuthorization()
                },
                markInitialAuthorizationPrompted: {
                    UserDefaults.standard.set(true, forKey: Self.initialAuthorizationPromptedKey)
                },
                loadAllStats: { [viewModel] in
                    await viewModel.loadAllStats()
                },
                requestInitialAuthorization: { [viewModel] in
                    guard let providerID = ProviderRegistry.allProviders.first?.id else { return false }
                    return await viewModel.requestAuthorization(for: providerID)
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

    /// 立即重新加载所有 provider 的统计数据。
    @objc func refreshNow(_ sender: Any?) {
        Task { await viewModel.loadAllStats() }
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
        UserDefaults.standard.bool(forKey: openMainWindowOnLaunchKey)
            || ProcessInfo.processInfo.arguments.contains("-\(openMainWindowOnLaunchKey)")
    }

    private static func hasPromptedInitialAuthorization() -> Bool {
        UserDefaults.standard.bool(forKey: initialAuthorizationPromptedKey)
            || ProcessInfo.processInfo.arguments.contains("-\(initialAuthorizationPromptedKey)")
    }
}

/// 构建主窗口。App 启动、主菜单和 UI 测试入口都走同一套窗口配置。
@MainActor
enum MainWindowFactory {
    static let contentSize = NSSize(width: 1180, height: 760)

    static func makeWindowController(
        languageSettings: AppLanguageSettings = .shared
    ) -> NSWindowController {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.isReleasedWhenClosed = false
        window.contentViewController = ViewController(languageSettings: languageSettings)
        window.setContentSize(contentSize)
        window.center()
        return NSWindowController(window: window)
    }
}

/// 协调应用启动时的数据加载和首次授权弹窗。
@MainActor
struct AppLaunchAuthorizationCoordinator {
    let hasBookmark: () -> Bool
    let hasPromptedInitialAuthorization: () -> Bool
    let markInitialAuthorizationPrompted: () -> Void
    let loadAllStats: () async -> Void
    let requestInitialAuthorization: () async -> Bool

    /// 执行启动流程:已有授权直接加载;首次缺失授权则弹出授权,取消后回落为普通未授权状态。
    func performStartupWork() async {
        if hasBookmark() {
            await loadAllStats()
            return
        }

        guard !hasPromptedInitialAuthorization() else {
            await loadAllStats()
            return
        }

        markInitialAuthorizationPrompted()
        let didAuthorize = await requestInitialAuthorization()
        if !didAuthorize {
            await loadAllStats()
        }
    }
}
