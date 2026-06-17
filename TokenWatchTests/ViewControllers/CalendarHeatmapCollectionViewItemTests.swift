import AppKit
import Testing
@testable import TokenWatch

@Suite("CalendarHeatmapCollectionViewItem")
struct CalendarHeatmapCollectionViewItemTests {

    @Test("placeholder 隐藏文字和 tooltip")
    func placeholderStyleHidesContent() {
        let style = CalendarHeatmapCellStyle.make(for: .placeholder(id: "p0"))

        #expect(style.title == "")
        #expect(style.toolTip == nil)
        #expect(style.isHidden)
    }

    @Test("day style 显示日期和 token tooltip")
    func dayStyleShowsDayNumberAndTooltip() {
        let day = CalendarHeatmapDay(
            id: "2026-06-10",
            date: Date(timeIntervalSince1970: 0),
            dateKey: "2026-06-10",
            dayNumber: 10,
            totalTokens: 12_345,
            intensity: 3,
            isToday: false,
            isFuture: false
        )

        let style = CalendarHeatmapCellStyle.make(for: .day(day))

        #expect(style.title == "10")
        #expect(style.toolTip == "2026-06-10 · 12,345 tokens")
        #expect(!style.isHidden)
        #expect(style.alpha == 1.0)
    }

    @Test("future day style 使用弱化透明度")
    func futureDayStyleIsDimmed() {
        let day = CalendarHeatmapDay(
            id: "2026-06-20",
            date: Date(timeIntervalSince1970: 0),
            dateKey: "2026-06-20",
            dayNumber: 20,
            totalTokens: 0,
            intensity: 0,
            isToday: false,
            isFuture: true
        )

        let style = CalendarHeatmapCellStyle.make(for: .day(day))

        #expect(style.alpha < 1.0)
        #expect(style.toolTip == "2026-06-20 · 0 tokens")
    }

    @Test("token tooltip 使用固定逗号分组")
    func tokenTooltipUsesStableCommaGrouping() {
        let day = CalendarHeatmapDay(
            id: "2026-06-15",
            date: Date(timeIntervalSince1970: 0),
            dateKey: "2026-06-15",
            dayNumber: 15,
            totalTokens: 1_234_567,
            intensity: 4,
            isToday: false,
            isFuture: false
        )

        let style = CalendarHeatmapCellStyle.make(for: .day(day))

        #expect(style.toolTip == "2026-06-15 · 1,234,567 tokens")
    }

    @MainActor
    @Test("复用 item 时重置公开 view 状态")
    func reusedItemResetsPublicViewState() {
        let item = CalendarHeatmapCollectionViewItem()
        item.loadView()
        item.configure(with: .placeholder(id: "p0"))

        let day = CalendarHeatmapDay(
            id: "2026-06-10",
            date: Date(timeIntervalSince1970: 0),
            dateKey: "2026-06-10",
            dayNumber: 10,
            totalTokens: 12_345,
            intensity: 3,
            isToday: false,
            isFuture: false
        )

        item.configure(with: .day(day))

        #expect(item.view.isHidden == false)
        #expect(item.view.toolTip == "2026-06-10 · 12,345 tokens")
        #expect(item.view.alphaValue == 1.0)
    }
}
