# Calendar Heatmap Popover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the empty status-bar left-click popover with a current-month calendar heatmap showing total token usage per day across all providers.

**Architecture:** Keep the existing AppKit status-bar stack. Add a pure `CalendarHeatmapBuilder` that converts `TokenStatsViewModel.ProviderState` values into testable month/cell data, then render that snapshot with an AppKit `NSCollectionView` inside a dedicated `StatusPopoverViewController`.

**Tech Stack:** Swift 6, AppKit, Swift Testing, Xcode file-system synchronized groups, existing `UsageSummary` / `AggregatedStats` / `TokenStatsViewModel`.

---

## File Structure

- Create `TokenWatch/ViewControllers/CalendarHeatmapBuilder.swift`
  - Owns all date-key generation, cross-provider aggregation, `byMonth` monthly total fallback, weekday labels, placeholder cells, future-day detection, and intensity calculation.
- Create `TokenWatch/ViewControllers/CalendarHeatmapCollectionViewItem.swift`
  - AppKit collection item for one placeholder/day cell. Uses a small pure style helper so rendering decisions can be unit tested without a real collection view.
- Create `TokenWatch/ViewControllers/StatusPopoverViewController.swift`
  - Popover content controller. Owns labels, weekday header, `NSCollectionView`, view-model observation, and snapshot reload.
- Modify `TokenWatch/ViewControllers/StatusBarController.swift`
  - Replace `EmptyStatusPopoverView` with `StatusPopoverViewController(viewModel:)`; remove the obsolete empty view.
- Create `TokenWatchTests/ViewControllers/CalendarHeatmapBuilderTests.swift`
  - Swift Testing coverage for all data behavior.
- Create `TokenWatchTests/ViewControllers/CalendarHeatmapCollectionViewItemTests.swift`
  - Swift Testing coverage for tooltip/text/visibility/style helper behavior.
- Create `TokenWatchTests/ViewControllers/StatusPopoverViewControllerTests.swift`
  - Swift Testing coverage that the popover view loads and exposes a 7-column collection view for the zero-state snapshot.

The project uses `PBXFileSystemSynchronizedRootGroup`, so creating files under `TokenWatch/` and `TokenWatchTests/` is enough; do not edit `TokenWatch.xcodeproj/project.pbxproj` unless Xcode build proves the synchronized group did not pick them up.

---

### Task 1: CalendarHeatmapBuilder

**Files:**
- Create: `TokenWatchTests/ViewControllers/CalendarHeatmapBuilderTests.swift`
- Create: `TokenWatch/ViewControllers/CalendarHeatmapBuilder.swift`

- [ ] **Step 1: Write the failing builder tests**

Create `TokenWatchTests/ViewControllers/CalendarHeatmapBuilderTests.swift`:

```swift
import Foundation
import Testing
@testable import TokenWatch

@Suite("CalendarHeatmapBuilder")
struct CalendarHeatmapBuilderTests {

    @Test("生成当前月 day cell 并补齐首周 placeholder")
    func buildsCurrentMonthCellsWithLeadingPlaceholders() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2 // Monday

        let snapshot = CalendarHeatmapBuilder.build(
            states: [:],
            month: date(2026, 6, 17, calendar: calendar),
            now: date(2026, 6, 17, calendar: calendar),
            calendar: calendar
        )

        #expect(snapshot.monthKey == "2026-06")
        #expect(snapshot.monthTitle == "2026 年 6 月")
        #expect(snapshot.weekdaySymbols == ["一", "二", "三", "四", "五", "六", "日"])
        #expect(snapshot.cells.count == 30)
        #expect(snapshot.dayCells.count == 30)
        #expect(snapshot.dayCells.first?.dateKey == "2026-06-01")
        #expect(snapshot.dayCells.last?.dateKey == "2026-06-30")
    }

    @Test("按 firstWeekday 生成首周 placeholder")
    func leadingPlaceholdersRespectCalendarFirstWeekday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 1 // Sunday

        let snapshot = CalendarHeatmapBuilder.build(
            states: [:],
            month: date(2026, 6, 17, calendar: calendar),
            now: date(2026, 6, 17, calendar: calendar),
            calendar: calendar
        )

        let placeholders = snapshot.cells.prefix { cell in
            if case .placeholder = cell { return true }
            return false
        }
        #expect(placeholders.count == 1)
        #expect(snapshot.dayCells.first?.dateKey == "2026-06-01")
    }

    @Test("跨 provider 合并 byDay token")
    func sumsDailyTokensAcrossProviders() {
        let calendar = utcCalendar(firstWeekday: 2)
        let claudeStats = makeStats(
            byDay: ["2026-06-10": makeSummary(total: 100)],
            byMonth: ["2026-06": makeSummary(total: 100)]
        )
        let codexStats = makeStats(
            byDay: ["2026-06-10": makeSummary(total: 25)],
            byMonth: ["2026-06": makeSummary(total: 25)]
        )
        let snapshot = CalendarHeatmapBuilder.build(
            states: [
                .claude: .init(stats: claudeStats, isLoading: false, errorMessage: nil, needsAuthorization: false),
                .codex: .init(stats: codexStats, isLoading: false, errorMessage: nil, needsAuthorization: false),
                .opencode: .init(stats: nil, isLoading: false, errorMessage: nil, needsAuthorization: true),
            ],
            month: date(2026, 6, 17, calendar: calendar),
            now: date(2026, 6, 17, calendar: calendar),
            calendar: calendar
        )

        #expect(snapshot.day("2026-06-10")?.totalTokens == 125)
        #expect(snapshot.monthTotalTokens == 125)
    }

    @Test("缺失日期补 0")
    func missingDayBucketsAreZero() {
        let calendar = utcCalendar(firstWeekday: 2)
        let stats = makeStats(
            byDay: ["2026-06-05": makeSummary(total: 300)],
            byMonth: ["2026-06": makeSummary(total: 300)]
        )

        let snapshot = CalendarHeatmapBuilder.build(
            states: [.claude: .init(stats: stats, isLoading: false, errorMessage: nil, needsAuthorization: false)],
            month: date(2026, 6, 17, calendar: calendar),
            now: date(2026, 6, 17, calendar: calendar),
            calendar: calendar
        )

        #expect(snapshot.day("2026-06-04")?.totalTokens == 0)
        #expect(snapshot.day("2026-06-05")?.totalTokens == 300)
    }

    @Test("优先使用 byMonth 作为月总量")
    func usesByMonthForMonthTotalWhenPresent() {
        let calendar = utcCalendar(firstWeekday: 2)
        let stats = makeStats(
            byDay: ["2026-06-01": makeSummary(total: 10)],
            byMonth: ["2026-06": makeSummary(total: 999)]
        )

        let snapshot = CalendarHeatmapBuilder.build(
            states: [.claude: .init(stats: stats, isLoading: false, errorMessage: nil, needsAuthorization: false)],
            month: date(2026, 6, 17, calendar: calendar),
            now: date(2026, 6, 17, calendar: calendar),
            calendar: calendar
        )

        #expect(snapshot.monthTotalTokens == 999)
    }

    @Test("byMonth 缺失时用本月 byDay fallback")
    func fallsBackToCurrentMonthDaySumWhenMonthBucketMissing() {
        let calendar = utcCalendar(firstWeekday: 2)
        let stats = makeStats(
            byDay: [
                "2026-06-01": makeSummary(total: 10),
                "2026-06-02": makeSummary(total: 20),
                "2026-05-31": makeSummary(total: 999),
            ],
            byMonth: [:]
        )

        let snapshot = CalendarHeatmapBuilder.build(
            states: [.claude: .init(stats: stats, isLoading: false, errorMessage: nil, needsAuthorization: false)],
            month: date(2026, 6, 17, calendar: calendar),
            now: date(2026, 6, 17, calendar: calendar),
            calendar: calendar
        )

        #expect(snapshot.monthTotalTokens == 30)
    }

    @Test("token 强度映射到 0...4")
    func intensityUsesDailyMaximum() {
        let calendar = utcCalendar(firstWeekday: 2)
        let stats = makeStats(
            byDay: [
                "2026-06-01": makeSummary(total: 0),
                "2026-06-02": makeSummary(total: 1),
                "2026-06-03": makeSummary(total: 25),
                "2026-06-04": makeSummary(total: 50),
                "2026-06-05": makeSummary(total: 100),
            ],
            byMonth: ["2026-06": makeSummary(total: 176)]
        )

        let snapshot = CalendarHeatmapBuilder.build(
            states: [.claude: .init(stats: stats, isLoading: false, errorMessage: nil, needsAuthorization: false)],
            month: date(2026, 6, 17, calendar: calendar),
            now: date(2026, 6, 17, calendar: calendar),
            calendar: calendar
        )

        #expect(snapshot.maxDailyTokens == 100)
        #expect(snapshot.day("2026-06-01")?.intensity == 0)
        #expect(snapshot.day("2026-06-02")?.intensity == 1)
        #expect(snapshot.day("2026-06-03")?.intensity == 1)
        #expect(snapshot.day("2026-06-04")?.intensity == 2)
        #expect(snapshot.day("2026-06-05")?.intensity == 4)
    }

    @Test("未来日期弱化并视作 0")
    func futureDaysAreZeroIntensity() {
        let calendar = utcCalendar(firstWeekday: 2)
        let stats = makeStats(
            byDay: ["2026-06-20": makeSummary(total: 1_000)],
            byMonth: ["2026-06": makeSummary(total: 1_000)]
        )

        let snapshot = CalendarHeatmapBuilder.build(
            states: [.claude: .init(stats: stats, isLoading: false, errorMessage: nil, needsAuthorization: false)],
            month: date(2026, 6, 1, calendar: calendar),
            now: date(2026, 6, 17, calendar: calendar),
            calendar: calendar
        )

        #expect(snapshot.day("2026-06-20")?.isFuture == true)
        #expect(snapshot.day("2026-06-20")?.totalTokens == 0)
        #expect(snapshot.day("2026-06-20")?.intensity == 0)
    }

    private func utcCalendar(firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func makeSummary(total: Int) -> UsageSummary {
        UsageSummary(
            inputTokens: total,
            outputTokens: 0,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            reasoningTokens: 0,
            totalTokens: total,
            cost: 0,
            entryCount: 1,
            modelBreakdown: [:]
        )
    }

    private func makeStats(
        byDay: [String: UsageSummary],
        byMonth: [String: UsageSummary]
    ) -> AggregatedStats {
        AggregatedStats(
            overall: .zero,
            byHour: [:],
            byDay: byDay,
            byWeek: [:],
            byMonth: byMonth,
            bySession: [:],
            byModel: [:],
            byProject: [:],
            dataSourceCount: 1
        )
    }
}

private extension CalendarHeatmapSnapshot {
    var dayCells: [CalendarHeatmapDay] {
        cells.compactMap { cell in
            if case .day(let day) = cell { return day }
            return nil
        }
    }

    func day(_ key: String) -> CalendarHeatmapDay? {
        dayCells.first { $0.dateKey == key }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/CalendarHeatmapBuilderTests test
```

