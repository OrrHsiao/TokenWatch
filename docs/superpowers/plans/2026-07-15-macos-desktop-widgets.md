# macOS Desktop Chart Widgets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two separately installable macOS desktop widgets that reproduce TokenWatch's existing 22-week heatmap and today's 24-hour line chart.

**Architecture:** The main app remains the only process that scans and aggregates provider data. After a complete all-provider refresh, it maps the existing chart builders into a versioned Codable snapshot, writes that snapshot atomically to an App Group container, and asks WidgetKit to reload two static timelines. The Widget Extension reads only that snapshot and renders two pure-SwiftUI `.systemMedium` widgets.

**Tech Stack:** Swift 6, AppKit, SwiftUI, Swift Charts, WidgetKit, Foundation App Groups, Swift Testing, Xcode 26.5 / macOS 15 deployment target.

## Global Constraints

- The deployment target remains exactly `macOS 15.0`.
- The app, shared production sources, and Widget Extension use Swift 6; do not add third-party packages.
- The Widget bundle identifier is `com.xiaoao.tokenwatch.widgets`.
- Both products use the App Group `group.com.xiaoao.tokenwatch` and the file `widget-usage-v1.json`.
- Publish exactly two widget kinds: `TokenHeatmapWidget` and `TokenHourlyLineWidget`.
- Both widgets support only `.systemMedium`.
- Heatmap data is exactly 22 columns × 7 rows; hourly data is exactly the local wall-clock hours `0...23`.
- Token totals use the existing popover `UsageSummary.totalTokens` semantics, including reasoning tokens.
- The Extension never scans provider logs, restores security-scoped bookmarks, or persists paths/session/model details.
- Preserve system widget margins, semantic backgrounds, light/dark appearance, and the existing popover's chart constants.
- Document the invariants of every shared/core type and method; comments explain cross-process, schema, calendar, or publication decisions rather than restating syntax.
- A missing snapshot, a valid zero snapshot, and a stale snapshot are three different states.
- Prefer Xcode MCP for builds/tests when an Xcode workspace tab is available. Every shell fallback must use `-derivedDataPath .build/DerivedData`.
- Run real tests outside the sandbox or with approval when `testmanagerd` is blocked; `build-for-testing` proves compilation only.
- Do not modify or stage the unrelated localization plan `docs/superpowers/plans/2026-07-15-codex-ui-locales.md`.

## File Map

Shared by the app and Widget Extension:

- `TokenWatchShared/Widgets/WidgetSharedConfiguration.swift`: identifiers and schema constants.
- `TokenWatchShared/Widgets/WidgetUsageSnapshot.swift`: Codable DTOs and semantic comparison.
- `TokenWatchShared/Widgets/JSONWidgetSnapshotStore.swift`: App Group URL resolution, validation, and atomic JSON IO.
- `TokenWatchShared/Widgets/WidgetChartVisualStyle.swift`: framework-neutral colors, layout numbers, and compact formatters.
- `TokenWatchShared/Widgets/WidgetChartRendering.swift`: the framework-neutral Catmull–Rom rendering semantic mapped by each UI target.
- `TokenWatchShared/Widgets/WidgetTimelinePlanning.swift`: current/stale/not-ready classification and next-midnight scheduling.
- `TokenWatchShared/Widgets/WidgetChartPresentation.swift`: pure presentation models for zero, stale, preview, and not-ready states.

Main-app only:

- `TokenWatch/Widgets/WidgetSnapshotBuilder.swift`: maps existing app chart snapshots to the shared DTO.
- `TokenWatch/Widgets/WidgetSnapshotPublisher.swift`: actor-isolated deduplication, write, logging, and timeline reload.
- `TokenWatch/ViewModels/TokenStatsViewModel.swift`: all-refresh gate and consistent publication point.
- `TokenWatch/AppDelegate.swift`: injects the live publisher.
- `TokenWatch/Localization/AppStrings.swift`: four Widget content strings in every supported app language.
- `TokenWatch/ViewControllers/CompactNumberFormatter.swift`: delegates to the shared formatter.
- `TokenWatch/ViewControllers/CalendarHeatmapCollectionViewItem.swift`: delegates palette values to shared RGBA constants.
- `TokenWatch/ViewControllers/TodayHourlyTokenLineChartView.swift`: delegates numeric rendering constants to shared style values.

Widget Extension only:

- `TokenWatchWidgets/Info.plist`: WidgetKit extension point.
- `TokenWatchWidgets/TokenWatchWidgets.entitlements`: sandbox and App Group.
- `TokenWatchWidgets/TokenWatchWidgetsBundle.swift`: registers both Widget configurations.
- `TokenWatchWidgets/WidgetTimelineProvider.swift`: thin WidgetKit adapter over shared store/planning logic.
- `TokenWatchWidgets/WidgetSampleSnapshotFactory.swift`: deterministic gallery/preview data and system-language fallback text.
- `TokenWatchWidgets/WidgetChartHeader.swift`: shared title/total header.
- `TokenWatchWidgets/TokenHeatmapWidget.swift`: configuration and heatmap view.
- `TokenWatchWidgets/TokenHourlyLineWidget.swift`: configuration and Swift Charts view.
- `TokenWatchWidgets/Localizable.xcstrings`: gallery names/descriptions and first-run fallback copy.

Signing/project files:

- `TokenWatch/TokenWatch.entitlements`: preserves app sandbox/file access and adds App Group.
- `TokenWatch.xcodeproj/project.pbxproj`: shared root, Widget target/product, dependency, embed phase, build settings.
- `TokenWatch.xcodeproj/xcshareddata/xcschemes/TokenWatchWidgets.xcscheme`: direct extension build/debug scheme.

Tests:

- `TokenWatchTests/Widgets/WidgetUsageSnapshotTests.swift`
- `TokenWatchTests/Widgets/WidgetChartVisualStyleTests.swift`
- `TokenWatchTests/Widgets/JSONWidgetSnapshotStoreTests.swift`
- `TokenWatchTests/Widgets/WidgetSnapshotBuilderTests.swift`
- `TokenWatchTests/Widgets/WidgetSnapshotPublisherTests.swift`
- `TokenWatchTests/ViewModels/TokenStatsViewModelWidgetPublishingTests.swift`
- `TokenWatchTests/Widgets/WidgetTimelinePlanningTests.swift`
- `TokenWatchTests/Widgets/WidgetChartPresentationTests.swift`
- Existing formatter, heatmap item, line-chart, language, and builder suites remain regression coverage.

---

### Task 1: Add the Shared Snapshot Contract

**Files:**
- Create: `TokenWatchShared/Widgets/WidgetSharedConfiguration.swift`
- Create: `TokenWatchShared/Widgets/WidgetUsageSnapshot.swift`
- Create: `TokenWatchTests/Widgets/WidgetUsageSnapshotTests.swift`
- Modify: `TokenWatch.xcodeproj/project.pbxproj:32-48, 74-95, 98-119`

**Interfaces:**
- Consumes: only Foundation value types.
- Produces: `WidgetSharedConfiguration`, `WidgetUsageSnapshot`, `WidgetLocalizedText`, `WidgetHeatmapSnapshot`, `WidgetHeatmapCell`, `WidgetHourlyLineSnapshot`, and `WidgetHourlyPoint`.

- [ ] **Step 1: Write the failing DTO tests**

Create the test suite with these exact behaviors:

```swift
import Foundation
import Testing
@testable import TokenWatch

@Suite("WidgetUsageSnapshot")
struct WidgetUsageSnapshotTests {
    @Test("schema 1 snapshot round-trips through JSON")
    func schemaOneRoundTrips() throws {
        let source = makeSnapshot(generatedAt: Date(timeIntervalSince1970: 100))
        let data = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(WidgetUsageSnapshot.self, from: data)
        #expect(decoded == source)
        #expect(decoded.schemaVersion == WidgetSharedConfiguration.schemaVersion)
    }

    @Test("semantic comparison ignores generatedAt and nothing else")
    func semanticComparisonIgnoresGeneratedAtOnly() {
        let first = makeSnapshot(generatedAt: Date(timeIntervalSince1970: 100))
        let later = makeSnapshot(generatedAt: Date(timeIntervalSince1970: 200))
        let changed = makeSnapshot(
            generatedAt: Date(timeIntervalSince1970: 200),
            todayTotal: 43
        )

        #expect(first.hasSameContent(as: later))
        #expect(!first.hasSameContent(as: changed))
    }

    private func makeSnapshot(
        generatedAt: Date,
        todayTotal: Int = 42
    ) -> WidgetUsageSnapshot {
        WidgetUsageSnapshot(
            schemaVersion: WidgetSharedConfiguration.schemaVersion,
            generatedAt: generatedAt,
            localDayKey: "2026-07-15",
            localizedText: WidgetLocalizedText(
                heatmapTitle: "最近 22 周",
                todayUsageTitle: "今日用量",
                datedUsageTitle: "7/15 用量",
                updatedThroughTitle: "更新至 7/15",
                notReadyMessage: "打开 TokenWatch 刷新数据"
            ),
            heatmap: WidgetHeatmapSnapshot(
                totalTokens: 42,
                maxDailyTokens: 42,
                cells: [
                    WidgetHeatmapCell(
                        dateKey: "2026-07-15",
                        totalTokens: 42,
                        intensity: 4,
                        isPlaceholder: false
                    )
                ]
            ),
            hourlyLine: WidgetHourlyLineSnapshot(
                dayKey: "2026-07-15",
                totalTokens: todayTotal,
                maxHourlyTokens: todayTotal,
                points: [
                    WidgetHourlyPoint(
                        hour: 0,
                        hourKey: "2026-07-15T00",
                        hourLabel: "0时",
                        totalTokens: todayTotal,
                        isCurrentHour: true
                    )
                ]
            )
        )
    }
}
```

- [ ] **Step 2: Run the suite to verify RED**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/WidgetUsageSnapshotTests -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData test
```

Expected: compilation fails with `cannot find 'WidgetUsageSnapshot' in scope`.

- [ ] **Step 3: Add the synchronized shared root to the app target**

Create `TokenWatchShared/Widgets/`, then add one `PBXFileSystemSynchronizedRootGroup` with ID `C0D300012FD0000000000001`, path `TokenWatchShared`, to the main group and to `TokenWatch.fileSystemSynchronizedGroups`. The relevant relationships must be exactly:

```text
PBXFileSystemSynchronizedRootGroup C0D300012FD0000000000001 → path TokenWatchShared
PBXGroup AAA358012FDD7BFB0018086B.children → add C0D300012FD0000000000001
PBXNativeTarget AAA358092FDD7BFB0018086B.fileSystemSynchronizedGroups → add C0D300012FD0000000000001
```

- [ ] **Step 4: Implement the minimal shared contract**

Use these constants and types:

```swift
import Foundation

enum WidgetSharedConfiguration {
    static let schemaVersion = 1
    static let appGroupIdentifier = "group.com.xiaoao.tokenwatch"
    static let snapshotFilename = "widget-usage-v1.json"
    static let heatmapKind = "TokenHeatmapWidget"
    static let hourlyLineKind = "TokenHourlyLineWidget"
}
```

```swift
import Foundation

struct WidgetUsageSnapshot: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let generatedAt: Date
    let localDayKey: String
    let localizedText: WidgetLocalizedText
    let heatmap: WidgetHeatmapSnapshot
    let hourlyLine: WidgetHourlyLineSnapshot

    /// Compares every render-relevant value while deliberately ignoring generation time.
    func hasSameContent(as other: WidgetUsageSnapshot) -> Bool {
        schemaVersion == other.schemaVersion
            && localDayKey == other.localDayKey
            && localizedText == other.localizedText
            && heatmap == other.heatmap
            && hourlyLine == other.hourlyLine
    }
}

struct WidgetLocalizedText: Codable, Equatable, Sendable {
    let heatmapTitle: String
    let todayUsageTitle: String
    let datedUsageTitle: String
    let updatedThroughTitle: String
    let notReadyMessage: String
}

struct WidgetHeatmapSnapshot: Codable, Equatable, Sendable {
    let totalTokens: Int
    let maxDailyTokens: Int
    let cells: [WidgetHeatmapCell]
}

struct WidgetHeatmapCell: Codable, Equatable, Sendable {
    let dateKey: String?
    let totalTokens: Int
    let intensity: Int
    let isPlaceholder: Bool
}

struct WidgetHourlyLineSnapshot: Codable, Equatable, Sendable {
    let dayKey: String
    let totalTokens: Int
    let maxHourlyTokens: Int
    let points: [WidgetHourlyPoint]
}

struct WidgetHourlyPoint: Codable, Equatable, Identifiable, Sendable {
    var id: String { hourKey }

    let hour: Int
    let hourKey: String
    let hourLabel: String
    let totalTokens: Int
    let isCurrentHour: Bool
}
```

- [ ] **Step 5: Run GREEN and the existing snapshot-adjacent tests**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/WidgetUsageSnapshotTests -only-testing:TokenWatchTests/CalendarHeatmapBuilderTests -only-testing:TokenWatchTests/MonthlyTokenChartBuilderTests -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData test
```

Expected: all selected tests pass.

- [ ] **Step 6: Commit the shared contract**

```bash
git add TokenWatchShared/Widgets/WidgetSharedConfiguration.swift TokenWatchShared/Widgets/WidgetUsageSnapshot.swift TokenWatchTests/Widgets/WidgetUsageSnapshotTests.swift TokenWatch.xcodeproj/project.pbxproj
git commit -m "feat(widget): 添加共享快照模型"
```

### Task 2: Extract Shared Chart Formatting and Visual Constants

**Files:**
- Create: `TokenWatchShared/Widgets/WidgetChartVisualStyle.swift`
- Create: `TokenWatchShared/Widgets/WidgetChartRendering.swift`
- Create: `TokenWatchTests/Widgets/WidgetChartVisualStyleTests.swift`
- Modify: `TokenWatch/ViewControllers/CompactNumberFormatter.swift:1-67`
- Modify: `TokenWatch/ViewControllers/CalendarHeatmapCollectionViewItem.swift:218-251`
- Modify: `TokenWatch/ViewControllers/TodayHourlyTokenLineChartView.swift:5-8, 139-160, 182-226`
- Modify: `TokenWatch/ViewControllers/MonthlyBarChartStyle.swift:42-63`

**Interfaces:**
- Consumes: `WidgetSharedConfiguration` only for shared-module membership.
- Produces: `WidgetChartRGBA`, `WidgetChartVisualStyle`, `WidgetChartNumberFormatter`, `WidgetLineInterpolationStyle`, and `WidgetChartRendering` for both the popover and Widget.

- [ ] **Step 1: Write failing tests for every approved visual constant**

```swift
import Testing
@testable import TokenWatch

@Suite("Widget chart visual style")
struct WidgetChartVisualStyleTests {
    @Test("heatmap geometry and hourly chart constants match the popover")
    func constantsMatchPopover() {
        #expect(WidgetChartVisualStyle.heatmapColumns == 22)
        #expect(WidgetChartVisualStyle.heatmapRows == 7)
        #expect(WidgetChartVisualStyle.heatmapMaximumIntensity == 4)
        #expect(WidgetChartVisualStyle.heatmapSpacing == 3)
        #expect(WidgetChartVisualStyle.heatmapCornerRadius == 2)
        #expect(WidgetChartVisualStyle.hourAxisValues == [0, 6, 12, 18, 23])
        #expect(WidgetChartVisualStyle.lineWidth == 2)
        #expect(WidgetChartVisualStyle.currentPointSize == 22)
        #expect(WidgetChartVisualStyle.areaPeakOpacity == 0.8)
        #expect(WidgetChartVisualStyle.areaBaselineOpacity == 0.05)
        #expect(WidgetChartVisualStyle.gridOpacity == 0.16)
        #expect(WidgetChartRendering.lineInterpolationStyle == .catmullRom)
        #expect(WidgetChartRendering.lineInterpolationMethodName == "catmullRom")
    }

    @Test("palette values exactly match light and dark popover colors")
    func paletteMatchesPopover() {
        #expect(WidgetChartVisualStyle.heatmapRGBA(intensity: 0, isDark: false) == .bytes(216, 222, 232))
        #expect(WidgetChartVisualStyle.heatmapRGBA(intensity: 4, isDark: false) == .bytes(33, 110, 57))
        #expect(WidgetChartVisualStyle.heatmapRGBA(intensity: 0, isDark: true) == .bytes(25, 30, 37))
        #expect(WidgetChartVisualStyle.heatmapRGBA(intensity: 4, isDark: true) == .bytes(57, 211, 83))
        #expect(WidgetChartVisualStyle.heatmapRGBA(intensity: -1, isDark: false) == .bytes(216, 222, 232))
        #expect(WidgetChartVisualStyle.heatmapRGBA(intensity: 9, isDark: true) == .bytes(57, 211, 83))
    }

    @Test("medium heatmap and zero chart calculations are stable")
    func layoutAndZeroScaleAreStable() {
        #expect(WidgetChartVisualStyle.heatmapTileSide(availableWidth: 327, availableHeight: 102) == 12)
        #expect(WidgetChartVisualStyle.heatmapIndex(column: 0, row: 0) == 0)
        #expect(WidgetChartVisualStyle.heatmapIndex(column: 21, row: 6) == 153)
        #expect(WidgetChartVisualStyle.hourlyMaximumY(maxHourlyTokens: 0) == 1)
    }

    @Test("shared formatter matches existing widget and axis boundaries")
    func formatterMatchesExistingBoundaries() {
        #expect(WidgetChartNumberFormatter.compact(99_999) == "99.9k")
        #expect(WidgetChartNumberFormatter.compact(1_234_567) == "1.2M")
        #expect(WidgetChartNumberFormatter.dashboard(0) == "0.0M")
        #expect(WidgetChartNumberFormatter.axis(0) == "0")
        #expect(WidgetChartNumberFormatter.axis(1_500_000) == "2M")
    }
}
```

- [ ] **Step 2: Run the tests to verify RED**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/WidgetChartVisualStyleTests -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData test
```

Expected: compilation fails because `WidgetChartVisualStyle` does not exist.

- [ ] **Step 3: Implement the framework-neutral shared style**

```swift
import Foundation

struct WidgetChartRGBA: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    static func bytes(_ red: Int, _ green: Int, _ blue: Int) -> WidgetChartRGBA {
        WidgetChartRGBA(
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            alpha: 1
        )
    }
}

enum WidgetChartVisualStyle {
    static let heatmapColumns = 22
    static let heatmapRows = 7
    static let heatmapMaximumIntensity = 4
    static let heatmapSpacing = 3.0
    static let heatmapCornerRadius = 2.0
    static let hourAxisValues = [0, 6, 12, 18, 23]
    static let lineWidth = 2.0
    static let currentPointSize = 22.0
    static let areaPeakOpacity = 0.8
    static let areaBaselineOpacity = 0.05
    static let gridOpacity = 0.16

    private static let lightPalette: [WidgetChartRGBA] = [
        .bytes(216, 222, 232), .bytes(155, 233, 168),
        .bytes(64, 196, 99), .bytes(48, 161, 78), .bytes(33, 110, 57),
    ]
    private static let darkPalette: [WidgetChartRGBA] = [
        .bytes(25, 30, 37), .bytes(14, 68, 41),
        .bytes(0, 109, 50), .bytes(38, 166, 65), .bytes(57, 211, 83),
    ]

    static func heatmapRGBA(intensity: Int, isDark: Bool) -> WidgetChartRGBA {
        let clamped = min(max(intensity, 0), heatmapMaximumIntensity)
        return (isDark ? darkPalette : lightPalette)[clamped]
    }

