# Statusbar Hourly Line Chart Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在状态栏左键 popover 的热力图下方增加一张用系统 Charts 绘制的本日 24 小时 token 用量折线图。

**Architecture:** 新增 `TodayHourlyTokenLineChartView`,这是一个 AppKit `NSView` 包装层,内部用 `NSHostingView<AnyView>` 承载 SwiftUI `Chart`。`StatusPopoverViewController` 继续负责数据装配,复用 `MonthlyTokenChartBuilder.build(period: .today)` 生成小时桶,并把 hover 文案汇入现有 hover label。

**Tech Stack:** Swift 6.0, AppKit, SwiftUI, Charts, Swift Testing。

---

## File Structure

| 文件 | 责任 | 改动类型 |
|---|---|---|
| `TokenWatch/ViewControllers/TodayHourlyTokenLineChartView.swift` | popover 专用本日小时 Charts 折线图视图 | 新增 |
| `TokenWatch/ViewControllers/StatusPopoverViewController.swift` | 将折线图接入 popover 布局与渲染 | 修改 |
| `TokenWatchTests/ViewControllers/TodayHourlyTokenLineChartViewTests.swift` | 折线图视图单元测试 | 新增 |
| `TokenWatchTests/ViewControllers/StatusPopoverViewControllerTests.swift` | popover 集成与布局测试 | 修改 |

Xcode 项目使用 `PBXFileSystemSynchronizedRootGroup`,新增 Swift 文件放进对应目录即可自动纳入 target,不需要手改 `TokenWatch.xcodeproj/project.pbxproj`。

---

### Task 1: TodayHourlyTokenLineChartView 测试先行

**Files:**
- Create: `TokenWatchTests/ViewControllers/TodayHourlyTokenLineChartViewTests.swift`

- [ ] **Step 1: 写失败测试文件**

创建 `TokenWatchTests/ViewControllers/TodayHourlyTokenLineChartViewTests.swift`:

```swift
import AppKit
import SwiftUI
import Testing
@testable import TokenWatch

@MainActor
@Suite("TodayHourlyTokenLineChartView")
struct TodayHourlyTokenLineChartViewTests {

    @Test("配置 snapshot 后保留二十四个小时点并使用 Charts 宿主")
    func configureRendersTwentyFourHourlyPoints() throws {
        let view = TodayHourlyTokenLineChartView()
        let snapshot = makeSnapshot(tokens: Array(0..<24).map { $0 * 10 })

        view.configure(with: snapshot)

        #expect(view.debugPointCount == 24)
        #expect(view.debugXAxisLabels == ["0", "6", "12", "18", "23"])
        #expect(view.debugNormalizedHeights.first == 0)
        #expect(view.debugNormalizedHeights.last == 1.0)
        #expect(view.allDescendants(ofType: NSHostingView<AnyView>.self).count == 1)
    }

    @Test("全零数据保持稳定高度")
    func zeroDataKeepsStableLineState() {
        let view = TodayHourlyTokenLineChartView()
        let snapshot = makeSnapshot(tokens: Array(repeating: 0, count: 24))

        view.configure(with: snapshot)

        #expect(view.debugPointCount == 24)
        #expect(view.debugNormalizedHeights.allSatisfy { $0 == 0 })
    }

    @Test("鼠标划过小时点时回传该小时 token 文案")
    func hoveringHourEmitsTokenUsageText() {
        let view = TodayHourlyTokenLineChartView()
        let snapshot = makeSnapshot(tokens: Array(repeating: 0, count: 24), override: [9: 1_234_567])
        var hoverTexts: [String?] = []
        view.onHoverTextChange = { hoverTexts.append($0) }

        view.configure(with: snapshot)
        view.debugSimulateHover(monthKey: "2026-06-20T09")
        view.debugSimulateHover(monthKey: nil)

        #expect(hoverTexts == ["9时 · 1.2M", nil])
    }

    @Test("英文 hover 小时标签不带中文时")
    func englishHoverTextUsesHourNumberOnly() {
        let view = TodayHourlyTokenLineChartView()
        let snapshot = makeSnapshot(tokens: Array(repeating: 0, count: 24), override: [14: 250_000])
        var hoverTexts: [String?] = []
        view.onHoverTextChange = { hoverTexts.append($0) }

        view.configure(with: snapshot, language: .en)
        view.debugSimulateHover(monthKey: "2026-06-20T14")

        #expect(hoverTexts == ["14 · 250.0k"])
    }

    private func makeSnapshot(tokens: [Int], override: [Int: Int] = [:]) -> MonthlyTokenChartSnapshot {
        let resolvedTokens = tokens.enumerated().map { index, total in
            override[index] ?? total
        }
        let maxTokens = resolvedTokens.max() ?? 0
        let buckets = resolvedTokens.indices.map { index in
            let total = resolvedTokens[index]
            let key = String(format: "2026-06-20T%02d", index)
            return MonthlyTokenBucket(
                id: key,
                monthKey: key,
                monthLabel: "\(index)时",
                totalTokens: total,
                totalCost: 0,
                normalizedHeight: maxTokens > 0 ? Double(total) / Double(maxTokens) : 0,
                normalizedCostHeight: 0,
                isCurrentMonth: index == 14,
                modelSegments: []
            )
        }

        return MonthlyTokenChartSnapshot(
            monthBuckets: buckets,
            totalTokens: resolvedTokens.reduce(0, +),
            totalCost: 0,
            maxMonthlyTokens: maxTokens,
            maxMonthlyCost: 0,
            toolShareSlices: [],
            modelShareSlices: [],
            loadedProviderCount: 1,
            loadingProviderCount: 0,
            unauthorizedProviderCount: 0,
            errorMessages: []
        )
    }
}

private extension NSView {
    func allDescendants<T: NSView>(ofType type: T.Type) -> [T] {
        let current = (self as? T).map { [$0] } ?? []
        return current + subviews.flatMap { $0.allDescendants(ofType: type) }
    }
}
```

