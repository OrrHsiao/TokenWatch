import AppKit
import Testing
@testable import TokenWatch

@MainActor
@Suite("StatusBarQuotaSettingsView")
struct StatusBarQuotaSettingsViewTests {

    @Test("设置页在应用偏好之后新增状态栏订阅额度区块，并可纵向滚动")
    func settingsPageHostsQuotaSectionInScrollView() throws {
        let suiteName = "StatusBarQuotaSettingsViewTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let languageSettings = AppLanguageSettings(defaults: defaults)
        languageSettings.selectedPreference = .language(.zhHans)
        let controller = SettingsViewController(
            isAuthorized: { true },
            autoRefreshSettings: AutoRefreshSettings(defaults: defaults),
            languageSettings: languageSettings,
            monthlyBudgetSettings: MonthlyBudgetSettings(defaults: defaults),
            displaySettings: StatusBarDisplaySettings(defaults: defaults),
            quotaAccess: SubscriptionQuotaAccess(isUnlocked: true)
        )
        controller.loadViewIfNeeded()

        let scrollView = try #require(descendant(identifier: "SettingsScrollView", in: controller.view) as? NSScrollView)
        let section = try #require(descendant(identifier: "SettingsStatusBarQuotaSection", in: controller.view))
        let preferences = try #require(descendant(identifier: "SettingsAppPreferencesSection", in: controller.view))
        #expect(section.isDescendant(of: scrollView))
        #expect(scrollView.documentView?.isFlipped == true)
        let title = try #require(descendant(identifier: "StatusBarQuotaTitleLabel", in: controller.view) as? NSTextField)
        #expect(title.stringValue == "状态栏订阅额度")

        let contentStack = try #require(section.superview as? NSStackView)
        let sectionIndex = try #require(contentStack.arrangedSubviews.firstIndex(of: section))
        let preferencesIndex = try #require(contentStack.arrangedSubviews.firstIndex(of: preferences))
        #expect(sectionIndex == preferencesIndex + 1)
        #expect(sectionIndex == contentStack.arrangedSubviews.count - 1)
    }

    @Test("未购买时显示付费说明，周期开关与样式全部禁用，购买控制器不可用时不显示购买按钮")
    func lockedStateDisablesControls() throws {
        let (view, settings, cleanup) = try makeView(quotaAccess: SubscriptionQuotaAccess(isUnlocked: false))
        defer { cleanup() }

        #expect(view.debugShowsPurchasePanel)
        #expect(view.debugLockedMessage == "订阅额度为付费功能，与桌面小组件共用一次永久买断。")
        for provider in SubscriptionQuotaProvider.allCases {
            for kind in SubscriptionQuotaWindowKind.allCases {
                let visibilitySwitch = try #require(windowSwitch(provider, kind, in: view))
                let stylePopUp = try #require(stylePopUpButton(provider, kind, in: view))
                #expect(!visibilitySwitch.isEnabled)
                #expect(!stylePopUp.isEnabled)
                #expect(visibilitySwitch.state == .on)
            }
        }
        #expect(try #require(button(identifier: "StatusBarQuotaPurchaseButton", in: view)).isHidden)
        #expect(try #require(button(identifier: "StatusBarQuotaRestoreButton", in: view)).isHidden)

        // 未解锁时即使收到操作也不写入设置。
        let claudeFiveHour = try #require(windowSwitch(.claude, .fiveHour, in: view))
        claudeFiveHour.state = .off
        _ = claudeFiveHour.sendAction(claudeFiveHour.action, to: claudeFiveHour.target)
        #expect(settings.quotaWindowConfiguration(provider: .claude, kind: .fiveHour).isVisible)
        #expect(claudeFiveHour.state == .on)
    }

    @Test("未购买时购买按钮使用 StoreKit 本地化价格，与小组件共用同一商品")
    func lockedStateShowsPurchaseActions() async throws {
        let purchaseController = WidgetPurchaseReviewFixtures.makeLockedController()
        defer { purchaseController.stop() }
        await purchaseController.refresh()
        let quotaAccess = SubscriptionQuotaAccess(purchaseController: purchaseController)
        let (view, _, cleanup) = try makeView(quotaAccess: quotaAccess)
        defer { cleanup() }

        let purchaseButton = try #require(button(identifier: "StatusBarQuotaPurchaseButton", in: view))
        let restoreButton = try #require(button(identifier: "StatusBarQuotaRestoreButton", in: view))
        #expect(!purchaseButton.isHidden)
        #expect(purchaseButton.isEnabled)
        #expect(purchaseButton.title == "以 $2.99 永久解锁")
        #expect(restoreButton.title == "恢复购买")

        await purchaseController.purchase(in: NSWindow())

        #expect(!view.debugShowsPurchasePanel)
        #expect(try #require(windowSwitch(.codex, .sevenDay, in: view)).isEnabled)
    }

