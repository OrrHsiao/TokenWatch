# WidgetKit Desktop Widgets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two macOS WidgetKit desktop widgets for TokenWatch: a recent 22-week token heatmap and a today hourly token line chart.

**Architecture:** The main app remains the only process that scans provider data and aggregates usage. It converts existing `CalendarHeatmapBuilder` and `MonthlyTokenChartBuilder(period: .today)` snapshots into a small shared `Codable` snapshot, writes it into an App Group container, and asks WidgetKit to reload timelines. The WidgetKit extension reads that snapshot and renders two independent SwiftUI widgets without touching security-scoped bookmarks or provider files.

**Tech Stack:** Swift 6.0, AppKit main app, SwiftUI, WidgetKit, Charts, Swift Testing, Xcode filesystem-synchronized groups.

---

## Scope Check

The spec contains three coupled subsystems: shared snapshot storage, main-app publishing, and WidgetKit rendering. They are not independent enough to split into separate specs because the widgets cannot work without the shared snapshot contract and App Group target configuration. This single plan keeps them incremental: each task either adds tested shared logic, connects the app publisher, or makes the extension buildable.

## File Structure

| 文件 | 责任 | 改动类型 |
|---|---|---|
| `TokenWatchShared/TokenWatchWidgetSnapshot.swift` | Widget 快照数据模型、示例数据、紧凑数字格式、最小 widget 文案、尺寸布局枚举 | 新增 |
| `TokenWatchShared/TokenWatchWidgetSnapshotStore.swift` | App Group JSON 快照读写 | 新增 |
| `TokenWatch/Widgets/WidgetSnapshotBuilder.swift` | 主 App 将 `TokenStatsViewModel` 状态转换为 shared widget 快照 | 新增 |
| `TokenWatch/Widgets/WidgetSnapshotPublisher.swift` | 主 App 写快照、记录日志、触发 `WidgetCenter` timeline reload | 新增 |
| `TokenWatch/ViewModels/TokenStatsViewModel.swift` | 注入 publisher,在刷新完成后发布 widget 快照 | 修改 |
| `TokenWatch/TokenWatch.entitlements` | 主 App sandbox、只读用户选择文件、App Group entitlement | 新增 |
| `TokenWatchWidgets/TokenWatchWidgets.entitlements` | Widget Extension sandbox、App Group entitlement | 新增 |
| `TokenWatchWidgets/Info.plist` | WidgetKit extension point plist | 新增 |
| `TokenWatchWidgets/TokenWatchWidgetsBundle.swift` | Widget bundle 入口 | 新增 |
| `TokenWatchWidgets/TokenWatchWidgetTimelineProvider.swift` | 共用 timeline provider | 新增 |
| `TokenWatchWidgets/TokenWatchHeatmapWidget.swift` | 热力图 widget 配置与 SwiftUI view | 新增 |
| `TokenWatchWidgets/TokenWatchTodayLineWidget.swift` | 今日折线图 widget 配置与 SwiftUI view | 新增 |
| `TokenWatchWidgets/Assets.xcassets/Contents.json` | Extension asset catalog 根文件 | 新增 |
| `TokenWatch.xcodeproj/project.pbxproj` | 新增 shared/widget groups、WidgetKit extension target、embed app extension、entitlements build settings | 修改 |
| `TokenWatchTests/Widgets/TokenWatchWidgetSnapshotTests.swift` | shared snapshot、格式化、文案、布局测试 | 新增 |
| `TokenWatchTests/Widgets/TokenWatchWidgetSnapshotStoreTests.swift` | App Group store 读写/损坏文件/无 container 测试 | 新增 |
| `TokenWatchTests/Widgets/WidgetSnapshotBuilderTests.swift` | 主 App 状态到 widget 快照的映射测试 | 新增 |
| `TokenWatchTests/ViewModels/TokenStatsViewModelObserverTests.swift` | 刷新完成后发布 widget 快照的集成测试 | 修改 |

---

### Task 1: Shared Widget Snapshot Model

**Files:**
- Create: `TokenWatchTests/Widgets/TokenWatchWidgetSnapshotTests.swift`
- Create: `TokenWatchShared/TokenWatchWidgetSnapshot.swift`
- Modify: `TokenWatch.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write the failing tests**

Create `TokenWatchTests/Widgets/TokenWatchWidgetSnapshotTests.swift`:

```swift
import Foundation
import Testing
@testable import TokenWatch

@Suite("TokenWatchWidgetSnapshot")
struct TokenWatchWidgetSnapshotTests {

    @Test("示例快照包含固定热力图单元和二十四个小时桶")
    func sampleSnapshotHasStableShape() {
        let snapshot = TokenWatchWidgetSnapshot.sample(
            generatedAt: Date(timeIntervalSince1970: 1_779_811_200),
            languageIdentifier: "zh-Hans"
        )

        #expect(snapshot.status == .ready)
        #expect(snapshot.languageIdentifier == "zh-Hans")
        #expect(snapshot.heatmap.cells.count == 154)
        #expect(snapshot.todayLine.buckets.count == 24)
        #expect(snapshot.todayLine.currentHourKey == "2026-06-27T14")
    }

    @Test("空快照可以表达未授权状态")
    func emptySnapshotCanRepresentNeedsAuthorization() {
        let snapshot = TokenWatchWidgetSnapshot.empty(
            generatedAt: Date(timeIntervalSince1970: 1_779_811_200),
            languageIdentifier: "en",
            status: .needsAuthorization
        )

        #expect(snapshot.status == .needsAuthorization)
        #expect(snapshot.heatmap.cells.count == 154)
        #expect(snapshot.heatmap.summary.todayTokens == 0)
        #expect(snapshot.todayLine.totalTokens == 0)
        #expect(snapshot.todayLine.buckets.allSatisfy { $0.totalTokens == 0 })
    }

    @Test("紧凑数字格式与状态栏格式一致")
    func compactFormatterMatchesStatusBarRules() {
        #expect(TokenWatchWidgetCompactNumberFormatter.format(0) == "0")
        #expect(TokenWatchWidgetCompactNumberFormatter.format(999) == "999")
        #expect(TokenWatchWidgetCompactNumberFormatter.format(12_345) == "12.3k")
        #expect(TokenWatchWidgetCompactNumberFormatter.format(1_234_567) == "1.2M")
        #expect(TokenWatchWidgetCompactNumberFormatter.formatHoverTokens(99_999) == "99.9k")
        #expect(TokenWatchWidgetCompactNumberFormatter.formatHoverTokens(100_000) == "0.1M")
    }

    @Test("Widget 文案按快照语言回退")
    func widgetCopyUsesSnapshotLanguage() {
        #expect(TokenWatchWidgetCopy.text(.openAppToAuthorize, languageIdentifier: "zh-Hans") == "打开 TokenWatch 完成授权")
        #expect(TokenWatchWidgetCopy.text(.openAppToAuthorize, languageIdentifier: "zh-Hant") == "開啟 TokenWatch 完成授權")
        #expect(TokenWatchWidgetCopy.text(.openAppToAuthorize, languageIdentifier: "fr") == "Open TokenWatch to authorize")
        #expect(TokenWatchWidgetCopy.text(.today, languageIdentifier: "zh-Hans") == "今日")
        #expect(TokenWatchWidgetCopy.text(.today, languageIdentifier: "en") == "Today")
    }

    @Test("Widget 尺寸映射到稳定布局")
    func widgetFamilyLayoutMappingIsStable() {
        #expect(TokenWatchHeatmapWidgetLayout.layout(for: .small) == .compact)
        #expect(TokenWatchHeatmapWidgetLayout.layout(for: .medium) == .summary)
        #expect(TokenWatchHeatmapWidgetLayout.layout(for: .large) == .expanded)
        #expect(TokenWatchTodayLineWidgetLayout.layout(for: .small) == .compact)
        #expect(TokenWatchTodayLineWidgetLayout.layout(for: .medium) == .chart)
        #expect(TokenWatchTodayLineWidgetLayout.layout(for: .large) == .expanded)
    }
}
```

- [ ] **Step 2: Run the tests and verify they fail**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/TokenWatchWidgetSnapshotTests test
```

Expected: FAIL with compile errors such as `Cannot find 'TokenWatchWidgetSnapshot' in scope`.

