# Monthly Cost Chart Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a second monthly bar chart on the "按月" page showing USD cost per month for the past 12 months.

**Architecture:** Extend the existing `MonthlyTokenChartBuilder` snapshot with cost totals and cost normalization while keeping token chart behavior intact. Add a focused `MonthlyCostChartView` that consumes the same snapshot and render it below the existing token chart in `MonthlyStatsViewController`.

**Tech Stack:** Swift 6 app code, AppKit views, Swift Testing unit tests, `xcodebuild` for macOS test execution.

---

## File Structure

- Modify `TokenWatch/ViewControllers/MonthlyTokenChartBuilder.swift`
  - Add `totalCost`, `maxMonthlyCost`, `MonthlyTokenBucket.totalCost`, and `MonthlyTokenBucket.normalizedCostHeight`.
  - Sum `UsageSummary.cost` from `AggregatedStats.byMonth`.
- Create `TokenWatch/ViewControllers/MonthlyCostChartView.swift`
  - Render 12 monthly cost bars from `MonthlyTokenChartSnapshot`.
  - Keep debug properties aligned with `MonthlyTokenChartView`.
- Modify `TokenWatch/ViewControllers/MonthlyStatsViewController.swift`
  - Add total cost summary label.
  - Add and configure `MonthlyCostChartView` below `MonthlyTokenChartView`.
- Modify `TokenWatchTests/ViewControllers/MonthlyTokenChartBuilderTests.swift`
  - Add cost aggregation and cost normalization tests.
- Create `TokenWatchTests/ViewControllers/MonthlyCostChartViewTests.swift`
  - Add view behavior tests for 12 bars, replacement, and clamping.
- Modify `TokenWatchTests/ViewControllers/MonthlyStatsViewControllerTests.swift`
  - Add page-level cost summary and cost chart tests.

The project uses file-system-synchronized Xcode groups, so adding Swift files under the target folders is enough; no `project.pbxproj` edit is required.

---

### Task 1: Monthly Cost Data In Builder

**Files:**
- Modify: `TokenWatchTests/ViewControllers/MonthlyTokenChartBuilderTests.swift`
- Modify: `TokenWatch/ViewControllers/MonthlyTokenChartBuilder.swift`

- [ ] **Step 1: Write the failing builder tests**

Add these tests inside `MonthlyTokenChartBuilderTests`:

```swift
@Test("跨 provider 合并 byMonth cost 并缺失月份补零")
func sumsMonthlyCostsAcrossProvidersAndFillsMissingMonths() {
    let calendar = utcCalendar()
    let claudeStats = makeStats(byMonth: [
        "2026-05": makeSummary(total: 100, cost: 1.25),
        "2026-06": makeSummary(total: 300, cost: 2.50),
    ])
    let codexStats = makeStats(byMonth: [
        "2026-06": makeSummary(total: 50, cost: 0.75),
    ])

    let snapshot = MonthlyTokenChartBuilder.build(
        states: [
            .claude: .init(stats: claudeStats, isLoading: false, errorMessage: nil, needsAuthorization: false),
            .codex: .init(stats: codexStats, isLoading: false, errorMessage: nil, needsAuthorization: false),
        ],
        now: date(2026, 6, 20, calendar: calendar),
        calendar: calendar
    )

    #expect(snapshot.bucket("2026-04")?.totalCost == 0)
    #expect(snapshot.bucket("2026-05")?.totalCost == 1.25)
    #expect(snapshot.bucket("2026-06")?.totalCost == 3.25)
    #expect(snapshot.totalCost == 4.50)
    #expect(snapshot.maxMonthlyCost == 3.25)
}

@Test("normalizedCostHeight 保持在 0...1 且全零费用时稳定")
func normalizedCostHeightIsBoundedAndStableForZeroData() {
    let calendar = utcCalendar()

    let emptySnapshot = MonthlyTokenChartBuilder.build(
        states: [.claude: .init(stats: makeStats(byMonth: [:]), isLoading: false, errorMessage: nil, needsAuthorization: false)],
        now: date(2026, 6, 20, calendar: calendar),
        calendar: calendar
    )

    #expect(emptySnapshot.maxMonthlyCost == 0)
    #expect(emptySnapshot.monthBuckets.allSatisfy { $0.normalizedCostHeight == 0 })

    let filledSnapshot = MonthlyTokenChartBuilder.build(
        states: [.claude: .init(stats: makeStats(byMonth: [
            "2026-05": makeSummary(total: 50, cost: 1.0),
            "2026-06": makeSummary(total: 100, cost: 4.0),
        ]), isLoading: false, errorMessage: nil, needsAuthorization: false)],
        now: date(2026, 6, 20, calendar: calendar),
        calendar: calendar
    )

    #expect(filledSnapshot.bucket("2026-05")?.normalizedCostHeight == 0.25)
    #expect(filledSnapshot.bucket("2026-06")?.normalizedCostHeight == 1.0)
    #expect(filledSnapshot.monthBuckets.allSatisfy {
        $0.normalizedCostHeight >= 0 && $0.normalizedCostHeight <= 1
    })
}
```

