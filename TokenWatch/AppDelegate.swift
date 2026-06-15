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

    /// ViewModel 实例,协调数据加载和统计计算
    /// `internal`: 让 ViewController 通过 `NSApp.delegate` 拿到同一实例,避免引入 DI 容器
    let viewModel = TokenStatsViewModel()

    /// 状态栏控制器,长驻 menu bar 显示当日 token 数
    /// 在 didFinishLaunching 时创建,terminate 时 stop() 释放 Timer + 摘掉 status item
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // 先建状态栏(订阅 ViewModel),再异步加载,确保首次 onStateChange 能被状态栏接到
        statusBarController = StatusBarController(viewModel: viewModel)

        // 尝试恢复所有 provider 的 Security-Scoped Bookmark 并并发加载数据
        // ViewController 会在 viewDidLoad 注册 observer,此处异步加载到完成时它已 ready
        Task {
            await viewModel.loadAllStats()
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // 关停状态栏:释放 Timer、移除 observer、摘掉 status item
        statusBarController?.stop()
        statusBarController = nil
        // 停止所有 provider 的 Security-Scoped 访问，释放资源
        SecurityScopedBookmarkManager.shared.stopAccessingAll()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}