    @Test("解锁后可分别配置 Claude 与 Codex 各周期的展示与简洁 / 详细样式")
    func unlockedControlsUpdateSettings() throws {
        let (view, settings, cleanup) = try makeView(quotaAccess: SubscriptionQuotaAccess(isUnlocked: true))
        defer { cleanup() }
        var notifications = 0
        settings.observe { notifications += 1 }

        #expect(!view.debugShowsPurchasePanel)
        let stylePopUp = try #require(stylePopUpButton(.codex, .sevenDay, in: view))
        #expect(stylePopUp.itemTitles == ["简洁", "详细"])
        #expect(stylePopUp.titleOfSelectedItem == "详细")

        stylePopUp.selectItem(at: 0)
        _ = stylePopUp.sendAction(stylePopUp.action, to: stylePopUp.target)
        #expect(settings.quotaWindowConfiguration(provider: .codex, kind: .sevenDay) == .init(
            isVisible: true,
            style: .compact
        ))
        #expect(settings.quotaWindowConfiguration(provider: .claude, kind: .sevenDay).style == .detailed)

        let claudeFiveHour = try #require(windowSwitch(.claude, .fiveHour, in: view))
        claudeFiveHour.state = .off
        _ = claudeFiveHour.sendAction(claudeFiveHour.action, to: claudeFiveHour.target)
        #expect(!settings.quotaWindowConfiguration(provider: .claude, kind: .fiveHour).isVisible)
        // 周期隐藏后样式不再生效，样式下拉禁用。
        #expect(try #require(stylePopUpButton(.claude, .fiveHour, in: view)).isEnabled == false)
        #expect(try #require(stylePopUpButton(.codex, .fiveHour, in: view)).isEnabled)
        #expect(notifications == 2)
    }

    @Test("切换语言后周期名称与样式选项跟随更新")
    func reloadsLocalizedText() throws {
        let (view, _, cleanup) = try makeView(quotaAccess: SubscriptionQuotaAccess(isUnlocked: true))
        defer { cleanup() }

        view.reloadLocalizedText(language: .en)

        let stylePopUp = try #require(stylePopUpButton(.claude, .fiveHour, in: view))
        #expect(stylePopUp.itemTitles == ["Compact", "Detailed"])
        #expect(stylePopUp.titleOfSelectedItem == "Detailed")
        #expect(stylePopUp.accessibilityLabel() == "Claude 5 hours")
    }

    // MARK: - Helpers

    private func makeView(
        quotaAccess: SubscriptionQuotaAccess
    ) throws -> (StatusBarQuotaSettingsView, StatusBarDisplaySettings, () -> Void) {
        let suiteName = "StatusBarQuotaSettingsViewTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let settings = StatusBarDisplaySettings(defaults: defaults)
        let view = StatusBarQuotaSettingsView(
            displaySettings: settings,
            quotaAccess: quotaAccess,
            language: .zhHans
        )
        return (view, settings, { defaults.removePersistentDomain(forName: suiteName) })
    }

    private func windowSwitch(
        _ provider: SubscriptionQuotaProvider,
        _ kind: SubscriptionQuotaWindowKind,
        in root: NSView
    ) -> NSSwitch? {
        descendant(identifier: "StatusBarQuotaWindowSwitch.\(provider.rawValue).\(kind.rawValue)", in: root) as? NSSwitch
    }

    private func stylePopUpButton(
        _ provider: SubscriptionQuotaProvider,
        _ kind: SubscriptionQuotaWindowKind,
        in root: NSView
    ) -> NSPopUpButton? {
        descendant(
            identifier: "StatusBarQuotaWindowStylePopUpButton.\(provider.rawValue).\(kind.rawValue)",
            in: root
        ) as? NSPopUpButton
    }

    private func button(identifier: String, in root: NSView) -> NSButton? {
        descendant(identifier: identifier, in: root) as? NSButton
    }

    private func descendant(identifier: String, in root: NSView) -> NSView? {
        if root.identifier?.rawValue == identifier {
            return root
        }
        for subview in root.subviews {
            if let match = descendant(identifier: identifier, in: subview) {
                return match
            }
        }
        return nil
    }
}
