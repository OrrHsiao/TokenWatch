# Widget Lifetime Purchase — App Review Notes

## In-App Purchase

- Product ID: `com.xiaoao.tokenwatch.widgets.lifetime`
- Type: Non-Consumable
- Access: Permanently unlocks all 7 desktop widgets
- Restore: Available from the same Widgets page
- Review screenshot: `2026-08-06-widget-lifetime-purchase-en-US.jpg`

## Review Steps

1. Launch AI Token Watch.
2. Select **Widgets** in the left sidebar.
3. The purchase card shows the StoreKit-localized price and a **Restore Purchases** action.
4. Complete the purchase with an App Review sandbox account.
5. After StoreKit verifies the transaction, the purchase actions disappear and all widgets can display usage data.
6. To verify restoration, reinstall or launch on another Mac using the same sandbox account, return to **Widgets**, and select **Restore Purchases**.

The app does not require an account. Widget usage data is read locally; the entitlement is granted only after StoreKit verification and is shared with the widget extension through the app's App Group.

## Submission Checklist

- Attach this non-consumable to the new `1.0.5` app version when submitting the first in-app purchase.
- Upload the review screenshot to the in-app purchase's App Review Screenshot field.
- Select a processed `1.0.5` Xcode Cloud build before submitting the app version and in-app purchase together.
