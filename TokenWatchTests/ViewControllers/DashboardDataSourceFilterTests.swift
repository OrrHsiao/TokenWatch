import AppKit
import Foundation
import Testing
@testable import TokenWatch

private extension NSView {
    func firstDescendant(identifier: String) -> NSView? {
        if accessibilityIdentifier() == identifier || self.identifier?.rawValue == identifier {
            return self
        }
        for subview in subviews {
            if let match = subview.firstDescendant(identifier: identifier) {
                return match
            }
        }
        return nil
    }
}

@Suite("DashboardDataSourceFilterTests")
struct DashboardDataSourceFilterTests {

    @Test("数据源切片不超过限制时原样返回")
    func aggregateToolShareSlicesReturnsSameWhenUnderLimit() {
        let slices = [
            UsageShareSlice(id: "claude", label: "Claude Code", totalTokens: 500, percentage: 0.5),
            UsageShareSlice(id: "codex", label: "Codex", totalTokens: 300, percentage: 0.3),
            UsageShareSlice(id: "antigravity", label: "Antigravity", totalTokens: 200, percentage: 0.2),
        ]
        let aggregated = DashboardRangeSnapshot.aggregateToolShareSlices(
            slices,
            maxVisible: 4,
            otherLabel: "其他"
        )
        #expect(aggregated == slices)
        #expect(aggregated.count == 3)
    }

    @Test("数据源切片等于最大数量时不聚合其他切片")
    func aggregateToolShareSlicesDoesNotAggregateAtExactLimit() {
        let slices = [
            UsageShareSlice(id: "s1", label: "S1", totalTokens: 400, percentage: 0.4),
            UsageShareSlice(id: "s2", label: "S2", totalTokens: 300, percentage: 0.3),
            UsageShareSlice(id: "s3", label: "S3", totalTokens: 200, percentage: 0.2),
            UsageShareSlice(id: "s4", label: "S4", totalTokens: 100, percentage: 0.1),
        ]
        let aggregated = DashboardRangeSnapshot.aggregateToolShareSlices(
            slices,
            maxVisible: 4,
            otherLabel: "其他"
        )
        #expect(aggregated.count == 4)
        #expect(!aggregated.contains(where: { $0.id == "__other__" }))
    }

    @Test("数据源切片超过限制时聚合成Top3加其他且比例守恒")
    func aggregateToolShareSlicesAggregatesOverflowToOther() {
        let slices = [
            UsageShareSlice(id: "s1", label: "S1", totalTokens: 500, percentage: 0.50),
            UsageShareSlice(id: "s2", label: "S2", totalTokens: 250, percentage: 0.25),
            UsageShareSlice(id: "s3", label: "S3", totalTokens: 150, percentage: 0.15),
            UsageShareSlice(id: "s4", label: "S4", totalTokens: 60, percentage: 0.06),
            UsageShareSlice(id: "s5", label: "S5", totalTokens: 40, percentage: 0.04),
        ]
        let aggregated = DashboardRangeSnapshot.aggregateToolShareSlices(
            slices,
            maxVisible: 4,
            otherLabel: "其他"
        )
        #expect(aggregated.count == 4)
        #expect(aggregated[0].id == "s1")
        #expect(aggregated[1].id == "s2")
        #expect(aggregated[2].id == "s3")

        let other = aggregated[3]
        #expect(other.id == "__other__")
        #expect(other.label == "其他")
        #expect(other.totalTokens == 100)
        #expect(abs(other.percentage - 0.10) < 0.0001)

        let totalPercentage = aggregated.reduce(0.0) { $0 + $1.percentage }
        #expect(abs(totalPercentage - 1.0) < 0.0001)
    }