Expected: FAIL because `CalendarHeatmapBuilder`, `CalendarHeatmapSnapshot`, `CalendarHeatmapCell`, and `CalendarHeatmapDay` do not exist.

- [ ] **Step 3: Implement the builder**

Create `TokenWatch/ViewControllers/CalendarHeatmapBuilder.swift`:

```swift
import Foundation

/// 单个日历热力图快照,供 AppKit collection view 直接渲染。
struct CalendarHeatmapSnapshot: Sendable, Equatable {
    let monthKey: String
    let monthTitle: String
    let monthTotalTokens: Int
    let weekdaySymbols: [String]
    let cells: [CalendarHeatmapCell]
    let maxDailyTokens: Int
}

/// 日历热力图 collection view 的单元数据。
enum CalendarHeatmapCell: Sendable, Equatable, Identifiable {
    case placeholder(id: String)
    case day(CalendarHeatmapDay)

    var id: String {
        switch self {
        case .placeholder(let id):
            return id
        case .day(let day):
            return day.id
        }
    }
}

/// 某一天的 token 热力信息。
struct CalendarHeatmapDay: Sendable, Equatable, Identifiable {
    let id: String
    let dateKey: String
    let dayNumber: Int
    let totalTokens: Int
    let intensity: Int
    let isFuture: Bool
}

/// 将多 provider 聚合状态转换成本月日历热力图数据。
enum CalendarHeatmapBuilder {

    /// 构建当前月份热力图快照。
    /// - Parameters:
    ///   - states: 所有 provider 当前状态。
    ///   - month: 目标月份内任意日期。
    ///   - now: 当前时间,用于判断未来日期。
    ///   - calendar: 用于日期切分和星期起点的日历。
    /// - Returns: 可直接渲染的月视图快照。
    static func build(
        states: [ProviderID: TokenStatsViewModel.ProviderState],
        month: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> CalendarHeatmapSnapshot {
        guard let monthStart = calendar.dateInterval(of: .month, for: month)?.start,
              let dayRange = calendar.range(of: .day, in: .month, for: monthStart) else {
            return CalendarHeatmapSnapshot(
                monthKey: "unknown",
                monthTitle: "未知月份",
                monthTotalTokens: 0,
                weekdaySymbols: weekdaySymbols(calendar: calendar),
                cells: [],
                maxDailyTokens: 0
            )
        }

        let monthKey = monthKey(from: monthStart, calendar: calendar)
        let todayStart = calendar.startOfDay(for: now)
        var days: [CalendarHeatmapDay] = []

        for dayNumber in dayRange {
            guard let date = calendar.date(byAdding: .day, value: dayNumber - 1, to: monthStart) else { continue }
            let dateKey = dayKey(from: date, calendar: calendar)
            let isFuture = calendar.startOfDay(for: date) > todayStart
            let tokens = isFuture ? 0 : dailyTokens(states: states, dateKey: dateKey)
            days.append(CalendarHeatmapDay(
                id: dateKey,
                dateKey: dateKey,
                dayNumber: dayNumber,
                totalTokens: tokens,
                intensity: 0,
                isFuture: isFuture
            ))
        }

        let maxDailyTokens = days.map(\.totalTokens).max() ?? 0
        let classifiedDays = days.map { day in
            CalendarHeatmapDay(
                id: day.id,
                dateKey: day.dateKey,
                dayNumber: day.dayNumber,
                totalTokens: day.totalTokens,
                intensity: intensity(tokens: day.totalTokens, maxDailyTokens: maxDailyTokens),
                isFuture: day.isFuture
            )
        }

        let cells = leadingPlaceholders(for: monthStart, calendar: calendar)
            + classifiedDays.map(CalendarHeatmapCell.day)

        return CalendarHeatmapSnapshot(
            monthKey: monthKey,
            monthTitle: monthTitle(from: monthStart, calendar: calendar),
            monthTotalTokens: monthTotalTokens(states: states, monthKey: monthKey),
            weekdaySymbols: weekdaySymbols(calendar: calendar),
            cells: cells,
            maxDailyTokens: maxDailyTokens
        )
    }

    private static func dailyTokens(
        states: [ProviderID: TokenStatsViewModel.ProviderState],
        dateKey: String
    ) -> Int {
        states.values.reduce(0) { total, state in
            total + (state.stats?.byDay[dateKey]?.totalTokens ?? 0)
        }
    }

    private static func monthTotalTokens(
        states: [ProviderID: TokenStatsViewModel.ProviderState],
        monthKey: String
    ) -> Int {
        states.values.reduce(0) { total, state in
            guard let stats = state.stats else { return total }
            if let month = stats.byMonth[monthKey] {
                return total + month.totalTokens
            }
            let fallback = stats.byDay.reduce(0) { partial, entry in
                entry.key.hasPrefix("\(monthKey)-") ? partial + entry.value.totalTokens : partial
            }
            return total + fallback
        }
    }

    private static func leadingPlaceholders(for monthStart: Date, calendar: Calendar) -> [CalendarHeatmapCell] {
        let weekday = calendar.component(.weekday, from: monthStart)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        return (0..<offset).map { .placeholder(id: "placeholder-\($0)") }
    }

    private static func intensity(tokens: Int, maxDailyTokens: Int) -> Int {
        guard tokens > 0, maxDailyTokens > 0 else { return 0 }
        return max(1, min(4, Int(ceil(Double(tokens) / Double(maxDailyTokens) * 4.0))))
    }

    private static func weekdaySymbols(calendar: Calendar) -> [String] {
        let symbols = ["日", "一", "二", "三", "四", "五", "六"]
        let start = max(0, calendar.firstWeekday - 1)
        return Array(symbols[start...] + symbols[..<start])
    }

    private static func monthTitle(from date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        guard let year = components.year, let month = components.month else { return "未知月份" }
        return "\(year) 年 \(month) 月"
    }

    private static func monthKey(from date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        guard let year = components.year, let month = components.month else { return "unknown" }
        return String(format: "%04d-%02d", year, month)
    }

    private static func dayKey(from date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return "unknown"
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
```