- [ ] **Step 2: 运行新测试确认失败**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/TodayHourlyTokenLineChartViewTests test
```

Expected: FAIL,编译错误提示 `Cannot find 'TodayHourlyTokenLineChartView' in scope`。

---

### Task 2: 实现 Charts 折线图视图

**Files:**
- Create: `TokenWatch/ViewControllers/TodayHourlyTokenLineChartView.swift`
- Test: `TokenWatchTests/ViewControllers/TodayHourlyTokenLineChartViewTests.swift`

- [ ] **Step 1: 新增最小可用视图**

创建 `TokenWatch/ViewControllers/TodayHourlyTokenLineChartView.swift`:

```swift
import AppKit
import Charts
import SwiftUI

/// 状态栏 popover 专用的本日小时 token 折线图。
final class TodayHourlyTokenLineChartView: NSView {
    private static let visibleAxisHourIndexes = [0, 6, 12, 18, 23]

    private let chartHost = NSHostingView(rootView: AnyView(TodayHourlyTokenLineChartContent(
        buckets: [],
        language: .zhHans,
        axisKeys: [],
        accessibilityLabelText: UsageStatsPeriod.today.tokenChartAccessibilityLabel(language: .zhHans),
        onHoverMonthKeyChange: { _ in }
    )))
    private var buckets: [MonthlyTokenBucket] = []
    private var language: AppLanguage = .zhHans

    private(set) var debugNormalizedHeights: [Double] = []
    private(set) var debugXAxisLabels: [String] = []
    private(set) var debugAccessibilityLabel = UsageStatsPeriod.today
        .tokenChartAccessibilityLabel(language: .zhHans)
    var onHoverTextChange: ((String?) -> Void)?