Change the test helper signature:

```swift
private func makeSummary(total: Int, cost: Double = 0) -> UsageSummary {
    UsageSummary(
        inputTokens: total,
        outputTokens: 0,
        cacheReadTokens: 0,
        cacheCreationTokens: 0,
        reasoningTokens: 0,
        totalTokens: total,
        cost: cost,
        entryCount: 1,
        modelBreakdown: [:]
    )
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/MonthlyTokenChartBuilderTests test
```

Expected: FAIL because `MonthlyTokenChartSnapshot` has no `totalCost` / `maxMonthlyCost` and `MonthlyTokenBucket` has no `totalCost` / `normalizedCostHeight`.

- [ ] **Step 3: Implement minimal builder changes**

Update `MonthlyTokenChartBuilder.swift`:

```swift
struct MonthlyTokenChartSnapshot: Sendable, Equatable {
    let monthBuckets: [MonthlyTokenBucket]
    let totalTokens: Int
    let totalCost: Double
    let maxMonthlyTokens: Int
    let maxMonthlyCost: Double
    let loadedProviderCount: Int
    let loadingProviderCount: Int
    let unauthorizedProviderCount: Int
    let errorMessages: [String]
}

struct MonthlyTokenBucket: Sendable, Equatable, Identifiable {
    let id: String
    let monthKey: String
    let monthLabel: String
    let totalTokens: Int
    let totalCost: Double
    let normalizedHeight: Double
    let normalizedCostHeight: Double
    let isCurrentMonth: Bool
}
```

Inside `build`, create and fill a cost dictionary:

```swift
var totals = Dictionary(uniqueKeysWithValues: monthKeys.map { ($0, 0) })
var costs = Dictionary(uniqueKeysWithValues: monthKeys.map { ($0, 0.0) })
```

Inside the per-provider `monthKeys` loop:

```swift
let summary = stats.byMonth[monthKey]
totals[monthKey, default: 0] += summary?.totalTokens ?? 0
costs[monthKey, default: 0] += summary?.cost ?? 0
```

Build cost normalization:

```swift
let maxMonthlyTokens = totals.values.max() ?? 0
let maxMonthlyCost = costs.values.max() ?? 0
```

Inside each bucket:

```swift
let totalCost = costs[key, default: 0]
let normalizedCostHeight = maxMonthlyCost > 0
    ? totalCost / maxMonthlyCost
    : 0
```

Return the expanded snapshot:

```swift
return MonthlyTokenChartSnapshot(
    monthBuckets: buckets,
    totalTokens: buckets.reduce(0) { $0 + $1.totalTokens },
    totalCost: buckets.reduce(0) { $0 + $1.totalCost },
    maxMonthlyTokens: maxMonthlyTokens,
    maxMonthlyCost: maxMonthlyCost,
    loadedProviderCount: loadedProviderCount,
    loadingProviderCount: loadingProviderCount,
    unauthorizedProviderCount: unauthorizedProviderCount,
    errorMessages: errorMessages
)
```

