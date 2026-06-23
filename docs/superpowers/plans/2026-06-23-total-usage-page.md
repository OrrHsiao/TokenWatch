# Total Usage Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a sidebar-level `总计` page above `最近 12 个月` that shows all-time cross-provider token totals, total cost, and model token usage sorted by consumption.

**Architecture:** Add a focused `TotalStatsBuilder` that converts provider states into a testable snapshot, then render that snapshot in `TotalStatsViewController`. Wire `ViewController` and the private sidebar model to route the new `总计` item without changing the default first-provider startup selection.

**Tech Stack:** Swift 6, AppKit, Swift Testing, existing file-system-synchronized Xcode project groups.

---

### Task 1: Total Snapshot Builder

**Files:**
- Create: `TokenWatch/ViewControllers/TotalStatsBuilder.swift`
- Test: `TokenWatchTests/ViewControllers/TotalStatsBuilderTests.swift`

- [ ] **Step 1: Write the failing builder tests**

Create `TokenWatchTests/ViewControllers/TotalStatsBuilderTests.swift`:

```swift
import Foundation
import Testing
@testable import TokenWatch

@Suite("TotalStatsBuilder")
struct TotalStatsBuilderTests {

    @Test("跨 provider 汇总总 token、费用和同模型 token")
    func sumsTotalsAndMergesModelsAcrossProviders() {
        let claudeStats = makeStats(
            total: 1_200,
            cost: 12.50,
            byModel: [
                "claude-sonnet": 900,
                "claude-haiku": 300,
            ]
        )
        let codexStats = makeStats(
            total: 800,
            cost: 4.25,
            byModel: [
                "gpt-5": 500,
                "claude-haiku": 300,
            ]
        )

        let snapshot = TotalStatsBuilder.build(states: [
            .claude: .init(stats: claudeStats, isLoading: false, errorMessage: nil, needsAuthorization: false),
            .codex: .init(stats: codexStats, isLoading: false, errorMessage: nil, needsAuthorization: false),
        ])

        #expect(snapshot.totalTokens == 2_000)
        #expect(snapshot.totalCost == 16.75)
        #expect(snapshot.modelRows.map(\.modelName) == ["claude-sonnet", "claude-haiku", "gpt-5"])
        #expect(snapshot.modelRows.map(\.totalTokens) == [900, 600, 500])
    }

    @Test("模型 token 相同时按模型名排序并过滤零值")
    func sortsEqualTokenModelsByNameAndFiltersZeroRows() {
        let stats = makeStats(
            total: 300,
            cost: 1.00,
            byModel: [
                "zeta": 100,
                "Alpha": 100,
                "empty": 0,
                "beta": 100,
            ]
        )

        let snapshot = TotalStatsBuilder.build(states: [
            .claude: .init(stats: stats, isLoading: false, errorMessage: nil, needsAuthorization: false),
        ])

        #expect(snapshot.modelRows.map(\.modelName) == ["Alpha", "beta", "zeta"])
        #expect(snapshot.modelRows.map(\.totalTokens) == [100, 100, 100])
    }

    @Test("统计 provider 状态")
    func countsProviderStatesAndCollectsErrors() {
        let snapshot = TotalStatsBuilder.build(states: [
            .claude: .init(stats: makeStats(total: 10), isLoading: false, errorMessage: nil, needsAuthorization: false),
            .codex: .init(stats: nil, isLoading: true, errorMessage: nil, needsAuthorization: false),
            .opencode: .init(stats: nil, isLoading: false, errorMessage: "OpenCode 失败", needsAuthorization: true),
        ])

        #expect(snapshot.loadedProviderCount == 1)
        #expect(snapshot.loadingProviderCount == 1)
        #expect(snapshot.unauthorizedProviderCount == 1)
        #expect(snapshot.errorMessages == ["OpenCode 失败"])
    }

    private func makeStats(
        total: Int,
        cost: Double = 0,
        byModel: [String: Int] = [:]
    ) -> AggregatedStats {
        let modelSummaries = byModel.mapValues { tokens in
            UsageSummary(
                inputTokens: tokens,
                outputTokens: 0,
                cacheReadTokens: 0,
                cacheCreationTokens: 0,
                reasoningTokens: 0,
                totalTokens: tokens,
                cost: 0,
                entryCount: tokens > 0 ? 1 : 0,
                modelBreakdown: [:]
            )
        }
        return AggregatedStats(
            overall: UsageSummary(
                inputTokens: total,
                outputTokens: 0,
                cacheReadTokens: 0,
                cacheCreationTokens: 0,
                reasoningTokens: 0,
                totalTokens: total,
                cost: cost,
                entryCount: total > 0 ? 1 : 0,
                modelBreakdown: modelSummaries
            ),
            byHour: [:],
            byDay: [:],
            byWeek: [:],
            byMonth: [:],
            bySession: [:],
            byModel: modelSummaries,
            byProject: [:],
            dataSourceCount: 1
        )
    }
}
```