    var debugPointCount: Int { buckets.count }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    func configure(with snapshot: MonthlyTokenChartSnapshot, language: AppLanguage = .zhHans) {
        self.language = language
        buckets = snapshot.monthBuckets
        debugNormalizedHeights = snapshot.monthBuckets.map { clampHourlyNormalizedHeight($0.normalizedHeight) }
        debugXAxisLabels = Self.visibleAxisHourIndexes.compactMap { index in
            guard snapshot.monthBuckets.indices.contains(index) else { return nil }
            return MonthlyBarChartStyle.monthAxisLabel(
                for: snapshot.monthBuckets[index].monthKey,
                language: language
            )
        }
        debugAccessibilityLabel = UsageStatsPeriod.today.tokenChartAccessibilityLabel(language: language)

        let axisKeys = Self.visibleAxisHourIndexes.compactMap { index in
            snapshot.monthBuckets.indices.contains(index) ? snapshot.monthBuckets[index].monthKey : nil
        }
        chartHost.rootView = AnyView(TodayHourlyTokenLineChartContent(
            buckets: snapshot.monthBuckets,
            language: language,
            axisKeys: axisKeys,
            accessibilityLabelText: debugAccessibilityLabel,
            onHoverMonthKeyChange: { [weak self] monthKey in
                self?.updateHoverText(monthKey: monthKey)
            }
        ))
    }

