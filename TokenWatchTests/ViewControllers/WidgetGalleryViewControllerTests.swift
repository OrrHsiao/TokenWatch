import AppKit
import SwiftUI
import Testing
@testable import TokenWatch

@MainActor
@Suite("Widget gallery")
struct WidgetGalleryViewControllerTests {
    @Test("示例快照保持所有小组件的固定图表形状")
    func sampleSnapshotUsesFixedWidgetShapes() throws {
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 3,
            hour: 15
        )))
        let snapshot = WidgetGallerySampleSnapshotFactory.make(
            now: now,
            calendar: calendar,
            language: .zhHans
        )

        #expect(snapshot.heatmap.cells.count == 154)
        #expect(snapshot.hourlyLine.points.map(\.hour) == Array(0...23))
        #expect(snapshot.hourlyLine.points.filter(\.isCurrentHour).map(\.hour) == [15])
        #expect(snapshot.heatmap.cells.allSatisfy { !$0.isPlaceholder })
        #expect(
            Array(snapshot.heatmap.cells.prefix(10).map(\.intensity))
                == [0, 1, 2, 3, 4, 0, 1, 2, 3, 4]
        )
        #expect(snapshot.hourlyLine.points[6].totalTokens == 200_000)
        #expect(snapshot.localizedText.heatmapTitle == "热力图")
        #expect(snapshot.localizedText.weeklySummaryTitle == "最近 7 天")
        #expect(snapshot.monthlyBudget?.title == "本月预算")
        #expect(snapshot.monthlyBudget?.budgetUSD == 100)
        #expect(WidgetUsageSnapshotValidator.isValid(snapshot))
    }

    @Test("侧栏小组件入口展示全部预览")
    func widgetNavigationShowsAllPreviews() throws {
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 3,
            hour: 15
        )))
        let settings = languageSettings(language: .zhHans)
        let controller = DashboardViewController(
            settingsViewController: SettingsViewController(languageSettings: settings),
            stateProvider: { [:] },
            refreshAction: {},
            nowProvider: { now },
            calendar: calendar,
            languageSettings: settings
        )
        controller.loadViewIfNeeded()
        controller.view.setFrameSize(MainWindowFactory.contentSize)

        let widgetsButton = try #require(
            view(identifier: "DashboardNav.widgets", in: controller.view) as? NSButton
        )
        widgetsButton.performClick(nil)
        controller.view.layoutSubtreeIfNeeded()

        #expect(textValues(in: controller.view).contains("小组件"))
        #expect(textValues(in: controller.view).contains("查看 TokenWatch 当前支持的小组件示例样式。"))
        #expect(view(identifier: "DashboardWidgetsScrollView", in: controller.view) is NSScrollView)
        let heatmapPreview = try #require(
            view(identifier: "DashboardWidgetPreview.heatmap", in: controller.view)
        )
        let hourlyLinePreview = try #require(
            view(identifier: "DashboardWidgetPreview.hourlyLine", in: controller.view)
        )
        let weeklySmallPreview = try #require(
            view(identifier: "DashboardWidgetPreview.weeklySummary.small", in: controller.view)
        )
        let weeklyMediumPreview = try #require(
            view(identifier: "DashboardWidgetPreview.weeklySummary.medium", in: controller.view)
        )
        let monthlyBudgetPreview = try #require(
            view(identifier: "DashboardWidgetPreview.monthlyBudget", in: controller.view)
        )
        let heatmapContent = try #require(
            view(identifier: "DashboardWidgetPreview.heatmap.content", in: controller.view)
        )
        let hourlyLineContent = try #require(
            view(identifier: "DashboardWidgetPreview.hourlyLine.content", in: controller.view)
        )
        let weeklySmallContent = try #require(
            view(identifier: "DashboardWidgetPreview.weeklySummary.small.content", in: controller.view)
        )
        let weeklyMediumContent = try #require(
            view(identifier: "DashboardWidgetPreview.weeklySummary.medium.content", in: controller.view)
        )
        let monthlyBudgetContent = try #require(
            view(identifier: "DashboardWidgetPreview.monthlyBudget.content", in: controller.view)
        )
        let mediumSize = WidgetGalleryViewController.systemMediumPreviewSize
        let smallSize = WidgetGalleryViewController.systemSmallPreviewSize
        for preview in [heatmapPreview, hourlyLinePreview, weeklyMediumPreview, monthlyBudgetPreview] {
            assertSize(preview, equals: mediumSize)
        }
        for content in [heatmapContent, hourlyLineContent, weeklyMediumContent, monthlyBudgetContent] {
            assertSize(content, equals: mediumSize)
        }
        assertSize(weeklySmallPreview, equals: smallSize)
        assertSize(weeklySmallContent, equals: smallSize)
        #expect(controller.view.allDescendants(ofType: NSHostingView<AnyView>.self).count == 5)

        let widgetsPage = try #require(view(identifier: "DashboardWidgetsPage", in: controller.view))
        let initialWidth = widgetsPage.frame.width
        widgetsButton.performClick(nil)
        controller.view.setFrameSize(NSSize(
            width: MainWindowFactory.contentSize.width + 120,
            height: MainWindowFactory.contentSize.height
        ))
        controller.view.layoutSubtreeIfNeeded()

        #expect(widgetsPage.frame.width > initialWidth)
        for preview in [heatmapPreview, hourlyLinePreview, weeklyMediumPreview, monthlyBudgetPreview] {
            assertSize(preview, equals: mediumSize)
        }
        assertSize(weeklySmallPreview, equals: smallSize)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func languageSettings(language: AppLanguage) -> AppLanguageSettings {
        let defaults = UserDefaults(suiteName: "WidgetGalleryViewControllerTests.\(UUID().uuidString)")!
        let settings = AppLanguageSettings(defaults: defaults, preferredLanguagesProvider: { [language.rawValue] })
        settings.selectedPreference = .language(language)
        return settings
    }

    private func view(identifier: String, in root: NSView) -> NSView? {
        if root.identifier?.rawValue == identifier || root.accessibilityIdentifier() == identifier {
            return root
        }
        for subview in root.subviews {
            if let match = view(identifier: identifier, in: subview) {
                return match
            }
        }
        return nil
    }

    private func textValues(in root: NSView) -> [String] {
        let current = (root as? NSTextField).map { [$0.stringValue] } ?? []
        return current + root.subviews.flatMap(textValues)
    }

    private func assertSize(_ view: NSView, equals expected: CGSize) {
        #expect(abs(view.frame.width - expected.width) < 0.5)
        #expect(abs(view.frame.height - expected.height) < 0.5)
    }
}

private extension NSView {
    func allDescendants<T: NSView>(ofType type: T.Type) -> [T] {
        let current = (self as? T).map { [$0] } ?? []
        return current + subviews.flatMap { $0.allDescendants(ofType: type) }
    }
}