- [ ] **Step 4: Run builder tests to verify green**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/MonthlyTokenChartBuilderTests test
```

Expected: PASS.

---

### Task 2: Monthly Cost Chart View

**Files:**
- Create: `TokenWatchTests/ViewControllers/MonthlyCostChartViewTests.swift`
- Create: `TokenWatch/ViewControllers/MonthlyCostChartView.swift`
- Modify: `TokenWatchTests/ViewControllers/MonthlyTokenChartViewTests.swift`

- [ ] **Step 1: Update existing snapshot helpers for new fields**

In `MonthlyTokenChartViewTests`, update test snapshot construction so the existing token chart tests keep compiling:

```swift
MonthlyTokenBucket(
    id: monthKeys[index],
    monthKey: monthKeys[index],
    monthLabel: monthLabels[index],
    totalTokens: total,
    totalCost: 0,
    normalizedHeight: maxTokens > 0 ? Double(total) / Double(maxTokens) : 0,
    normalizedCostHeight: 0,
    isCurrentMonth: index == monthKeys.indices.last
)
```

And update the manual bucket helper:

```swift
MonthlyTokenBucket(
    id: "manual-\(index)",
    monthKey: "manual-\(index)",
    monthLabel: "\(index + 1)月",
    totalTokens: index,
    totalCost: 0,
    normalizedHeight: normalizedHeights[index],
    normalizedCostHeight: 0,
    isCurrentMonth: index == normalizedHeights.indices.last
)
```

Update `MonthlyTokenChartSnapshot` construction in that file with:

```swift
totalCost: 0,
maxMonthlyCost: 0,
```

- [ ] **Step 2: Write the failing cost chart view tests**

Create `TokenWatchTests/ViewControllers/MonthlyCostChartViewTests.swift`:

```swift
import AppKit
import Testing
@testable import TokenWatch

@Suite("MonthlyCostChartView")
struct MonthlyCostChartViewTests {