    func debugSimulateHover(monthKey: String?) {
        updateHoverText(monthKey: monthKey)
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        chartHost.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chartHost)
        NSLayoutConstraint.activate([
            chartHost.leadingAnchor.constraint(equalTo: leadingAnchor),
            chartHost.trailingAnchor.constraint(equalTo: trailingAnchor),
            chartHost.topAnchor.constraint(equalTo: topAnchor),
            chartHost.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func updateHoverText(monthKey: String?) {
        guard let monthKey,
              let bucket = buckets.first(where: { $0.monthKey == monthKey }) else {
            onHoverTextChange?(nil)
            return
        }
        let periodLabel = MonthlyBarChartStyle.hoverPeriodLabel(
            for: bucket.monthKey,
            fallback: bucket.monthLabel,
            language: language
        )
        onHoverTextChange?("\(periodLabel) · \(CompactNumberFormatter.formatMillions(bucket.totalTokens))")
    }
}
```

- [ ] **Step 2: 在同文件追加 SwiftUI Charts 内容**

在 `TodayHourlyTokenLineChartView.swift` 末尾追加:

```swift
private func clampHourlyNormalizedHeight(_ value: Double) -> Double {
    guard value.isFinite else { return 0 }
    return min(max(value, 0), 1)
}

private struct TodayHourlyTokenLineChartContent: View {
    let buckets: [MonthlyTokenBucket]
    let language: AppLanguage
    let axisKeys: [String]
    let accessibilityLabelText: String
    let onHoverMonthKeyChange: (String?) -> Void

    private var maxTokens: Double {
        max(1, Double(buckets.map(\.totalTokens).max() ?? 0))
    }

    var body: some View {
        Chart {
            ForEach(buckets) { bucket in
                LineMark(
                    x: .value(axisValueName, bucket.monthKey),
                    y: .value("Tokens", Double(bucket.totalTokens))
                )
                .foregroundStyle(Color(nsColor: .controlAccentColor))
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .accessibilityLabel(accessibilityLabel(for: bucket))
                .accessibilityValue(CompactNumberFormatter.formatMillions(bucket.totalTokens))

                if bucket.isCurrentMonth {
                    PointMark(
                        x: .value(axisValueName, bucket.monthKey),
                        y: .value("Tokens", Double(bucket.totalTokens))
                    )
                    .foregroundStyle(Color(nsColor: .controlAccentColor))
                    .symbolSize(22)
                }
            }
        }
        .chartLegend(.hidden)
        .chartYScale(domain: 0...maxTokens)
        .chartXAxis {
            AxisMarks(values: axisKeys) { value in
                AxisTick()
                AxisValueLabel {
                    if let monthKey = value.as(String.self) {
                        Text(MonthlyBarChartStyle.monthAxisLabel(for: monthKey, language: language))
                            .font(.system(size: 8))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                    .foregroundStyle(.secondary.opacity(0.16))
                AxisTick()
                if let tokens = value.as(Double.self) {
                    AxisValueLabel(MonthlyBarChartStyle.tokenAxisLabel(for: tokens))
                        .font(.system(size: 8))
                }
            }
        }
        .chartOverlay { proxy in
            hoverOverlay(proxy: proxy)
        }
        .padding(.top, 4)
        .accessibilityLabel(accessibilityLabelText)
    }

    private var axisValueName: String {
        language.periodAxisValueName
    }

    private func accessibilityLabel(for bucket: MonthlyTokenBucket) -> String {
        MonthlyBarChartStyle.hoverPeriodLabel(
            for: bucket.monthKey,
            fallback: bucket.monthLabel,
            language: language
        )
    }

    private func hoverOverlay(proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    guard let plotFrame = proxy.plotFrame else {
                        onHoverMonthKeyChange(nil)
                        return
                    }
                    let frame = geometry[plotFrame]
                    switch phase {
                    case .active(let location):
                        guard frame.contains(location) else {
                            onHoverMonthKeyChange(nil)
                            return
                        }
                        let xPosition = location.x - frame.origin.x
                        onHoverMonthKeyChange(proxy.value(atX: xPosition, as: String.self))
                    case .ended:
                        onHoverMonthKeyChange(nil)
                    }
                }
        }
    }
}
```

- [ ] **Step 3: 运行折线图测试确认通过**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/TodayHourlyTokenLineChartViewTests test
```

Expected: PASS。

---

### Task 3: StatusPopoverViewController 集成测试先行

**Files:**
- Modify: `TokenWatchTests/ViewControllers/StatusPopoverViewControllerTests.swift`

- [ ] **Step 1: 在 popover 测试中加入折线图断言**

在 `loadViewCreatesTwentyTwoColumnCollectionView()` 末尾追加:

```swift
        #expect(controller.debugHourlyLineChartView != nil)
        #expect(controller.debugHourlyLineChartPointCount == 24)
        #expect(controller.debugHourlyLineChartXAxisLabels == ["0", "6", "12", "18", "23"])
```

- [ ] **Step 2: 在布局测试区域加入折线图布局测试**

在 `collectionViewWidthFitsTwentyTwoWeekColumns()` 后追加:

```swift
    @Test("本日小时折线图位于热力图下方并与热力图等宽")
    func hourlyLineChartSitsBelowHeatmapAndMatchesWidth() {
        let controller = makeController()

        controller.loadViewIfNeeded()
        controller.view.layoutSubtreeIfNeeded()

        #expect(controller.debugHourlyLineChartSitsBelowCollectionView)
        #expect(controller.debugHourlyLineChartWidthMatchesCollectionView)
        #expect(controller.debugHourlyLineChartBottomFitsInRootBounds)
    }
```

- [ ] **Step 3: 在 hover 测试区域加入折线图 hover 复用测试**

在 `hoverTextAppearsAtHeatmapTopTrailingCorner()` 后追加:

```swift
    @Test("折线图 hover 复用热力图 hover label")
    func hourlyLineChartHoverUsesSharedHoverLabel() {
        let controller = makeController()

        controller.loadViewIfNeeded()
        controller.debugSimulateHourlyLineChartHover(monthKey: "2026-06-17T09")

        #expect(controller.debugHoverText == "9时 · 0")

        controller.debugSimulateHourlyLineChartHover(monthKey: nil)
        #expect(controller.debugHoverText == "")
    }
```

- [ ] **Step 4: 运行 popover 测试确认失败**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/StatusPopoverViewControllerTests test
```

Expected: FAIL,编译错误提示缺少 `debugHourlyLineChartView`、`debugHourlyLineChartPointCount` 等 debug API。

---

### Task 4: 接入 StatusPopoverViewController

**Files:**
- Modify: `TokenWatch/ViewControllers/StatusPopoverViewController.swift`
- Test: `TokenWatchTests/ViewControllers/StatusPopoverViewControllerTests.swift`

- [ ] **Step 1: 添加尺寸常量和折线图属性**

在 `StatusPopoverViewController` 常量区域调整 `contentSize` 并新增常量:

```swift
    nonisolated static let contentSize = NSSize(width: 370, height: 318)
    private static let hourlyLineChartTopSpacing: CGFloat = 14
    private static let hourlyLineChartHeight: CGFloat = 74
```

在视图属性区域新增:

```swift
    private let hourlyLineChartView = TodayHourlyTokenLineChartView()
```

- [ ] **Step 2: 添加 debug API**

在现有 debug 属性区域追加:

```swift
    var debugHourlyLineChartView: TodayHourlyTokenLineChartView? { hourlyLineChartView }
    var debugHourlyLineChartPointCount: Int { hourlyLineChartView.debugPointCount }
    var debugHourlyLineChartXAxisLabels: [String] { hourlyLineChartView.debugXAxisLabels }
    var debugHourlyLineChartSitsBelowCollectionView: Bool {
        hasConstraint(
            firstItem: hourlyLineChartView,
            firstAttribute: .top,
            secondItem: collectionView,
            secondAttribute: .bottom,
            constant: Self.hourlyLineChartTopSpacing
        )
    }
    var debugHourlyLineChartWidthMatchesCollectionView: Bool {
        hasConstraint(
            firstItem: hourlyLineChartView,
            firstAttribute: .width,
            secondItem: collectionView,
            secondAttribute: .width,
            constant: 0
        )
    }
    var debugHourlyLineChartBottomFitsInRootBounds: Bool {
        let frameInRoot = hourlyLineChartView.convert(hourlyLineChartView.bounds, to: view)
        return frameInRoot.minY >= Self.outerMargin
            && frameInRoot.maxY <= view.bounds.maxY - Self.outerMargin
    }
    func debugSimulateHourlyLineChartHover(monthKey: String?) {
        hourlyLineChartView.debugSimulateHover(monthKey: monthKey)
    }
```

- [ ] **Step 3: 在 setupSubviews 中配置和约束折线图**

在 `collectionView.translatesAutoresizingMaskIntoConstraints = false` 后追加:

```swift
        hourlyLineChartView.translatesAutoresizingMaskIntoConstraints = false
        hourlyLineChartView.onHoverTextChange = { [weak self] text in
            self?.updateHoverText(text)
        }
```

在 `view.addSubview(collectionView)` 后追加:

```swift
        view.addSubview(hourlyLineChartView)
```

在约束列表中,保留 collection view 现有约束,再追加:

```swift
            hourlyLineChartView.topAnchor.constraint(
                equalTo: collectionView.bottomAnchor,
                constant: Self.hourlyLineChartTopSpacing
            ),
            hourlyLineChartView.centerXAnchor.constraint(equalTo: collectionView.centerXAnchor),
            hourlyLineChartView.widthAnchor.constraint(equalTo: collectionView.widthAnchor),
            hourlyLineChartView.heightAnchor.constraint(equalToConstant: Self.hourlyLineChartHeight),
            hourlyLineChartView.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -Self.outerMargin),
```

- [ ] **Step 4: 在 render 中配置小时折线图**

在 `render()` 中 `self.snapshot = snapshot` 之后追加:

```swift
        let hourlySnapshot = MonthlyTokenChartBuilder.build(
            states: viewModel.states,
            period: .today,
            now: now,
            calendar: calendar,
            language: language
        )
        hourlyLineChartView.configure(with: hourlySnapshot, language: language)
```

- [ ] **Step 5: 运行 popover 测试确认通过**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/StatusPopoverViewControllerTests test
```

Expected: PASS。

---

### Task 5: 集成验证

**Files:**
- Verify all changed files

- [ ] **Step 1: 运行两个相关测试套件**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/TodayHourlyTokenLineChartViewTests -only-testing:TokenWatchTests/StatusPopoverViewControllerTests test
```

Expected: PASS。

- [ ] **Step 2: 运行完整单元测试 target**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests test
```

Expected: PASS。

- [ ] **Step 3: 查看工作区 diff**

Run:

```bash
git diff -- TokenWatch/ViewControllers/TodayHourlyTokenLineChartView.swift TokenWatch/ViewControllers/StatusPopoverViewController.swift TokenWatchTests/ViewControllers/TodayHourlyTokenLineChartViewTests.swift TokenWatchTests/ViewControllers/StatusPopoverViewControllerTests.swift
```

Expected: diff 只包含本日小时折线图及其测试,没有无关重构。