    @MainActor
    @Test("侧边栏活跃数据源仅作为纯状态展示且不可点击筛选")
    func sidebarActiveRowIsNotClickableFilter() throws {
        let viewController = DashboardViewController(
            settingsViewController: SettingsViewController(languageSettings: .shared),
            stateProvider: {
                [
                    .claude: .init(stats: nil, isLoading: false, errorMessage: nil, needsAuthorization: false),
                    .codex: .init(stats: nil, isLoading: false, errorMessage: nil, needsAuthorization: true),
                ]
            },
            refreshAction: {},
            languageSettings: .shared
        )
        viewController.loadViewIfNeeded()
        viewController.view.setFrameSize(MainWindowFactory.contentSize)
        viewController.view.layoutSubtreeIfNeeded()

        let claudeRow = try #require(
            viewController.view.firstDescendant(identifier: "DashboardDataSourceRow.claude") as? DashboardDataSourceRowButton
        )
        #expect(claudeRow.isAuthorized == true)
        #expect(claudeRow.action == nil)
        #expect(claudeRow.target == nil)
        #expect(claudeRow.isSelectedSource == false)
    }

    @MainActor
    @Test("主内容区数据源下拉框可选择特定Agent或全部进行全局过滤")
    func sourcePopUpButtonFiltersDataAndSyncs() throws {
        let settingsController = SettingsViewController(languageSettings: .shared)
        let viewController = DashboardViewController(
            settingsViewController: settingsController,
            stateProvider: {
                [
                    .claude: .init(stats: nil, isLoading: false, errorMessage: nil, needsAuthorization: false),
                    .codex: .init(stats: nil, isLoading: false, errorMessage: nil, needsAuthorization: false),
                ]
            },
            refreshAction: {},
            languageSettings: .shared
        )
        viewController.loadViewIfNeeded()
        viewController.view.setFrameSize(MainWindowFactory.contentSize)
        viewController.view.layoutSubtreeIfNeeded()

        let popUp = try #require(
            viewController.view.firstDescendant(identifier: "DashboardOverviewSourcePopUp") as? DashboardSourcePopUpButton
        )
        #expect(popUp.indexOfSelectedItem == 0)
        #expect(popUp.selectedItem?.title == AppStrings.text(.dashboardRangeAll, language: .zhHans))

        // 选中 Claude
        let claudeItem = try #require(
            popUp.menu?.items.first(where: { ($0.representedObject as? ProviderID) == .claude })
        )
        popUp.select(claudeItem)
        popUp.sendAction(popUp.action, to: popUp.target)

        #expect((popUp.selectedItem?.representedObject as? ProviderID) == .claude)
        #expect(popUp.selectedItem?.title == "Claude Code")

        // 切换回“全部”
        popUp.selectItem(at: 0)
        popUp.sendAction(popUp.action, to: popUp.target)
        #expect(popUp.indexOfSelectedItem == 0)
        #expect(popUp.selectedItem?.representedObject == nil)

        // 选择“设置...”应打开设置面板并自动恢复下拉框选中项
        let settingsItem = try #require(
            popUp.menu?.items.first(where: { ($0.representedObject as? String) == "settings" })
        )
        popUp.select(settingsItem)
        popUp.sendAction(popUp.action, to: popUp.target)

        #expect(settingsController.view.superview != nil)
        #expect(popUp.indexOfSelectedItem == 0)
    }

    @MainActor
    @Test("未授权数据源点击导航至设置页")
    func clickingUnauthorizedDataSourceNavigatesToSettings() throws {
        let settingsController = SettingsViewController(languageSettings: .shared)
        let viewController = DashboardViewController(
            settingsViewController: settingsController,
            stateProvider: {
                [
                    .claude: .init(stats: nil, isLoading: false, errorMessage: nil, needsAuthorization: false),
                    .codex: .init(stats: nil, isLoading: false, errorMessage: nil, needsAuthorization: true),
                ]
            },
            refreshAction: {},
            languageSettings: .shared
        )
        viewController.loadViewIfNeeded()
        viewController.view.setFrameSize(MainWindowFactory.contentSize)
        viewController.view.layoutSubtreeIfNeeded()

        let codexRow = try #require(
            viewController.view.firstDescendant(identifier: "DashboardDataSourceRow.codex") as? DashboardDataSourceRowButton
        )
        #expect(codexRow.isAuthorized == false)

        #expect(settingsController.view.superview == nil)
        codexRow.performClick(nil)
        #expect(settingsController.view.superview != nil)
    }

    @MainActor
    @Test("折叠面板切换展开与收起")
    func disclosureToggleExpandsAndCollapsesOtherSources() throws {
        let viewController = DashboardViewController(
            settingsViewController: SettingsViewController(languageSettings: .shared),
            stateProvider: {
                [
                    .claude: .init(stats: nil, isLoading: false, errorMessage: nil, needsAuthorization: false),
                    .codex: .init(stats: nil, isLoading: false, errorMessage: nil, needsAuthorization: true),
                ]
            },
            refreshAction: {},
            languageSettings: .shared
        )
        viewController.loadViewIfNeeded()
        viewController.view.setFrameSize(MainWindowFactory.contentSize)
        viewController.view.layoutSubtreeIfNeeded()

        let toggleButton = try #require(
            viewController.view.firstDescendant(identifier: "DashboardDataSourceOtherToggle") as? DashboardDisclosureHeaderButton
        )
        #expect(toggleButton.isExpanded == false)

        toggleButton.performClick(nil)
        #expect(toggleButton.isExpanded == true)

        toggleButton.performClick(nil)
        #expect(toggleButton.isExpanded == false)
    }
}