    static func heatmapTileSide(availableWidth: Double, availableHeight: Double) -> Double {
        let horizontalGaps = heatmapSpacing * Double(heatmapColumns - 1)
        let verticalGaps = heatmapSpacing * Double(heatmapRows - 1)
        let widthBound = floor((availableWidth - horizontalGaps) / Double(heatmapColumns))
        let heightBound = floor((availableHeight - verticalGaps) / Double(heatmapRows))
        return min(12, max(0, min(widthBound, heightBound)))
    }

    static func heatmapIndex(column: Int, row: Int) -> Int {
        column * heatmapRows + row
    }

    static func hourlyMaximumY(maxHourlyTokens: Int) -> Double {
        max(1, Double(maxHourlyTokens))
    }
}

enum WidgetChartNumberFormatter {
    static func compact(_ value: Int) -> String {
        guard value > 0 else { return "0" }
        if value < 1_000 { return String(value) }
        let divisor = value < 1_000_000 ? 100 : 100_000
        let suffix = value < 1_000_000 ? "k" : "M"
        let tenths = value / divisor
        return "\(tenths / 10).\(tenths % 10)\(suffix)"
    }

    static func dashboard(_ value: Int) -> String {
        guard value > 0 else { return "0.0M" }
        if value < 1_000 { return String(value) }
        let divisor = value < 100_000 ? 100 : 100_000
        let suffix = value < 100_000 ? "k" : "M"
        let tenths = value / divisor
        return "\(tenths / 10).\(tenths % 10)\(suffix)"
    }

    static func axis(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "0" }
        let rounded = value.rounded()
        if rounded < 1_000 { return String(format: "%.0f", locale: Locale(identifier: "en_US_POSIX"), rounded) }
        if rounded < 1_000_000 { return String(format: "%.0fk", locale: Locale(identifier: "en_US_POSIX"), (rounded / 1_000).rounded()) }
        return String(format: "%.0fM", locale: Locale(identifier: "en_US_POSIX"), (rounded / 1_000_000).rounded())
    }
}
```

Create the framework-neutral `WidgetChartRendering.swift` at the same GREEN
step. It must not import Swift Charts; each UI target performs the exhaustive
mapping to its framework type:

```swift
enum WidgetLineInterpolationStyle: String, Equatable, Sendable {
    case catmullRom
}

enum WidgetChartRendering {
    static let lineInterpolationStyle: WidgetLineInterpolationStyle = .catmullRom
    static let lineInterpolationMethodName = lineInterpolationStyle.rawValue
}
```

- [ ] **Step 4: Delegate existing popover helpers to the shared values**

Keep the existing public-to-module names stable and make these exact replacements:

```swift
// CompactNumberFormatter.swift
static func format(_ value: Int) -> String {
    WidgetChartNumberFormatter.compact(value)
}

static func formatMillions(_ value: Int) -> String {
    WidgetChartNumberFormatter.dashboard(value)
}

static func formatHoverTokens(_ value: Int) -> String {
    WidgetChartNumberFormatter.dashboard(value)
}

// MonthlyBarChartStyle.swift
static func tokenAxisLabel(for value: Double) -> String {
    WidgetChartNumberFormatter.axis(value)
}
```

Replace `CalendarHeatmapGitHubPalette`'s duplicated arrays with `WidgetChartVisualStyle.heatmapRGBA(intensity:isDark:)`, converting the result to `NSColor`. Set `maxIntensity` to `WidgetChartVisualStyle.heatmapMaximumIntensity` after adding `static let heatmapMaximumIntensity = 4` to the shared style. In `TodayHourlyTokenLineChartView`, delegate its interpolation semantic/name to `WidgetChartRendering`, and replace the duplicated axis values, line width, point size, area opacities, Y maximum, and grid opacity with the corresponding shared constants; convert framework-neutral `Double` geometry constants with `CGFloat(...)` wherever AppKit/SwiftUI requires `CGFloat`.

Use this exhaustive Charts mapping in `TodayHourlyLineChartRendering`, keeping
the shared source independent of UI frameworks:

```swift
static let interpolationMethod: InterpolationMethod = {
    switch WidgetChartRendering.lineInterpolationStyle {
    case .catmullRom:
        return .catmullRom
    }
}()
static let interpolationMethodName = WidgetChartRendering.lineInterpolationMethodName
```

The palette conversion is:

```swift
enum CalendarHeatmapGitHubPalette {
    static let maxIntensity = WidgetChartVisualStyle.heatmapMaximumIntensity

    static func color(forIntensity intensity: Int) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return color(WidgetChartVisualStyle.heatmapRGBA(
                intensity: intensity,
                isDark: isDark
            ))
        }
    }

    static var maxIntensityColor: NSColor {
        color(forIntensity: maxIntensity)
    }

    private static func color(_ rgba: WidgetChartRGBA) -> NSColor {
        NSColor(
            calibratedRed: CGFloat(rgba.red),
            green: CGFloat(rgba.green),
            blue: CGFloat(rgba.blue),
            alpha: CGFloat(rgba.alpha)
        )
    }
}
```

- [ ] **Step 5: Run shared and existing visual regression tests**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/WidgetChartVisualStyleTests -only-testing:TokenWatchTests/CompactNumberFormatterTests -only-testing:TokenWatchTests/CalendarHeatmapCollectionViewItemTests -only-testing:TokenWatchTests/TodayHourlyTokenLineChartViewTests -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData test
```

Expected: all selected tests pass and existing popover expectations remain unchanged.

- [ ] **Step 6: Commit the shared visual contract**

```bash
git add TokenWatchShared/Widgets/WidgetChartVisualStyle.swift TokenWatchShared/Widgets/WidgetChartRendering.swift TokenWatchTests/Widgets/WidgetChartVisualStyleTests.swift TokenWatch/ViewControllers/CompactNumberFormatter.swift TokenWatch/ViewControllers/CalendarHeatmapCollectionViewItem.swift TokenWatch/ViewControllers/TodayHourlyTokenLineChartView.swift TokenWatch/ViewControllers/MonthlyBarChartStyle.swift
git commit -m "refactor(widget): 共享图表视觉常量"
```

### Task 3: Add Validated Atomic Snapshot Storage

**Files:**
- Create: `TokenWatchShared/Widgets/JSONWidgetSnapshotStore.swift`
- Create: `TokenWatchTests/Widgets/JSONWidgetSnapshotStoreTests.swift`

**Interfaces:**
- Consumes: `WidgetSharedConfiguration` and `WidgetUsageSnapshot` from Task 1.
- Produces: `WidgetSnapshotStoring`, `WidgetSnapshotReadResult`, `WidgetSnapshotReadFailure`, `WidgetSnapshotStoreError`, `WidgetUsageSnapshotValidator`, and `JSONWidgetSnapshotStore`.

- [ ] **Step 1: Write failing storage and validation tests**

Create the complete suite, including its valid fixture and every invalid mutation:

```swift
import Foundation
import Testing
@testable import TokenWatch

@Suite("JSON widget snapshot store")
struct JSONWidgetSnapshotStoreTests {
    @Test("valid snapshot saves and loads exactly")
    func validSnapshotRoundTrips() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("snapshot.json", isDirectory: false)
        let source = makeValidSnapshot(totalTokens: 42)
        let store = JSONWidgetSnapshotStore(fileURL: fileURL)

        try store.save(source)

        #expect(store.load() == .available(source))
    }

    @Test("missing file is distinct from corrupt data")
    func missingFileReturnsMissing() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("snapshot.json", isDirectory: false)

        #expect(JSONWidgetSnapshotStore(fileURL: fileURL).load() == .missing)
    }

    @Test("invalid JSON is reported as corrupt")
    func corruptJSONReturnsCorrupt() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("snapshot.json", isDirectory: false)
        try Data("not-json".utf8).write(to: fileURL)

        #expect(JSONWidgetSnapshotStore(fileURL: fileURL).load() == .invalid(.corrupt))
    }

    @Test("unknown schema is recognized before payload decoding")
    func unknownSchemaIsRejectedBeforePayloadDecode() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("snapshot.json", isDirectory: false)
        try Data(#"{"schemaVersion":2}"#.utf8).write(to: fileURL)

        #expect(JSONWidgetSnapshotStore(fileURL: fileURL).load() == .invalid(.unsupportedSchema(2)))
    }

    @Test("every invalid render shape is rejected")
    func invalidShapesReturnCorrupt() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("snapshot.json", isDirectory: false)
        let store = JSONWidgetSnapshotStore(fileURL: fileURL)

        for (name, snapshot) in invalidSnapshots() {
            try JSONEncoder().encode(snapshot).write(to: fileURL)
            #expect(
                store.load() == .invalid(.corrupt),
                "mutation must be rejected: \(name)"
            )
            #expect(
                !WidgetUsageSnapshotValidator.isValid(snapshot),
                "validator must reject: \(name)"
            )
        }
    }

    @Test("atomic write failure leaves the old bytes readable")
    func failedAtomicWritePreservesExistingSnapshot() throws {
        struct InjectedWriteError: Error {}

        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("snapshot.json", isDirectory: false)
        let old = makeValidSnapshot(totalTokens: 10)
        let realStore = JSONWidgetSnapshotStore(fileURL: fileURL)
        try realStore.save(old)

        let failingStore = JSONWidgetSnapshotStore(
            fileURL: fileURL,
            atomicWrite: { _, _ in throw InjectedWriteError() }
        )
        #expect(throws: InjectedWriteError.self) {
            try failingStore.save(makeValidSnapshot(totalTokens: 20))
        }
        #expect(realStore.load() == .available(old))
    }

    private func invalidSnapshots() -> [(String, WidgetUsageSnapshot)] {
        let validCells = makeHeatmapCells(totalTokens: 42)
        let validPoints = makeHourlyPoints(totalTokens: 42)

        var duplicateHours = validPoints
        duplicateHours[23] = copyPoint(duplicateHours[23], hour: 22)

        var outOfOrderHours = validPoints
        outOfOrderHours.swapAt(0, 1)

        var duplicateHourKeys = validPoints
        duplicateHourKeys[23] = copyPoint(
            duplicateHourKeys[23],
            hourKey: validPoints[0].hourKey
        )

        let zeroCurrentMarkers = validPoints.map {
            copyPoint($0, isCurrentHour: false)
        }

        var twoCurrentMarkers = validPoints
        twoCurrentMarkers[12] = copyPoint(twoCurrentMarkers[12], isCurrentHour: true)

        var excessiveIntensity = validCells
        excessiveIntensity[0] = copyCell(excessiveIntensity[0], intensity: 5)

        var nonzeroPlaceholder = validCells
        nonzeroPlaceholder[153] = WidgetHeatmapCell(
            dateKey: nil,
            totalTokens: 1,
            intensity: 1,
            isPlaceholder: true
        )

        var negativeCellTotal = validCells
        negativeCellTotal[0] = copyCell(negativeCellTotal[0], totalTokens: -1)

        var negativePointTotal = validPoints
        negativePointTotal[0] = copyPoint(negativePointTotal[0], totalTokens: -1)

        return [
            ("153 heatmap cells", makeValidSnapshot(
                heatmapCells: Array(validCells.dropLast())
            )),
            ("23 hourly points", makeValidSnapshot(
                hourlyPoints: Array(validPoints.dropLast())
            )),
            ("duplicate and missing hour", makeValidSnapshot(
                hourlyPoints: duplicateHours
            )),
            ("out-of-order hours", makeValidSnapshot(
                hourlyPoints: outOfOrderHours
            )),
            ("duplicate hour key", makeValidSnapshot(
                hourlyPoints: duplicateHourKeys
            )),
            ("zero current markers", makeValidSnapshot(
                hourlyPoints: zeroCurrentMarkers
            )),
            ("two current markers", makeValidSnapshot(
                hourlyPoints: twoCurrentMarkers
            )),
            ("intensity above four", makeValidSnapshot(
                heatmapCells: excessiveIntensity
            )),
            ("nonzero placeholder", makeValidSnapshot(
                heatmapCells: nonzeroPlaceholder
            )),
            ("negative heatmap total", makeValidSnapshot(
                heatmapTotalTokens: -1
            )),
            ("negative heatmap maximum", makeValidSnapshot(
                maxDailyTokens: -1
            )),
            ("negative hourly total", makeValidSnapshot(
                hourlyTotalTokens: -1
            )),
            ("negative hourly maximum", makeValidSnapshot(
                maxHourlyTokens: -1
            )),
            ("negative heatmap cell", makeValidSnapshot(
                heatmapCells: negativeCellTotal
            )),
            ("negative hourly point", makeValidSnapshot(
                hourlyPoints: negativePointTotal
            )),
            ("mismatched day keys", makeValidSnapshot(
                hourlyDayKey: "2026-07-14"
            )),
        ]
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "JSONWidgetSnapshotStoreTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }

    private func makeValidSnapshot(
        totalTokens: Int = 42,
        heatmapCells: [WidgetHeatmapCell]? = nil,
        hourlyPoints: [WidgetHourlyPoint]? = nil,
        heatmapTotalTokens: Int? = nil,
        maxDailyTokens: Int = 42,
        hourlyTotalTokens: Int? = nil,
        maxHourlyTokens: Int = 42,
        hourlyDayKey: String = "2026-07-15"
    ) -> WidgetUsageSnapshot {
        WidgetUsageSnapshot(
            schemaVersion: WidgetSharedConfiguration.schemaVersion,
            generatedAt: Date(timeIntervalSince1970: 100),
            localDayKey: "2026-07-15",
            localizedText: WidgetLocalizedText(
                heatmapTitle: "最近 22 周",
                todayUsageTitle: "今日用量",
                datedUsageTitle: "7/15 用量",
                updatedThroughTitle: "更新至 7/15",
                notReadyMessage: "打开 TokenWatch 刷新数据"
            ),
            heatmap: WidgetHeatmapSnapshot(
                totalTokens: heatmapTotalTokens ?? totalTokens,
                maxDailyTokens: maxDailyTokens,
                cells: heatmapCells ?? makeHeatmapCells(totalTokens: totalTokens)
            ),
            hourlyLine: WidgetHourlyLineSnapshot(
                dayKey: hourlyDayKey,
                totalTokens: hourlyTotalTokens ?? totalTokens,
                maxHourlyTokens: maxHourlyTokens,
                points: hourlyPoints ?? makeHourlyPoints(totalTokens: totalTokens)
            )
        )
    }

    private func makeHeatmapCells(totalTokens: Int) -> [WidgetHeatmapCell] {
        (0..<154).map { index in
            let isPlaceholder = index >= 152
            let cellTotal = index == 0 ? totalTokens : 0
            return WidgetHeatmapCell(
                dateKey: isPlaceholder ? nil : "heatmap-day-\(index)",
                totalTokens: isPlaceholder ? 0 : cellTotal,
                intensity: !isPlaceholder && cellTotal > 0 ? 4 : 0,
                isPlaceholder: isPlaceholder
            )
        }
    }

    private func makeHourlyPoints(totalTokens: Int) -> [WidgetHourlyPoint] {
        (0...23).map { hour in
            WidgetHourlyPoint(
                hour: hour,
                hourKey: String(format: "2026-07-15T%02d", hour),
                hourLabel: "\(hour)时",
                totalTokens: hour == 13 ? totalTokens : 0,
                isCurrentHour: hour == 13
            )
        }
    }

    private func copyCell(
        _ cell: WidgetHeatmapCell,
        totalTokens: Int? = nil,
        intensity: Int? = nil
    ) -> WidgetHeatmapCell {
        WidgetHeatmapCell(
            dateKey: cell.dateKey,
            totalTokens: totalTokens ?? cell.totalTokens,
            intensity: intensity ?? cell.intensity,
            isPlaceholder: cell.isPlaceholder
        )
    }

    private func copyPoint(
        _ point: WidgetHourlyPoint,
        hour: Int? = nil,
        hourKey: String? = nil,
        totalTokens: Int? = nil,
        isCurrentHour: Bool? = nil
    ) -> WidgetHourlyPoint {
        WidgetHourlyPoint(
            hour: hour ?? point.hour,
            hourKey: hourKey ?? point.hourKey,
            hourLabel: point.hourLabel,
            totalTokens: totalTokens ?? point.totalTokens,
            isCurrentHour: isCurrentHour ?? point.isCurrentHour
        )
    }
}
```

- [ ] **Step 2: Run the suite to verify RED**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/JSONWidgetSnapshotStoreTests -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData test
```

Expected: compilation fails because `JSONWidgetSnapshotStore` and the read-result types do not exist.

- [ ] **Step 3: Implement the store contract and validator**

Use these exact public-to-module interfaces:

```swift
import Foundation

enum WidgetSnapshotReadFailure: Equatable, Sendable {
    case unreadable
    case corrupt
    case unsupportedSchema(Int)
}

enum WidgetSnapshotReadResult: Equatable, Sendable {
    case available(WidgetUsageSnapshot)
    case missing
    case invalid(WidgetSnapshotReadFailure)
}

enum WidgetSnapshotStoreError: Error, Equatable, Sendable {
    case appGroupContainerUnavailable
    case invalidSnapshot
}

protocol WidgetSnapshotStoring: Sendable {
    func load() -> WidgetSnapshotReadResult
    func save(_ snapshot: WidgetUsageSnapshot) throws
}

enum WidgetUsageSnapshotValidator {
    static func isValid(_ snapshot: WidgetUsageSnapshot) -> Bool {
        guard snapshot.schemaVersion == WidgetSharedConfiguration.schemaVersion,
              snapshot.localDayKey == snapshot.hourlyLine.dayKey,
              snapshot.heatmap.totalTokens >= 0,
              snapshot.heatmap.maxDailyTokens >= 0,
              snapshot.hourlyLine.totalTokens >= 0,
              snapshot.hourlyLine.maxHourlyTokens >= 0,
              snapshot.heatmap.cells.count
                == WidgetChartVisualStyle.heatmapColumns * WidgetChartVisualStyle.heatmapRows,
              snapshot.hourlyLine.points.count == 24 else {
            return false
        }

        let cellsAreValid = snapshot.heatmap.cells.allSatisfy { cell in
            cell.totalTokens >= 0
                && (0...WidgetChartVisualStyle.heatmapMaximumIntensity).contains(cell.intensity)
                && cell.isPlaceholder == (cell.dateKey == nil)
                && (!cell.isPlaceholder || (cell.totalTokens == 0 && cell.intensity == 0))
        }
        let hours = snapshot.hourlyLine.points.map(\.hour)
        let pointsAreValid = hours == Array(0...23)
            && Set(snapshot.hourlyLine.points.map(\.hourKey)).count == 24
            && snapshot.hourlyLine.points.filter(\.isCurrentHour).count == 1
            && snapshot.hourlyLine.points.allSatisfy {
                $0.totalTokens >= 0 && !$0.hourKey.isEmpty && !$0.hourLabel.isEmpty
            }
        return cellsAreValid && pointsAreValid
    }
}
```

Implement the concrete store as follows. The envelope decode must happen before the full decode so future schemas do not look corrupt:

```swift
struct JSONWidgetSnapshotStore: WidgetSnapshotStoring, Sendable {
    typealias AtomicWrite = @Sendable (Data, URL) throws -> Void

    private struct SchemaEnvelope: Decodable {
        let schemaVersion: Int
    }

    let fileURL: URL
    private let atomicWrite: AtomicWrite

