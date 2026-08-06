import Foundation

/// Purchase-card copy for the two App Store localizations configured for the widget product.
///
/// TokenWatch supports additional UI languages, but App Store Connect currently localizes this
/// product in English and Simplified Chinese. Other app languages deliberately fall back to the
/// English commerce copy so the price and purchase action are never synthesized or mistranslated.
struct WidgetPurchaseCopy: Equatable, Sendable {
    let lockedTitle: String
    let lockedDescription: String
    let unlockedTitle: String
    let unlockedDescription: String
    let lockedStatus: String
    let unlockedStatus: String
    let loadingMessage: String
    let purchasingMessage: String
    let restoringMessage: String
    let pendingMessage: String
    let noPurchaseMessage: String
    let unavailableMessage: String
    let failedMessage: String
    let verificationFailedMessage: String
    let purchaseUnavailableTitle: String
    let restoreTitle: String

    /// Returns commerce copy matching the app's selected language when the product is localized.
    /// - Parameter language: The language selected inside TokenWatch.
    /// - Returns: Simplified/Traditional Chinese copy for Chinese locales, otherwise English.
    static func make(language: AppLanguage) -> WidgetPurchaseCopy {
        switch language {
        case .zhHans:
            return WidgetPurchaseCopy(
                lockedTitle: "解锁全部 7 款桌面小组件",
                lockedDescription: "一次购买，永久解锁；可随时恢复购买。",
                unlockedTitle: "全部小组件已解锁",
                unlockedDescription: "购买权益已验证，桌面小组件现在可以显示用量数据。",
                lockedStatus: "未解锁",
                unlockedStatus: "已购买",
                loadingMessage: "正在连接 App Store…",
                purchasingMessage: "正在完成购买…",
                restoringMessage: "正在恢复购买…",
                pendingMessage: "购买正在等待批准。",
                noPurchaseMessage: "未找到可恢复的购买记录。",
                unavailableMessage: "暂时无法载入 App Store 商品，请稍后重试。",
                failedMessage: "购买未能完成，请重试。",
                verificationFailedMessage: "无法验证这笔交易，未授予小组件权限。",
                purchaseUnavailableTitle: "从 App Store 永久解锁",
                restoreTitle: "恢复购买"
            )
        case .zhHK, .zhHant:
            return WidgetPurchaseCopy(
                lockedTitle: "解鎖全部 7 款桌面小工具",
                lockedDescription: "一次購買，永久解鎖；可隨時恢復購買。",
                unlockedTitle: "全部小工具已解鎖",
                unlockedDescription: "購買權益已驗證，桌面小工具現在可以顯示用量資料。",
                lockedStatus: "未解鎖",
                unlockedStatus: "已購買",
                loadingMessage: "正在連接 App Store…",
                purchasingMessage: "正在完成購買…",
                restoringMessage: "正在恢復購買…",
                pendingMessage: "購買正在等待批准。",
                noPurchaseMessage: "找不到可恢復的購買記錄。",
                unavailableMessage: "暫時無法載入 App Store 商品，請稍後再試。",
                failedMessage: "購買未能完成，請再試一次。",
                verificationFailedMessage: "無法驗證此交易，未授予小工具權限。",
                purchaseUnavailableTitle: "從 App Store 永久解鎖",
                restoreTitle: "恢復購買"
            )
        default:
            return WidgetPurchaseCopy(
                lockedTitle: "Unlock all 7 desktop widgets",
                lockedDescription: "One purchase, permanent access, with restore available anytime.",
                unlockedTitle: "All widgets are unlocked",
                unlockedDescription: "Your purchase is verified and widgets can now display usage data.",
                lockedStatus: "Locked",
                unlockedStatus: "Purchased",
                loadingMessage: "Connecting to the App Store…",
                purchasingMessage: "Completing purchase…",
                restoringMessage: "Restoring purchases…",
                pendingMessage: "This purchase is awaiting approval.",
                noPurchaseMessage: "No previous purchase was found.",
                unavailableMessage: "The App Store product is temporarily unavailable. Try again later.",
                failedMessage: "The purchase couldn't be completed. Please try again.",
                verificationFailedMessage: "The transaction couldn't be verified, so widget access remains locked.",
                purchaseUnavailableTitle: "Unlock with the App Store",
                restoreTitle: "Restore Purchases"
            )
        }
    }

    /// Builds the primary purchase button from StoreKit's localized display price.
    /// - Parameter displayPrice: The exact localized price returned by StoreKit.
    /// - Returns: A localized call to action that preserves the StoreKit price verbatim.
    func purchaseTitle(displayPrice: String) -> String {
        if lockedTitle.hasPrefix("解鎖") {
            return "以 \(displayPrice) 永久解鎖"
        }
        if lockedTitle.hasPrefix("解锁") {
            return "以 \(displayPrice) 永久解锁"
        }
        return "Unlock forever for \(displayPrice)"
    }
}
