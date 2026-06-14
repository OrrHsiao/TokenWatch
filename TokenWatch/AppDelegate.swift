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

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // 尝试恢复所有 provider 的 Security-Scoped Bookmark 并并发加载数据
        // ViewController 会在 viewDidLoad 注册 onStateChange,此处异步加载到完成时它已 ready
        Task {
            await viewModel.loadAllStats()
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // 停止所有 provider 的 Security-Scoped 访问，释放资源
        SecurityScopedBookmarkManager.shared.stopAccessingAll()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}