    init(
        fileURL: URL,
        atomicWrite: @escaping AtomicWrite = { data, url in
            try data.write(to: url, options: .atomic)
        }
    ) {
        self.fileURL = fileURL
        self.atomicWrite = atomicWrite
    }

    static func appGroupStore(
        fileManager: FileManager = .default
    ) throws -> JSONWidgetSnapshotStore {
        guard let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: WidgetSharedConfiguration.appGroupIdentifier
        ) else {
            throw WidgetSnapshotStoreError.appGroupContainerUnavailable
        }
        return JSONWidgetSnapshotStore(
            fileURL: containerURL.appendingPathComponent(
                WidgetSharedConfiguration.snapshotFilename,
                isDirectory: false
            )
        )
    }

    func load() -> WidgetSnapshotReadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .missing
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            return .invalid(.unreadable)
        }

        let decoder = JSONDecoder()
        guard let envelope = try? decoder.decode(SchemaEnvelope.self, from: data) else {
            return .invalid(.corrupt)
        }
        guard envelope.schemaVersion == WidgetSharedConfiguration.schemaVersion else {
            return .invalid(.unsupportedSchema(envelope.schemaVersion))
        }
        guard let snapshot = try? decoder.decode(WidgetUsageSnapshot.self, from: data),
              WidgetUsageSnapshotValidator.isValid(snapshot) else {
            return .invalid(.corrupt)
        }
        return .available(snapshot)
    }

    func save(_ snapshot: WidgetUsageSnapshot) throws {
        guard WidgetUsageSnapshotValidator.isValid(snapshot) else {
            throw WidgetSnapshotStoreError.invalidSnapshot
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try atomicWrite(try encoder.encode(snapshot), fileURL)
    }
}
```

- [ ] **Step 4: Run storage GREEN**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/JSONWidgetSnapshotStoreTests -only-testing:TokenWatchTests/WidgetUsageSnapshotTests -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData test
```

Expected: both suites pass, including all invalid-shape mutations and atomic-write preservation.

- [ ] **Step 5: Commit storage**

```bash
git add TokenWatchShared/Widgets/JSONWidgetSnapshotStore.swift TokenWatchTests/Widgets/JSONWidgetSnapshotStoreTests.swift
git commit -m "feat(widget): 添加原子快照存储"
```

### Task 4: Build Widget Snapshots from Existing Aggregates

**Files:**
- Create: `TokenWatch/Widgets/WidgetSnapshotBuilder.swift`
- Create: `TokenWatchTests/Widgets/WidgetSnapshotBuilderTests.swift`
- Modify: `TokenWatch/Localization/AppStrings.swift:8-148` and every language table

**Interfaces:**
- Consumes: `CalendarHeatmapBuilder`, `MonthlyTokenChartBuilder(period: .today)`, current provider states, calendar, date, and resolved app language.
- Produces: `WidgetSnapshotBuilder.build(states:now:calendar:language:) -> WidgetUsageSnapshot?`.

- [ ] **Step 1: Add failing builder and localization tests**

Create the full suite with its calendar and aggregate fixtures:

```swift
import Foundation
import Testing
@testable import TokenWatch

@Suite("Widget snapshot builder")
struct WidgetSnapshotBuilderTests {
    @Test("no provider stats preserves the previous shared snapshot")
    func noValidStatsReturnsNil() {
        let states: [ProviderID: TokenStatsViewModel.ProviderState] = [
            .claude: .init(
                stats: nil,
                isLoading: false,
                errorMessage: nil,
                needsAuthorization: true
            ),
        ]

        #expect(WidgetSnapshotBuilder.build(
            states: states,
            now: fixedNow,
            calendar: shanghaiCalendar,
            language: .zhHans
        ) == nil)
    }

    @Test("valid zero stats still produce fixed render shapes")
    func validZeroStatsBuilds154CellsAnd24Points() throws {
        let snapshot = try #require(WidgetSnapshotBuilder.build(
            states: [.claude: loadedState(stats: makeStats())],
            now: fixedNow,
            calendar: shanghaiCalendar,
            language: .zhHans
        ))

        #expect(snapshot.heatmap.cells.count == 154)
        #expect(snapshot.hourlyLine.points.map(\.hour) == Array(0...23))
        #expect(snapshot.heatmap.totalTokens == 0)
        #expect(snapshot.hourlyLine.totalTokens == 0)
        #expect(WidgetUsageSnapshotValidator.isValid(snapshot))
    }

    @Test("provider totals use saturated addition for the same day and hour")
    func providerTotalsUseSaturatedAddition() throws {
        let almostMaximum = makeSummary(total: Int.max - 10)
        let overflow = makeSummary(total: 50)
        let states: [ProviderID: TokenStatsViewModel.ProviderState] = [
            .claude: loadedState(stats: makeStats(
                byHour: ["2026-07-15T13": almostMaximum],
                byDay: ["2026-07-15": almostMaximum]
            )),
            .codex: loadedState(stats: makeStats(
                byHour: ["2026-07-15T13": overflow],
                byDay: ["2026-07-15": overflow]
            )),
        ]

        let snapshot = try #require(WidgetSnapshotBuilder.build(
            states: states,
            now: fixedNow,
            calendar: shanghaiCalendar,
            language: .zhHans
        ))

        #expect(snapshot.heatmap.cells.first {
            $0.dateKey == "2026-07-15"
        }?.totalTokens == Int.max)
        #expect(snapshot.hourlyLine.points.first {
            $0.hour == 13
        }?.totalTokens == Int.max)
        #expect(snapshot.heatmap.totalTokens == Int.max)
        #expect(snapshot.hourlyLine.totalTokens == Int.max)
    }

    @Test("heatmap preserves padding, real zero days, and builder intensities")
    func heatmapMappingMatchesExistingBuilder() throws {
        let states: [ProviderID: TokenStatsViewModel.ProviderState] = [
            .claude: loadedState(stats: makeStats(byDay: [
                "2026-07-14": makeSummary(total: 100),
                "2026-07-15": makeSummary(total: 0),
            ])),
        ]
        let expected = CalendarHeatmapBuilder.build(
            states: states,
            month: fixedNow,
            now: fixedNow,
            calendar: shanghaiCalendar,
            language: .zhHans
        )
        let actual = try #require(WidgetSnapshotBuilder.build(
            states: states,
            now: fixedNow,
            calendar: shanghaiCalendar,
            language: .zhHans
        ))

        #expect(actual.heatmap.cells.count == expected.cells.count)
        for (source, mapped) in zip(expected.cells, actual.heatmap.cells) {
            switch source {
            case .placeholder:
                #expect(mapped.dateKey == nil)
                #expect(mapped.totalTokens == 0)
                #expect(mapped.intensity == 0)
                #expect(mapped.isPlaceholder)
            case .day(let day):
                #expect(mapped.dateKey == day.dateKey)
                #expect(mapped.totalTokens == day.totalTokens)
                #expect(mapped.intensity == day.intensity)
                #expect(!mapped.isPlaceholder)
            }
        }
        let realZeroDay = try #require(actual.heatmap.cells.first {
            $0.dateKey == "2026-07-15"
        })
        #expect(realZeroDay.totalTokens == 0)
        #expect(!realZeroDay.isPlaceholder)
        #expect(actual.heatmap.cells.contains { $0.isPlaceholder })
    }

    @Test("only the matching wall-clock hour is current")
    func currentHourMarkerUsesHourKey() throws {
        let snapshot = try #require(WidgetSnapshotBuilder.build(
            states: [.claude: loadedState(stats: makeStats())],
            now: fixedNow,
            calendar: shanghaiCalendar,
            language: .zhHans
        ))

        let current = snapshot.hourlyLine.points.filter(\.isCurrentHour)
        #expect(current.count == 1)
        #expect(current.first?.hour == 13)
        #expect(current.first?.hourKey == "2026-07-15T13")
    }

    @Test("spring-forward day remains twenty-four wall-clock buckets")
    func springForwardKeepsTwentyFourWallClockHours() throws {
        try assertTwentyFourWallClockHours(year: 2026, month: 3, day: 8)
    }

    @Test("fall-back day remains twenty-four wall-clock buckets")
    func fallBackKeepsTwentyFourWallClockHours() throws {
        try assertTwentyFourWallClockHours(year: 2026, month: 11, day: 1)
    }

    @Test("English render copy uses the fixed local date")
    func englishRenderCopyIsExact() throws {
        let snapshot = try #require(WidgetSnapshotBuilder.build(
            states: [.claude: loadedState(stats: makeStats())],
            now: fixedNow,
            calendar: shanghaiCalendar,
            language: .en
        ))

        #expect(snapshot.localizedText.todayUsageTitle == "Today's Usage")
        #expect(snapshot.localizedText.datedUsageTitle == "7/15 Usage")
        #expect(snapshot.localizedText.updatedThroughTitle == "Updated through 7/15")
        #expect(snapshot.localizedText.notReadyMessage == "Open TokenWatch to refresh data")
    }

    @Test("all supported languages define all four widget strings")
    func everyLanguageHasExactWidgetStrings() throws {
        let expected: [AppLanguage: [AppStringKey: String]] = [
            .zhHans: [
                .widgetTodayUsageTitle: "今日用量",
                .widgetDatedUsageTitleFormat: "%@ 用量",
                .widgetUpdatedThroughTitleFormat: "更新至 %@",
                .widgetNotReadyMessage: "打开 TokenWatch 刷新数据",
            ],
            .zhHant: [
                .widgetTodayUsageTitle: "今日用量",
                .widgetDatedUsageTitleFormat: "%@ 用量",
                .widgetUpdatedThroughTitleFormat: "更新至 %@",
                .widgetNotReadyMessage: "開啟 TokenWatch 重新整理資料",
            ],
            .ja: [
                .widgetTodayUsageTitle: "今日の使用量",
                .widgetDatedUsageTitleFormat: "%@の使用量",
                .widgetUpdatedThroughTitleFormat: "%@ まで更新",
                .widgetNotReadyMessage: "TokenWatchを開いてデータを更新",
            ],
            .ko: [
                .widgetTodayUsageTitle: "오늘 사용량",
                .widgetDatedUsageTitleFormat: "%@ 사용량",
                .widgetUpdatedThroughTitleFormat: "%@까지 업데이트",
                .widgetNotReadyMessage: "TokenWatch를 열어 데이터를 새로고침",
            ],
            .es: [
                .widgetTodayUsageTitle: "Uso de hoy",
                .widgetDatedUsageTitleFormat: "Uso del %@",
                .widgetUpdatedThroughTitleFormat: "Actualizado hasta %@",
                .widgetNotReadyMessage: "Abre TokenWatch para actualizar los datos",
            ],
            .de: [
                .widgetTodayUsageTitle: "Heutige Nutzung",
                .widgetDatedUsageTitleFormat: "Nutzung am %@",
                .widgetUpdatedThroughTitleFormat: "Aktualisiert bis %@",
                .widgetNotReadyMessage: "TokenWatch öffnen, um Daten zu aktualisieren",
            ],
            .fr: [
                .widgetTodayUsageTitle: "Utilisation aujourd’hui",
                .widgetDatedUsageTitleFormat: "Utilisation du %@",
                .widgetUpdatedThroughTitleFormat: "Mis à jour jusqu’au %@",
                .widgetNotReadyMessage: "Ouvrez TokenWatch pour actualiser les données",
            ],
            .ptBR: [
                .widgetTodayUsageTitle: "Uso de hoje",
                .widgetDatedUsageTitleFormat: "Uso em %@",
                .widgetUpdatedThroughTitleFormat: "Atualizado até %@",
                .widgetNotReadyMessage: "Abra o TokenWatch para atualizar os dados",
            ],
            .it: [
                .widgetTodayUsageTitle: "Utilizzo di oggi",
                .widgetDatedUsageTitleFormat: "Utilizzo del %@",
                .widgetUpdatedThroughTitleFormat: "Aggiornato al %@",
                .widgetNotReadyMessage: "Apri TokenWatch per aggiornare i dati",
            ],
            .nl: [
                .widgetTodayUsageTitle: "Gebruik vandaag",
                .widgetDatedUsageTitleFormat: "Gebruik op %@",
                .widgetUpdatedThroughTitleFormat: "Bijgewerkt tot %@",
                .widgetNotReadyMessage: "Open TokenWatch om gegevens te verversen",
            ],
            .pl: [
                .widgetTodayUsageTitle: "Dzisiejsze użycie",
                .widgetDatedUsageTitleFormat: "Użycie: %@",
                .widgetUpdatedThroughTitleFormat: "Zaktualizowano do %@",
                .widgetNotReadyMessage: "Otwórz TokenWatch, aby odświeżyć dane",
            ],
            .en: [
                .widgetTodayUsageTitle: "Today's Usage",
                .widgetDatedUsageTitleFormat: "%@ Usage",
                .widgetUpdatedThroughTitleFormat: "Updated through %@",
                .widgetNotReadyMessage: "Open TokenWatch to refresh data",
            ],
        ]
        let keys: [AppStringKey] = [
            .widgetTodayUsageTitle,
            .widgetDatedUsageTitleFormat,
            .widgetUpdatedThroughTitleFormat,
            .widgetNotReadyMessage,
        ]

        #expect(expected.count == AppLanguage.allCases.count)
        for language in AppLanguage.allCases {
            let table = try #require(expected[language])
            #expect(table.count == keys.count)
            for key in keys {
                let expectedValue = try #require(table[key])
                #expect(AppStrings.text(key, language: language) == expectedValue)
            }
        }
    }

    private var shanghaiCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.firstWeekday = 2
        return calendar
    }

    private var fixedNow: Date {
        shanghaiCalendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 15,
            hour: 13,
            minute: 30
        ))!
    }

    private func assertTwentyFourWallClockHours(
        year: Int,
        month: Int,
        day: Int
    ) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        calendar.firstWeekday = 2
        let now = try #require(calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: 13
        )))
        let snapshot = try #require(WidgetSnapshotBuilder.build(
            states: [.claude: loadedState(stats: makeStats())],
            now: now,
            calendar: calendar,
            language: .en
        ))

        #expect(snapshot.hourlyLine.points.map(\.hour) == Array(0...23))
        #expect(Set(snapshot.hourlyLine.points.map(\.hourKey)).count == 24)
        #expect(snapshot.hourlyLine.points.filter(\.isCurrentHour).map(\.hour) == [13])
        #expect(WidgetUsageSnapshotValidator.isValid(snapshot))
    }

    private func loadedState(
        stats: AggregatedStats
    ) -> TokenStatsViewModel.ProviderState {
        .init(
            stats: stats,
            isLoading: false,
            errorMessage: nil,
            needsAuthorization: false
        )
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
            entryCount: total == 0 ? 0 : 1,
            modelBreakdown: [:]
        )
    }

    private func makeStats(
        byHour: [String: UsageSummary] = [:],
        byDay: [String: UsageSummary] = [:],
        byMonth: [String: UsageSummary] = [:]
    ) -> AggregatedStats {
        AggregatedStats(
            overall: .zero,
            byHour: byHour,
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
```

- [ ] **Step 2: Run the focused builder test to verify RED**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/WidgetSnapshotBuilderTests -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData test
```

Expected: compilation fails because `WidgetSnapshotBuilder` and the four string keys do not exist.

- [ ] **Step 3: Add the four app-localization keys in all 12 tables**

Add `widgetTodayUsageTitle`, `widgetDatedUsageTitleFormat`, `widgetUpdatedThroughTitleFormat`, and `widgetNotReadyMessage` to `AppStringKey`. Use this exact matrix; the existing `heatmapRecent22Weeks` remains the heatmap title:

```swift
case widgetTodayUsageTitle
case widgetDatedUsageTitleFormat
case widgetUpdatedThroughTitleFormat
case widgetNotReadyMessage
```

| Language | Today title | Dated title format | Updated-through format | Not-ready message |
|---|---|---|---|---|
| zh-Hans | `今日用量` | `%@ 用量` | `更新至 %@` | `打开 TokenWatch 刷新数据` |
| zh-Hant | `今日用量` | `%@ 用量` | `更新至 %@` | `開啟 TokenWatch 重新整理資料` |
| ja | `今日の使用量` | `%@の使用量` | `%@ まで更新` | `TokenWatchを開いてデータを更新` |
| ko | `오늘 사용량` | `%@ 사용량` | `%@까지 업데이트` | `TokenWatch를 열어 데이터를 새로고침` |
| es | `Uso de hoy` | `Uso del %@` | `Actualizado hasta %@` | `Abre TokenWatch para actualizar los datos` |
| de | `Heutige Nutzung` | `Nutzung am %@` | `Aktualisiert bis %@` | `TokenWatch öffnen, um Daten zu aktualisieren` |
| fr | `Utilisation aujourd’hui` | `Utilisation du %@` | `Mis à jour jusqu’au %@` | `Ouvrez TokenWatch pour actualiser les données` |
| pt-BR | `Uso de hoje` | `Uso em %@` | `Atualizado até %@` | `Abra o TokenWatch para atualizar os dados` |
| it | `Utilizzo di oggi` | `Utilizzo del %@` | `Aggiornato al %@` | `Apri TokenWatch per aggiornare i dati` |
| nl | `Gebruik vandaag` | `Gebruik op %@` | `Bijgewerkt tot %@` | `Open TokenWatch om gegevens te verversen` |
| pl | `Dzisiejsze użycie` | `Użycie: %@` | `Zaktualizowano do %@` | `Otwórz TokenWatch, aby odświeżyć dane` |
| en | `Today's Usage` | `%@ Usage` | `Updated through %@` | `Open TokenWatch to refresh data` |

- [ ] **Step 4: Implement the minimal builder**

Use one local formatter whose calendar/time zone come from the injected calendar and whose locale comes from `language.localeIdentifier`:

```swift
import Foundation

enum WidgetSnapshotBuilder {
    /// Returns nil only when no provider has a valid aggregate; a valid zero aggregate returns a snapshot.
    static func build(
        states: [ProviderID: TokenStatsViewModel.ProviderState],
        now: Date,
        calendar: Calendar,
        language: AppLanguage
    ) -> WidgetUsageSnapshot? {
        guard states.values.contains(where: { $0.stats != nil }) else {
            return nil
        }

        let heatmap = CalendarHeatmapBuilder.build(
            states: states,
            month: now,
            now: now,
            calendar: calendar,
            language: language
        )
        let hourly = MonthlyTokenChartBuilder.build(
            states: states,
            period: .today,
            now: now,
            calendar: calendar,
            language: language
        )
        let dateText = localizedMonthDay(now, calendar: calendar, language: language)
        let localDayKey = dayKey(now, calendar: calendar)

        return WidgetUsageSnapshot(
            schemaVersion: WidgetSharedConfiguration.schemaVersion,
            generatedAt: now,
            localDayKey: localDayKey,
            localizedText: WidgetLocalizedText(
                heatmapTitle: heatmap.monthTitle,
                todayUsageTitle: AppStrings.text(.widgetTodayUsageTitle, language: language),
                datedUsageTitle: String(
                    format: AppStrings.text(.widgetDatedUsageTitleFormat, language: language),
                    dateText
                ),
                updatedThroughTitle: String(
                    format: AppStrings.text(.widgetUpdatedThroughTitleFormat, language: language),
                    dateText
                ),
                notReadyMessage: AppStrings.text(.widgetNotReadyMessage, language: language)
            ),
            heatmap: WidgetHeatmapSnapshot(
                totalTokens: heatmap.monthTotalTokens,
                maxDailyTokens: heatmap.maxDailyTokens,
                cells: heatmap.cells.map(mapHeatmapCell)
            ),
            hourlyLine: WidgetHourlyLineSnapshot(
                dayKey: localDayKey,
                totalTokens: hourly.totalTokens,
                maxHourlyTokens: hourly.maxMonthlyTokens,
                points: hourly.monthBuckets.enumerated().map { hour, bucket in
                    WidgetHourlyPoint(
                        hour: hour,
                        hourKey: bucket.monthKey,
                        hourLabel: bucket.monthLabel,
                        totalTokens: bucket.totalTokens,
                        isCurrentHour: bucket.isCurrentMonth
                    )
                }
            )
        )
    }

    private static func mapHeatmapCell(_ cell: CalendarHeatmapCell) -> WidgetHeatmapCell {
        switch cell {
        case .placeholder:
            return WidgetHeatmapCell(
                dateKey: nil,
                totalTokens: 0,
                intensity: 0,
                isPlaceholder: true
            )
        case .day(let day):
            return WidgetHeatmapCell(
                dateKey: day.dateKey,
                totalTokens: day.totalTokens,
                intensity: day.intensity,
                isPlaceholder: false
            )
        }
    }

    private static func localizedMonthDay(
        _ date: Date,
        calendar: Calendar,
        language: AppLanguage
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: language.localeIdentifier)
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return formatter.string(from: date)
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}
```

