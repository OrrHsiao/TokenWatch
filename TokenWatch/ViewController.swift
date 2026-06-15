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

    /// observer 凭证 — 用于 deinit 时取消订阅,避免 ViewModel 持有失效闭包
    private var observerToken: TokenStatsViewModel.ObservationToken?

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

    /// 把 ViewModel 的状态变更回调多路复用到 Notification,
    /// 各 Tab 的 ProviderStatsViewController 自行订阅自己 provider id 的事件
    private func bindViewModel() {
        observerToken = viewModel?.observe { providerID in
            NotificationCenter.default.post(
                name: .providerStateDidChange,
                object: nil,
                userInfo: ["providerID": providerID]
            )
        }
    }

    deinit {
        guard let token = observerToken else { return }
        // 由 AppDelegate 强引用的 ViewModel 仍存活;deinit 在 main actor 调度路径中触发,
        // 用 assumeIsolated 同步移除,避免 fire-and-forget Task 在销毁后仍 fire 闭包
        MainActor.assumeIsolated {
            (NSApp.delegate as? AppDelegate)?.viewModel.removeObserver(token)
        }
    }
}