- [ ] **Step 2: Run the builder tests to verify RED**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/TotalStatsBuilderTests test
```

Expected: build fails because `TotalStatsBuilder` is not defined.

- [ ] **Step 3: Add the minimal builder implementation**

Create `TokenWatch/ViewControllers/TotalStatsBuilder.swift`:

```swift
import Foundation

/// 总计页的完整数据快照,供 UI 直接渲染。
struct TotalStatsSnapshot: Sendable, Equatable {
    let totalTokens: Int
    let totalCost: Double
    let modelRows: [TotalStatsModelRow]
    let loadedProviderCount: Int
    let loadingProviderCount: Int
    let unauthorizedProviderCount: Int
    let errorMessages: [String]
}

/// 总计页中的单个模型用量行。
struct TotalStatsModelRow: Sendable, Equatable, Identifiable {
    let modelName: String
    let totalTokens: Int

    var id: String { modelName }
}

/// 将多 provider 状态构建为全量总计快照。
enum TotalStatsBuilder {
    /// 汇总所有已加载 provider 的全量 token、费用和模型 token。
    /// - Parameter states: 各 provider 的统计状态;没有 stats 的 provider 不参与用量求和。
    /// - Returns: 可直接渲染的总计页快照。
    static func build(states: [ProviderID: TokenStatsViewModel.ProviderState]) -> TotalStatsSnapshot {
        var totalTokens = 0
        var totalCost = 0.0
        var modelTotals: [String: Int] = [:]
        var loadedProviderCount = 0
        var loadingProviderCount = 0
        var unauthorizedProviderCount = 0
        var errorMessages: [String] = []

        for (_, state) in states {
            if state.isLoading {
                loadingProviderCount += 1
            }
            if state.needsAuthorization {
                unauthorizedProviderCount += 1
            }
            if let errorMessage = state.errorMessage {
                errorMessages.append(errorMessage)
            }
            guard let stats = state.stats else { continue }

            loadedProviderCount += 1
            totalTokens += stats.overall.totalTokens
            totalCost += stats.overall.cost
            for (model, summary) in stats.byModel {
                modelTotals[model, default: 0] += summary.totalTokens
            }
        }

        let modelRows = modelTotals
            .filter { $0.value > 0 }
            .sorted { lhs, rhs in
                if lhs.value != rhs.value {
                    return lhs.value > rhs.value
                }
                return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
            }
            .map { TotalStatsModelRow(modelName: $0.key, totalTokens: $0.value) }

        return TotalStatsSnapshot(
            totalTokens: totalTokens,
            totalCost: totalCost,
            modelRows: modelRows,
            loadedProviderCount: loadedProviderCount,
            loadingProviderCount: loadingProviderCount,
            unauthorizedProviderCount: unauthorizedProviderCount,
            errorMessages: errorMessages
        )
    }
}
```

- [ ] **Step 4: Run the builder tests to verify GREEN**

Run the same `xcodebuild ... TotalStatsBuilderTests test` command. Expected: PASS.

### Task 2: Total Stats View Controller

**Files:**
- Create: `TokenWatch/ViewControllers/TotalStatsViewController.swift`
- Test: `TokenWatchTests/ViewControllers/TotalStatsViewControllerTests.swift`

- [ ] **Step 1: Write failing page tests**

Create `TokenWatchTests/ViewControllers/TotalStatsViewControllerTests.swift` with tests that instantiate `TotalStatsViewController(stateProvider:)`, assert labels contain `总计`, `跨 provider 全量汇总`, formatted total token, formatted total cost, model rows in sorted order, and status strings for loading, authorization, no data, and provider errors.

- [ ] **Step 2: Run page tests to verify RED**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/TotalStatsViewControllerTests test
```