- [ ] **Step 3: Add the shared snapshot model and include it in the app target**

Create `TokenWatchShared/TokenWatchWidgetSnapshot.swift`:

```swift
import Foundation

enum TokenWatchWidgetDataStatus: String, Codable, Equatable, Sendable {
    case ready
    case needsAuthorization
    case empty
}

struct TokenWatchWidgetSnapshot: Codable, Equatable, Sendable {
    let generatedAt: Date
    let languageIdentifier: String
    let status: TokenWatchWidgetDataStatus
    let heatmap: TokenWatchWidgetHeatmapSnapshot
    let todayLine: TokenWatchWidgetTodayLineSnapshot

    static func empty(
        generatedAt: Date = Date(),
        languageIdentifier: String = "zh-Hans",
        status: TokenWatchWidgetDataStatus = .empty
    ) -> TokenWatchWidgetSnapshot {
        TokenWatchWidgetSnapshot(
            generatedAt: generatedAt,
            languageIdentifier: languageIdentifier,
            status: status,
            heatmap: .empty(title: TokenWatchWidgetCopy.text(.recent22Weeks, languageIdentifier: languageIdentifier)),
            todayLine: .empty()
        )
    }

    static func sample(
        generatedAt: Date = Date(),
        languageIdentifier: String = "zh-Hans"
    ) -> TokenWatchWidgetSnapshot {
        let heatmapCells = (0..<154).map { index in
            TokenWatchWidgetHeatmapCell(
                id: "sample-\(index)",
                kind: .day,
                dateKey: "2026-06-\((index % 27) + 1)",
                totalTokens: index % 5 == 0 ? 0 : (index + 1) * 12_345,
                intensity: index % 5,
                isToday: index == 153,
                isFuture: false
            )
        }
        let hourlyBuckets = (0..<24).map { hour in
            TokenWatchWidgetTodayLineBucket(
                id: String(format: "2026-06-27T%02d", hour),
                hourKey: String(format: "2026-06-27T%02d", hour),
                hourLabel: "\(hour)",
                totalTokens: hour <= 14 ? (hour + 1) * 42_000 : 0,
                normalizedHeight: hour <= 14 ? Double(hour + 1) / 15.0 : 0,
                isCurrentHour: hour == 14
            )
        }

        return TokenWatchWidgetSnapshot(
            generatedAt: generatedAt,
            languageIdentifier: languageIdentifier,
            status: .ready,
            heatmap: TokenWatchWidgetHeatmapSnapshot(
                title: TokenWatchWidgetCopy.text(.recent22Weeks, languageIdentifier: languageIdentifier),
                summary: TokenWatchWidgetHeatmapSummary(
                    monthTokens: 3_200_000,
                    weekTokens: 820_000,
                    todayTokens: 630_000,
                    averageDailyTokens: 118_000
                ),
                cells: heatmapCells,
                maxDailyTokens: 1_900_000
            ),
            todayLine: TokenWatchWidgetTodayLineSnapshot(
                totalTokens: hourlyBuckets.reduce(0) { $0 + $1.totalTokens },
                maxHourlyTokens: hourlyBuckets.map(\.totalTokens).max() ?? 0,
                currentHourKey: "2026-06-27T14",
                buckets: hourlyBuckets
            )
        )
    }
}

struct TokenWatchWidgetHeatmapSnapshot: Codable, Equatable, Sendable {
    let title: String
    let summary: TokenWatchWidgetHeatmapSummary
    let cells: [TokenWatchWidgetHeatmapCell]
    let maxDailyTokens: Int

    static func empty(title: String) -> TokenWatchWidgetHeatmapSnapshot {
        TokenWatchWidgetHeatmapSnapshot(
            title: title,
            summary: TokenWatchWidgetHeatmapSummary(
                monthTokens: 0,
                weekTokens: 0,
                todayTokens: 0,
                averageDailyTokens: 0
            ),
            cells: (0..<154).map {
                TokenWatchWidgetHeatmapCell(
                    id: "empty-\($0)",
                    kind: .placeholder,
                    dateKey: nil,
                    totalTokens: 0,
                    intensity: 0,
                    isToday: false,
                    isFuture: false
                )
            },
            maxDailyTokens: 0
        )
    }
}

struct TokenWatchWidgetHeatmapSummary: Codable, Equatable, Sendable {
    let monthTokens: Int
    let weekTokens: Int
    let todayTokens: Int
    let averageDailyTokens: Int
}

enum TokenWatchWidgetHeatmapCellKind: String, Codable, Equatable, Sendable {
    case placeholder
    case day
}

struct TokenWatchWidgetHeatmapCell: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let kind: TokenWatchWidgetHeatmapCellKind
    let dateKey: String?
    let totalTokens: Int
    let intensity: Int
    let isToday: Bool
    let isFuture: Bool
}

struct TokenWatchWidgetTodayLineSnapshot: Codable, Equatable, Sendable {
    let totalTokens: Int
    let maxHourlyTokens: Int
    let currentHourKey: String?
    let buckets: [TokenWatchWidgetTodayLineBucket]

    static func empty() -> TokenWatchWidgetTodayLineSnapshot {
        let buckets = (0..<24).map { hour in
            TokenWatchWidgetTodayLineBucket(
                id: String(format: "empty-%02d", hour),
                hourKey: String(format: "empty-%02d", hour),
                hourLabel: "\(hour)",
                totalTokens: 0,
                normalizedHeight: 0,
                isCurrentHour: false
            )
        }
        return TokenWatchWidgetTodayLineSnapshot(
            totalTokens: 0,
            maxHourlyTokens: 0,
            currentHourKey: nil,
            buckets: buckets
        )
    }
}

struct TokenWatchWidgetTodayLineBucket: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let hourKey: String
    let hourLabel: String
    let totalTokens: Int
    let normalizedHeight: Double
    let isCurrentHour: Bool
}

enum TokenWatchWidgetCompactNumberFormatter {
    static func format(_ value: Int) -> String {
        guard value > 0 else { return "0" }
        if value < 1_000 {
            return String(value)
        }
        if value < 1_000_000 {
            let tenths = value / 100
            return "\(tenths / 10).\(tenths % 10)k"
        }
        let tenths = value / 100_000
        return "\(tenths / 10).\(tenths % 10)M"
    }

    static func formatMillions(_ value: Int) -> String {
        let tenths = max(value, 0) / 100_000
        return "\(tenths / 10).\(tenths % 10)M"
    }

    static func formatHoverTokens(_ value: Int) -> String {
        let safeValue = max(value, 0)
        if safeValue > 0 && safeValue < 100_000 {
            let tenths = safeValue / 100
            return "\(tenths / 10).\(tenths % 10)k"
        }
        return formatMillions(safeValue)
    }
}

enum TokenWatchWidgetCopyKey: Hashable, Sendable {
    case recent22Weeks
    case month
    case week
    case today
    case dailyAverage
    case updated
    case openAppToAuthorize
    case waitingForRefresh
    case noTokenData
    case dataMayBeStale
    case tokenHeatmapDisplayName
    case tokenHeatmapDescription
    case todayLineDisplayName
    case todayLineDescription
}

enum TokenWatchWidgetCopy {
    static func text(_ key: TokenWatchWidgetCopyKey, languageIdentifier: String) -> String {
        let normalized = languageIdentifier.lowercased()
        if normalized.hasPrefix("zh-hant") {
            return zhHant[key] ?? en[key] ?? String(describing: key)
        }
        if normalized.hasPrefix("zh") {
            return zhHans[key] ?? en[key] ?? String(describing: key)
        }
        return en[key] ?? String(describing: key)
    }

    private static let zhHans: [TokenWatchWidgetCopyKey: String] = [
        .recent22Weeks: "最近 22 周",
        .month: "本月",
        .week: "本周",
        .today: "今日",
        .dailyAverage: "日均",
        .updated: "更新于",
        .openAppToAuthorize: "打开 TokenWatch 完成授权",
        .waitingForRefresh: "等待 TokenWatch 刷新",
        .noTokenData: "暂无 token 数据",
        .dataMayBeStale: "数据可能不是最新",
        .tokenHeatmapDisplayName: "Token 热力图",
        .tokenHeatmapDescription: "查看最近 22 周 token 用量热力图。",
        .todayLineDisplayName: "今日 Token",
        .todayLineDescription: "查看今日每小时 token 用量趋势。",
    ]

    private static let zhHant: [TokenWatchWidgetCopyKey: String] = [
        .recent22Weeks: "最近 22 週",
        .month: "本月",
        .week: "本週",
        .today: "今日",
        .dailyAverage: "日均",
        .updated: "更新於",
        .openAppToAuthorize: "開啟 TokenWatch 完成授權",
        .waitingForRefresh: "等待 TokenWatch 重新整理",
        .noTokenData: "暫無 token 資料",
        .dataMayBeStale: "資料可能不是最新",
        .tokenHeatmapDisplayName: "Token 熱力圖",
        .tokenHeatmapDescription: "查看最近 22 週 token 用量熱力圖。",
        .todayLineDisplayName: "今日 Token",
        .todayLineDescription: "查看今日每小時 token 用量趨勢。",
    ]

    private static let en: [TokenWatchWidgetCopyKey: String] = [
        .recent22Weeks: "Recent 22 Weeks",
        .month: "Month",
        .week: "Week",
        .today: "Today",
        .dailyAverage: "Daily Avg",
        .updated: "Updated",
        .openAppToAuthorize: "Open TokenWatch to authorize",
        .waitingForRefresh: "Waiting for TokenWatch to refresh",
        .noTokenData: "No token data",
        .dataMayBeStale: "Data may be stale",
        .tokenHeatmapDisplayName: "Token Heatmap",
        .tokenHeatmapDescription: "See token usage over the recent 22 weeks.",
        .todayLineDisplayName: "Today Tokens",
        .todayLineDescription: "See today's hourly token usage trend.",
    ]
}

enum TokenWatchWidgetDisplayFamily: Sendable {
    case small
    case medium
    case large
}

enum TokenWatchHeatmapWidgetLayout: Equatable, Sendable {
    case compact
    case summary
    case expanded

    static func layout(for family: TokenWatchWidgetDisplayFamily) -> TokenWatchHeatmapWidgetLayout {
        switch family {
        case .small:
            return .compact
        case .medium:
            return .summary
        case .large:
            return .expanded
        }
    }
}

enum TokenWatchTodayLineWidgetLayout: Equatable, Sendable {
    case compact
    case chart
    case expanded

    static func layout(for family: TokenWatchWidgetDisplayFamily) -> TokenWatchTodayLineWidgetLayout {
        switch family {
        case .small:
            return .compact
        case .medium:
            return .chart
        case .large:
            return .expanded
        }
    }
}
```

