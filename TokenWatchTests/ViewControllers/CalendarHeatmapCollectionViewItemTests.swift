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

    @Test("day style 隐藏日期数字并保留 token tooltip")
    func dayStyleHidesDayNumberAndKeepsTooltip() {
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

        #expect(style.title == "")
        #expect(style.toolTip == "2026-06-10 · 12.3k")
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
        #expect(style.toolTip == "2026-06-20 · 0.0M")
    }

    @Test("token tooltip 使用 M 单位且不足 0.1M 时回退到 k")
    func tokenTooltipUsesMillionsWithKFallback() {
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

        #expect(style.toolTip == "2026-06-15 · 1.2M")
        #expect(CalendarHeatmapCellStyle.make(for: .day(day), language: .en).toolTip == "2026-06-15 · 1.2M")
    }

    @Test("token tooltip 在 0.1M 边界切换单位")
    func tokenTooltipSwitchesUnitAtOneTenthMillion() {
        let underThresholdDay = CalendarHeatmapDay(
            id: "2026-06-15",
            date: Date(timeIntervalSince1970: 0),
            dateKey: "2026-06-15",
            dayNumber: 15,
            totalTokens: 99_999,
            intensity: 4,
            isToday: false,
            isFuture: false
        )
        let thresholdDay = CalendarHeatmapDay(
            id: "2026-06-16",
            date: Date(timeIntervalSince1970: 0),
            dateKey: "2026-06-16",
            dayNumber: 16,
            totalTokens: 100_000,
            intensity: 4,
            isToday: false,
            isFuture: false
        )

        #expect(CalendarHeatmapCellStyle.make(for: .day(underThresholdDay)).toolTip == "2026-06-15 · 99.9k")
        #expect(CalendarHeatmapCellStyle.make(for: .day(thresholdDay)).toolTip == "2026-06-16 · 0.1M")
    }

    @Test("day style 使用调用方 calendar 和时区格式化辅助功能日期")
    func styleUsesProvidedCalendarAndTimeZone() throws {
        var calendar = Calendar(identifier: .buddhist)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let date = try #require(ISO8601DateFormatter().date(from: "2026-06-10T01:00:00Z"))
        let day = CalendarHeatmapDay(
            id: "2026-06-09",
            date: date,
            dateKey: "2026-06-09",
            dayNumber: 9,
            totalTokens: 0,
            intensity: 0,
            isToday: true,
            isFuture: false
        )

        let style = CalendarHeatmapCellStyle.make(
            for: .day(day),
            language: .en,
            calendar: calendar
        )

        #expect(style.accessibilityLabel == "June 9, 2569 BE")
    }

    @MainActor
    @Test("cell 使用 GitHub 风格小方块")
    func cellUsesGitHubStyleSquareTile() {
        let item = CalendarHeatmapCollectionViewItem()
        item.loadView()

        #expect(item.view.frame.size == NSSize(width: 12, height: 12))
        #expect(item.view.layer?.cornerRadius == 2)
    }

    @MainActor
    @Test("最高强度使用 GitHub 绿色")
    func maxIntensityUsesGitHubGreen() {
        let item = CalendarHeatmapCollectionViewItem()
        item.loadView()
        item.view.appearance = NSAppearance(named: .aqua)

        let day = CalendarHeatmapDay(
            id: "2026-06-10",
            date: Date(timeIntervalSince1970: 0),
            dateKey: "2026-06-10",
            dayNumber: 10,
            totalTokens: 12_345,
            intensity: 4,
            isToday: false,
            isFuture: false
        )

        item.configure(with: .day(day))

        #expect(item.view.layer?.backgroundColor?.roundedRGBAComponents == [0.129, 0.431, 0.224, 1.0])
    }

    @MainActor
    @Test("暗色模式 0 token 方块使用更亮的中性色")
    func zeroTokenUsesLighterNeutralInDarkMode() {
        let item = CalendarHeatmapCollectionViewItem()
        item.loadView()
        item.view.appearance = NSAppearance(named: .darkAqua)

        let day = CalendarHeatmapDay(
            id: "2026-06-10",
            date: Date(timeIntervalSince1970: 0),
            dateKey: "2026-06-10",
            dayNumber: 10,
            totalTokens: 0,
            intensity: 0,
            isToday: false,
            isFuture: false
        )

        item.configure(with: .day(day))

        #expect(item.view.layer?.backgroundColor?.roundedRGBAComponents == [0.098, 0.118, 0.145, 1.0])
        #expect(item.view.toolTip == "2026-06-10 · 0.0M")
    }

    @MainActor
    @Test("浅色模式 0 token 方块使用更清晰的中性色")
    func zeroTokenUsesClearerNeutralInLightMode() {
        let item = CalendarHeatmapCollectionViewItem()
        item.loadView()
        item.view.appearance = NSAppearance(named: .aqua)

        let day = CalendarHeatmapDay(
            id: "2026-06-10",
            date: Date(timeIntervalSince1970: 0),
            dateKey: "2026-06-10",
            dayNumber: 10,
            totalTokens: 0,
            intensity: 0,
            isToday: false,
            isFuture: false
        )

        item.configure(with: .day(day))

        #expect(item.view.layer?.backgroundColor?.roundedRGBAComponents == [0.847, 0.871, 0.91, 1.0])
        #expect(item.view.toolTip == "2026-06-10 · 0.0M")
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
        #expect(item.view.toolTip == "2026-06-10 · 12.3k")
        #expect(item.view.alphaValue == 1.0)
    }

    @MainActor
    @Test("鼠标划过 day cell 时立即回传 token 文案")
    func hoveringDayCellEmitsTokenTextImmediately() {
        let item = CalendarHeatmapCollectionViewItem()
        item.loadView()

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
        var hoverTexts: [String?] = []
        item.onHoverTextChange = { text in
            hoverTexts.append(text)
        }

        item.configure(with: .day(day))
        item.debugSimulateMouseEntered()
        item.debugSimulateMouseExited()

        #expect(hoverTexts.count == 2)
        #expect(hoverTexts[0] == "2026-06-10 · 12.3k")
        #expect(hoverTexts[1] == nil)
    }

    @MainActor
    @Test("外观变化时重新应用背景色")
    func appearanceChangeReappliesBackgroundColor() {
        let item = CalendarHeatmapCollectionViewItem()
        item.loadView()

        let day = CalendarHeatmapDay(
            id: "2026-06-10",
            date: Date(timeIntervalSince1970: 0),
            dateKey: "2026-06-10",
            dayNumber: 10,
            totalTokens: 12_345,
            intensity: 4,
            isToday: false,
            isFuture: false
        )

        item.configure(with: .day(day))
        let configuredComponents = item.view.layer?.backgroundColor?.components

        item.view.layer?.backgroundColor = nil
        item.view.viewDidChangeEffectiveAppearance()
        let refreshedComponents = item.view.layer?.backgroundColor?.components

        #expect(configuredComponents != nil)
        #expect(refreshedComponents == configuredComponents)
    }

    @MainActor
    @Test("day cell 暴露本地化日期和 token 辅助功能语义")
    func dayCellExposesLocalizedAccessibilitySemantics() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 6,
            day: 10
        )))
        let day = CalendarHeatmapDay(
            id: "2026-06-10",
            date: date,
            dateKey: "2026-06-10",
            dayNumber: 10,
            totalTokens: 12_345,
            intensity: 3,
            isToday: false,
            isFuture: false
        )
        let item = CalendarHeatmapCollectionViewItem()
        item.loadView()

        item.configure(with: .day(day), language: .en, calendar: calendar)

        #expect(item.view.isAccessibilityElement())
        #expect(item.view.accessibilityRole() == .staticText)
        #expect(item.view.accessibilityLabel() == "June 10, 2026")
        #expect(item.view.accessibilityValue() as? String == "12.3k Tokens")

        item.configure(with: .day(day), language: .zhHans, calendar: calendar)
        #expect(item.view.accessibilityLabel() == "2026年6月10日")
        #expect(item.view.accessibilityValue() as? String == "12.3k Tokens")
    }

    @MainActor
    @Test("placeholder 退出辅助功能树并清除复用残留")
    func placeholderClearsReusedAccessibilityState() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 6,
            day: 10
        )))
        let day = CalendarHeatmapDay(
            id: "2026-06-10",
            date: date,
            dateKey: "2026-06-10",
            dayNumber: 10,
            totalTokens: 12_345,
            intensity: 3,
            isToday: false,
            isFuture: false
        )
        let item = CalendarHeatmapCollectionViewItem()
        item.loadView()
        item.configure(with: .day(day), language: .en, calendar: calendar)

        item.configure(with: .placeholder(id: "p0"), language: .en, calendar: calendar)

        #expect(!item.view.isAccessibilityElement())
        #expect(item.view.accessibilityRole() == nil)
        #expect(item.view.accessibilityLabel() == nil)
        #expect(item.view.accessibilityValue() == nil)
        #expect(item.view.isHidden)
    }

    @MainActor
    @Test("popover data source 透传语言、calendar 和时区")
    func popoverDataSourcePassesLanguageAndCalendar() throws {
        let suiteName = "CalendarHeatmapCollectionViewItemTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let languageSettings = AppLanguageSettings(
            defaults: defaults,
            preferredLanguagesProvider: { ["en-US"] }
        )
        languageSettings.selectedPreference = .en

        var calendar = Calendar(identifier: .buddhist)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let now = try #require(ISO8601DateFormatter().date(from: "2026-06-10T01:00:00Z"))
        let controller = StatusPopoverViewController(
            viewModel: TokenStatsViewModel(
                languageSettings: languageSettings,
                providers: []
            ),
            nowProvider: { now },
            calendar: calendar,
            languageSettings: languageSettings
        )
        let snapshot = CalendarHeatmapBuilder.build(
            states: [:],
            month: now,
            now: now,
            calendar: calendar,
            language: .en
        )
        let dayIndex = try #require(snapshot.cells.lastIndex { cell in
            if case .day = cell { return true }
            return false
        })

        controller.loadViewIfNeeded()
        let collectionView = try #require(controller.debugCollectionView)
        let item = try #require(controller.collectionView(
            collectionView,
            itemForRepresentedObjectAt: IndexPath(item: dayIndex, section: 0)
        ) as? CalendarHeatmapCollectionViewItem)

        #expect(item.view.accessibilityLabel() == "June 9, 2569 BE")
        #expect(item.view.accessibilityValue() as? String == "0.0M Tokens")
    }
}

private extension CGColor {
    var roundedRGBAComponents: [CGFloat]? {
        guard let components else { return nil }
        return components.map { ($0 * 1_000).rounded() / 1_000 }
    }
}