    @MainActor
    @Test("配置 snapshot 后渲染十二根费用柱")
    func configureRendersTwelveCostBars() {
        let view = MonthlyCostChartView()
        let snapshot = makeSnapshot(costs: [0, 0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 5])

        view.configure(with: snapshot)

        #expect(view.debugBarCount == 12)
        #expect(view.debugMonthLabels == [
            "7月", "8月", "9月", "10月", "11月", "12月",
            "1月", "2月", "3月", "4月", "5月", "6月",
        ])
        #expect(view.debugNormalizedHeights.last == 1.0)
    }

    @MainActor
    @Test("全零费用保持稳定柱高状态")
    func zeroCostsKeepStableBarState() {
        let view = MonthlyCostChartView()
        let snapshot = makeSnapshot(costs: Array(repeating: 0, count: 12))

        view.configure(with: snapshot)

        #expect(view.debugBarCount == 12)
        #expect(view.debugNormalizedHeights.allSatisfy { $0 == 0 })
    }

    @MainActor
    @Test("重复配置会替换旧费用柱")
    func repeatedConfigureReplacesExistingCostBars() {
        let view = MonthlyCostChartView()

        view.configure(with: makeSnapshot(costs: Array(repeating: 1, count: 12)))
        view.configure(with: makeSnapshot(costs: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20]))

        #expect(view.debugBarCount == 12)
        #expect(view.debugNormalizedHeights.first == 0)
        #expect(view.debugNormalizedHeights[10] == 0.5)
        #expect(view.debugNormalizedHeights.last == 1.0)
    }

    @MainActor
    @Test("debug 高度与渲染使用相同的稳定 clamp 值")
    func debugHeightsUseClampedFiniteValues() {
        let view = MonthlyCostChartView()
        let snapshot = makeSnapshot(normalizedCostHeights: [-0.2, 1.4, .nan, 0.25])

        view.configure(with: snapshot)

        #expect(view.debugNormalizedHeights[0] == 0)
        #expect(view.debugNormalizedHeights[1] == 1)
        #expect(view.debugNormalizedHeights[2] == 0)
        #expect(view.debugNormalizedHeights[3] == 0.25)
        #expect(view.debugNormalizedHeights.allSatisfy { $0.isFinite && (0...1).contains($0) })
    }

    @MainActor
    @Test("单根费用柱提供确定 intrinsic 尺寸")
    func barViewHasDeterministicIntrinsicSize() {
        let barView = MonthlyCostBarView()

        #expect(barView.intrinsicContentSize.width == 18)
        #expect(barView.intrinsicContentSize.height == 160)
    }

    private func makeSnapshot(costs: [Double]) -> MonthlyTokenChartSnapshot {
        let monthKeys = [
            "2025-07", "2025-08", "2025-09", "2025-10",
            "2025-11", "2025-12", "2026-01", "2026-02",
            "2026-03", "2026-04", "2026-05", "2026-06",
        ]
        let monthLabels = [
            "7月", "8月", "9月", "10月", "11月", "12月",
            "1月", "2月", "3月", "4月", "5月", "6月",
        ]
        let maxCost = costs.max() ?? 0
        let buckets = zip(monthKeys.indices, costs).map { index, totalCost in
            MonthlyTokenBucket(
                id: monthKeys[index],
                monthKey: monthKeys[index],
                monthLabel: monthLabels[index],
                totalTokens: 0,
                totalCost: totalCost,
                normalizedHeight: 0,
                normalizedCostHeight: maxCost > 0 ? totalCost / maxCost : 0,
                isCurrentMonth: index == monthKeys.indices.last
            )
        }

        return MonthlyTokenChartSnapshot(
            monthBuckets: buckets,
            totalTokens: 0,
            totalCost: costs.reduce(0, +),
            maxMonthlyTokens: 0,
            maxMonthlyCost: maxCost,
            loadedProviderCount: 1,
            loadingProviderCount: 0,
            unauthorizedProviderCount: 0,
            errorMessages: []
        )
    }

    private func makeSnapshot(normalizedCostHeights: [Double]) -> MonthlyTokenChartSnapshot {
        let buckets = normalizedCostHeights.indices.map { index in
            MonthlyTokenBucket(
                id: "manual-\(index)",
                monthKey: "manual-\(index)",
                monthLabel: "\(index + 1)月",
                totalTokens: 0,
                totalCost: Double(index),
                normalizedHeight: 0,
                normalizedCostHeight: normalizedCostHeights[index],
                isCurrentMonth: index == normalizedCostHeights.indices.last
            )
        }

        return MonthlyTokenChartSnapshot(
            monthBuckets: buckets,
            totalTokens: 0,
            totalCost: 0,
            maxMonthlyTokens: 0,
            maxMonthlyCost: 0,
            loadedProviderCount: 1,
            loadingProviderCount: 0,
            unauthorizedProviderCount: 0,
            errorMessages: []
        )
    }
}
```

- [ ] **Step 3: Run cost chart test to verify it fails**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/MonthlyCostChartViewTests test
```

Expected: FAIL because `MonthlyCostChartView` and `MonthlyCostBarView` do not exist.

- [ ] **Step 4: Implement the cost chart view**

Create `TokenWatch/ViewControllers/MonthlyCostChartView.swift`:

```swift
import AppKit

/// 过去 12 个月费用柱状图。只消费 snapshot,不读取 ViewModel。
final class MonthlyCostChartView: NSView {
    private let barsStack = NSStackView()
    private(set) var debugNormalizedHeights: [Double] = []
    private(set) var debugMonthLabels: [String] = []

    var debugBarCount: Int {
        barsStack.arrangedSubviews.count
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    /// 用新的 snapshot 替换费用图表内容。
    func configure(with snapshot: MonthlyTokenChartSnapshot) {
        clearBars()
        debugNormalizedHeights = snapshot.monthBuckets.map { clampNormalizedCostHeight($0.normalizedCostHeight) }
        debugMonthLabels = snapshot.monthBuckets.map(\.monthLabel)

        for bucket in snapshot.monthBuckets {
            barsStack.addArrangedSubview(makeColumn(for: bucket))
        }
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        barsStack.translatesAutoresizingMaskIntoConstraints = false
        barsStack.orientation = .horizontal
        barsStack.alignment = .bottom
        barsStack.distribution = .fillEqually
        barsStack.spacing = 10

        addSubview(barsStack)
        NSLayoutConstraint.activate([
            barsStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            barsStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            barsStack.topAnchor.constraint(equalTo: topAnchor),
            barsStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 220),
        ])
    }

    private func clearBars() {
        for view in barsStack.arrangedSubviews {
            barsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    private func makeColumn(for bucket: MonthlyTokenBucket) -> NSView {
        let column = NSStackView()
        column.orientation = .vertical
        column.alignment = .centerX
        column.spacing = 8

        let barView = MonthlyCostBarView()
        barView.translatesAutoresizingMaskIntoConstraints = false
        barView.normalizedHeight = bucket.normalizedCostHeight
        barView.fillColor = bucket.isCurrentMonth ? .controlAccentColor : .systemGreen
        barView.toolTip = "\(bucket.monthKey) · \(formatCurrency(bucket.totalCost))"

        let label = NSTextField(labelWithString: bucket.monthLabel)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.alignment = .center

        column.addArrangedSubview(barView)
        column.addArrangedSubview(label)

        return column
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }
}

private func clampNormalizedCostHeight(_ value: Double) -> Double {
    guard value.isFinite else { return 0 }
    return min(max(value, 0), 1)
}

/// 单根费用柱子的可测试绘制视图。完整高度由布局决定,柱子高度由 normalizedHeight 决定。
final class MonthlyCostBarView: NSView {
    private var clampedNormalizedHeight: Double = 0

    var normalizedHeight: Double {
        get {
            clampedNormalizedHeight
        }
        set {
            clampedNormalizedHeight = clampNormalizedCostHeight(newValue)
            needsDisplay = true
        }
    }

    var fillColor: NSColor = .systemGreen {
        didSet {
            needsDisplay = true
        }
    }

    override var isFlipped: Bool {
        false
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 18, height: 160)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let barHeight = bounds.height * CGFloat(clampedNormalizedHeight)
        guard barHeight > 0 else { return }

        let rect = NSRect(x: 0, y: 0, width: bounds.width, height: barHeight)
        fillColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
    }
}
```

- [ ] **Step 5: Run cost chart tests to verify green**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/MonthlyCostChartViewTests test
```

Expected: PASS.

---

### Task 3: Monthly Page Wiring

**Files:**
- Modify: `TokenWatchTests/ViewControllers/MonthlyStatsViewControllerTests.swift`
- Modify: `TokenWatch/ViewControllers/MonthlyStatsViewController.swift`

- [ ] **Step 1: Write failing page tests**

In `MonthlyStatsViewControllerTests`, extend `rendersTitleSubtitleAndTotal`:

```swift
stats: makeStats(byMonth: ["2026-06": makeSummary(total: 1_200_000, cost: 12.5)]),
```

Add expectations:

```swift
#expect(labels.contains("$12.50"))

let costChartView = try #require(viewController.view.firstDescendant(ofType: MonthlyCostChartView.self))
#expect(costChartView.debugBarCount == 12)
```

Add a new test:

```swift
@MainActor
@Test("token 有数据但费用为零时仍展示费用图")
func rendersCostChartWhenCostIsZero() throws {
    let calendar = utcCalendar()
    let viewController = MonthlyStatsViewController(
        stateProvider: {
            [.claude: .init(
                stats: makeStats(byMonth: ["2026-06": makeSummary(total: 500, cost: 0)]),
                isLoading: false,
                errorMessage: nil,
                needsAuthorization: false
            )]
        },
        nowProvider: { date(2026, 6, 20, calendar: calendar) },
        calendar: calendar
    )

    viewController.loadViewIfNeeded()

    let costChartView = try #require(viewController.view.firstDescendant(ofType: MonthlyCostChartView.self))
    #expect(costChartView.debugBarCount == 12)
    #expect(costChartView.debugNormalizedHeights.allSatisfy { $0 == 0 })
}
```

Change the local helper:

```swift
private func makeSummary(total: Int, cost: Double = 0) -> UsageSummary {
    UsageSummary(
        inputTokens: total,
        outputTokens: 0,
        cacheReadTokens: 0,
        cacheCreationTokens: 0,
        reasoningTokens: 0,
        totalTokens: total,
        cost: cost,
        entryCount: 1,
        modelBreakdown: [:]
    )
}
```

- [ ] **Step 2: Run page test to verify it fails**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/MonthlyStatsViewControllerTests test
```

