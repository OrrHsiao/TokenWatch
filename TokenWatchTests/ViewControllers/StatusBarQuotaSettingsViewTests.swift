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
            displaySettings: StatusBarDisplaySettings(defaults: defaults)
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

    @Test("无需购买即可分别配置 Claude 与 Codex 各周期的展示与简洁 / 详细样式")
    func freeControlsUpdateSettings() throws {
        let (view, settings, cleanup) = try makeView()
        defer { cleanup() }
        var notifications = 0
        settings.observe { notifications += 1 }

        #expect(descendant(identifier: "StatusBarQuotaPurchasePanel", in: view) == nil)
        for provider in SubscriptionQuotaProvider.allCases {
            for kind in SubscriptionQuotaWindowKind.allCases {
                #expect(try #require(windowSwitch(provider, kind, in: view)).isEnabled)
                #expect(try #require(stylePopUpButton(provider, kind, in: view)).isEnabled)
            }
        }
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
        let (view, _, cleanup) = try makeView()
        defer { cleanup() }

        view.reloadLocalizedText(language: .en)

        let stylePopUp = try #require(stylePopUpButton(.claude, .fiveHour, in: view))
        #expect(stylePopUp.itemTitles == ["Compact", "Detailed"])
        #expect(stylePopUp.titleOfSelectedItem == "Detailed")
        #expect(stylePopUp.accessibilityLabel() == "Claude 5 hours")
    }

    // MARK: - Helpers

    private func makeView() throws -> (StatusBarQuotaSettingsView, StatusBarDisplaySettings, () -> Void) {
        let suiteName = "StatusBarQuotaSettingsViewTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let settings = StatusBarDisplaySettings(defaults: defaults)
        let view = StatusBarQuotaSettingsView(
            displaySettings: settings,
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
