import Foundation

/// Localized purchase-card copy for the widget product.
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
    let entitlementPersistenceFailedMessage: String
    let verificationFailedMessage: String
    let purchaseUnavailableTitle: String
    let restoreTitle: String
    let purchaseActionFormat: String

    /// Returns commerce copy matching the app's selected language.
    /// - Parameter language: The language selected inside TokenWatch.
    /// - Returns: Fully localized purchase copy for the selected supported language.
    static func make(language: AppLanguage) -> WidgetPurchaseCopy {
        let text: (AppStringKey) -> String = {
            AppStrings.text($0, language: language)
        }
        return WidgetPurchaseCopy(
            lockedTitle: text(.widgetPurchaseLockedTitle),
            lockedDescription: text(.widgetPurchaseLockedDescription),
            unlockedTitle: text(.widgetPurchaseUnlockedTitle),
            unlockedDescription: text(.widgetPurchaseUnlockedDescription),
            lockedStatus: text(.widgetPurchaseLockedStatus),
            unlockedStatus: text(.widgetPurchaseUnlockedStatus),
            loadingMessage: text(.widgetPurchaseLoadingMessage),
            purchasingMessage: text(.widgetPurchasePurchasingMessage),
            restoringMessage: text(.widgetPurchaseRestoringMessage),
            pendingMessage: text(.widgetPurchasePendingMessage),
            noPurchaseMessage: text(.widgetPurchaseNoPurchaseMessage),
            unavailableMessage: text(.widgetPurchaseUnavailableMessage),
            failedMessage: text(.widgetPurchaseFailedMessage),
            entitlementPersistenceFailedMessage: text(
                .widgetPurchaseEntitlementPersistenceFailedMessage
            ),
            verificationFailedMessage: text(.widgetPurchaseVerificationFailedMessage),
            purchaseUnavailableTitle: text(.widgetPurchaseUnavailableTitle),
            restoreTitle: text(.widgetPurchaseRestoreTitle),
            purchaseActionFormat: text(.widgetPurchaseActionFormat)
        )
    }

    /// Builds the primary purchase button from StoreKit's localized display price.
    /// - Parameter displayPrice: The exact localized price returned by StoreKit.
    /// - Returns: A localized call to action that preserves the StoreKit price verbatim.
    func purchaseTitle(displayPrice: String) -> String {
        String(format: purchaseActionFormat, displayPrice)
    }
}