- [ ] **Step 5: Run builder, localization, and existing builder suites**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/WidgetSnapshotBuilderTests -only-testing:TokenWatchTests/AppLanguageSettingsTests -only-testing:TokenWatchTests/CalendarHeatmapBuilderTests -only-testing:TokenWatchTests/MonthlyTokenChartBuilderTests -only-testing:TokenWatchTests/LocalHourBucketDescriptorTests -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData test
```

Expected: all selected suites pass, including both Los Angeles DST dates.

- [ ] **Step 6: Commit the builder and strings**

```bash
git add TokenWatch/Widgets/WidgetSnapshotBuilder.swift TokenWatchTests/Widgets/WidgetSnapshotBuilderTests.swift TokenWatch/Localization/AppStrings.swift
git commit -m "feat(widget): 构建小组件渲染快照"
```

### Task 5: Add Deduplicated Actor-Isolated Publication

**Files:**
- Create: `TokenWatch/Widgets/WidgetSnapshotPublisher.swift`
- Create: `TokenWatchTests/Widgets/WidgetSnapshotPublisherTests.swift`

**Interfaces:**
- Consumes: provider states, resolved language, `WidgetSnapshotBuilder`, `WidgetSnapshotStoring`, and a timeline reloader seam.
- Produces: `WidgetSnapshotPublishing`, `WidgetSnapshotPublisher`, `WidgetSnapshotPublishResult`, `WidgetTimelineReloading`, `WidgetKitTimelineReloader`, and `WidgetSnapshotPublisherFactory`.

- [ ] **Step 1: Write failing publisher sequencing tests**

Create the complete suite with a single lock-protected event recorder shared by the fake store and reloader, so cross-object order is observable:

```swift
import Foundation
import Testing
@testable import TokenWatch

@Suite("Widget snapshot publisher")
struct WidgetSnapshotPublisherTests {
    @Test("changed content saves before reloading both exact kinds")
    func newContentSavesBeforeReloadingBothKinds() async {
        let events = LockedEventRecorder()
        let store = LockedSnapshotStore(loadResult: .missing, events: events)
        let reloader = RecordingTimelineReloader(events: events)
        let publisher = makePublisher(store: store, reloader: reloader)

        let result = await publisher.publish(states: validStates, language: .zhHans)

        #expect(result == .published)
        #expect(events.values == [
            "save",
            "reload:\(WidgetSharedConfiguration.heatmapKind)",
            "reload:\(WidgetSharedConfiguration.hourlyLineKind)",
        ])
        #expect(store.loadCount == 1)
        #expect(store.saveCount == 1)
        #expect(store.savedSnapshots.count == 1)
        #expect(reloader.kinds == [
            WidgetSharedConfiguration.heatmapKind,
            WidgetSharedConfiguration.hourlyLineKind,
        ])
    }

    @Test("generatedAt-only change neither writes nor reloads")
    func generatedAtOnlyChangeDoesNotSaveOrReload() async throws {
        let candidate = try #require(WidgetSnapshotBuilder.build(
            states: validStates,
            now: fixedNow,
            calendar: fixedCalendar,
            language: .zhHans
        ))
        let existing = replacingGeneratedAt(
            in: candidate,
            with: candidate.generatedAt.addingTimeInterval(-60)
        )
        let events = LockedEventRecorder()
        let store = LockedSnapshotStore(
            loadResult: .available(existing),
            events: events
        )
        let reloader = RecordingTimelineReloader(events: events)
        let publisher = makePublisher(store: store, reloader: reloader)

        let result = await publisher.publish(states: validStates, language: .zhHans)

        #expect(result == .unchanged)
        #expect(events.values.isEmpty)
        #expect(store.loadCount == 1)
        #expect(store.saveCount == 0)
        #expect(reloader.kinds.isEmpty)
    }

    @Test("no valid provider stats preserve the old file")
    func noValidStatsPreservesExistingSnapshot() async {
        let states: [ProviderID: TokenStatsViewModel.ProviderState] = [
            .claude: .init(
                stats: nil,
                isLoading: false,
                errorMessage: nil,
                needsAuthorization: true
            ),
        ]
        let events = LockedEventRecorder()
        let store = LockedSnapshotStore(loadResult: .missing, events: events)
        let reloader = RecordingTimelineReloader(events: events)
        let publisher = makePublisher(store: store, reloader: reloader)

        let result = await publisher.publish(states: states, language: .zhHans)

        #expect(result == .skippedNoValidStats)
        #expect(store.loadCount == 0)
        #expect(store.saveCount == 0)
        #expect(events.values.isEmpty)
        #expect(reloader.kinds.isEmpty)
    }

    @Test("write failure never reloads a timeline")
    func writeFailureDoesNotReload() async {
        let events = LockedEventRecorder()
        let store = LockedSnapshotStore(
            loadResult: .missing,
            shouldFailSave: true,
            events: events
        )
        let reloader = RecordingTimelineReloader(events: events)
        let publisher = makePublisher(store: store, reloader: reloader)

        let result = await publisher.publish(states: validStates, language: .zhHans)

        #expect(result == .failed)
        #expect(events.values == ["save"])
        #expect(store.saveCount == 1)
        #expect(store.savedSnapshots.isEmpty)
        #expect(reloader.kinds.isEmpty)
    }

    @Test("a corrupt old snapshot is replaced by a valid candidate")
    func corruptOldSnapshotIsReplaced() async {
        let events = LockedEventRecorder()
        let store = LockedSnapshotStore(
            loadResult: .invalid(.corrupt),
            events: events
        )
        let reloader = RecordingTimelineReloader(events: events)
        let publisher = makePublisher(store: store, reloader: reloader)

        let result = await publisher.publish(states: validStates, language: .en)

        #expect(result == .published)
        #expect(events.values == [
            "save",
            "reload:\(WidgetSharedConfiguration.heatmapKind)",
            "reload:\(WidgetSharedConfiguration.hourlyLineKind)",
        ])
        #expect(store.loadCount == 1)
        #expect(store.saveCount == 1)
        #expect(store.savedSnapshots.first?.localizedText.todayUsageTitle == "Today's Usage")
    }

    private var fixedCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.firstWeekday = 2
        return calendar
    }

    private var fixedNow: Date {
        fixedCalendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 15,
            hour: 13,
            minute: 30
        ))!
    }

    private var validStates: [ProviderID: TokenStatsViewModel.ProviderState] {
        [
            .claude: .init(
                stats: .zero,
                isLoading: false,
                errorMessage: nil,
                needsAuthorization: false
            ),
        ]
    }

    private func makePublisher(
        store: LockedSnapshotStore,
        reloader: RecordingTimelineReloader
    ) -> WidgetSnapshotPublisher {
        let now = fixedNow
        let calendar = fixedCalendar
        return WidgetSnapshotPublisher(
            store: store,
            timelineReloader: reloader,
            now: { now },
            calendar: { calendar }
        )
    }

    private func replacingGeneratedAt(
        in snapshot: WidgetUsageSnapshot,
        with generatedAt: Date
    ) -> WidgetUsageSnapshot {
        WidgetUsageSnapshot(
            schemaVersion: snapshot.schemaVersion,
            generatedAt: generatedAt,
            localDayKey: snapshot.localDayKey,
            localizedText: snapshot.localizedText,
            heatmap: snapshot.heatmap,
            hourlyLine: snapshot.hourlyLine
        )
    }
}