Expected: FAIL because `MonthlyStatsViewController` does not render the `$12.50` label or the cost chart.

- [ ] **Step 3: Wire cost summary and chart into page**

In `MonthlyStatsViewController.swift`, add properties:

```swift
private let costLabel = NSTextField(labelWithString: "$0.00")
private let costChartView = MonthlyCostChartView()
```

In `setupSubviews`, configure the label:

```swift
costLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .medium)
costLabel.textColor = .secondaryLabelColor
```

Set the cost chart layout:

```swift
costChartView.translatesAutoresizingMaskIntoConstraints = false
```

Use both summary labels in the header:

```swift
let summaryStack = NSStackView(views: [totalLabel, costLabel])
summaryStack.orientation = .vertical
summaryStack.alignment = .trailing
summaryStack.spacing = 4

let headerStack = NSStackView(views: [headerTextStack, summaryStack])
```

Add `costChartView` below `chartView` in `contentStack`:

```swift
let contentStack = NSStackView(views: [headerStack, chartView, costChartView, statusLabel])
```

Add constraints:

```swift
costChartView.leadingAnchor.constraint(equalTo: contentStack.leadingAnchor),
costChartView.trailingAnchor.constraint(equalTo: contentStack.trailingAnchor),
```

In `render`, configure cost UI:

```swift
costChartView.configure(with: snapshot)
costLabel.stringValue = formatCurrency(snapshot.totalCost)
```

Add the private formatter:

```swift
private func formatCurrency(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .currency
    formatter.currencyCode = "USD"
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
}
```

- [ ] **Step 4: Run page tests to verify green**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/MonthlyStatsViewControllerTests test
```

Expected: PASS.

---

### Task 4: Full Verification And Commit

**Files:**
- Verify all changed files.

- [ ] **Step 1: Run focused tests**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/MonthlyTokenChartBuilderTests -only-testing:TokenWatchTests/MonthlyTokenChartViewTests -only-testing:TokenWatchTests/MonthlyCostChartViewTests -only-testing:TokenWatchTests/MonthlyStatsViewControllerTests test
```

Expected: PASS.

- [ ] **Step 2: Run full unit tests**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests test
```

Expected: PASS.

- [ ] **Step 3: Review git diff**

Run:

```bash
git diff --stat
git diff -- TokenWatch/ViewControllers/MonthlyTokenChartBuilder.swift TokenWatch/ViewControllers/MonthlyCostChartView.swift TokenWatch/ViewControllers/MonthlyStatsViewController.swift TokenWatchTests/ViewControllers/MonthlyTokenChartBuilderTests.swift TokenWatchTests/ViewControllers/MonthlyTokenChartViewTests.swift TokenWatchTests/ViewControllers/MonthlyCostChartViewTests.swift TokenWatchTests/ViewControllers/MonthlyStatsViewControllerTests.swift
```

Expected: Only monthly cost chart files, tests, and this implementation plan changed; `.superpowers/` remains untouched.

- [ ] **Step 4: Commit implementation if verification passes**

Run:

```bash
git add TokenWatch/ViewControllers/MonthlyTokenChartBuilder.swift TokenWatch/ViewControllers/MonthlyCostChartView.swift TokenWatch/ViewControllers/MonthlyStatsViewController.swift TokenWatchTests/ViewControllers/MonthlyTokenChartBuilderTests.swift TokenWatchTests/ViewControllers/MonthlyTokenChartViewTests.swift TokenWatchTests/ViewControllers/MonthlyCostChartViewTests.swift TokenWatchTests/ViewControllers/MonthlyStatsViewControllerTests.swift docs/superpowers/plans/2026-06-21-monthly-cost-chart.md
git commit -m "feat(ui): 新增按月费用柱状图"
```

Expected: One implementation commit with tests and plan.