- [ ] **Step 4: Run builder tests to verify they pass**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/CalendarHeatmapBuilderTests test
```

Expected: PASS.

- [ ] **Step 5: Commit builder**

```bash
git add TokenWatch/ViewControllers/CalendarHeatmapBuilder.swift TokenWatchTests/ViewControllers/CalendarHeatmapBuilderTests.swift
git commit -m "feat(statusbar): 添加日历热力图数据构建器"
```

---

### Task 2: CalendarHeatmapCollectionViewItem

**Files:**
- Create: `TokenWatchTests/ViewControllers/CalendarHeatmapCollectionViewItemTests.swift`
- Create: `TokenWatch/ViewControllers/CalendarHeatmapCollectionViewItem.swift`

- [ ] **Step 1: Write failing item style tests**

Create `TokenWatchTests/ViewControllers/CalendarHeatmapCollectionViewItemTests.swift`:

```swift
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
            dateKey: "2026-06-10",
            dayNumber: 10,
            totalTokens: 12_345,
            intensity: 3,
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
            dateKey: "2026-06-20",
            dayNumber: 20,
            totalTokens: 0,
            intensity: 0,
            isFuture: true
        )

        let style = CalendarHeatmapCellStyle.make(for: .day(day))

        #expect(style.alpha < 1.0)
        #expect(style.toolTip == "2026-06-20 · 0 tokens")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/CalendarHeatmapCollectionViewItemTests test