Expected: build fails because `TotalStatsViewController` is not defined.

- [ ] **Step 3: Add the page implementation**

Create `TokenWatch/ViewControllers/TotalStatsViewController.swift`:

- Use `NSScrollView` + vertical `NSStackView`.
- Header labels: `总计`, `跨 provider 全量汇总`.
- Summary stack with `CompactNumberFormatter.formatMillions(snapshot.totalTokens)` and `String(format: "$%.2f", snapshot.totalCost)`.
- Model section title `模型消耗`.
- Rebuild model rows on every render; each row has left model name and right token total.
- Subscribe to `.providerStateDidChange` and re-render.
- Status text follows the spec order.

- [ ] **Step 4: Run page tests to verify GREEN**

Run the same `xcodebuild ... TotalStatsViewControllerTests test` command. Expected: PASS.

### Task 3: Sidebar Routing

**Files:**
- Modify: `TokenWatch/ViewController.swift`
- Test: `TokenWatchTests/TokenWatchTests.swift`

- [ ] **Step 1: Write failing routing tests**

Modify `TokenWatchTests/TokenWatchTests.swift`:

- Change sidebar expected titles to append `["总计", "最近 12 个月", "最近 30 天", "本日", "设置"]`.
- Add `selectingTotalShowsTotalStatsPage`, selecting row `sidebar.numberOfRows - 5`, then assert labels contain `总计` and `跨 provider 全量汇总`.
- Update the monthly/recent/today row offsets to `-4`, `-3`, `-2` after adding `总计`.

- [ ] **Step 2: Run routing tests to verify RED**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/TokenWatchTests test
```

Expected: fails because the sidebar does not contain `总计` and selecting the new row does not route.

- [ ] **Step 3: Implement sidebar routing**

Modify `TokenWatch/ViewController.swift`:

- Add `private let totalStatsViewController = TotalStatsViewController()`.
- Add `case total` to `SidebarContent`.
- Add `case total` to `ProviderSidebarItem`, title `总计`.
- Add `var onSelectTotal: (() -> Void)?` to `ProviderSidebarViewController`.
- Change items to `providers.map { .provider($0) } + [.total, .monthly, .recentThirtyDays, .today, .settings]`.
- Wire `sidebarViewController.onSelectTotal = { [weak self] in self?.showTotal() }`.
- Add `private func showTotal()` that installs `totalStatsViewController` and sets `selectedContent = .total`.
- In `tableViewSelectionDidChange`, call `onSelectTotal?()` for `.total`.

- [ ] **Step 4: Run routing tests to verify GREEN**

Run the same `xcodebuild ... TokenWatchTests test` command. Expected: PASS.

### Task 4: Full Verification

**Files:**
- No source changes expected unless verification finds failures.

- [ ] **Step 1: Run focused tests**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/TotalStatsBuilderTests -only-testing:TokenWatchTests/TotalStatsViewControllerTests -only-testing:TokenWatchTests/TokenWatchTests test
```

Expected: PASS.

- [ ] **Step 2: Run the full unit test bundle**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests test
```

Expected: PASS.

- [ ] **Step 3: Review git diff**

Run:

```bash
git diff -- TokenWatch TokenWatchTests docs/superpowers/plans/2026-06-23-total-usage-page.md
```

Expected: only total-page builder, controller, routing, tests, and this plan changed.