private final class LockedEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [String] = []

    var values: [String] {
        withLock { storedValues }
    }

    func append(_ value: String) {
        withLock { storedValues.append(value) }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private final class LockedSnapshotStore: WidgetSnapshotStoring, @unchecked Sendable {
    private struct InjectedSaveError: Error {}

    private let lock = NSLock()
    private let loadResult: WidgetSnapshotReadResult
    private let shouldFailSave: Bool
    private let events: LockedEventRecorder
    private var storedLoadCount = 0
    private var storedSaveCount = 0
    private var storedSnapshots: [WidgetUsageSnapshot] = []

    init(
        loadResult: WidgetSnapshotReadResult,
        shouldFailSave: Bool = false,
        events: LockedEventRecorder
    ) {
        self.loadResult = loadResult
        self.shouldFailSave = shouldFailSave
        self.events = events
    }

    var loadCount: Int { withLock { storedLoadCount } }
    var saveCount: Int { withLock { storedSaveCount } }
    var savedSnapshots: [WidgetUsageSnapshot] { withLock { storedSnapshots } }

    func load() -> WidgetSnapshotReadResult {
        withLock { storedLoadCount += 1 }
        return loadResult
    }

    func save(_ snapshot: WidgetUsageSnapshot) throws {
        events.append("save")
        withLock { storedSaveCount += 1 }
        if shouldFailSave {
            throw InjectedSaveError()
        }
        withLock { storedSnapshots.append(snapshot) }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private final class RecordingTimelineReloader: WidgetTimelineReloading, @unchecked Sendable {
    private let lock = NSLock()
    private let events: LockedEventRecorder
    private var storedKinds: [String] = []

    init(events: LockedEventRecorder) {
        self.events = events
    }

    var kinds: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storedKinds
    }

    func reloadTimelines(ofKind kind: String) {
        lock.lock()
        storedKinds.append(kind)
        lock.unlock()
        events.append("reload:\(kind)")
    }
}
```

- [ ] **Step 2: Run publisher tests to verify RED**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/WidgetSnapshotPublisherTests -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData test
```

Expected: compilation fails because `WidgetSnapshotPublisher` does not exist.

- [ ] **Step 3: Implement publication in the required order**

```swift
import Foundation
import os.log
import WidgetKit

enum WidgetSnapshotPublishResult: Equatable, Sendable {
    case published
    case unchanged
    case skippedNoValidStats
    case failed
}

protocol WidgetSnapshotPublishing: Sendable {
    @discardableResult
    func publish(
        states: [ProviderID: TokenStatsViewModel.ProviderState],
        language: AppLanguage
    ) async -> WidgetSnapshotPublishResult
}

protocol WidgetTimelineReloading: Sendable {
    func reloadTimelines(ofKind kind: String)
}

struct WidgetKitTimelineReloader: WidgetTimelineReloading, Sendable {
    func reloadTimelines(ofKind kind: String) {
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }
}

actor WidgetSnapshotPublisher: WidgetSnapshotPublishing {
    private let store: any WidgetSnapshotStoring
    private let timelineReloader: any WidgetTimelineReloading
    private let now: @Sendable () -> Date
    private let calendar: @Sendable () -> Calendar
    private let logger = Logger(
        subsystem: "com.xiaoao.TokenWatch",
        category: "WidgetSnapshotPublisher"
    )

    init(
        store: any WidgetSnapshotStoring,
        timelineReloader: any WidgetTimelineReloading,
        now: @escaping @Sendable () -> Date = Date.init,
        calendar: @escaping @Sendable () -> Calendar = { .autoupdatingCurrent }
    ) {
        self.store = store
        self.timelineReloader = timelineReloader
        self.now = now
        self.calendar = calendar
    }

    @discardableResult
    func publish(
        states: [ProviderID: TokenStatsViewModel.ProviderState],
        language: AppLanguage
    ) async -> WidgetSnapshotPublishResult {
        let currentDate = now()
        guard let candidate = WidgetSnapshotBuilder.build(
            states: states,
            now: currentDate,
            calendar: calendar(),
            language: language
        ) else {
            logger.info("No valid aggregate; preserving the existing widget snapshot")
            return .skippedNoValidStats
        }

        switch store.load() {
        case .available(let existing) where existing.hasSameContent(as: candidate):
            return .unchanged
        case .invalid(.unreadable):
            logger.error("Existing widget snapshot is unreadable; attempting replacement")
        case .invalid(.corrupt):
            logger.error("Existing widget snapshot is corrupt; attempting replacement")
        case .invalid(.unsupportedSchema(_)):
            logger.error("Existing widget snapshot uses an unsupported schema; attempting replacement")
        case .available, .missing:
            break
        }

        do {
            try store.save(candidate)
        } catch {
            logger.error("Widget snapshot write failed")
            return .failed
        }

        timelineReloader.reloadTimelines(ofKind: WidgetSharedConfiguration.heatmapKind)
        timelineReloader.reloadTimelines(ofKind: WidgetSharedConfiguration.hourlyLineKind)
        return .published
    }
}

enum WidgetSnapshotPublisherFactory {
    private static let logger = Logger(
        subsystem: "com.xiaoao.TokenWatch",
        category: "WidgetSnapshotPublisherFactory"
    )

    static func makeLive() -> (any WidgetSnapshotPublishing)? {
        do {
            return WidgetSnapshotPublisher(
                store: try JSONWidgetSnapshotStore.appGroupStore(),
                timelineReloader: WidgetKitTimelineReloader()
            )
        } catch {
            logger.error("App Group container unavailable; widget publication disabled")
            return nil
        }
    }
}
```

Do not log paths, provider payloads, token totals, or localized copy. `save` must complete before either reload call, and a failed save must return before both calls.

- [ ] **Step 4: Run publisher GREEN**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/WidgetSnapshotPublisherTests -only-testing:TokenWatchTests/WidgetSnapshotBuilderTests -only-testing:TokenWatchTests/JSONWidgetSnapshotStoreTests -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData test
```

Expected: all selected tests pass and the changed-content event order is exact.

- [ ] **Step 5: Commit publication**

```bash
git add TokenWatch/Widgets/WidgetSnapshotPublisher.swift TokenWatchTests/Widgets/WidgetSnapshotPublisherTests.swift
git commit -m "feat(widget): 添加去重快照发布"
```

### Task 6: Publish Only Complete Refreshes and Republish Language Changes

**Files:**
- Modify: `TokenWatch/ViewModels/TokenStatsViewModel.swift:40-64, 108-117`
- Modify: `TokenWatch/AppDelegate.swift:14-32`
- Create: `TokenWatchTests/ViewModels/TokenStatsViewModelWidgetPublishingTests.swift`

**Interfaces:**
- Consumes: an optional `any WidgetSnapshotPublishing` dependency and the existing synchronous `AppLanguageSettings` observer.
- Produces: one publication after a complete all-provider refresh, with overlapping refresh suppression and deferred language republishing.

- [ ] **Step 1: Write failing ViewModel consistency tests**

Create `TokenWatchTests/ViewModels/TokenStatsViewModelWidgetPublishingTests.swift` with the complete test file:

```swift
import Foundation
import Testing
@testable import TokenWatch

@Suite("TokenStatsViewModel widget publication")
@MainActor
struct TokenStatsViewModelWidgetPublishingTests {
    @Test("all-provider refresh publishes once after every provider finishes")
    func loadAllPublishesOnceAfterEveryProviderCompletes() async throws {
        let fixture = makeLanguageSettings()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let claude = MutableTestUsageProvider(id: .claude, totalTokens: 10)
        let codex = BlockingTestUsageProvider(id: .codex, totalTokens: 20)
        defer { codex.resume() }
        let publisher = RecordingWidgetSnapshotPublisher()
        let viewModel = makeViewModel(
            settings: fixture.settings,
            providers: [claude, codex],
            publisher: publisher
        )

        let refresh = Task { await viewModel.loadAllStats() }
        try await waitUntil {
            codex.isWaiting
                && viewModel.states[.claude]?.stats?.overall.totalTokens == 10
        }

        let countBeforeCodexFinishes = await publisher.callCount()
        #expect(countBeforeCodexFinishes == 0)
        codex.resume()
        await refresh.value

        let calls = await publisher.recordedCalls()
        let call = try #require(calls.first)
        #expect(calls.count == 1)
        #expect(call.states[.claude]?.stats?.overall.totalTokens == 10)
        #expect(call.states[.codex]?.stats?.overall.totalTokens == 20)
    }

    @Test("overlapping all-provider refresh never publishes an intermediate snapshot")
    func overlappingLoadAllDoesNotPublishIntermediateStates() async throws {
        let fixture = makeLanguageSettings()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let claude = MutableTestUsageProvider(id: .claude, totalTokens: 10)
        let codex = BlockingTestUsageProvider(id: .codex, totalTokens: 20)
        defer { codex.resume() }
        let publisher = RecordingWidgetSnapshotPublisher()
        let viewModel = makeViewModel(
            settings: fixture.settings,
            providers: [claude, codex],
            publisher: publisher
        )

        let firstRefresh = Task { await viewModel.loadAllStats() }
        try await waitUntil { codex.isWaiting }
        await viewModel.loadAllStats()

        #expect(claude.scanCount == 1)
        #expect(codex.scanCount == 1)
        let countBeforeFirstRefreshFinishes = await publisher.callCount()
        #expect(countBeforeFirstRefreshFinishes == 0)

        codex.resume()
        await firstRefresh.value

        #expect(claude.scanCount == 1)
        #expect(codex.scanCount == 1)
        let finalOverlapCount = await publisher.callCount()
        #expect(finalOverlapCount == 1)
    }

    @Test("partial failure publishes the retained valid provider state")
    func partialFailureStillPublishesAvailableStats() async throws {
        let fixture = makeLanguageSettings()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let claude = MutableTestUsageProvider(id: .claude, totalTokens: 10)
        let codex = MutableTestUsageProvider(id: .codex, totalTokens: 20)
        let publisher = RecordingWidgetSnapshotPublisher()
        let viewModel = makeViewModel(
            settings: fixture.settings,
            providers: [claude, codex],
            publisher: publisher
        )

        await viewModel.loadAllStats()
        await publisher.reset()
        claude.setTotalTokens(30)
        codex.failNextLoad()

        await viewModel.loadAllStats()

        let calls = await publisher.recordedCalls()
        let call = try #require(calls.first)
        #expect(calls.count == 1)
        #expect(call.states[.claude]?.stats?.overall.totalTokens == 30)
        #expect(call.states[.codex]?.stats?.overall.totalTokens == 20)
        #expect(call.states[.codex]?.errorMessage != nil)
        #expect(claude.scanCount == 2)
        #expect(codex.scanCount == 2)
    }

    @Test("language change republishes memory without rescanning")
    func languageChangeRepublishesWithoutRescanning() async throws {
        let fixture = makeLanguageSettings()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let claude = MutableTestUsageProvider(id: .claude, totalTokens: 10)
        let codex = MutableTestUsageProvider(id: .codex, totalTokens: 20)
        let publisher = RecordingWidgetSnapshotPublisher()
        let viewModel = makeViewModel(
            settings: fixture.settings,
            providers: [claude, codex],
            publisher: publisher
        )

        await viewModel.loadAllStats()
        let initialLanguagePublishCount = await publisher.callCount()
        #expect(initialLanguagePublishCount == 1)
        let claudeScans = claude.scanCount
        let codexScans = codex.scanCount

        fixture.settings.selectedPreference = .en
        try await waitUntil { await publisher.callCount() == 2 }

        let calls = await publisher.recordedCalls()
        #expect(calls.map(\.language) == [.zhHans, .en])
        #expect(claude.scanCount == claudeScans)
        #expect(codex.scanCount == codexScans)
    }

    @Test("language changes before and during publish use a final republish loop")
    func languageChangeDuringLoadIsDeferred() async throws {
        let fixture = makeLanguageSettings()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let claude = MutableTestUsageProvider(id: .claude, totalTokens: 10)
        let codex = BlockingTestUsageProvider(id: .codex, totalTokens: 20)
        defer { codex.resume() }
        let publisher = RecordingWidgetSnapshotPublisher()
        await publisher.suspendNextPublish()
        let viewModel = makeViewModel(
            settings: fixture.settings,
            providers: [claude, codex],
            publisher: publisher
        )

        let refresh = Task { await viewModel.loadAllStats() }
        try await waitUntil { codex.isWaiting }
        fixture.settings.selectedPreference = .en
        let countBeforeBlockedProviderFinishes = await publisher.callCount()
        #expect(countBeforeBlockedProviderFinishes == 0)

        codex.resume()
        try await waitUntil { await publisher.isPublishSuspended() }
        fixture.settings.selectedPreference = .ja
        await publisher.resumeSuspendedPublish()
        await refresh.value

        let calls = await publisher.recordedCalls()
        #expect(calls.map(\.language) == [.en, .ja])
        #expect(claude.scanCount == 1)
        #expect(codex.scanCount == 1)
    }

    private func makeViewModel(
        settings: AppLanguageSettings,
        providers: [any UsageProvider],
        publisher: RecordingWidgetSnapshotPublisher
    ) -> TokenStatsViewModel {
        TokenStatsViewModel(
            languageSettings: settings,
            providers: providers,
            bookmarkManager: AlwaysAuthorizedBookmarkManager(),
            aggregator: UsageAggregator(),
            widgetSnapshotPublisher: publisher
        )
    }

    private func makeLanguageSettings() -> (
        settings: AppLanguageSettings,
        defaults: UserDefaults,
        suiteName: String
    ) {
        let suiteName = "TokenStatsViewModelWidgetPublishingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (
            AppLanguageSettings(
                defaults: defaults,
                preferredLanguagesProvider: { ["zh-Hans"] }
            ),
            defaults,
            suiteName
        )
    }

    private func waitUntil(
        _ predicate: @escaping @MainActor () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !(await predicate()) {
            guard Date() < deadline else {
                throw WidgetPublishingTestTimeout()
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

private struct WidgetPublishingTestTimeout: Error {}

private struct WidgetPublishingInjectedLoadError: LocalizedError {
    var errorDescription: String? { "injected provider failure" }
}

private actor RecordingWidgetSnapshotPublisher: WidgetSnapshotPublishing {
    struct Call: Sendable {
        let states: [ProviderID: TokenStatsViewModel.ProviderState]
        let language: AppLanguage
    }

    private var calls: [Call] = []
    private var shouldSuspendNextPublish = false
    private var publishIsSuspended = false
    private var continuation: CheckedContinuation<Void, Never>?

    func publish(
        states: [ProviderID: TokenStatsViewModel.ProviderState],
        language: AppLanguage
    ) async -> WidgetSnapshotPublishResult {
        calls.append(Call(states: states, language: language))
        if shouldSuspendNextPublish {
            shouldSuspendNextPublish = false
            publishIsSuspended = true
            await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
            publishIsSuspended = false
        }
        return .published
    }

    func callCount() -> Int {
        calls.count
    }

    func recordedCalls() -> [Call] {
        calls
    }

    func reset() {
        calls.removeAll()
    }

    func suspendNextPublish() {
        shouldSuspendNextPublish = true
    }

    func isPublishSuspended() -> Bool {
        publishIsSuspended
    }

    func resumeSuspendedPublish() {
        let continuation = continuation
        self.continuation = nil
        continuation?.resume()
    }
}

private final class MutableTestUsageProvider: UsageProvider, @unchecked Sendable {
    let id: ProviderID
    let displayName: String
    let bookmarkKey: String
    let openPanelMessage = "Select a folder"
    let hasCacheWriteDimension = true
    let hasReasoningDimension = false

    private let lock = NSLock()
    private var storedTotalTokens: Int
    private var shouldFailNextLoad = false
    private var storedScanCount = 0

    init(id: ProviderID, totalTokens: Int) {
        self.id = id
        self.displayName = "Test \(id.rawValue)"
        self.bookmarkKey = "TestBookmark.\(id.rawValue)"
        self.storedTotalTokens = totalTokens
    }

    var scanCount: Int {
        withLock { storedScanCount }
    }

    func setTotalTokens(_ totalTokens: Int) {
        withLock { storedTotalTokens = totalTokens }
    }

    func failNextLoad() {
        withLock { shouldFailNextLoad = true }
    }

    func loadEntries(from rootURL: URL) throws -> [ParsedUsageEntry] {
        let result: (totalTokens: Int, shouldFail: Bool) = withLock {
            storedScanCount += 1
            let failure = shouldFailNextLoad
            shouldFailNextLoad = false
            return (storedTotalTokens, failure)
        }
        if result.shouldFail {
            throw WidgetPublishingInjectedLoadError()
        }
        return [makeWidgetPublishingEntry(
            provider: id,
            totalTokens: result.totalTokens
        )]
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private final class BlockingTestUsageProvider: UsageProvider, @unchecked Sendable {
    let id: ProviderID
    let displayName: String
    let bookmarkKey: String
    let openPanelMessage = "Select a folder"
    let hasCacheWriteDimension = true
    let hasReasoningDimension = false

    private let condition = NSCondition()
    private let totalTokens: Int
    private var released = false
    private var waiting = false
    private var storedScanCount = 0

    init(id: ProviderID, totalTokens: Int) {
        self.id = id
        self.displayName = "Blocking \(id.rawValue)"
        self.bookmarkKey = "BlockingBookmark.\(id.rawValue)"
        self.totalTokens = totalTokens
    }

    var scanCount: Int {
        condition.lock()
        defer { condition.unlock() }
        return storedScanCount
    }

    var isWaiting: Bool {
        condition.lock()
        defer { condition.unlock() }
        return waiting
    }

    func resume() {
        condition.lock()
        released = true
        condition.broadcast()
        condition.unlock()
    }

    func loadEntries(from rootURL: URL) throws -> [ParsedUsageEntry] {
        condition.lock()
        storedScanCount += 1
        waiting = true
        condition.broadcast()
        while !released {
            condition.wait()
        }
        waiting = false
        condition.unlock()
        return [makeWidgetPublishingEntry(
            provider: id,
            totalTokens: totalTokens
        )]
    }
}

@MainActor
private final class AlwaysAuthorizedBookmarkManager: BookmarkAccessManaging {
    private let rootURL = FileManager.default.temporaryDirectory

    func hasBookmark(forKey key: String) -> Bool {
        true
    }

    func promptUserToSelectDirectory(
        forProvider provider: any UsageProvider
    ) async -> URL? {
        rootURL
    }

    func restoreBookmarkAndAccess(forKey key: String) -> URL? {
        rootURL
    }

    func stopAccessing(forKey key: String) {}
}

private func makeWidgetPublishingEntry(
    provider: ProviderID,
    totalTokens: Int
) -> ParsedUsageEntry {
    ParsedUsageEntry(
        recordUUID: "record-\(provider.rawValue)",
        messageId: "message-\(provider.rawValue)",
        requestId: nil,
        sessionID: "session-\(provider.rawValue)",
        timestamp: Date(timeIntervalSince1970: 1_800_000_000),
        model: "claude-sonnet-4-5",
        upstreamModelID: nil,
        cwd: "/test",
        agentId: nil,
        usage: TokenUsage(
            inputTokens: totalTokens,
            cacheCreationInputTokens: 0,
            cacheReadInputTokens: 0,
            outputTokens: 0,
            reasoningTokens: 0,
            serverToolUse: ServerToolUse(
                webSearchRequests: 0,
                webFetchRequests: 0
            ),
            serviceTier: "standard",
            cacheCreation: nil,
            inferenceGeo: "",
            iterations: [],
            speed: "standard"
        ),
        isSubagent: false,
        provider: provider,
        upstreamProviderID: nil,
        upstreamCost: nil
    )
}
```

- [ ] **Step 2: Run the focused suite to verify RED**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/TokenStatsViewModelWidgetPublishingTests -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData test
```

Expected: the new initializer argument and publication behavior are missing.

- [ ] **Step 3: Add the full-refresh gate and language observer**

Add these fields:

```swift
private let widgetSnapshotPublisher: (any WidgetSnapshotPublishing)?
private var languageSettingsObserverToken: AppLanguageSettings.ObservationToken?
private var isLoadingAllStats = false
private var needsLanguageRepublish = false
```

Append the dependency to the initializer with a default of `nil`, assign it before registering the observer, and register only when it is non-nil:

```swift
init(
    languageSettings: AppLanguageSettings = .shared,
    providers: [any UsageProvider] = ProviderRegistry.allProviders,
    bookmarkManager: any BookmarkAccessManaging = SecurityScopedBookmarkManager.shared,
    aggregator: any UsageAggregating = UsageAggregator(),
    nowProvider: @escaping @Sendable () -> Date = Date.init,
    widgetSnapshotPublisher: (any WidgetSnapshotPublishing)? = nil
) {
    self.languageSettings = languageSettings
    self.providers = providers
    self.bookmarkManager = bookmarkManager
    self.aggregator = aggregator
    self.nowProvider = nowProvider
    self.widgetSnapshotPublisher = widgetSnapshotPublisher
    for provider in providers {
        states[provider.id] = ProviderState()
    }
    if widgetSnapshotPublisher != nil {
        languageSettingsObserverToken = languageSettings.observe { [weak self] in
            self?.handleLanguageChangeForWidgets()
        }
    }
}
```

Replace `loadAllStats` with the full-operation gate. Keep the existing comment about the Swift 6 task-group actor hop:

```swift
func loadAllStats(mode: LoadMode = .interactive) async {
    guard !isLoadingAllStats else {
        logger.info("All-provider refresh already in progress; skipping duplicate request")
        return
    }
    isLoadingAllStats = true
    defer { isLoadingAllStats = false }

    await withTaskGroup(of: Void.self) { group in
        for provider in providers {
            let id = provider.id
            group.addTask {
                await self.loadStats(for: id, mode: mode)
            }
        }
    }

    repeat {
        needsLanguageRepublish = false
        await publishCurrentWidgetSnapshot()
    } while needsLanguageRepublish
}

private func publishCurrentWidgetSnapshot() async {
    guard let widgetSnapshotPublisher else { return }
    await widgetSnapshotPublisher.publish(
        states: states,
        language: languageSettings.resolvedLanguage
    )
}

private func handleLanguageChangeForWidgets() {
    guard widgetSnapshotPublisher != nil else { return }
    if isLoadingAllStats {
        needsLanguageRepublish = true
        return
    }
    Task { @MainActor [weak self] in
        await self?.publishCurrentWidgetSnapshot()
    }
}
```

Remove the observer synchronously on the actor path, following the existing controller pattern:

```swift
deinit {
    MainActor.assumeIsolated {
        if let languageSettingsObserverToken {
            languageSettings.removeObserver(languageSettingsObserverToken)
        }
    }
}
```

- [ ] **Step 4: Inject one live publisher into the production AppDelegate**

Change the stored property from an inline initializer to `let viewModel: TokenStatsViewModel`. The system initializer enables the live publisher; the existing test-oriented language initializer defaults to no live App Group writes:

```swift
let viewModel: TokenStatsViewModel
private let languageSettings: AppLanguageSettings

override init() {
    let settings = AppLanguageSettings.shared
    self.languageSettings = settings
    self.viewModel = TokenStatsViewModel(
        languageSettings: settings,
        widgetSnapshotPublisher: WidgetSnapshotPublisherFactory.makeLive()
    )
    super.init()
}

init(
    languageSettings: AppLanguageSettings,
    widgetSnapshotPublisher: (any WidgetSnapshotPublishing)? = nil
) {
    self.languageSettings = languageSettings
    self.viewModel = TokenStatsViewModel(
        languageSettings: languageSettings,
        widgetSnapshotPublisher: widgetSnapshotPublisher
    )
    super.init()
}
```

No call to `loadStats(for:)` publishes independently; all existing production refresh entry points already call `loadAllStats`, so only a complete provider set crosses the process boundary.

- [ ] **Step 5: Run ViewModel and launch regressions**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/TokenStatsViewModelWidgetPublishingTests -only-testing:TokenWatchTests/TokenStatsViewModelObserverTests -only-testing:TokenWatchTests/AppLanguageSettingsTests -only-testing:TokenWatchTests/TokenWatchTests -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData test
```

Expected: publication occurs only after the task group, the overlap test scans once, and language changes do not rescan.

- [ ] **Step 6: Commit refresh integration**

```bash
git add TokenWatch/ViewModels/TokenStatsViewModel.swift TokenWatch/AppDelegate.swift TokenWatchTests/ViewModels/TokenStatsViewModelWidgetPublishingTests.swift
git commit -m "feat(widget): 接入全量刷新与语言重发"
```

### Task 7: Plan Timelines and Derive Render Presentations

**Files:**
- Create: `TokenWatchShared/Widgets/WidgetTimelinePlanning.swift`
- Create: `TokenWatchShared/Widgets/WidgetChartPresentation.swift`
- Create: `TokenWatchTests/Widgets/WidgetTimelinePlanningTests.swift`
- Create: `TokenWatchTests/Widgets/WidgetChartPresentationTests.swift`

**Interfaces:**
- Consumes: validated store results, snapshots, fallback text, a date, and a calendar.
- Produces: `WidgetUsageEntryState`, `WidgetTimelinePlanner`, `WidgetHeatmapPresentationCell`, `WidgetHeatmapPresentation`, `WidgetHourlyLinePresentation`, and `WidgetChartPresentationBuilder` without importing WidgetKit or SwiftUI.

- [ ] **Step 1: Write failing state, DST, and presentation tests**

```swift
import Foundation
import Testing
@testable import TokenWatch

@Suite("Widget timeline planning")
struct WidgetTimelinePlanningTests {
    @Test("same local day is current and prior local day is stale")
    func classifiesCurrentAndStale() {
        let currentSnapshot = snapshot(dayKey: "2026-07-15")
        let staleSnapshot = snapshot(dayKey: "2026-07-14")

        #expect(WidgetTimelinePlanner.state(
            for: .available(currentSnapshot),
            at: isoDate("2026-07-15T13:00:00+08:00"),
            calendar: shanghaiCalendar,
            fallbackText: fallback
        ) == .current(currentSnapshot))
        #expect(WidgetTimelinePlanner.state(
            for: .available(staleSnapshot),
            at: isoDate("2026-07-15T00:01:00+08:00"),
            calendar: shanghaiCalendar,
            fallbackText: fallback
        ) == .stale(staleSnapshot))
    }

    @Test("missing and every invalid read use not-ready fallback")
    func missingAndInvalidAreNotReady() {
        let results: [WidgetSnapshotReadResult] = [
            .missing,
            .invalid(.unreadable),
            .invalid(.corrupt),
            .invalid(.unsupportedSchema(2)),
        ]

        for result in results {
            #expect(WidgetTimelinePlanner.state(
                for: result,
                at: isoDate("2026-07-15T13:00:00+08:00"),
                calendar: shanghaiCalendar,
                fallbackText: fallback
            ) == .notReady(fallback))
        }
    }

    @Test("next midnight respects the 23-hour spring-forward day")
    func nextMidnightRespectsSpringForward() throws {
        let calendar = losAngelesCalendar
        let reference = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 3,
            day: 8,
            hour: 12
        )))
        let dayStart = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 3,
            day: 8
        )))
        let expected = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 3,
            day: 9
        )))

        let actual = WidgetTimelinePlanner.nextLocalMidnight(
            after: reference,
            calendar: calendar
        )

        #expect(actual == expected)
        #expect(actual.timeIntervalSince(dayStart) == 23 * 60 * 60)
    }

    @Test("next midnight respects the 25-hour fall-back day")
    func nextMidnightRespectsFallBack() throws {
        let calendar = losAngelesCalendar
        let reference = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 11,
            day: 1,
            hour: 12
        )))
        let dayStart = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 11,
            day: 1
        )))
        let expected = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 11,
            day: 2
        )))

        let actual = WidgetTimelinePlanner.nextLocalMidnight(
            after: reference,
            calendar: calendar
        )

        #expect(actual == expected)
        #expect(actual.timeIntervalSince(dayStart) == 25 * 60 * 60)
    }

    private var shanghaiCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private var losAngelesCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    private var fallback: WidgetLocalizedText {
        WidgetLocalizedText(
            heatmapTitle: "Recent 22 Weeks",
            todayUsageTitle: "Today's Usage",
            datedUsageTitle: "7/15 Usage",
            updatedThroughTitle: "Updated through 7/15",
            notReadyMessage: "Open TokenWatch to refresh data"
        )
    }

    private func isoDate(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }

    private func snapshot(dayKey: String) -> WidgetUsageSnapshot {
        WidgetUsageSnapshot(
            schemaVersion: WidgetSharedConfiguration.schemaVersion,
            generatedAt: isoDate("2026-07-15T05:00:00Z"),
            localDayKey: dayKey,
            localizedText: fallback,
            heatmap: WidgetHeatmapSnapshot(
                totalTokens: 42,
                maxDailyTokens: 42,
                cells: (0..<154).map { index in
                    WidgetHeatmapCell(
                        dateKey: "heatmap-date-\(index)",
                        totalTokens: index == 0 ? 42 : 0,
                        intensity: index == 0 ? 4 : 0,
                        isPlaceholder: false
                    )
                }
            ),
            hourlyLine: WidgetHourlyLineSnapshot(
                dayKey: dayKey,
                totalTokens: 42,
                maxHourlyTokens: 42,
                points: (0...23).map { hour in
                    WidgetHourlyPoint(
                        hour: hour,
                        hourKey: "hour-key-\(hour)",
                        hourLabel: "\(hour)",
                        totalTokens: hour == 13 ? 42 : 0,
                        isCurrentHour: hour == 13
                    )
                }
            )
        )
    }
}
```

Create the second test file in full:

```swift
import Foundation
import Testing
@testable import TokenWatch

@Suite("Widget chart presentation")
struct WidgetChartPresentationTests {
    @Test("current valid zero is data, not an empty state")
    func currentZeroRemainsARealVisualization() {
        let state = WidgetUsageEntryState.current(makeSnapshot(totalTokens: 0))
        let heatmap = WidgetChartPresentationBuilder.heatmap(for: state)
        let hourly = WidgetChartPresentationBuilder.hourlyLine(for: state)

        #expect(heatmap.message == nil)
        #expect(heatmap.totalText == "0")
        #expect(heatmap.cells.count == 154)
        #expect(heatmap.cells[0].isVisible)
        #expect(!heatmap.cells[152].isVisible)
        #expect(!heatmap.cells[153].isVisible)
        #expect(hourly.message == nil)
        #expect(hourly.totalText == "0")
        #expect(hourly.points.count == 24)
        #expect(hourly.maximumY == 1)
    }

