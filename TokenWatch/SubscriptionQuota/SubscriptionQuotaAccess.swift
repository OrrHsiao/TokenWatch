import Foundation
import os.log

/// 订阅额度的付费访问状态。
///
/// 额度展示与桌面小组件共用同一个永久买断商品，这里把购买控制器的状态收敛为“是否已解锁”，
/// 供状态栏、弹窗与设置页统一判断。购买控制器不可用（App Group 建立失败）时按未解锁处理，
/// 与小组件的 fail-closed 策略保持一致。
@MainActor
final class SubscriptionQuotaAccess {
    struct ObservationToken: Hashable {
        let id: UUID
    }

    /// 购买与恢复入口；nil 表示当前无法发起购买（App Group 失败或固定状态）。
    let purchaseController: WidgetPurchaseController?
    private(set) var isUnlocked: Bool

    private var observers: [ObservationToken: @MainActor () -> Void] = [:]
    private var purchaseObservationToken: WidgetPurchaseController.ObservationToken?
    private let logger = Logger(subsystem: "com.xiaoao.TokenWatch", category: "SubscriptionQuotaAccess")

    /// 跟随购买控制器的解锁状态；只有解锁状态变化时才通知观察者。
    /// - Parameter purchaseController: 小组件与额度共用的购买控制器。
    init(purchaseController: WidgetPurchaseController?) {
        self.purchaseController = purchaseController
        self.isUnlocked = purchaseController?.state.isUnlocked ?? false
        purchaseObservationToken = purchaseController?.observe { [weak self] state in
            self?.updateUnlocked(state.isUnlocked)
        }
    }

    /// 固定解锁状态，用于测试与截图导出，不提供购买入口。
    /// - Parameter isUnlocked: 是否视为已购买。
    init(isUnlocked: Bool) {
        self.purchaseController = nil
        self.isUnlocked = isUnlocked
    }

    deinit {
        MainActor.assumeIsolated {
            if let purchaseObservationToken {
                purchaseController?.removeObserver(purchaseObservationToken)
            }
        }
    }

    /// 注册解锁状态变化回调。
    /// - Parameter handler: 解锁状态变化后在主线程调用。
    /// - Returns: 用于移除观察者的 token。
    @discardableResult
    func observe(_ handler: @escaping @MainActor () -> Void) -> ObservationToken {
        let token = ObservationToken(id: UUID())
        observers[token] = handler
        return token
    }

    func removeObserver(_ token: ObservationToken) {
        observers.removeValue(forKey: token)
    }

    private func updateUnlocked(_ next: Bool) {
        guard isUnlocked != next else { return }
        isUnlocked = next
        logger.info("订阅额度付费状态变化: unlocked=\(next)")
        for handler in Array(observers.values) {
            handler()
        }
    }
}
