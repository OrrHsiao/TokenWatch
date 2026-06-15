//
//  ViewController.swift
//  TokenWatch
//
//  Created by OrrHsiao on 2026/6/13.
//

import Cocoa

/// 主视图控制器 — NSTabViewController 容器
/// 每个 provider 一个 Tab,内容由 ProviderStatsViewController 提供
///
/// 设计:Storyboard 仍指向本类,但运行时用 NSTabView 替换默认视图,
/// 把 ProviderRegistry 注册的 provider 一一装载为 TabViewItem。
class ViewController: NSTabViewController {

    /// 通过 NSApp.delegate 获取与 AppDelegate 同一个 ViewModel 实例
    private var viewModel: TokenStatsViewModel? {
        (NSApp.delegate as? AppDelegate)?.viewModel
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tabStyle = .toolbar
        installTabs()
        bindViewModel()
    }

    /// 把 ProviderRegistry 注册的 provider 顺序装入 Tab
    private func installTabs() {
        for provider in ProviderRegistry.allProviders {
            let vc = ProviderStatsViewController(provider: provider)
            let item = NSTabViewItem(viewController: vc)
            item.label = provider.displayName
            addTabViewItem(item)
        }
    }

    /// 把 ViewModel 的 onStateChange 回调多路复用到 Notification,
    /// 各 Tab 的 ProviderStatsViewController 自行订阅自己 provider id 的事件
    private func bindViewModel() {
        viewModel?.onStateChange = { providerID in
            NotificationCenter.default.post(
                name: .providerStateDidChange,
                object: nil,
                userInfo: ["providerID": providerID]
            )
        }
    }
}