    @Test("not-ready uses neutral full shapes and no current marker")
    func notReadyUsesNeutralVisualization() {
        let state = WidgetUsageEntryState.notReady(fallback)
        let heatmap = WidgetChartPresentationBuilder.heatmap(for: state)
        let hourly = WidgetChartPresentationBuilder.hourlyLine(for: state)

        #expect(heatmap.message == fallback.notReadyMessage)
        #expect(heatmap.cells.count == 154)
        #expect(heatmap.cells.allSatisfy { $0.intensity == 0 && $0.isVisible })
        #expect(hourly.message == fallback.notReadyMessage)
        #expect(hourly.points.map(\.hour) == Array(0...23))
        #expect(hourly.points.allSatisfy {
            $0.totalTokens == 0 && !$0.isCurrentHour
        })
        #expect(hourly.maximumY == 1)
        #expect(hourly.currentPoint == nil)
    }

    @Test("stale data uses dated titles and hides the current-hour marker")
    func stalePresentationUsesStaleCopy() {
        let snapshot = makeSnapshot(totalTokens: 42)
        let state = WidgetUsageEntryState.stale(snapshot)
        let heatmap = WidgetChartPresentationBuilder.heatmap(for: state)
        let hourly = WidgetChartPresentationBuilder.hourlyLine(for: state)

        #expect(heatmap.title == snapshot.localizedText.heatmapTitle)
        #expect(heatmap.subtitle == snapshot.localizedText.updatedThroughTitle)
        #expect(heatmap.message == nil)
        #expect(hourly.title == snapshot.localizedText.datedUsageTitle)
        #expect(hourly.currentPoint == nil)
        #expect(hourly.points.contains(where: \.isCurrentHour))
    }

    @Test("current and placeholder states use today's title and current point")
    func currentAndPlaceholderUseCurrentCopy() {
        let snapshot = makeSnapshot(totalTokens: 42)
        let states: [WidgetUsageEntryState] = [
            .current(snapshot),
            .placeholder(snapshot),
        ]

        for state in states {
            let heatmap = WidgetChartPresentationBuilder.heatmap(for: state)
            let hourly = WidgetChartPresentationBuilder.hourlyLine(for: state)
            #expect(heatmap.subtitle == nil)
            #expect(hourly.title == snapshot.localizedText.todayUsageTitle)
            #expect(hourly.currentPoint?.hour == 13)
        }
    }

    @Test("accessibility labels summarize aggregates without enumerating data points")
    func accessibilityLabelsAreAggregateOnly() {
        let snapshot = makeSnapshot(totalTokens: 42)
        let heatmap = WidgetChartPresentationBuilder.heatmap(for: .current(snapshot))
        let hourly = WidgetChartPresentationBuilder.hourlyLine(for: .current(snapshot))

        #expect(heatmap.accessibilityLabel.contains(heatmap.title))
        #expect(heatmap.accessibilityLabel.contains(heatmap.totalText))
        #expect(heatmap.accessibilityLabel.contains(
            snapshot.localizedText.updatedThroughTitle
        ))
        #expect(hourly.accessibilityLabel.contains(hourly.title))
        #expect(hourly.accessibilityLabel.contains(hourly.totalText))
        #expect(hourly.accessibilityLabel.contains(
            snapshot.localizedText.datedUsageTitle
        ))
        for cell in snapshot.heatmap.cells {
            if let dateKey = cell.dateKey {
                #expect(!heatmap.accessibilityLabel.contains(dateKey))
            }
        }
        for point in snapshot.hourlyLine.points {
            #expect(!hourly.accessibilityLabel.contains(point.hourKey))
        }
    }

    private var fallback: WidgetLocalizedText {
        WidgetLocalizedText(
            heatmapTitle: "Recent 22 Weeks",
            todayUsageTitle: "Today's Usage",
            datedUsageTitle: "7/15 Usage",
            updatedThroughTitle: "Updated through 7/15",
            notReadyMessage: "Open TokenWatch to refresh data"
        )
    }

    private func makeSnapshot(totalTokens: Int) -> WidgetUsageSnapshot {
        WidgetUsageSnapshot(
            schemaVersion: WidgetSharedConfiguration.schemaVersion,
            generatedAt: Date(timeIntervalSince1970: 100),
            localDayKey: "2026-07-15",
            localizedText: fallback,
            heatmap: WidgetHeatmapSnapshot(
                totalTokens: totalTokens,
                maxDailyTokens: totalTokens,
                cells: (0..<154).map { index in
                    let isPlaceholder = index >= 152
                    return WidgetHeatmapCell(
                        dateKey: isPlaceholder ? nil : "heatmap-date-\(index)",
                        totalTokens: index == 0 ? totalTokens : 0,
                        intensity: index == 0 && totalTokens > 0 ? 4 : 0,
                        isPlaceholder: isPlaceholder
                    )
                }
            ),
            hourlyLine: WidgetHourlyLineSnapshot(
                dayKey: "2026-07-15",
                totalTokens: totalTokens,
                maxHourlyTokens: totalTokens,
                points: (0...23).map { hour in
                    WidgetHourlyPoint(
                        hour: hour,
                        hourKey: "hour-key-\(hour)",
                        hourLabel: "\(hour)",
                        totalTokens: hour == 13 ? totalTokens : 0,
                        isCurrentHour: hour == 13
                    )
                }
            )
        )
    }
}
```

- [ ] **Step 2: Run both suites to verify RED**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/WidgetTimelinePlanningTests -only-testing:TokenWatchTests/WidgetChartPresentationTests -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData test
```

Expected: compilation fails because the timeline and presentation types do not exist.

- [ ] **Step 3: Implement pure timeline planning**

```swift
import Foundation

enum WidgetUsageEntryState: Equatable, Sendable {
    case placeholder(WidgetUsageSnapshot)
    case current(WidgetUsageSnapshot)
    case stale(WidgetUsageSnapshot)
    case notReady(WidgetLocalizedText)
}

enum WidgetTimelinePlanner {
    static func state(
        for result: WidgetSnapshotReadResult,
        at date: Date,
        calendar: Calendar,
        fallbackText: WidgetLocalizedText
    ) -> WidgetUsageEntryState {
        switch result {
        case .available(let snapshot):
            return snapshot.localDayKey == dayKey(date, calendar: calendar)
                ? .current(snapshot)
                : .stale(snapshot)
        case .missing, .invalid:
            return .notReady(fallbackText)
        }
    }

    static func nextLocalMidnight(after date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: start)
            ?? date.addingTimeInterval(60 * 60)
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}
```

- [ ] **Step 4: Implement pure chart presentations**

Use these exact models:

```swift
struct WidgetHeatmapPresentationCell: Equatable, Sendable {
    let intensity: Int
    let isVisible: Bool
}

struct WidgetHeatmapPresentation: Equatable, Sendable {
    let title: String
    let subtitle: String?
    let totalText: String
    let cells: [WidgetHeatmapPresentationCell]
    let message: String?
    let accessibilityLabel: String
}

struct WidgetHourlyLinePresentation: Equatable, Sendable {
    let title: String
    let totalText: String
    let points: [WidgetHourlyPoint]
    let maximumY: Double
    let currentPoint: WidgetHourlyPoint?
    let message: String?
    let accessibilityLabel: String
}
```

Add the complete builder below. Real calendar padding is transparent, while the
not-ready state deliberately renders a full neutral grid; stale line data keeps
its points but suppresses the current-hour marker.

```swift
enum WidgetChartPresentationBuilder {
    static func heatmap(
        for state: WidgetUsageEntryState
    ) -> WidgetHeatmapPresentation {
        switch state {
        case .placeholder(let snapshot), .current(let snapshot):
            return heatmap(snapshot: snapshot, isStale: false)
        case .stale(let snapshot):
            return heatmap(snapshot: snapshot, isStale: true)
        case .notReady(let text):
            let totalText = WidgetChartNumberFormatter.compact(0)
            let cells = Array(
                repeating: WidgetHeatmapPresentationCell(
                    intensity: 0,
                    isVisible: true
                ),
                count: WidgetChartVisualStyle.heatmapColumns
                    * WidgetChartVisualStyle.heatmapRows
            )
            return WidgetHeatmapPresentation(
                title: text.heatmapTitle,
                subtitle: nil,
                totalText: totalText,
                cells: cells,
                message: text.notReadyMessage,
                accessibilityLabel: aggregateLabel([
                    text.heatmapTitle,
                    text.notReadyMessage,
                    totalText,
                ])
            )
        }
    }

    static func hourlyLine(
        for state: WidgetUsageEntryState
    ) -> WidgetHourlyLinePresentation {
        switch state {
        case .placeholder(let snapshot), .current(let snapshot):
            return hourlyLine(snapshot: snapshot, isStale: false)
        case .stale(let snapshot):
            return hourlyLine(snapshot: snapshot, isStale: true)
        case .notReady(let text):
            let totalText = WidgetChartNumberFormatter.compact(0)
            let points = (0...23).map { hour in
                WidgetHourlyPoint(
                    hour: hour,
                    hourKey: "not-ready-hour-\(hour)",
                    hourLabel: "\(hour)",
                    totalTokens: 0,
                    isCurrentHour: false
                )
            }
            return WidgetHourlyLinePresentation(
                title: text.todayUsageTitle,
                totalText: totalText,
                points: points,
                maximumY: WidgetChartVisualStyle.hourlyMaximumY(
                    maxHourlyTokens: 0
                ),
                currentPoint: nil,
                message: text.notReadyMessage,
                accessibilityLabel: aggregateLabel([
                    text.todayUsageTitle,
                    text.notReadyMessage,
                    totalText,
                ])
            )
        }
    }

    private static func heatmap(
        snapshot: WidgetUsageSnapshot,
        isStale: Bool
    ) -> WidgetHeatmapPresentation {
        let title = snapshot.localizedText.heatmapTitle
        let subtitle = isStale
            ? snapshot.localizedText.updatedThroughTitle
            : nil
        let totalText = WidgetChartNumberFormatter.compact(
            snapshot.heatmap.totalTokens
        )
        let cells = snapshot.heatmap.cells.map { cell in
            WidgetHeatmapPresentationCell(
                intensity: cell.intensity,
                isVisible: !cell.isPlaceholder
            )
        }
        return WidgetHeatmapPresentation(
            title: title,
            subtitle: subtitle,
            totalText: totalText,
            cells: cells,
            message: nil,
            accessibilityLabel: aggregateLabel([
                title,
                snapshot.localizedText.updatedThroughTitle,
                totalText,
            ])
        )
    }

    private static func hourlyLine(
        snapshot: WidgetUsageSnapshot,
        isStale: Bool
    ) -> WidgetHourlyLinePresentation {
        let title = isStale
            ? snapshot.localizedText.datedUsageTitle
            : snapshot.localizedText.todayUsageTitle
        let totalText = WidgetChartNumberFormatter.compact(
            snapshot.hourlyLine.totalTokens
        )
        let currentPoint = isStale
            ? nil
            : snapshot.hourlyLine.points.first(where: \.isCurrentHour)
        return WidgetHourlyLinePresentation(
            title: title,
            totalText: totalText,
            points: snapshot.hourlyLine.points,
            maximumY: WidgetChartVisualStyle.hourlyMaximumY(
                maxHourlyTokens: snapshot.hourlyLine.maxHourlyTokens
            ),
            currentPoint: currentPoint,
            message: nil,
            accessibilityLabel: aggregateLabel([
                title,
                isStale ? nil : snapshot.localizedText.datedUsageTitle,
                totalText,
            ])
        )
    }

    private static func aggregateLabel(_ values: [String?]) -> String {
        values
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}
```

- [ ] **Step 5: Run timeline/presentation GREEN**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/WidgetTimelinePlanningTests -only-testing:TokenWatchTests/WidgetChartPresentationTests -only-testing:TokenWatchTests/WidgetChartVisualStyleTests -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData test
```

Expected: current/stale/not-ready semantics, valid zero behavior, and both DST transitions pass.

- [ ] **Step 6: Commit shared timeline logic**

```bash
git add TokenWatchShared/Widgets/WidgetTimelinePlanning.swift TokenWatchShared/Widgets/WidgetChartPresentation.swift TokenWatchTests/Widgets/WidgetTimelinePlanningTests.swift TokenWatchTests/Widgets/WidgetChartPresentationTests.swift
git commit -m "feat(widget): 添加时间线与渲染状态"
```

### Task 8: Create the Widget Extension and Heatmap Widget

**Files:**
- Create: `TokenWatch/TokenWatch.entitlements`
- Create: `TokenWatchWidgets/Info.plist`
- Create: `TokenWatchWidgets/TokenWatchWidgets.entitlements`
- Create: `TokenWatchWidgets/Localizable.xcstrings`
- Create: `TokenWatchWidgets/WidgetTimelineProvider.swift`
- Create: `TokenWatchWidgets/WidgetSampleSnapshotFactory.swift`
- Create: `TokenWatchWidgets/WidgetChartHeader.swift`
- Create: `TokenWatchWidgets/TokenHeatmapWidget.swift`
- Create: `TokenWatchWidgets/TokenWatchWidgetsBundle.swift`
- Create: `TokenWatch.xcodeproj/xcshareddata/xcschemes/TokenWatchWidgets.xcscheme`
- Modify: `TokenWatch.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: the shared store, planner, presentation models, and chart style.
- Produces: an embedded WidgetKit `.appex`, a real timeline provider, deterministic preview data, and one `.systemMedium` heatmap configuration.

- [ ] **Step 1: Establish the failing build check**

Before adding the target, run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatchWidgets -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData build
```

Expected: `The project named "TokenWatch" does not contain a scheme named "TokenWatchWidgets"`.

- [ ] **Step 2: Add explicit App Group entitlements**

Create `TokenWatch/TokenWatch.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.xiaoao.tokenwatch</string>
    </array>
    <key>com.apple.security.files.user-selected.read-only</key>
    <true/>
</dict>
</plist>
```

Create `TokenWatchWidgets/TokenWatchWidgets.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.xiaoao.tokenwatch</string>
    </array>
</dict>
</plist>
```

Create `TokenWatchWidgets/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>$(DEVELOPMENT_LANGUAGE)</string>
    <key>CFBundleDisplayName</key>
    <string>TokenWatch Widgets</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$(PRODUCT_NAME)</string>
    <key>CFBundlePackageType</key>
    <string>$(PRODUCT_BUNDLE_PACKAGE_TYPE)</string>
    <key>CFBundleShortVersionString</key>
    <string>$(MARKETING_VERSION)</string>
    <key>CFBundleVersion</key>
    <string>$(CURRENT_PROJECT_VERSION)</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.widgetkit-extension</string>
    </dict>
</dict>
</plist>
```

- [ ] **Step 3: Add the synchronized Widget target and embed relationship**

Prefer creating the target/capability with Xcode MCP so Xcode serializes the project. If that capability is unavailable, edit `project.pbxproj` with `apply_patch` and use these reserved IDs exactly:

| ID | Object |
|---|---|
| `C0D300012FD0000000000002` | `PBXFileSystemSynchronizedRootGroup` path `TokenWatchWidgets` |
| `C0D300012FD0000000000003` | product `PBXFileReference` path `TokenWatchWidgets.appex` |
| `C0D300012FD0000000000004` | `PBXBuildFile` for embedding the appex, attribute `RemoveHeadersOnCopy` |
| `C0D300012FD0000000000005` | `PBXCopyFilesBuildPhase` named `Embed App Extensions`, `dstSubfolderSpec = 13` |
| `C0D300012FD0000000000006` | extension `PBXSourcesBuildPhase` |
| `C0D300012FD0000000000007` | extension `PBXFrameworksBuildPhase` |
| `C0D300012FD0000000000008` | extension `PBXResourcesBuildPhase` |
| `C0D300012FD0000000000009` | `PBXNativeTarget` named `TokenWatchWidgets` |
| `C0D300012FD000000000000A` | extension `PBXContainerItemProxy` |
| `C0D300012FD000000000000B` | app-to-extension `PBXTargetDependency` |
| `C0D300012FD000000000000C` | extension Debug `XCBuildConfiguration` |
| `C0D300012FD000000000000D` | extension Release `XCBuildConfiguration` |
| `C0D300012FD000000000000E` | extension `XCConfigurationList` |
| `C0D300012FD000000000000F` | `PBXFileSystemSynchronizedBuildFileExceptionSet` for extension `Info.plist` |

The object graph must satisfy all of these relationships:

- main group contains the existing shared root `C0D300012FD0000000000001` and Widget root `C0D300012FD0000000000002`;
- Widget root `C0D300012FD0000000000002` references exception set `C0D300012FD000000000000F`, whose sole `membershipExceptions` entry is `Info.plist` for target `C0D300012FD0000000000009`, preventing the processed Info plist from also being copied as a resource;
- Products contains `C0D300012FD0000000000003`;
- extension target `C0D300012FD0000000000009` has phases `C0D300012FD0000000000006`, `C0D300012FD0000000000007`, `C0D300012FD0000000000008` and synchronized roots `C0D300012FD0000000000002`, `C0D300012FD0000000000001`;
- app target `AAA358092FDD7BFB0018086B` has copy phase `C0D300012FD0000000000005` and dependency `C0D300012FD000000000000B`;
- copy phase contains build file `C0D300012FD0000000000004`, whose product reference is `C0D300012FD0000000000003`;
- proxy `C0D300012FD000000000000A` points to target `C0D300012FD0000000000009`, and dependency `C0D300012FD000000000000B` points to both;
- project target attributes and `targets` include `C0D300012FD0000000000009` with `CreatedOnToolsVersion = 26.5`;
- extension product type is `com.apple.product-type.app-extension`;
- both app configurations `AAA3582F2FDD7BFD0018086B` and `AAA358302FDD7BFD0018086B` set `CODE_SIGN_ENTITLEMENTS = TokenWatch/TokenWatch.entitlements`.

Use these extension build settings in both Debug and Release; Debug additionally inherits the project Debug optimization/conditions and Release inherits the project Release settings:

```text
APPLICATION_EXTENSION_API_ONLY = YES
CODE_SIGN_ENTITLEMENTS = TokenWatchWidgets/TokenWatchWidgets.entitlements
CODE_SIGN_IDENTITY = Apple Development
CODE_SIGN_STYLE = Automatic
CURRENT_PROJECT_VERSION = 1
DEVELOPMENT_TEAM = 8525Z2FVDF
ENABLE_APP_SANDBOX = YES
GENERATE_INFOPLIST_FILE = NO
INFOPLIST_FILE = TokenWatchWidgets/Info.plist
LD_RUNPATH_SEARCH_PATHS = $(inherited), @executable_path/../Frameworks, @executable_path/../../../../Frameworks
MACOSX_DEPLOYMENT_TARGET = 15.0
MARKETING_VERSION = 1.0
PRODUCT_BUNDLE_IDENTIFIER = com.xiaoao.tokenwatch.widgets
PRODUCT_NAME = $(TARGET_NAME)
REGISTER_APP_GROUPS = YES
SKIP_INSTALL = YES
STRING_CATALOG_GENERATE_SYMBOLS = YES
SWIFT_APPROACHABLE_CONCURRENCY = YES
SWIFT_EMIT_LOC_STRINGS = YES
SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES
SWIFT_VERSION = 6.0
```

For the shell fallback, add these complete objects to their matching
`project.pbxproj` sections. The snippets are intentionally complete so no object
shape needs to be inferred:

```text
/* Begin PBXBuildFile section */
		C0D300012FD0000000000004 /* TokenWatchWidgets.appex in Embed App Extensions */ = {
			isa = PBXBuildFile;
			fileRef = C0D300012FD0000000000003 /* TokenWatchWidgets.appex */;
			settings = {
				ATTRIBUTES = (
					RemoveHeadersOnCopy,
				);
			};
		};