```

Expected: FAIL because `CalendarHeatmapCellStyle` and `CalendarHeatmapCollectionViewItem` do not exist.

- [ ] **Step 3: Implement collection item and style helper**

Create `TokenWatch/ViewControllers/CalendarHeatmapCollectionViewItem.swift`:

```swift
import AppKit
import Foundation

/// 纯样式模型,让 collection item 的展示规则可单元测试。
struct CalendarHeatmapCellStyle: Equatable {
    let title: String
    let toolTip: String?
    let isHidden: Bool
    let alpha: CGFloat
    let intensity: Int

    static func make(for cell: CalendarHeatmapCell) -> CalendarHeatmapCellStyle {
        switch cell {
        case .placeholder:
            return CalendarHeatmapCellStyle(
                title: "",
                toolTip: nil,
                isHidden: true,
                alpha: 0,
                intensity: 0
            )
        case .day(let day):
            return CalendarHeatmapCellStyle(
                title: "\(day.dayNumber)",
                toolTip: "\(day.dateKey) · \(formatTokens(day.totalTokens)) tokens",
                isHidden: false,
                alpha: day.isFuture ? 0.45 : 1.0,
                intensity: day.intensity
            )
        }
    }

    private static func formatTokens(_ value: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }
}

/// 日历热力图单个 collection item。
final class CalendarHeatmapCollectionViewItem: NSCollectionViewItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("CalendarHeatmapCollectionViewItem")

    private let dayLabel = NSTextField(labelWithString: "")

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        view.wantsLayer = true
        view.layer?.cornerRadius = 5
        view.layer?.masksToBounds = true

        dayLabel.translatesAutoresizingMaskIntoConstraints = false
        dayLabel.alignment = .center
        dayLabel.font = .systemFont(ofSize: 11, weight: .medium)
        dayLabel.textColor = .labelColor

        view.addSubview(dayLabel)
        NSLayoutConstraint.activate([
            dayLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            dayLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    func configure(with cell: CalendarHeatmapCell) {
        let style = CalendarHeatmapCellStyle.make(for: cell)
        dayLabel.stringValue = style.title
        view.toolTip = style.toolTip
        view.isHidden = style.isHidden
        view.alphaValue = style.alpha
        view.layer?.backgroundColor = backgroundColor(forIntensity: style.intensity).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        view.needsDisplay = true
    }

    private func backgroundColor(forIntensity intensity: Int) -> NSColor {
        switch intensity {
        case 1:
            return NSColor.systemGreen.withAlphaComponent(0.28)
        case 2:
            return NSColor.systemGreen.withAlphaComponent(0.46)
        case 3:
            return NSColor.systemGreen.withAlphaComponent(0.68)
        case 4:
            return NSColor.systemGreen.withAlphaComponent(0.92)
        default:
            return NSColor.separatorColor.withAlphaComponent(0.35)
        }
    }
}
```

- [ ] **Step 4: Run item tests to verify they pass**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/CalendarHeatmapCollectionViewItemTests test
```

Expected: PASS.

- [ ] **Step 5: Commit item**

```bash
git add TokenWatch/ViewControllers/CalendarHeatmapCollectionViewItem.swift TokenWatchTests/ViewControllers/CalendarHeatmapCollectionViewItemTests.swift
git commit -m "feat(statusbar): 添加日历热力图单元格"
```

---

### Task 3: StatusPopoverViewController

**Files:**
- Create: `TokenWatchTests/ViewControllers/StatusPopoverViewControllerTests.swift`
- Create: `TokenWatch/ViewControllers/StatusPopoverViewController.swift`

- [ ] **Step 1: Write failing popover controller test**

Create `TokenWatchTests/ViewControllers/StatusPopoverViewControllerTests.swift`:

```swift
import AppKit
import Testing
@testable import TokenWatch

@MainActor
@Suite("StatusPopoverViewController")
struct StatusPopoverViewControllerTests {

    @Test("加载后创建标题和 7 列 collection view")
    func loadViewCreatesCalendarCollectionView() {
        let viewModel = TokenStatsViewModel()
        let controller = StatusPopoverViewController(
            viewModel: viewModel,
            nowProvider: { fixedDate() },
            calendar: fixedCalendar()
        )

        controller.loadViewIfNeeded()

        #expect(controller.debugMonthTitle == "2026 年 6 月")
        #expect(controller.debugCollectionView != nil)
        #expect(controller.debugWeekdayLabelCount == 7)
        #expect(controller.debugCollectionItemCount == 30)
    }

    private func fixedCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }

    private func fixedDate() -> Date {
        fixedCalendar().date(from: DateComponents(year: 2026, month: 6, day: 17))!
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/StatusPopoverViewControllerTests test
```

Expected: FAIL because `StatusPopoverViewController` does not exist.

- [ ] **Step 3: Implement popover controller**

Create `TokenWatch/ViewControllers/StatusPopoverViewController.swift`:

```swift
import AppKit

/// 状态栏 popover 内容控制器,展示本月跨 provider token 日历热力图。
@MainActor
final class StatusPopoverViewController: NSViewController {

    private let viewModel: TokenStatsViewModel
    private let nowProvider: () -> Date
    private let calendar: Calendar
    private var observerToken: TokenStatsViewModel.ObservationToken?
    private var snapshot: CalendarHeatmapSnapshot?

    private let titleLabel = NSTextField(labelWithString: "")
    private let totalLabel = NSTextField(labelWithString: "")
    private let weekdayStack = NSStackView()
    private let collectionView = NSCollectionView()

    var debugMonthTitle: String { titleLabel.stringValue }
    var debugCollectionView: NSCollectionView? { collectionView }
    var debugWeekdayLabelCount: Int { weekdayStack.arrangedSubviews.count }
    var debugCollectionItemCount: Int { snapshot?.cells.count ?? 0 }

    init(
        viewModel: TokenStatsViewModel,
        nowProvider: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.viewModel = viewModel
        self.nowProvider = nowProvider
        self.calendar = calendar
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = NSSize(width: 300, height: 260)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("StatusPopoverViewController 必须用 init(viewModel:) 构造")
    }

    override func loadView() {
        view = NSView(frame: NSRect(origin: .zero, size: preferredContentSize))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        setupSubviews()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        render()
        observerToken = viewModel.observe { [weak self] _ in
            self?.render()
        }
    }

    deinit {
        MainActor.assumeIsolated {
            if let observerToken {
                viewModel.removeObserver(observerToken)
            }
        }
    }

    private func setupSubviews() {
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .labelColor

        totalLabel.font = .systemFont(ofSize: 12)
        totalLabel.textColor = .secondaryLabelColor

        let headerStack = NSStackView(views: [titleLabel, totalLabel])
        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 2
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        weekdayStack.orientation = .horizontal
        weekdayStack.distribution = .fillEqually
        weekdayStack.spacing = 4
        weekdayStack.translatesAutoresizingMaskIntoConstraints = false

        let layout = NSCollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 4
        layout.minimumLineSpacing = 4
        layout.itemSize = NSSize(width: 34, height: 28)
        layout.sectionInset = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

        collectionView.collectionViewLayout = layout
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = false
        collectionView.dataSource = self
        collectionView.register(
            CalendarHeatmapCollectionViewItem.self,
            forItemWithIdentifier: CalendarHeatmapCollectionViewItem.reuseIdentifier
        )
        collectionView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(headerStack)
        view.addSubview(weekdayStack)
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            headerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            headerStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -14),

            weekdayStack.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 14),
            weekdayStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            weekdayStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            weekdayStack.heightAnchor.constraint(equalToConstant: 18),

            collectionView.topAnchor.constraint(equalTo: weekdayStack.bottomAnchor, constant: 6),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            collectionView.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -14),
        ])
    }

    private func render() {
        let snapshot = CalendarHeatmapBuilder.build(
            states: viewModel.states,
            month: nowProvider(),
            now: nowProvider(),
            calendar: calendar
        )
        self.snapshot = snapshot

        titleLabel.stringValue = snapshot.monthTitle
        totalLabel.stringValue = "本月 \(CompactNumberFormatter.format(snapshot.monthTotalTokens)) tokens"
        renderWeekdayLabels(snapshot.weekdaySymbols)
        collectionView.reloadData()
    }

    private func renderWeekdayLabels(_ symbols: [String]) {
        if weekdayStack.arrangedSubviews.count == symbols.count {
            for (view, symbol) in zip(weekdayStack.arrangedSubviews, symbols) {
                (view as? NSTextField)?.stringValue = symbol
            }
            return
        }

        weekdayStack.arrangedSubviews.forEach { view in
            weekdayStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for symbol in symbols {
            let label = NSTextField(labelWithString: symbol)
            label.alignment = .center
            label.font = .systemFont(ofSize: 10, weight: .medium)
            label.textColor = .secondaryLabelColor
            weekdayStack.addArrangedSubview(label)
        }
    }
}

extension StatusPopoverViewController: NSCollectionViewDataSource {
    func collectionView(
        _ collectionView: NSCollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        snapshot?.cells.count ?? 0
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        let item = collectionView.makeItem(
            withIdentifier: CalendarHeatmapCollectionViewItem.reuseIdentifier,
            for: indexPath
        )
        guard let heatmapItem = item as? CalendarHeatmapCollectionViewItem,
              let cell = snapshot?.cells[indexPath.item] else {
            return item
        }
        heatmapItem.configure(with: cell)
        return heatmapItem
    }
}
```

- [ ] **Step 4: Run popover controller test to verify it passes**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/StatusPopoverViewControllerTests test
```

Expected: PASS.

- [ ] **Step 5: Commit popover controller**

```bash
git add TokenWatch/ViewControllers/StatusPopoverViewController.swift TokenWatchTests/ViewControllers/StatusPopoverViewControllerTests.swift
git commit -m "feat(statusbar): 添加热力图弹窗控制器"
```

---

### Task 4: Wire Popover Into StatusBarController

**Files:**
- Modify: `TokenWatch/ViewControllers/StatusBarController.swift`
- Modify: `TokenWatchTests/ViewControllers/StatusBarControllerTests.swift`

- [ ] **Step 1: Add failing regression test for popover sizing contract**

Extend `TokenWatchTests/ViewControllers/StatusBarControllerTests.swift`:

```swift
/// 热力图 popover 尺寸要能容纳标题、星期行和 7 列日历网格。
@Test func heatmapPopoverContentSizeFitsCalendarGrid() {
    #expect(StatusBarPopoverLayout.contentSize == NSSize(width: 300, height: 260))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/StatusBarControllerTests/heatmapPopoverContentSizeFitsCalendarGrid test
```

Expected: FAIL because `StatusBarPopoverLayout` does not exist.

- [ ] **Step 3: Modify StatusBarController**

In `TokenWatch/ViewControllers/StatusBarController.swift`, add near the click/highlight helpers:

```swift
/// 状态栏 popover 固定布局参数。
enum StatusBarPopoverLayout {
    static let contentSize = NSSize(width: 300, height: 260)
}
```

Replace `configurePopover()` with:

```swift
private func configurePopover() {
    let contentViewController = StatusPopoverViewController(viewModel: viewModel)
    contentViewController.preferredContentSize = StatusBarPopoverLayout.contentSize

    popover.behavior = .transient
    popover.contentSize = StatusBarPopoverLayout.contentSize
    popover.contentViewController = contentViewController
    popoverCloseObserver = NotificationCenter.default.addObserver(
        forName: NSPopover.didCloseNotification,
        object: popover,
        queue: .main
    ) { [weak self] _ in
        Task { @MainActor in
            self?.setStatusButtonHighlighted(popoverIsShown: false)
        }
    }
}
```

Delete `EmptyStatusPopoverView` from the bottom of `StatusBarController.swift`.

- [ ] **Step 4: Run status bar controller tests**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/StatusBarControllerTests test
```

Expected: PASS.

- [ ] **Step 5: Run all new unit tests together**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/CalendarHeatmapBuilderTests -only-testing:TokenWatchTests/CalendarHeatmapCollectionViewItemTests -only-testing:TokenWatchTests/StatusPopoverViewControllerTests -only-testing:TokenWatchTests/StatusBarControllerTests test
```

Expected: PASS.

- [ ] **Step 6: Commit wiring**

```bash
git add TokenWatch/ViewControllers/StatusBarController.swift TokenWatchTests/ViewControllers/StatusBarControllerTests.swift
git commit -m "feat(statusbar): 在弹窗接入本月热力图"
```

---

### Task 5: Final Verification

**Files:**
- No new files.

- [ ] **Step 1: Run full unit test bundle**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests test
```

Expected: PASS.

- [ ] **Step 2: Run full app build**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Debug build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Inspect final diff**

Run:

```bash
git status --short
git diff --stat HEAD
```

Expected: working tree contains only intended implementation changes if not committed by prior tasks, or is clean if all task commits were made.