Patch `TokenWatch.xcodeproj/project.pbxproj` so `TokenWatchShared` is compiled by the app target before the tests run.

Add to `PBXFileSystemSynchronizedRootGroup section`:

```text
		AAB000000000000000000002 /* TokenWatchShared */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = TokenWatchShared;
			sourceTree = "<group>";
		};
```

In the main `PBXGroup` children list, add:

```text
				AAB000000000000000000002 /* TokenWatchShared */,
```

In the `TokenWatch` native target `fileSystemSynchronizedGroups`, add:

```text
				AAB000000000000000000002 /* TokenWatchShared */,
```

- [ ] **Step 4: Run the tests and verify they pass**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/TokenWatchWidgetSnapshotTests test
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add TokenWatchShared/TokenWatchWidgetSnapshot.swift TokenWatchTests/Widgets/TokenWatchWidgetSnapshotTests.swift TokenWatch.xcodeproj/project.pbxproj
git commit -m "feat(widget): 新增小组件共享快照模型"
```

---

### Task 2: App Group Snapshot Store

**Files:**
- Create: `TokenWatchTests/Widgets/TokenWatchWidgetSnapshotStoreTests.swift`
- Create: `TokenWatchShared/TokenWatchWidgetSnapshotStore.swift`

- [ ] **Step 1: Write the failing store tests**

Create `TokenWatchTests/Widgets/TokenWatchWidgetSnapshotStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import TokenWatch

@Suite("TokenWatchWidgetSnapshotStore")
struct TokenWatchWidgetSnapshotStoreTests {

    @Test("写入后可以读取同一份 JSON 快照")
    func writeThenReadSnapshot() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TokenWatchWidgetSnapshotStore(containerURLProvider: { directory })
        let snapshot = TokenWatchWidgetSnapshot.sample(
            generatedAt: Date(timeIntervalSince1970: 1_779_811_200),
            languageIdentifier: "en"
        )

        try store.write(snapshot)
        let decoded = try #require(store.read())
        let fileURL = try store.snapshotFileURL()

        #expect(decoded == snapshot)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test("缺失文件返回 nil 而不是崩溃")
    func missingFileReturnsNil() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TokenWatchWidgetSnapshotStore(containerURLProvider: { directory })