/* End PBXBuildFile section */

/* add inside PBXContainerItemProxy section */
		C0D300012FD000000000000A /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = AAA358022FDD7BFB0018086B /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = C0D300012FD0000000000009;
			remoteInfo = TokenWatchWidgets;
		};

/* Begin PBXCopyFilesBuildPhase section */
		C0D300012FD0000000000005 /* Embed App Extensions */ = {
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = "";
			dstSubfolderSpec = 13;
			files = (
				C0D300012FD0000000000004 /* TokenWatchWidgets.appex in Embed App Extensions */,
			);
			name = "Embed App Extensions";
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXCopyFilesBuildPhase section */

/* add inside PBXFileReference section */
		C0D300012FD0000000000003 /* TokenWatchWidgets.appex */ = {
			isa = PBXFileReference;
			explicitFileType = "wrapper.app-extension";
			includeInIndex = 0;
			path = TokenWatchWidgets.appex;
			sourceTree = BUILT_PRODUCTS_DIR;
		};

/* Begin PBXFileSystemSynchronizedBuildFileExceptionSet section */
		C0D300012FD000000000000F /* Exceptions for TokenWatchWidgets */ = {
			isa = PBXFileSystemSynchronizedBuildFileExceptionSet;
			membershipExceptions = (
				Info.plist,
			);
			target = C0D300012FD0000000000009 /* TokenWatchWidgets */;
		};
/* End PBXFileSystemSynchronizedBuildFileExceptionSet section */

/* add inside PBXFileSystemSynchronizedRootGroup section */
		C0D300012FD0000000000002 /* TokenWatchWidgets */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			exceptions = (
				C0D300012FD000000000000F /* Exceptions for TokenWatchWidgets */,
			);
			path = TokenWatchWidgets;
			sourceTree = "<group>";
		};

/* add inside PBXFrameworksBuildPhase section */
		C0D300012FD0000000000007 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};

/* add inside PBXNativeTarget section */
		C0D300012FD0000000000009 /* TokenWatchWidgets */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = C0D300012FD000000000000E /* Build configuration list for PBXNativeTarget "TokenWatchWidgets" */;
			buildPhases = (
				C0D300012FD0000000000006 /* Sources */,
				C0D300012FD0000000000007 /* Frameworks */,
				C0D300012FD0000000000008 /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				C0D300012FD0000000000002 /* TokenWatchWidgets */,
				C0D300012FD0000000000001 /* TokenWatchShared */,
			);
			name = TokenWatchWidgets;
			packageProductDependencies = (
			);
			productName = TokenWatchWidgets;
			productReference = C0D300012FD0000000000003 /* TokenWatchWidgets.appex */;
			productType = "com.apple.product-type.app-extension";
		};

/* add inside PBXResourcesBuildPhase section */
		C0D300012FD0000000000008 /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};

/* add inside PBXSourcesBuildPhase section */
		C0D300012FD0000000000006 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};

/* add inside PBXTargetDependency section */
		C0D300012FD000000000000B /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = C0D300012FD0000000000009 /* TokenWatchWidgets */;
			targetProxy = C0D300012FD000000000000A /* PBXContainerItemProxy */;
		};
```

Add both complete target configurations inside `XCBuildConfiguration`:

```text
		C0D300012FD000000000000C /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				APPLICATION_EXTENSION_API_ONLY = YES;
				CODE_SIGN_ENTITLEMENTS = TokenWatchWidgets/TokenWatchWidgets.entitlements;
				CODE_SIGN_IDENTITY = "Apple Development";
				"CODE_SIGN_IDENTITY[sdk=macosx*]" = "Apple Development";
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = 8525Z2FVDF;
				ENABLE_APP_SANDBOX = YES;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = TokenWatchWidgets/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/../Frameworks",
					"@executable_path/../../../../Frameworks",
				);
				MACOSX_DEPLOYMENT_TARGET = 15.0;
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.xiaoao.tokenwatch.widgets;
				PRODUCT_NAME = "$(TARGET_NAME)";
				PROVISIONING_PROFILE_SPECIFIER = "";
				REGISTER_APP_GROUPS = YES;
				SKIP_INSTALL = YES;
				STRING_CATALOG_GENERATE_SYMBOLS = YES;
				SWIFT_APPROACHABLE_CONCURRENCY = YES;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES;
				SWIFT_VERSION = 6.0;
			};
			name = Debug;
		};
		C0D300012FD000000000000D /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				APPLICATION_EXTENSION_API_ONLY = YES;
				CODE_SIGN_ENTITLEMENTS = TokenWatchWidgets/TokenWatchWidgets.entitlements;
				CODE_SIGN_IDENTITY = "Apple Development";
				"CODE_SIGN_IDENTITY[sdk=macosx*]" = "Apple Development";
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = 8525Z2FVDF;
				ENABLE_APP_SANDBOX = YES;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = TokenWatchWidgets/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/../Frameworks",
					"@executable_path/../../../../Frameworks",
				);
				MACOSX_DEPLOYMENT_TARGET = 15.0;
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.xiaoao.tokenwatch.widgets;
				PRODUCT_NAME = "$(TARGET_NAME)";
				PROVISIONING_PROFILE_SPECIFIER = "";
				REGISTER_APP_GROUPS = YES;
				SKIP_INSTALL = YES;
				STRING_CATALOG_GENERATE_SYMBOLS = YES;
				SWIFT_APPROACHABLE_CONCURRENCY = YES;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES;
				SWIFT_VERSION = 6.0;
			};
			name = Release;
		};
```

Add the complete configuration list inside `XCConfigurationList`:

```text
		C0D300012FD000000000000E /* Build configuration list for PBXNativeTarget "TokenWatchWidgets" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				C0D300012FD000000000000C /* Debug */,
				C0D300012FD000000000000D /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
```

Apply these exact edits to existing objects:

- append `C0D300012FD0000000000005` to
  `AAA358092FDD7BFB0018086B.buildPhases` and
  `C0D300012FD000000000000B` to its `dependencies`;
- keep the shared root `C0D300012FD0000000000001` added in Task 1 and append
  only Widget root `C0D300012FD0000000000002` to
  `AAA358012FDD7BFB0018086B.children`;
- append product `C0D300012FD0000000000003` to
  `AAA3580B2FDD7BFB0018086B.children`;
- append target `C0D300012FD0000000000009` to
  `AAA358022FDD7BFB0018086B.targets` and add this exact TargetAttributes entry:

  ```text
					C0D300012FD0000000000009 = {
						CreatedOnToolsVersion = 26.5;
						ProvisioningStyle = Automatic;
					};
  ```

- add `CODE_SIGN_ENTITLEMENTS = TokenWatch/TokenWatch.entitlements;` to both
  app configurations `AAA3582F2FDD7BFD0018086B` and
  `AAA358302FDD7BFD0018086B`.

Create
`TokenWatch.xcodeproj/xcshareddata/xcschemes/TokenWatchWidgets.xcscheme` with
this complete XML:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "2650"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES"
      buildArchitectures = "Automatic">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "C0D300012FD0000000000009"
               BuildableName = "TokenWatchWidgets.appex"
               BlueprintName = "TokenWatchWidgets"
               ReferencedContainer = "container:TokenWatch.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES"
      shouldAutocreateTestPlan = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      askForAppToLaunch = "YES"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      allowLocationSimulation = "YES">
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      askForAppToLaunch = "YES"
      debugDocumentVersioning = "YES">
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
```

Do not add the extension as a testable target.

- [ ] **Step 4: Add all extension-localized strings**

Create `TokenWatchWidgets/Localizable.xcstrings` with this complete catalog:

```json
{
  "sourceLanguage" : "en",
  "strings" : {
    "widget.dated.format" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "Nutzung am %@" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "%@ Usage" } },
        "es" : { "stringUnit" : { "state" : "translated", "value" : "Uso del %@" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "Utilisation du %@" } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "Utilizzo del %@" } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "%@の使用量" } },
        "ko" : { "stringUnit" : { "state" : "translated", "value" : "%@ 사용량" } },
        "nl" : { "stringUnit" : { "state" : "translated", "value" : "Gebruik op %@" } },
        "pl" : { "stringUnit" : { "state" : "translated", "value" : "Użycie: %@" } },
        "pt-BR" : { "stringUnit" : { "state" : "translated", "value" : "Uso em %@" } },
        "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "%@ 用量" } },
        "zh-Hant" : { "stringUnit" : { "state" : "translated", "value" : "%@ 用量" } }
      }
    },
    "widget.heatmap.description" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "Token-Nutzung der letzten 22 Wochen anzeigen" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "View token usage for the last 22 weeks" } },
        "es" : { "stringUnit" : { "state" : "translated", "value" : "Consulta el uso de tokens de las últimas 22 semanas" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "Afficher l’utilisation des tokens sur les 22 dernières semaines" } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "Visualizza l’utilizzo dei token nelle ultime 22 settimane" } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "過去22週間のToken使用量を表示" } },
        "ko" : { "stringUnit" : { "state" : "translated", "value" : "최근 22주의 Token 사용량 보기" } },
        "nl" : { "stringUnit" : { "state" : "translated", "value" : "Bekijk het tokengebruik van de afgelopen 22 weken" } },
        "pl" : { "stringUnit" : { "state" : "translated", "value" : "Wyświetla użycie tokenów z ostatnich 22 tygodni" } },
        "pt-BR" : { "stringUnit" : { "state" : "translated", "value" : "Veja o uso de tokens das últimas 22 semanas" } },
        "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "查看最近 22 周的 Token 用量" } },
        "zh-Hant" : { "stringUnit" : { "state" : "translated", "value" : "查看最近 22 週的 Token 用量" } }
      }
    },
    "widget.heatmap.name" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "Nutzungs-Heatmap" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Usage Heatmap" } },
        "es" : { "stringUnit" : { "state" : "translated", "value" : "Mapa de calor de uso" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "Carte thermique d’utilisation" } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "Mappa termica di utilizzo" } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "使用量ヒートマップ" } },
        "ko" : { "stringUnit" : { "state" : "translated", "value" : "사용량 히트맵" } },
        "nl" : { "stringUnit" : { "state" : "translated", "value" : "Gebruik-heatmap" } },
        "pl" : { "stringUnit" : { "state" : "translated", "value" : "Mapa użycia" } },
        "pt-BR" : { "stringUnit" : { "state" : "translated", "value" : "Mapa de calor de uso" } },
        "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "用量热力图" } },
        "zh-Hant" : { "stringUnit" : { "state" : "translated", "value" : "用量熱力圖" } }
      }
    },
    "widget.heatmap.title" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "Letzte 22 Wochen" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Last 22 Weeks" } },
        "es" : { "stringUnit" : { "state" : "translated", "value" : "Últimas 22 semanas" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "22 dernières semaines" } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "Ultime 22 settimane" } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "過去22週間" } },
        "ko" : { "stringUnit" : { "state" : "translated", "value" : "최근 22주" } },
        "nl" : { "stringUnit" : { "state" : "translated", "value" : "Afgelopen 22 weken" } },
        "pl" : { "stringUnit" : { "state" : "translated", "value" : "Ostatnie 22 tygodnie" } },
        "pt-BR" : { "stringUnit" : { "state" : "translated", "value" : "Últimas 22 semanas" } },
        "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "最近 22 周" } },
        "zh-Hant" : { "stringUnit" : { "state" : "translated", "value" : "最近 22 週" } }
      }
    },
    "widget.hourly.description" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "Heutige Token-Nutzung nach Stunde anzeigen" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "View today's token usage by hour" } },
        "es" : { "stringUnit" : { "state" : "translated", "value" : "Consulta por hora el uso de tokens de hoy" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "Afficher l’utilisation des tokens d’aujourd’hui par heure" } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "Visualizza per ora l’utilizzo dei token di oggi" } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "今日のToken使用量を時間別に表示" } },
        "ko" : { "stringUnit" : { "state" : "translated", "value" : "오늘의 Token 사용량을 시간별로 보기" } },
        "nl" : { "stringUnit" : { "state" : "translated", "value" : "Bekijk het tokengebruik van vandaag per uur" } },
        "pl" : { "stringUnit" : { "state" : "translated", "value" : "Wyświetla dzisiejsze użycie tokenów według godzin" } },
        "pt-BR" : { "stringUnit" : { "state" : "translated", "value" : "Veja por hora o uso de tokens de hoje" } },
        "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "按小时查看今天的 Token 用量" } },
        "zh-Hant" : { "stringUnit" : { "state" : "translated", "value" : "按小時查看今天的 Token 用量" } }
      }
    },
    "widget.hourly.name" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "Stündliche Nutzung" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Hourly Usage" } },
        "es" : { "stringUnit" : { "state" : "translated", "value" : "Uso por hora" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "Utilisation horaire" } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "Utilizzo orario" } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "時間別使用量" } },
        "ko" : { "stringUnit" : { "state" : "translated", "value" : "시간별 사용량" } },
        "nl" : { "stringUnit" : { "state" : "translated", "value" : "Gebruik per uur" } },
        "pl" : { "stringUnit" : { "state" : "translated", "value" : "Użycie godzinowe" } },
        "pt-BR" : { "stringUnit" : { "state" : "translated", "value" : "Uso por hora" } },
        "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "小时用量" } },
        "zh-Hant" : { "stringUnit" : { "state" : "translated", "value" : "小時用量" } }
      }
    },
    "widget.notReady" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "TokenWatch öffnen, um Daten zu aktualisieren" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Open TokenWatch to refresh data" } },
        "es" : { "stringUnit" : { "state" : "translated", "value" : "Abre TokenWatch para actualizar los datos" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "Ouvrez TokenWatch pour actualiser les données" } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "Apri TokenWatch per aggiornare i dati" } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "TokenWatchを開いてデータを更新" } },
        "ko" : { "stringUnit" : { "state" : "translated", "value" : "TokenWatch를 열어 데이터를 새로고침" } },
        "nl" : { "stringUnit" : { "state" : "translated", "value" : "Open TokenWatch om gegevens te verversen" } },
        "pl" : { "stringUnit" : { "state" : "translated", "value" : "Otwórz TokenWatch, aby odświeżyć dane" } },
        "pt-BR" : { "stringUnit" : { "state" : "translated", "value" : "Abra o TokenWatch para atualizar os dados" } },
        "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "打开 TokenWatch 刷新数据" } },
        "zh-Hant" : { "stringUnit" : { "state" : "translated", "value" : "開啟 TokenWatch 重新整理資料" } }
      }
    },
    "widget.today.title" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "Heutige Nutzung" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Today's Usage" } },
        "es" : { "stringUnit" : { "state" : "translated", "value" : "Uso de hoy" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "Utilisation aujourd’hui" } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "Utilizzo di oggi" } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "今日の使用量" } },
        "ko" : { "stringUnit" : { "state" : "translated", "value" : "오늘 사용량" } },
        "nl" : { "stringUnit" : { "state" : "translated", "value" : "Gebruik vandaag" } },
        "pl" : { "stringUnit" : { "state" : "translated", "value" : "Dzisiejsze użycie" } },
        "pt-BR" : { "stringUnit" : { "state" : "translated", "value" : "Uso de hoje" } },
        "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "今日用量" } },
        "zh-Hant" : { "stringUnit" : { "state" : "translated", "value" : "今日用量" } }
      }
    },
    "widget.updated.format" : {
      "localizations" : {
        "de" : { "stringUnit" : { "state" : "translated", "value" : "Aktualisiert bis %@" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Updated through %@" } },
        "es" : { "stringUnit" : { "state" : "translated", "value" : "Actualizado hasta %@" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "Mis à jour jusqu’au %@" } },
        "it" : { "stringUnit" : { "state" : "translated", "value" : "Aggiornato al %@" } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "%@ まで更新" } },
        "ko" : { "stringUnit" : { "state" : "translated", "value" : "%@까지 업데이트" } },
        "nl" : { "stringUnit" : { "state" : "translated", "value" : "Bijgewerkt tot %@" } },
        "pl" : { "stringUnit" : { "state" : "translated", "value" : "Zaktualizowano do %@" } },
        "pt-BR" : { "stringUnit" : { "state" : "translated", "value" : "Atualizado até %@" } },
        "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "更新至 %@" } },
        "zh-Hant" : { "stringUnit" : { "state" : "translated", "value" : "更新至 %@" } }
      }
    }
  },
  "version" : "1.0"
}
```

- [ ] **Step 5: Implement fallback text, preview data, entry, and provider**

Implement system-language fallback text in `WidgetSampleSnapshotFactory.swift`:

```swift
import Foundation

enum WidgetFallbackLocalization {
    static func make(date: Date, calendar: Calendar) -> WidgetLocalizedText {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("Md")
        let dateText = formatter.string(from: date)

        return WidgetLocalizedText(
            heatmapTitle: String(localized: "widget.heatmap.title"),
            todayUsageTitle: String(localized: "widget.today.title"),
            datedUsageTitle: String(
                format: String(localized: "widget.dated.format"),
                dateText
            ),
            updatedThroughTitle: String(
                format: String(localized: "widget.updated.format"),
                dateText
            ),
            notReadyMessage: String(localized: "widget.notReady")
        )
    }
}

enum WidgetSampleSnapshotFactory {
    static func make(
        date: Date,
        calendar: Calendar,
        localizedText: WidgetLocalizedText
    ) -> WidgetUsageSnapshot {
        let cells = (0..<(WidgetChartVisualStyle.heatmapColumns
            * WidgetChartVisualStyle.heatmapRows)).map { index in
            let intensity = index % (WidgetChartVisualStyle.heatmapMaximumIntensity + 1)
            return WidgetHeatmapCell(
                dateKey: "sample-\(index)",
                totalTokens: intensity * 100_000,
                intensity: intensity,
                isPlaceholder: false
            )
        }
        let currentHour = calendar.component(.hour, from: date)
        let points = (0...23).map { hour in
            let total = max(0, 18 - abs(14 - hour) * 2) * 100_000
            return WidgetHourlyPoint(
                hour: hour,
                hourKey: "sample-hour-\(hour)",
                hourLabel: "\(hour)",
                totalTokens: total,
                isCurrentHour: hour == currentHour
            )
        }
        let localDayKey = dayKey(date, calendar: calendar)

        return WidgetUsageSnapshot(
            schemaVersion: WidgetSharedConfiguration.schemaVersion,
            generatedAt: date,
            localDayKey: localDayKey,
            localizedText: localizedText,
            heatmap: WidgetHeatmapSnapshot(
                totalTokens: cells.reduce(0) { $0 + $1.totalTokens },
                maxDailyTokens: cells.map(\.totalTokens).max() ?? 0,
                cells: cells
            ),
            hourlyLine: WidgetHourlyLineSnapshot(
                dayKey: localDayKey,
                totalTokens: points.reduce(0) { $0 + $1.totalTokens },
                maxHourlyTokens: points.map(\.totalTokens).max() ?? 0,
                points: points
            )
        )
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}
```

Implement the WidgetKit adapter with these interfaces and behavior:

```swift
import Foundation
import os.log
import WidgetKit

struct WidgetUsageEntry: TimelineEntry, Equatable, Sendable {
    let date: Date
    let state: WidgetUsageEntryState
}

private struct MissingWidgetSnapshotStore: WidgetSnapshotStoring, Sendable {
    func load() -> WidgetSnapshotReadResult {
        .missing
    }

    func save(_ snapshot: WidgetUsageSnapshot) throws {
        throw WidgetSnapshotStoreError.invalidSnapshot
    }
}

struct WidgetTimelineProvider: TimelineProvider {
    typealias Entry = WidgetUsageEntry

    private static let logger = Logger(
        subsystem: "com.xiaoao.TokenWatch.widgets",
        category: "WidgetTimelineProvider"
    )

    private let store: any WidgetSnapshotStoring
    private let now: @Sendable () -> Date
    private let calendar: @Sendable () -> Calendar

    init(
        store: any WidgetSnapshotStoring = WidgetTimelineProvider.liveStore(),
        now: @escaping @Sendable () -> Date = Date.init,
        calendar: @escaping @Sendable () -> Calendar = { .autoupdatingCurrent }
    ) {
        self.store = store
        self.now = now
        self.calendar = calendar
    }

    static func liveStore() -> any WidgetSnapshotStoring {
        do {
            return try JSONWidgetSnapshotStore.appGroupStore()
        } catch {
            logger.error("App Group container unavailable; showing not-ready widget state")
            return MissingWidgetSnapshotStore()
        }
    }

    func placeholder(in context: Context) -> WidgetUsageEntry {
        let date = now()
        let calendar = calendar()
        let text = WidgetFallbackLocalization.make(date: date, calendar: calendar)
        return WidgetUsageEntry(
            date: date,
            state: .placeholder(WidgetSampleSnapshotFactory.make(
                date: date,
                calendar: calendar,
                localizedText: text
            ))
        )
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping @Sendable (WidgetUsageEntry) -> Void
    ) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        let date = now()
        let calendar = calendar()
        completion(currentEntry(date: date, calendar: calendar))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping @Sendable (Timeline<WidgetUsageEntry>) -> Void
    ) {
        let date = now()
        let calendar = calendar()
        let entry = currentEntry(date: date, calendar: calendar)
        let refreshDate = WidgetTimelinePlanner.nextLocalMidnight(
            after: date,
            calendar: calendar
        )
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }

    private func currentEntry(date: Date, calendar: Calendar) -> WidgetUsageEntry {
        let fallback = WidgetFallbackLocalization.make(date: date, calendar: calendar)
        let result = store.load()
        switch result {
        case .invalid(.unreadable):
            Self.logger.error("Shared widget snapshot is unreadable")
        case .invalid(.corrupt):
            Self.logger.error("Shared widget snapshot is corrupt")
        case .invalid(.unsupportedSchema(_)):
            Self.logger.error("Shared widget snapshot uses an unsupported schema")
        case .available, .missing:
            break
        }
        return WidgetUsageEntry(
            date: date,
            state: WidgetTimelinePlanner.state(
                for: result,
                at: date,
                calendar: calendar,
                fallbackText: fallback
            )
        )
    }
}
```

The provider reads once per snapshot/timeline request and never touches provider logs or bookmarks. Its logs contain only fixed failure categories.

- [ ] **Step 6: Implement the shared header and heatmap view**

Create `WidgetChartHeader.swift`:

```swift
import SwiftUI

struct WidgetChartHeader: View {
    let title: String
    let subtitle: String?
    let total: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Text(total)
                .font(.headline)
                .fontWeight(.semibold)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}
```

Create the heatmap view and configuration in `TokenHeatmapWidget.swift`:

```swift
import SwiftUI
import WidgetKit

struct TokenHeatmapWidgetView: View {
    let entry: WidgetUsageEntry
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let presentation = WidgetChartPresentationBuilder.heatmap(for: entry.state)

        VStack(spacing: 8) {
            WidgetChartHeader(
                title: presentation.title,
                subtitle: presentation.subtitle,
                total: presentation.totalText
            )
            ZStack {
                heatmapGrid(presentation)
                    .opacity(presentation.message == nil ? 1 : 0.35)
                if let message = presentation.message {
                    Text(message)
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                        .padding(6)
                        .background(
                            .regularMaterial,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    private func heatmapGrid(_ presentation: WidgetHeatmapPresentation) -> some View {
        GeometryReader { proxy in
            let side = CGFloat(WidgetChartVisualStyle.heatmapTileSide(
                availableWidth: Double(proxy.size.width),
                availableHeight: Double(proxy.size.height)
            ))
            let spacing = CGFloat(WidgetChartVisualStyle.heatmapSpacing)
            let radius = CGFloat(WidgetChartVisualStyle.heatmapCornerRadius)

            HStack(spacing: spacing) {
                ForEach(0..<WidgetChartVisualStyle.heatmapColumns, id: \.self) { column in
                    VStack(spacing: spacing) {
                        ForEach(0..<WidgetChartVisualStyle.heatmapRows, id: \.self) { row in
                            let index = WidgetChartVisualStyle.heatmapIndex(
                                column: column,
                                row: row
                            )
                            let cell = presentation.cells[index]
                            RoundedRectangle(cornerRadius: radius)
                                .fill(color(for: cell))
                                .frame(width: side, height: side)
                        }
                    }
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .center
            )
        }
    }

    private func color(for cell: WidgetHeatmapPresentationCell) -> Color {
        guard cell.isVisible else { return .clear }
        let rgba = WidgetChartVisualStyle.heatmapRGBA(
            intensity: cell.intensity,
            isDark: colorScheme == .dark
        )
        return Color(
            .sRGB,
            red: rgba.red,
            green: rgba.green,
            blue: rgba.blue,
            opacity: rgba.alpha
        )
    }
}

struct TokenHeatmapWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: WidgetSharedConfiguration.heatmapKind,
            provider: WidgetTimelineProvider()
        ) { entry in
            TokenHeatmapWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName(LocalizedStringKey("widget.heatmap.name"))
        .description(LocalizedStringKey("widget.heatmap.description"))
        .supportedFamilies([.systemMedium])
    }
}
```

This preserves transparent calendar padding, while not-ready presentation cells remain visible at neutral intensity under the message. The view exposes one aggregate accessibility element and ignores all 154 child tiles.

Do not call `contentMarginsDisabled()` and do not set `widgetURL`; WidgetKit's default tap behavior opens the containing app.

For this intermediate task, create `TokenWatchWidgetsBundle.swift` with only the heatmap so the extension remains buildable before Task 9:

```swift
import SwiftUI
import WidgetKit

@main
struct TokenWatchWidgetsBundle: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        TokenHeatmapWidget()
    }
}
```

- [ ] **Step 7: Build the extension and embedded app**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatchWidgets -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData build
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData build
test -d '.build/DerivedData/Build/Products/Debug/AI Token Watch.app/Contents/PlugIns/TokenWatchWidgets.appex'
```

Expected: both builds succeed and the final `test` exits 0.

- [ ] **Step 8: Verify both signed products expose the same App Group**

```bash
codesign -d --entitlements :- '.build/DerivedData/Build/Products/Debug/AI Token Watch.app'
codesign -d --entitlements :- '.build/DerivedData/Build/Products/Debug/AI Token Watch.app/Contents/PlugIns/TokenWatchWidgets.appex'
plutil -p '.build/DerivedData/Build/Products/Debug/AI Token Watch.app/Contents/PlugIns/TokenWatchWidgets.appex/Contents/Info.plist'
```

Expected: both entitlement dumps contain only the approved App Group value for `com.apple.security.application-groups`; the extension Info contains `com.apple.widgetkit-extension`. If automatic signing says the App Group is unavailable, stop and enable `group.com.xiaoao.tokenwatch` for both bundle IDs in team `8525Z2FVDF` rather than changing the identifiers.

- [ ] **Step 9: Commit the target and heatmap widget**

```bash
git add TokenWatch/TokenWatch.entitlements TokenWatchWidgets TokenWatch.xcodeproj/project.pbxproj TokenWatch.xcodeproj/xcshareddata/xcschemes/TokenWatchWidgets.xcscheme
git commit -m "feat(widget): 添加热力图桌面小组件"
```

### Task 9: Add the 24-Hour Line Widget

**Files:**
- Create: `TokenWatchWidgets/TokenHourlyLineWidget.swift`
- Modify: `TokenWatchWidgets/TokenWatchWidgetsBundle.swift`

**Interfaces:**
- Consumes: the same entry/provider, shared presentation, formatter, and exact popover visual constants.
- Produces: the second separately selectable `.systemMedium` Widget configuration.

- [ ] **Step 1: Re-run the line-presentation contract before UI work**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/WidgetChartPresentationTests -only-testing:TokenWatchTests/WidgetChartVisualStyleTests -only-testing:TokenWatchTests/TodayHourlyTokenLineChartViewTests -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData test
```

Expected: all contract tests pass, including 24 points, stale-marker suppression, Catmull–Rom style regressions, and zero Y maximum of 1.

- [ ] **Step 2: Implement the Swift Charts view**

Use `WidgetChartPresentationBuilder.hourlyLine(for:)` and this rendering structure:

```swift
import Charts
import SwiftUI
import WidgetKit

struct TokenHourlyLineWidgetView: View {
    let entry: WidgetUsageEntry
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let presentation = WidgetChartPresentationBuilder.hourlyLine(for: entry.state)

        VStack(spacing: 8) {
            WidgetChartHeader(
                title: presentation.title,
                subtitle: nil,
                total: presentation.totalText
            )
            ZStack {
                chart(presentation)
                    .opacity(presentation.message == nil ? 1 : 0.35)
                if let message = presentation.message {
                    Text(message)
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                        .padding(6)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    private func chart(_ presentation: WidgetHourlyLinePresentation) -> some View {
        Chart {
            ForEach(presentation.points) { point in
                AreaMark(
                    x: .value("Hour", point.hour),
                    y: .value("Tokens", point.totalTokens)
                )
                .interpolationMethod(lineInterpolationMethod)
                .foregroundStyle(areaGradient)
            }
            ForEach(presentation.points) { point in
                LineMark(
                    x: .value("Hour", point.hour),
                    y: .value("Tokens", point.totalTokens)
                )
                .interpolationMethod(lineInterpolationMethod)
                .foregroundStyle(Color.accentColor)
                .lineStyle(StrokeStyle(
                    lineWidth: CGFloat(WidgetChartVisualStyle.lineWidth),
                    lineCap: .round,
                    lineJoin: .round
                ))
            }
            if let point = presentation.currentPoint {
                PointMark(
                    x: .value("Hour", point.hour),
                    y: .value("Tokens", point.totalTokens)
                )
                .foregroundStyle(Color.accentColor)
                .symbolSize(CGFloat(WidgetChartVisualStyle.currentPointSize))
            }
        }
        .chartLegend(.hidden)
        .chartXScale(domain: 0...23)
        .chartYScale(domain: 0...presentation.maximumY)
        .chartXAxis {
            AxisMarks(values: WidgetChartVisualStyle.hourAxisValues) { value in
                AxisTick()
                AxisValueLabel {
                    if let hour = value.as(Int.self) {
                        Text("\(hour)").font(.system(size: 8))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                    .foregroundStyle(.secondary.opacity(WidgetChartVisualStyle.gridOpacity))
                AxisTick()
                AxisValueLabel {
                    if let tokens = value.as(Double.self) {
                        Text(WidgetChartNumberFormatter.axis(tokens))
                            .font(.system(size: 8))
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private var lineInterpolationMethod: InterpolationMethod {
        switch WidgetChartRendering.lineInterpolationStyle {
        case .catmullRom:
            return .catmullRom
        }
    }

    private var areaGradient: LinearGradient {
        let rgba = WidgetChartVisualStyle.heatmapRGBA(
            intensity: WidgetChartVisualStyle.heatmapMaximumIntensity,
            isDark: colorScheme == .dark
        )
        let green = Color(
            .sRGB,
            red: rgba.red,
            green: rgba.green,
            blue: rgba.blue,
            opacity: rgba.alpha
        )
        return LinearGradient(
            colors: [
                green.opacity(WidgetChartVisualStyle.areaPeakOpacity),
                green.opacity(WidgetChartVisualStyle.areaBaselineOpacity),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
```

There is no hover or tooltip in the desktop Widget. The current-hour point appears only when the presentation exposes it; stale and not-ready states expose none.

- [ ] **Step 3: Configure and register the second widget**

```swift
struct TokenHourlyLineWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: WidgetSharedConfiguration.hourlyLineKind,
            provider: WidgetTimelineProvider()
        ) { entry in
            TokenHourlyLineWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName(LocalizedStringKey("widget.hourly.name"))
        .description(LocalizedStringKey("widget.hourly.description"))
        .supportedFamilies([.systemMedium])
    }
}

@main
struct TokenWatchWidgetsBundle: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        TokenHeatmapWidget()
        TokenHourlyLineWidget()
    }
}
```

Again, preserve system margins and default host-app tap behavior; do not add a custom URL.

- [ ] **Step 4: Build both schemes**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatchWidgets -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData build
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData build
```

Expected: the extension compiles with Swift Charts and the app embeds it.

- [ ] **Step 5: Commit the hourly widget**

```bash
git add TokenWatchWidgets/TokenHourlyLineWidget.swift TokenWatchWidgets/TokenWatchWidgetsBundle.swift
git commit -m "feat(widget): 添加小时折线桌面小组件"
```

### Task 10: Full Verification and Visual Acceptance

**Files:**
- Verify only; modify implementation/tests only when a check reveals a defect.

- [ ] **Step 1: Run the entire unit-test target**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData test
```

Expected: every `TokenWatchTests` test passes. If sandboxed `testmanagerd` prevents execution, rerun with the required approval. Do not substitute `build-for-testing` for this pass claim.

- [ ] **Step 2: Build Debug and Release products**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatchWidgets -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData build
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData build
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Release -destination 'platform=macOS' -derivedDataPath .build/DerivedData build
```

Expected: all three builds succeed without availability warnings or extension-safe API violations.

- [ ] **Step 3: Inspect packaging, identifiers, and entitlements**

```bash
test -d '.build/DerivedData/Build/Products/Release/AI Token Watch.app/Contents/PlugIns/TokenWatchWidgets.appex'
plutil -extract CFBundleIdentifier raw '.build/DerivedData/Build/Products/Release/AI Token Watch.app/Contents/Info.plist'
plutil -extract CFBundleIdentifier raw '.build/DerivedData/Build/Products/Release/AI Token Watch.app/Contents/PlugIns/TokenWatchWidgets.appex/Contents/Info.plist'
codesign --verify --deep --strict --verbose=2 '.build/DerivedData/Build/Products/Release/AI Token Watch.app'
codesign -d --entitlements :- '.build/DerivedData/Build/Products/Release/AI Token Watch.app'
codesign -d --entitlements :- '.build/DerivedData/Build/Products/Release/AI Token Watch.app/Contents/PlugIns/TokenWatchWidgets.appex'
```

Expected identifiers: `com.xiaoao.tokenwatch` and `com.xiaoao.tokenwatch.widgets`. Both entitlement dumps contain `group.com.xiaoao.tokenwatch`, and strict signature verification succeeds.

- [ ] **Step 4: Perform desktop Widget acceptance on macOS 15+**

Use this order so the first-run state cannot be masked by an earlier refresh. The
commands below touch the real App Group container and therefore require the
normal out-of-sandbox approval when an agent executes them.

1. Quit TokenWatch, remove any existing TokenWatch Widget instances, and prepare
   an acceptance directory:

   ```bash
   mkdir -p /private/tmp/tokenwatch-widget-acceptance
   ```

   If the following live snapshot exists, move it aside before launching the app:

   ```bash
   mv '/Users/orrhsiao/Library/Group Containers/group.com.xiaoao.tokenwatch/widget-usage-v1.json' '/private/tmp/tokenwatch-widget-acceptance/preexisting.json'
   ```

   If it does not exist, skip only the `mv`. Add both Widget configurations from
   the gallery while TokenWatch remains closed. Confirm exactly two configurations,
   each offered only at medium size, and confirm both show a neutral graph plus the
   system-language open-TokenWatch prompt.

2. Launch the Debug app and finish one all-provider refresh. Confirm both widgets
   replace the prompt with current data. Copy this known-good snapshot before any
   mutation:

   ```bash
   cp '/Users/orrhsiao/Library/Group Containers/group.com.xiaoao.tokenwatch/widget-usage-v1.json' '/private/tmp/tokenwatch-widget-acceptance/valid.json'
   ```

   Verify a valid zero data set either with an actually empty authorized provider
   directory or the `current valid zero` fixture covered by
   `WidgetChartPresentationTests`: it must show `0` and the full zero graph, never
   the not-ready prompt. Quit the app and confirm the last valid snapshot remains.

3. Test an unsupported schema without changing any other payload field:

   ```bash
   cp '/private/tmp/tokenwatch-widget-acceptance/valid.json' '/private/tmp/tokenwatch-widget-acceptance/schema-2.json'
   plutil -replace schemaVersion -integer 2 '/private/tmp/tokenwatch-widget-acceptance/schema-2.json'
   cp '/private/tmp/tokenwatch-widget-acceptance/schema-2.json' '/Users/orrhsiao/Library/Group Containers/group.com.xiaoao.tokenwatch/widget-usage-v1.json'
   ```

   Remove and re-add one Widget instance to force a fresh timeline request. It must
   show not-ready without crashing or exposing a path. Then inject malformed JSON:

   ```bash
   printf '{invalid-json' > '/Users/orrhsiao/Library/Group Containers/group.com.xiaoao.tokenwatch/widget-usage-v1.json'
   ```

   Remove and re-add the other instance and verify the same safe state. Restore the
   known-good snapshot before continuing:

   ```bash
   cp '/private/tmp/tokenwatch-widget-acceptance/valid.json' '/Users/orrhsiao/Library/Group Containers/group.com.xiaoao.tokenwatch/widget-usage-v1.json'
   ```

   Remove and re-add both Widget instances once more (or launch TokenWatch and
   complete one refresh) so both timelines visibly return to the valid state.

4. With valid data restored, verify the remaining matrix:

   - after midnight, the line uses the dated title, heatmap shows updated-through
     copy, and no stale current-hour dot appears;
   - light and dark full-color modes match the popover's exact palette, 3-point
     spacing, 2-point radii, Catmull–Rom line, 2-point accent stroke, green area,
     and 22-point current marker;
   - system accented/vibrant rendering remains legible without custom overrides;
   - changing app language republishes text without another provider scan;
   - VoiceOver announces one aggregate summary per chart rather than 154/24
     children;
   - clicking either widget activates the main TokenWatch app.

5. Leave the refreshed `valid.json` copy installed. Keep
   `/private/tmp/tokenwatch-widget-acceptance/preexisting.json` only until all
   checks pass, then remove the temporary acceptance directory.

- [ ] **Step 5: Review the final diff and working tree**

```bash
git diff --check
git status --short
git log --oneline -10
```

Expected: no whitespace errors; only the implementation commits/files are present. The unrelated `docs/superpowers/plans/2026-07-15-codex-ui-locales.md` remains untouched.

- [ ] **Step 6: Record any verification-only fixes**

If Steps 1–5 required code/test changes, rerun the affected test plus Steps 1–3, then commit only those fixes:

Run `git status --short`, stage each verification-created path explicitly with one `git add path` command per path, then commit:

```bash
git commit -m "fix(widget): 修正桌面小组件验收问题"
```

If no files changed, do not create an empty commit.
