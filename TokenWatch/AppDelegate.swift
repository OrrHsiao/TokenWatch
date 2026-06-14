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

    /// ViewModel 实例，协调数据加载和统计计算
    private let viewModel = TokenStatsViewModel()

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // 尝试恢复 Security-Scoped Bookmark 并加载数据
        Task {
            await viewModel.loadStats()
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // 停止 Security-Scoped 访问，释放资源
        SecurityScopedBookmarkManager.shared.stopAccessing()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}

