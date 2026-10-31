import AppKit
import Testing
@testable import TokenWatch

@MainActor
@Suite("SubscriptionQuotaAccess")
struct SubscriptionQuotaAccessTests {

    @Test("购买控制器不可用时按未解锁处理")
    func missingPurchaseControllerIsLocked() {
        let access = SubscriptionQuotaAccess(purchaseController: nil)

        #expect(!access.isUnlocked)
        #expect(access.purchaseController == nil)
    }

    @Test("跟随小组件买断的解锁状态，只在解锁状态变化时通知")
    func followsWidgetPurchaseUnlockState() async {
        let purchaseController = WidgetPurchaseReviewFixtures.makeLockedController()
        defer { purchaseController.stop() }
        await purchaseController.refresh()
        let access = SubscriptionQuotaAccess(purchaseController: purchaseController)
        var notifications = 0
        access.observe { notifications += 1 }
        #expect(!access.isUnlocked)

        // 刷新只改变 operation（loading → idle），解锁状态不变，不应通知。
        await purchaseController.refresh()
        #expect(notifications == 0)

        await purchaseController.purchase(in: NSWindow())

        #expect(access.isUnlocked)
        #expect(notifications == 1)
        #expect(access.purchaseController === purchaseController)
    }

    @Test("创建时直接采用购买控制器的当前解锁状态")
    func adoptsCurrentUnlockState() async {
        let purchaseController = WidgetPurchaseReviewFixtures.makeUnlockedController()
        defer { purchaseController.stop() }
        await purchaseController.refresh()

        let access = SubscriptionQuotaAccess(purchaseController: purchaseController)

        #expect(access.isUnlocked)
    }
}