        #expect(store.read() == nil)
    }

    @Test("损坏 JSON 返回 nil")
    func corruptedJSONReturnsNil() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TokenWatchWidgetSnapshotStore(containerURLProvider: { directory })
        let fileURL = try store.snapshotFileURL()
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: fileURL)

        #expect(store.read() == nil)
    }

    @Test("App Group container 不可用时写入抛出明确错误")
    func unavailableContainerThrows() {
        let store = TokenWatchWidgetSnapshotStore(containerURLProvider: { nil })
        let snapshot = TokenWatchWidgetSnapshot.empty()

        do {
            try store.write(snapshot)
            Issue.record("Expected appGroupContainerUnavailable")
        } catch let error as TokenWatchWidgetSnapshotStoreError {
            #expect(error == .appGroupContainerUnavailable)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenWatchWidgetSnapshotStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
```

- [ ] **Step 2: Run the tests and verify they fail**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/TokenWatchWidgetSnapshotStoreTests test
```

Expected: FAIL with compile errors such as `Cannot find 'TokenWatchWidgetSnapshotStore' in scope`.

- [ ] **Step 3: Implement the store**

Create `TokenWatchShared/TokenWatchWidgetSnapshotStore.swift`:

```swift
import Foundation

enum TokenWatchWidgetSnapshotStoreError: Error, Equatable {
    case appGroupContainerUnavailable
}

struct TokenWatchWidgetSnapshotStore {
    static let appGroupIdentifier = "group.com.xiaoao.TokenWatch"
    private static let snapshotsDirectoryName = "WidgetSnapshots"
    private static let latestSnapshotFileName = "latest.json"

    private let fileManager: FileManager
    private let containerURLProvider: () -> URL?

    init(
        fileManager: FileManager = .default,
        containerURLProvider: @escaping () -> URL? = {
            FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: TokenWatchWidgetSnapshotStore.appGroupIdentifier
            )
        }
    ) {
        self.fileManager = fileManager
        self.containerURLProvider = containerURLProvider
    }

    func read() -> TokenWatchWidgetSnapshot? {
        guard let fileURL = try? snapshotFileURL(),
              fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(TokenWatchWidgetSnapshot.self, from: data)
    }

    func write(_ snapshot: TokenWatchWidgetSnapshot) throws {
        let fileURL = try snapshotFileURL()
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        let temporaryURL = directoryURL.appendingPathComponent("latest-\(UUID().uuidString).json")

        try data.write(to: temporaryURL, options: .atomic)
        if fileManager.fileExists(atPath: fileURL.path) {
            _ = try fileManager.replaceItemAt(fileURL, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: fileURL)
        }
    }

    func snapshotFileURL() throws -> URL {
        guard let containerURL = containerURLProvider() else {
            throw TokenWatchWidgetSnapshotStoreError.appGroupContainerUnavailable
        }

        return containerURL
            .appendingPathComponent(Self.snapshotsDirectoryName, isDirectory: true)
            .appendingPathComponent(Self.latestSnapshotFileName)
    }
}
```

- [ ] **Step 4: Run the store tests**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/TokenWatchWidgetSnapshotStoreTests test
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add TokenWatchShared/TokenWatchWidgetSnapshotStore.swift TokenWatchTests/Widgets/TokenWatchWidgetSnapshotStoreTests.swift
git commit -m "feat(widget): 增加小组件快照存储"
```

---

### Task 3: Main-App Snapshot Builder

**Files:**
- Create: `TokenWatchTests/Widgets/WidgetSnapshotBuilderTests.swift`
- Create: `TokenWatch/Widgets/WidgetSnapshotBuilder.swift`

- [ ] **Step 1: Write the failing builder tests**

Create `TokenWatchTests/Widgets/WidgetSnapshotBuilderTests.swift`:

```swift
import Foundation
import Testing
@testable import TokenWatch

@MainActor
@Suite("WidgetSnapshotBuilder")
struct WidgetSnapshotBuilderTests {

    @Test("有 token 数据时构建 ready 快照")
    func buildsReadySnapshotFromProviderStates() throws {
        let now = try #require(Self.date("2026-06-27T14:30:00Z"))
        let states: [ProviderID: TokenStatsViewModel.ProviderState] = [
            .claude: TokenStatsViewModel.ProviderState(
                stats: stats(dayTokens: 100_000, hourTokens: 25_000),
                isLoading: false,
                errorMessage: nil,
                needsAuthorization: false
            )
        ]

        let snapshot = WidgetSnapshotBuilder.build(
            states: states,
            now: now,
            calendar: Self.utcCalendar,
            language: .zhHans
        )

        #expect(snapshot.status == .ready)
        #expect(snapshot.languageIdentifier == "zh-Hans")
        #expect(snapshot.heatmap.cells.count == 154)
        #expect(snapshot.heatmap.summary.todayTokens == 100_000)
        #expect(snapshot.todayLine.buckets.count == 24)
        #expect(snapshot.todayLine.totalTokens == 25_000)
        #expect(snapshot.todayLine.currentHourKey == "2026-06-27T14")
        #expect(snapshot.todayLine.buckets[14].isCurrentHour)
    }

    @Test("全部 provider 未授权时构建 needsAuthorization 快照")
    func buildsNeedsAuthorizationSnapshot() throws {
        let now = try #require(Self.date("2026-06-27T14:30:00Z"))
        let states: [ProviderID: TokenStatsViewModel.ProviderState] = [
            .claude: TokenStatsViewModel.ProviderState(stats: nil, isLoading: false, errorMessage: nil, needsAuthorization: true),
            .codex: TokenStatsViewModel.ProviderState(stats: nil, isLoading: false, errorMessage: nil, needsAuthorization: true),
            .opencode: TokenStatsViewModel.ProviderState(stats: nil, isLoading: false, errorMessage: nil, needsAuthorization: true),
        ]

        let snapshot = WidgetSnapshotBuilder.build(
            states: states,
            now: now,
            calendar: Self.utcCalendar,
            language: .en
        )

        #expect(snapshot.status == .needsAuthorization)
        #expect(snapshot.languageIdentifier == "en")
        #expect(snapshot.heatmap.cells.count == 154)
        #expect(snapshot.todayLine.buckets.count == 24)
    }

    @Test("已授权但无 token 数据时构建 empty 快照")
    func buildsEmptySnapshotWhenAuthorizedButNoTokens() throws {
        let now = try #require(Self.date("2026-06-27T14:30:00Z"))
        let states: [ProviderID: TokenStatsViewModel.ProviderState] = [
            .claude: TokenStatsViewModel.ProviderState(
                stats: .zero,
                isLoading: false,
                errorMessage: nil,
                needsAuthorization: false
            )
        ]

        let snapshot = WidgetSnapshotBuilder.build(
            states: states,
            now: now,
            calendar: Self.utcCalendar,
            language: .en
        )

        #expect(snapshot.status == .empty)
        #expect(snapshot.todayLine.totalTokens == 0)
        #expect(snapshot.todayLine.maxHourlyTokens == 0)
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 1
        return calendar
    }

    private static func date(_ string: String) -> Date? {
        ISO8601DateFormatter().date(from: string)
    }

    private func stats(dayTokens: Int, hourTokens: Int) -> AggregatedStats {
        let daySummary = summary(totalTokens: dayTokens)
        let hourSummary = summary(totalTokens: hourTokens)
        return AggregatedStats(
            overall: summary(totalTokens: dayTokens),
            byHour: ["2026-06-27T14": hourSummary],
            byDay: ["2026-06-27": daySummary],
            byWeek: ["2026-W26": daySummary],
            byMonth: ["2026-06": daySummary],
            bySession: [:],
            byModel: [:],
            byProject: [:],
            dataSourceCount: 1
        )
    }

    private func summary(totalTokens: Int) -> UsageSummary {
        UsageSummary(
            inputTokens: totalTokens,
            outputTokens: 0,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            reasoningTokens: 0,
            totalTokens: totalTokens,
            cost: 0,
            entryCount: totalTokens > 0 ? 1 : 0,
            modelBreakdown: [:]
        )
    }
}
```

- [ ] **Step 2: Run the builder tests and verify they fail**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/WidgetSnapshotBuilderTests test
```

Expected: FAIL with compile error `Cannot find 'WidgetSnapshotBuilder' in scope`.

- [ ] **Step 3: Implement the builder**

Create `TokenWatch/Widgets/WidgetSnapshotBuilder.swift`:

```swift
import Foundation

@MainActor
enum WidgetSnapshotBuilder {
    static func build(
        states: [ProviderID: TokenStatsViewModel.ProviderState],
        now: Date,
        calendar: Calendar,
        language: AppLanguage
    ) -> TokenWatchWidgetSnapshot {
        let heatmapSnapshot = CalendarHeatmapBuilder.build(
            states: states,
            month: now,
            now: now,
            calendar: calendar,
            language: language
        )
        let todaySnapshot = MonthlyTokenChartBuilder.build(
            states: states,
            period: .today,
            now: now,
            calendar: calendar,
            language: language
        )
        let status = dataStatus(states: states, totalTokens: todaySnapshot.totalTokens + heatmapSnapshot.summary.monthTokens)

        return TokenWatchWidgetSnapshot(
            generatedAt: now,
            languageIdentifier: language.rawValue,
            status: status,
            heatmap: TokenWatchWidgetHeatmapSnapshot(
                title: heatmapSnapshot.monthTitle,
                summary: TokenWatchWidgetHeatmapSummary(
                    monthTokens: heatmapSnapshot.summary.monthTokens,
                    weekTokens: heatmapSnapshot.summary.weekTokens,
                    todayTokens: heatmapSnapshot.summary.todayTokens,
                    averageDailyTokens: heatmapSnapshot.summary.averageDailyTokens
                ),
                cells: heatmapSnapshot.cells.map(widgetCell),
                maxDailyTokens: heatmapSnapshot.maxDailyTokens
            ),
            todayLine: TokenWatchWidgetTodayLineSnapshot(
                totalTokens: todaySnapshot.totalTokens,
                maxHourlyTokens: todaySnapshot.maxMonthlyTokens,
                currentHourKey: todaySnapshot.monthBuckets.first(where: \.isCurrentMonth)?.monthKey,
                buckets: todaySnapshot.monthBuckets.map { bucket in
                    TokenWatchWidgetTodayLineBucket(
                        id: bucket.id,
                        hourKey: bucket.monthKey,
                        hourLabel: bucket.monthLabel,
                        totalTokens: bucket.totalTokens,
                        normalizedHeight: clamp(bucket.normalizedHeight),
                        isCurrentHour: bucket.isCurrentMonth
                    )
                }
            )
        )
    }

    private static func dataStatus(
        states: [ProviderID: TokenStatsViewModel.ProviderState],
        totalTokens: Int
    ) -> TokenWatchWidgetDataStatus {
        let hasStats = states.values.contains { $0.stats != nil }
        let allKnownProvidersNeedAuthorization = !states.isEmpty
            && states.values.allSatisfy { $0.needsAuthorization && $0.stats == nil }

        if allKnownProvidersNeedAuthorization {
            return .needsAuthorization
        }

        if !hasStats || totalTokens <= 0 {
            return .empty
        }

        return .ready
    }

    private static func widgetCell(_ cell: CalendarHeatmapCell) -> TokenWatchWidgetHeatmapCell {
        switch cell {
        case .placeholder(let id):
            return TokenWatchWidgetHeatmapCell(
                id: id,
                kind: .placeholder,
                dateKey: nil,
                totalTokens: 0,
                intensity: 0,
                isToday: false,
                isFuture: false
            )
        case .day(let day):
            return TokenWatchWidgetHeatmapCell(
                id: day.id,
                kind: .day,
                dateKey: day.dateKey,
                totalTokens: day.totalTokens,
                intensity: day.intensity,
                isToday: day.isToday,
                isFuture: day.isFuture
            )
        }
    }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}
```

- [ ] **Step 4: Run the builder tests**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/WidgetSnapshotBuilderTests test
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add TokenWatch/Widgets/WidgetSnapshotBuilder.swift TokenWatchTests/Widgets/WidgetSnapshotBuilderTests.swift
git commit -m "feat(widget): 构建小组件展示快照"
```

---

### Task 4: Publish Snapshots From TokenStatsViewModel

**Files:**
- Create: `TokenWatch/Widgets/WidgetSnapshotPublisher.swift`
- Modify: `TokenWatch/ViewModels/TokenStatsViewModel.swift`
- Modify: `TokenWatchTests/ViewModels/TokenStatsViewModelObserverTests.swift`

- [ ] **Step 1: Add failing publisher integration tests**

Append these tests inside `TokenStatsViewModelObserverTests` before the closing brace:

```swift
    @Test func singleProviderLoadPublishesWidgetSnapshotAfterStateSettles() async {
        let publisher = RecordingWidgetSnapshotPublisher()
        let vm = TokenStatsViewModel(widgetSnapshotPublisher: publisher)

        await vm.loadStats(for: .claude)

        #expect(publisher.publishCount == 1)
        #expect(publisher.lastStates?[.claude]?.needsAuthorization == true)
        #expect(publisher.lastStates?[.claude]?.isLoading == false)
    }

    @Test func loadAllStatsPublishesWidgetSnapshotOnce() async {
        let publisher = RecordingWidgetSnapshotPublisher()
        let vm = TokenStatsViewModel(widgetSnapshotPublisher: publisher)

        await vm.loadAllStats()

        #expect(publisher.publishCount == 1)
        #expect(Set(publisher.lastStates?.keys ?? []) == Set(ProviderID.allCases))
        #expect(publisher.lastStates?.values.allSatisfy { $0.isLoading == false } == true)
    }
```

Add this helper after `StubLocalizedError`:

```swift
@MainActor
private final class RecordingWidgetSnapshotPublisher: WidgetSnapshotPublishing {
    private(set) var publishCount = 0
    private(set) var lastStates: [ProviderID: TokenStatsViewModel.ProviderState]?

    func publish(states: [ProviderID: TokenStatsViewModel.ProviderState]) {
        publishCount += 1
        lastStates = states
    }
}
```

- [ ] **Step 2: Run the tests and verify they fail**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/TokenStatsViewModelObserverTests test
```

Expected: FAIL with compile errors for missing `WidgetSnapshotPublishing` and missing `TokenStatsViewModel(widgetSnapshotPublisher:)`.

- [ ] **Step 3: Add the publisher**

Create `TokenWatch/Widgets/WidgetSnapshotPublisher.swift`:

```swift
import Foundation
import os.log
import WidgetKit

@MainActor
protocol WidgetSnapshotPublishing: AnyObject, Sendable {
    func publish(states: [ProviderID: TokenStatsViewModel.ProviderState])
}

@MainActor
protocol WidgetTimelineReloading: AnyObject, Sendable {
    func reloadAllTimelines()
}

@MainActor
final class SystemWidgetTimelineReloader: WidgetTimelineReloading {
    func reloadAllTimelines() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}

@MainActor
final class WidgetSnapshotPublisher: WidgetSnapshotPublishing {
    static let shared = WidgetSnapshotPublisher()

    private let store: TokenWatchWidgetSnapshotStore
    private let reloader: WidgetTimelineReloading
    private let nowProvider: () -> Date
    private let calendar: Calendar
    private let languageSettings: AppLanguageSettings
    private let logger = Logger(subsystem: "com.xiaoao.TokenWatch", category: "WidgetSnapshotPublisher")

    init(
        store: TokenWatchWidgetSnapshotStore = TokenWatchWidgetSnapshotStore(),
        reloader: WidgetTimelineReloading = SystemWidgetTimelineReloader(),
        nowProvider: @escaping () -> Date = Date.init,
        calendar: Calendar = .current,
        languageSettings: AppLanguageSettings = .shared
    ) {
        self.store = store
        self.reloader = reloader
        self.nowProvider = nowProvider
        self.calendar = calendar
        self.languageSettings = languageSettings
    }

    func publish(states: [ProviderID: TokenStatsViewModel.ProviderState]) {
        let snapshot = WidgetSnapshotBuilder.build(
            states: states,
            now: nowProvider(),
            calendar: calendar,
            language: languageSettings.resolvedLanguage
        )

        do {
            try store.write(snapshot)
            logger.info("Widget 快照已写入,status=\(snapshot.status.rawValue),generatedAt=\(snapshot.generatedAt.ISO8601Format())")
            reloader.reloadAllTimelines()
        } catch {
            logger.error("Widget 快照写入失败: \(error.localizedDescription)")
        }
    }
}
```

- [ ] **Step 4: Inject the publisher into `TokenStatsViewModel`**

Modify `TokenWatch/ViewModels/TokenStatsViewModel.swift`:

```swift
    private let widgetSnapshotPublisher: WidgetSnapshotPublishing
    private var widgetSnapshotPublishSuspensionDepth = 0
```

Replace the initializer with:

```swift
    init(
        languageSettings: AppLanguageSettings = .shared,
        widgetSnapshotPublisher: WidgetSnapshotPublishing = WidgetSnapshotPublisher.shared
    ) {
        self.languageSettings = languageSettings
        self.widgetSnapshotPublisher = widgetSnapshotPublisher
        for provider in ProviderRegistry.allProviders {
            states[provider.id] = ProviderState()
        }
    }
```

Replace `loadAllStats()` with:

```swift
    /// 启动时并发触发所有 provider 的 loadStats
    /// 设计原因:Swift 6 region-based isolation checker 在 `withTaskGroup` 闭包中
    /// 显式标 `@MainActor [weak self]` 时会崩(编译器内部错误);
    /// 改为 `await self.loadStats(...)` 让 main actor 自动 hop,行为等价且 self 由 AppDelegate 持有不会循环引用。
    func loadAllStats() async {
        widgetSnapshotPublishSuspensionDepth += 1
        defer {
            widgetSnapshotPublishSuspensionDepth -= 1
            publishWidgetSnapshotIfAllowed()
        }

        await withTaskGroup(of: Void.self) { group in
            for provider in ProviderRegistry.allProviders {
                let id = provider.id
                group.addTask {
                    await self.loadStats(for: id)
                }
            }
        }
    }
```

In `loadStats(for:)`, replace:

```swift
        defer { loadGate.leave(id) }
```

with:

```swift
        defer {
            loadGate.leave(id)
            publishWidgetSnapshotIfAllowed()
        }
```

Add this helper before `markProvidersAuthorized(sharingBookmarkWith:)`:

```swift
    private func publishWidgetSnapshotIfAllowed() {
        guard widgetSnapshotPublishSuspensionDepth == 0 else { return }
        widgetSnapshotPublisher.publish(states: states)
    }
```

- [ ] **Step 5: Run the ViewModel tests**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/TokenStatsViewModelObserverTests test
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add TokenWatch/Widgets/WidgetSnapshotPublisher.swift TokenWatch/ViewModels/TokenStatsViewModel.swift TokenWatchTests/ViewModels/TokenStatsViewModelObserverTests.swift
git commit -m "feat(widget): 刷新后发布小组件快照"
```

---

### Task 5: Add WidgetKit Extension Target

**Files:**
- Create: `TokenWatch/TokenWatch.entitlements`
- Create: `TokenWatchWidgets/TokenWatchWidgets.entitlements`
- Create: `TokenWatchWidgets/Info.plist`
- Create: `TokenWatchWidgets/Assets.xcassets/Contents.json`
- Create: `TokenWatchWidgets/TokenWatchWidgetsBundle.swift`
- Create: `TokenWatchWidgets/TokenWatchWidgetTimelineProvider.swift`
- Create: `TokenWatchWidgets/TokenWatchHeatmapWidget.swift`
- Create: `TokenWatchWidgets/TokenWatchTodayLineWidget.swift`
- Modify: `TokenWatch.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add entitlements and extension plist files**

Create `TokenWatch/TokenWatch.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.files.user-selected.read-only</key>
	<true/>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.com.xiaoao.TokenWatch</string>
	</array>
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
		<string>group.com.xiaoao.TokenWatch</string>
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

Create `TokenWatchWidgets/Assets.xcassets/Contents.json`:

```json
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

- [ ] **Step 2: Add minimal buildable widget Swift files**

Create `TokenWatchWidgets/TokenWatchWidgetsBundle.swift`:

```swift
import SwiftUI
import WidgetKit

@main
struct TokenWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TokenWatchHeatmapWidget()
        TokenWatchTodayLineWidget()
    }
}
```

Create `TokenWatchWidgets/TokenWatchWidgetTimelineProvider.swift`:

```swift
import Foundation
import WidgetKit

struct TokenWatchWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: TokenWatchWidgetSnapshot
}

struct TokenWatchWidgetTimelineProvider: TimelineProvider {
    var store = TokenWatchWidgetSnapshotStore()

    func placeholder(in context: Context) -> TokenWatchWidgetEntry {
        TokenWatchWidgetEntry(date: Date(), snapshot: .sample())
    }

    func getSnapshot(in context: Context, completion: @escaping (TokenWatchWidgetEntry) -> Void) {
        let snapshot = store.read() ?? TokenWatchWidgetSnapshot.empty(status: .empty)
        completion(TokenWatchWidgetEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TokenWatchWidgetEntry>) -> Void) {
        let now = Date()
        let snapshot = store.read() ?? TokenWatchWidgetSnapshot.empty(generatedAt: now, status: .empty)
        let entry = TokenWatchWidgetEntry(date: now, snapshot: snapshot)
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: now) ?? now.addingTimeInterval(1_800)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}
```

Create `TokenWatchWidgets/TokenWatchHeatmapWidget.swift`:

```swift
import SwiftUI
import WidgetKit

struct TokenWatchHeatmapWidget: Widget {
    private let kind = "TokenWatchHeatmapWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TokenWatchWidgetTimelineProvider()) { entry in
            Text(TokenWatchWidgetCopy.text(.tokenHeatmapDisplayName, languageIdentifier: entry.snapshot.languageIdentifier))
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName(TokenWatchWidgetCopy.text(.tokenHeatmapDisplayName, languageIdentifier: "zh-Hans"))
        .description(TokenWatchWidgetCopy.text(.tokenHeatmapDescription, languageIdentifier: "zh-Hans"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
```

Create `TokenWatchWidgets/TokenWatchTodayLineWidget.swift`:

```swift
import SwiftUI
import WidgetKit

struct TokenWatchTodayLineWidget: Widget {
    private let kind = "TokenWatchTodayLineWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TokenWatchWidgetTimelineProvider()) { entry in
            Text(TokenWatchWidgetCopy.text(.todayLineDisplayName, languageIdentifier: entry.snapshot.languageIdentifier))
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName(TokenWatchWidgetCopy.text(.todayLineDisplayName, languageIdentifier: "zh-Hans"))
        .description(TokenWatchWidgetCopy.text(.todayLineDescription, languageIdentifier: "zh-Hans"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
```

- [ ] **Step 3: Patch the Xcode project**

Modify `TokenWatch.xcodeproj/project.pbxproj` with these exact project object additions.

Add this section after `/* End PBXContainerItemProxy section */`:

```text
/* Begin PBXCopyFilesBuildPhase section */
		AAB000000000000000000014 /* Embed App Extensions */ = {
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = "";
			dstSubfolderSpec = 13;
			files = (
				AAB000000000000000000004 /* TokenWatchWidgets.appex in Embed App Extensions */,
			);
			name = "Embed App Extensions";
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXCopyFilesBuildPhase section */
```

Add to `PBXContainerItemProxy section`:

```text
		AAB000000000000000000012 /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = AAA358022FDD7BFB0018086B /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = AAB000000000000000000008;
			remoteInfo = TokenWatchWidgets;
		};
```

Add to `PBXBuildFile section`. If the project does not have this section yet, create it before `PBXContainerItemProxy section`:

```text
/* Begin PBXBuildFile section */
		AAB000000000000000000004 /* TokenWatchWidgets.appex in Embed App Extensions */ = {isa = PBXBuildFile; fileRef = AAB000000000000000000001 /* TokenWatchWidgets.appex */; settings = {ATTRIBUTES = (RemoveHeadersOnCopy, CodeSignOnCopy, ); }; };
/* End PBXBuildFile section */
```

Add to `PBXFileReference section`:

```text
		AAB000000000000000000001 /* TokenWatchWidgets.appex */ = {isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = TokenWatchWidgets.appex; sourceTree = BUILT_PRODUCTS_DIR; };
```

Add to `PBXFileSystemSynchronizedRootGroup section`:

```text
		AAB000000000000000000003 /* TokenWatchWidgets */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = TokenWatchWidgets;
			sourceTree = "<group>";
		};
```

In the main `PBXGroup` children list, add:

```text
				AAB000000000000000000003 /* TokenWatchWidgets */,
```

In the `Products` group children list, add:

```text
				AAB000000000000000000001 /* TokenWatchWidgets.appex */,
```

In the `TokenWatch` native target:

```text
			buildPhases = (
				AAA358062FDD7BFB0018086B /* Sources */,
				AAA358072FDD7BFB0018086B /* Frameworks */,
				AAA358082FDD7BFB0018086B /* Resources */,
				AAB000000000000000000014 /* Embed App Extensions */,
			);
			dependencies = (
				AAB000000000000000000013 /* PBXTargetDependency */,
			);
			fileSystemSynchronizedGroups = (
				AAA3580C2FDD7BFB0018086B /* TokenWatch */,
				AAB000000000000000000002 /* TokenWatchShared */,
			);
```

Add this native target to `PBXNativeTarget section`:

```text
		AAB000000000000000000008 /* TokenWatchWidgets */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = AAB000000000000000000009 /* Build configuration list for PBXNativeTarget "TokenWatchWidgets" */;
			buildPhases = (
				AAB000000000000000000005 /* Sources */,
				AAB000000000000000000006 /* Frameworks */,
				AAB000000000000000000007 /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				AAB000000000000000000002 /* TokenWatchShared */,
				AAB000000000000000000003 /* TokenWatchWidgets */,
			);
			name = TokenWatchWidgets;
			packageProductDependencies = (
			);
			productName = TokenWatchWidgets;
			productReference = AAB000000000000000000001 /* TokenWatchWidgets.appex */;
			productType = "com.apple.product-type.app-extension";
		};
```

In `PBXProject` `TargetAttributes`, add:

```text
					AAB000000000000000000008 = {
						CreatedOnToolsVersion = 26.5;
					};
```

In `PBXProject` `targets`, add:

```text
				AAB000000000000000000008 /* TokenWatchWidgets */,
```

Add widget build phases:

```text
		AAB000000000000000000005 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		AAB000000000000000000006 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		AAB000000000000000000007 /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
```

Add to `PBXTargetDependency section`:

```text
		AAB000000000000000000013 /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = AAB000000000000000000008 /* TokenWatchWidgets */;
			targetProxy = AAB000000000000000000012 /* PBXContainerItemProxy */;
		};
```

Add app target build setting `CODE_SIGN_ENTITLEMENTS = TokenWatch/TokenWatch.entitlements;` to both `AAA3582F2FDD7BFD0018086B /* Debug */` and `AAA358302FDD7BFD0018086B /* Release */`.

Add widget `XCBuildConfiguration` entries:

```text
		AAB000000000000000000010 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_ENTITLEMENTS = TokenWatchWidgets/TokenWatchWidgets.entitlements;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				ENABLE_APP_SANDBOX = YES;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = TokenWatchWidgets/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/../Frameworks",
					"@executable_path/../../Frameworks",
				);
				MACOSX_DEPLOYMENT_TARGET = 15.0;
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.xiaoao.TokenWatch.TokenWatchWidgets;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SKIP_INSTALL = YES;
				STRING_CATALOG_GENERATE_SYMBOLS = NO;
				SWIFT_APPROACHABLE_CONCURRENCY = YES;
				SWIFT_EMIT_LOC_STRINGS = NO;
				SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES;
				SWIFT_VERSION = 6.0;
			};
			name = Debug;
		};
		AAB000000000000000000011 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_ENTITLEMENTS = TokenWatchWidgets/TokenWatchWidgets.entitlements;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				ENABLE_APP_SANDBOX = YES;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = TokenWatchWidgets/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/../Frameworks",
					"@executable_path/../../Frameworks",
				);
				MACOSX_DEPLOYMENT_TARGET = 15.0;
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.xiaoao.TokenWatch.TokenWatchWidgets;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SKIP_INSTALL = YES;
				STRING_CATALOG_GENERATE_SYMBOLS = NO;
				SWIFT_APPROACHABLE_CONCURRENCY = YES;
				SWIFT_EMIT_LOC_STRINGS = NO;
				SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES;
				SWIFT_VERSION = 6.0;
			};
			name = Release;
		};
```

Add widget configuration list:

```text
		AAB000000000000000000009 /* Build configuration list for PBXNativeTarget "TokenWatchWidgets" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				AAB000000000000000000010 /* Debug */,
				AAB000000000000000000011 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
```

- [ ] **Step 4: Verify the project lists the widget target**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -list
```

Expected: output includes targets or schemes named `TokenWatchWidgets` along with `TokenWatch`, `TokenWatchTests`, and `TokenWatchUITests`.

- [ ] **Step 5: Build the minimal app and extension**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Debug build
```

Expected: PASS. If signing fails because the local developer account has not registered `group.com.xiaoao.TokenWatch`, run this compile-only check to separate code errors from provisioning:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Expected: PASS for compile-only build.

- [ ] **Step 6: Commit**

```bash
git add TokenWatch/TokenWatch.entitlements TokenWatchWidgets TokenWatch.xcodeproj/project.pbxproj
git commit -m "feat(widget): 添加 WidgetKit 扩展目标"
```

---

### Task 6: Heatmap Widget UI

**Files:**
- Modify: `TokenWatchWidgets/TokenWatchHeatmapWidget.swift`

- [ ] **Step 1: Replace the minimal heatmap widget with the full heatmap UI**

Replace `TokenWatchWidgets/TokenWatchHeatmapWidget.swift` with:

```swift
import SwiftUI
import WidgetKit

struct TokenWatchHeatmapWidget: Widget {
    private let kind = "TokenWatchHeatmapWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TokenWatchWidgetTimelineProvider()) { entry in
            TokenWatchHeatmapWidgetView(snapshot: entry.snapshot)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName(TokenWatchWidgetCopy.text(.tokenHeatmapDisplayName, languageIdentifier: "zh-Hans"))
        .description(TokenWatchWidgetCopy.text(.tokenHeatmapDescription, languageIdentifier: "zh-Hans"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct TokenWatchHeatmapWidgetView: View {
    let snapshot: TokenWatchWidgetSnapshot

    @Environment(\.widgetFamily) private var widgetFamily
    @Environment(\.colorScheme) private var colorScheme

    private var layout: TokenWatchHeatmapWidgetLayout {
        TokenWatchHeatmapWidgetLayout.layout(for: widgetFamily.tokenWatchDisplayFamily)
    }

    var body: some View {
        Group {
            switch snapshot.status {
            case .ready:
                content
            case .needsAuthorization:
                statusView(.openAppToAuthorize)
            case .empty:
                statusView(.noTokenData)
            }
        }
        .padding(widgetPadding)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: verticalSpacing) {
            header
            if layout != .compact {
                summaryRow
            }
            heatmapGrid
            if layout == .expanded {
                legend
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.heatmap.title)
                    .font(.system(size: layout == .compact ? 12 : 13, weight: .semibold))
                    .lineLimit(1)
                Text("\(TokenWatchWidgetCopy.text(.today, languageIdentifier: snapshot.languageIdentifier)) \(TokenWatchWidgetCompactNumberFormatter.format(snapshot.heatmap.summary.todayTokens))")
                    .font(.system(size: layout == .compact ? 18 : 20, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if layout != .compact {
                Text(updatedText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var summaryRow: some View {
        HStack(spacing: 8) {
            summaryItem(.month, snapshot.heatmap.summary.monthTokens)
            summaryItem(.week, snapshot.heatmap.summary.weekTokens)
            summaryItem(.dailyAverage, snapshot.heatmap.summary.averageDailyTokens)
        }
    }

    private func summaryItem(_ key: TokenWatchWidgetCopyKey, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(TokenWatchWidgetCopy.text(key, languageIdentifier: snapshot.languageIdentifier))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            Text(TokenWatchWidgetCompactNumberFormatter.format(value))
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var heatmapGrid: some View {
        let rows = Array(repeating: GridItem(.fixed(tileSize), spacing: tileSpacing), count: 7)
        return LazyHGrid(rows: rows, spacing: tileSpacing) {
            ForEach(snapshot.heatmap.cells) { cell in
                RoundedRectangle(cornerRadius: max(1.5, tileSize * 0.18), style: .continuous)
                    .fill(color(for: cell))
                    .overlay {
                        if cell.isToday {
                            RoundedRectangle(cornerRadius: max(1.5, tileSize * 0.18), style: .continuous)
                                .stroke(Color.primary.opacity(0.45), lineWidth: 1)
                        }
                    }
                    .opacity(cell.isFuture ? 0.45 : 1)
                    .frame(width: tileSize, height: tileSize)
                    .accessibilityLabel(cell.dateKey ?? "")
                    .accessibilityValue(TokenWatchWidgetCompactNumberFormatter.format(cell.totalTokens))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var legend: some View {
        HStack(spacing: 4) {
            Spacer()
            ForEach(0...4, id: \.self) { intensity in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(paletteColor(for: intensity))
                    .frame(width: 10, height: 10)
            }
        }
        .accessibilityHidden(true)
    }

    private func statusView(_ key: TokenWatchWidgetCopyKey) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(TokenWatchWidgetCopy.text(.tokenHeatmapDisplayName, languageIdentifier: snapshot.languageIdentifier))
                .font(.system(size: 13, weight: .semibold))
            Text(TokenWatchWidgetCopy.text(key, languageIdentifier: snapshot.languageIdentifier))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            heatmapGrid
                .opacity(0.35)
        }
    }

    private func color(for cell: TokenWatchWidgetHeatmapCell) -> Color {
        guard cell.kind == .day else { return .clear }
        return paletteColor(for: cell.intensity)
    }

    private func paletteColor(for intensity: Int) -> Color {
        let clamped = min(max(intensity, 0), 4)
        let light: [(Double, Double, Double)] = [
            (235, 237, 240),
            (155, 233, 168),
            (64, 196, 99),
            (48, 161, 78),
            (33, 110, 57),
        ]
        let dark: [(Double, Double, Double)] = [
            (25, 30, 37),
            (14, 68, 41),
            (0, 109, 50),
            (38, 166, 65),
            (57, 211, 83),
        ]
        let value = (colorScheme == .dark ? dark : light)[clamped]
        return Color(red: value.0 / 255, green: value.1 / 255, blue: value.2 / 255)
    }

    private var updatedText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "\(TokenWatchWidgetCopy.text(.updated, languageIdentifier: snapshot.languageIdentifier)) \(formatter.string(from: snapshot.generatedAt))"
    }

    private var widgetPadding: CGFloat {
        switch layout {
        case .compact:
            return 12
        case .summary:
            return 14
        case .expanded:
            return 16
        }
    }

    private var verticalSpacing: CGFloat {
        switch layout {
        case .compact:
            return 8
        case .summary:
            return 10
        case .expanded:
            return 12
        }
    }

    private var tileSize: CGFloat {
        switch layout {
        case .compact:
            return 5.3
        case .summary:
            return 8.4
        case .expanded:
            return 10.8
        }
    }

    private var tileSpacing: CGFloat {
        switch layout {
        case .compact:
            return 1.6
        case .summary:
            return 2.4
        case .expanded:
            return 3
        }
    }
}

extension WidgetFamily {
    var tokenWatchDisplayFamily: TokenWatchWidgetDisplayFamily {
        switch self {
        case .systemSmall:
            return .small
        case .systemLarge:
            return .large
        case .systemMedium:
            return .medium
        default:
            return .medium
        }
    }
}
```

- [ ] **Step 2: Build the widget target**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -target TokenWatchWidgets -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add TokenWatchWidgets/TokenWatchHeatmapWidget.swift
git commit -m "feat(widget): 添加热力图小组件界面"
```

---

### Task 7: Today Hourly Line Widget UI

**Files:**
- Modify: `TokenWatchWidgets/TokenWatchTodayLineWidget.swift`

- [ ] **Step 1: Replace the minimal today-line widget with Charts UI**

Replace `TokenWatchWidgets/TokenWatchTodayLineWidget.swift` with:

```swift
import Charts
import SwiftUI
import WidgetKit

struct TokenWatchTodayLineWidget: Widget {
    private let kind = "TokenWatchTodayLineWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TokenWatchWidgetTimelineProvider()) { entry in
            TokenWatchTodayLineWidgetView(snapshot: entry.snapshot)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName(TokenWatchWidgetCopy.text(.todayLineDisplayName, languageIdentifier: "zh-Hans"))
        .description(TokenWatchWidgetCopy.text(.todayLineDescription, languageIdentifier: "zh-Hans"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct TokenWatchTodayLineWidgetView: View {
    let snapshot: TokenWatchWidgetSnapshot

    @Environment(\.widgetFamily) private var widgetFamily
    @Environment(\.colorScheme) private var colorScheme

    private var layout: TokenWatchTodayLineWidgetLayout {
        TokenWatchTodayLineWidgetLayout.layout(for: widgetFamily.tokenWatchDisplayFamily)
    }

    var body: some View {
        Group {
            switch snapshot.status {
            case .ready:
                content
            case .needsAuthorization:
                statusView(.openAppToAuthorize)
            case .empty:
                statusView(.noTokenData)
            }
        }
        .padding(widgetPadding)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: verticalSpacing) {
            header
            chart
            if layout == .expanded {
                footer
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(TokenWatchWidgetCopy.text(.today, languageIdentifier: snapshot.languageIdentifier))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(TokenWatchWidgetCompactNumberFormatter.format(snapshot.todayLine.totalTokens))
                    .font(.system(size: layout == .compact ? 22 : 24, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if layout != .compact {
                Text(updatedText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var chart: some View {
        Chart {
            ForEach(snapshot.todayLine.buckets) { bucket in
                AreaMark(
                    x: .value("Hour", bucket.hourKey),
                    y: .value("Tokens", Double(bucket.totalTokens))
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(areaGradient)

                LineMark(
                    x: .value("Hour", bucket.hourKey),
                    y: .value("Tokens", Double(bucket.totalTokens))
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.accentColor)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                if bucket.isCurrentHour {
                    PointMark(
                        x: .value("Hour", bucket.hourKey),
                        y: .value("Tokens", Double(bucket.totalTokens))
                    )
                    .foregroundStyle(Color.accentColor)
                    .symbolSize(layout == .compact ? 14 : 22)
                }
            }
        }
        .chartLegend(.hidden)
        .chartYScale(domain: 0...Double(max(1, snapshot.todayLine.maxHourlyTokens)))
        .chartXAxis {
            AxisMarks(values: axisKeys) { value in
                if layout != .compact {
                    AxisTick()
                    AxisValueLabel {
                        if let key = value.as(String.self),
                           let bucket = snapshot.todayLine.buckets.first(where: { $0.hourKey == key }) {
                            Text(bucket.hourLabel)
                                .font(.system(size: 8))
                        }
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: layout == .expanded ? 3 : 2)) { value in
                if layout != .compact {
                    AxisGridLine()
                        .foregroundStyle(.secondary.opacity(0.16))
                    if let tokens = value.as(Double.self), layout == .expanded {
                        AxisValueLabel(TokenWatchWidgetCompactNumberFormatter.format(Int(tokens)))
                            .font(.system(size: 8))
                    }
                }
            }
        }
        .frame(minHeight: chartHeight)
        .accessibilityLabel(TokenWatchWidgetCopy.text(.todayLineDisplayName, languageIdentifier: snapshot.languageIdentifier))
    }

    private var footer: some View {
        HStack {
            Text("\(TokenWatchWidgetCopy.text(.dailyAverage, languageIdentifier: snapshot.languageIdentifier)) \(TokenWatchWidgetCompactNumberFormatter.format(snapshot.todayLine.maxHourlyTokens))")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func statusView(_ key: TokenWatchWidgetCopyKey) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(TokenWatchWidgetCopy.text(.todayLineDisplayName, languageIdentifier: snapshot.languageIdentifier))
                .font(.system(size: 13, weight: .semibold))
            Text(TokenWatchWidgetCopy.text(key, languageIdentifier: snapshot.languageIdentifier))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            chart
                .opacity(0.35)
        }
    }

    private var axisKeys: [String] {
        [0, 6, 12, 18, 23].compactMap { index in
            snapshot.todayLine.buckets.indices.contains(index)
                ? snapshot.todayLine.buckets[index].hourKey
                : nil
        }
    }

    private var areaGradient: LinearGradient {
        let color = heatmapMaxColor
        return LinearGradient(
            colors: [
                color.opacity(0.8),
                color.opacity(0.05),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var heatmapMaxColor: Color {
        if colorScheme == .dark {
            return Color(red: 57 / 255, green: 211 / 255, blue: 83 / 255)
        }
        return Color(red: 33 / 255, green: 110 / 255, blue: 57 / 255)
    }

    private var updatedText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "\(TokenWatchWidgetCopy.text(.updated, languageIdentifier: snapshot.languageIdentifier)) \(formatter.string(from: snapshot.generatedAt))"
    }

    private var widgetPadding: CGFloat {
        switch layout {
        case .compact:
            return 12
        case .chart:
            return 14
        case .expanded:
            return 16
        }
    }

    private var verticalSpacing: CGFloat {
        switch layout {
        case .compact:
            return 8
        case .chart:
            return 10
        case .expanded:
            return 12
        }
    }

    private var chartHeight: CGFloat {
        switch layout {
        case .compact:
            return 58
        case .chart:
            return 92
        case .expanded:
            return 150
        }
    }
}
```

- [ ] **Step 2: Build the widget target**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -target TokenWatchWidgets -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add TokenWatchWidgets/TokenWatchTodayLineWidget.swift
git commit -m "feat(widget): 添加今日折线图小组件界面"
```

---

### Task 8: Final Verification

**Files:**
- Verify all changed files.

- [ ] **Step 1: Run focused widget-related tests**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/TokenWatchWidgetSnapshotTests -only-testing:TokenWatchTests/TokenWatchWidgetSnapshotStoreTests -only-testing:TokenWatchTests/WidgetSnapshotBuilderTests -only-testing:TokenWatchTests/TokenStatsViewModelObserverTests test
```

Expected: PASS.

- [ ] **Step 2: Run all unit tests**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests test
```

Expected: PASS.

- [ ] **Step 3: Build the app with the embedded extension**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Expected: PASS.

- [ ] **Step 4: Inspect git status**

Run:

```bash
git status --short
```

Expected: no unstaged changes unless signing/provisioning generated local user files outside the repository.

- [ ] **Step 5: Final commit if verification changes were needed**

If Task 8 required code fixes, commit them:

```bash
git add TokenWatch TokenWatchShared TokenWatchWidgets TokenWatchTests TokenWatch.xcodeproj/project.pbxproj
git commit -m "fix(widget): 修正小组件构建验证问题"
```

If Task 8 did not require code fixes, do not create an empty commit.

---

## Self-Review Notes

- Spec coverage: shared snapshot, App Group store, main-app publishing, two widget kinds, status/empty states, compact formatting, timeline provider, and build verification are each mapped to tasks.
- Type consistency: shared types are prefixed `TokenWatchWidget...`; app-only builder/publisher stay under `TokenWatch/Widgets`; widget extension imports only `TokenWatchShared` files through target membership.
- Project risk: manual `project.pbxproj` edits are isolated to Task 5 with fixed object IDs. If Xcode rewrites object ordering after opening the project, keep semantic target settings intact and avoid unrelated churn.
