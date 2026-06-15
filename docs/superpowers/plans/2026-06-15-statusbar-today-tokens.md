# 状态栏当日 Token 数显示 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 macOS 状态栏长驻一个图标 + 文本,展示「今日所有 provider 累加的 token 数」,定时刷新,并提供下拉菜单(打开主窗口 / 立即刷新 / 退出)。

**Architecture:** 新增 `StatusBarController`(`@MainActor`) 持有 `NSStatusItem`,订阅 `TokenStatsViewModel` 的状态变更回调,直接复用现有 `byDay` 聚合结果。`TokenStatsViewModel` 把单一 `onStateChange` 闭包改造为多订阅 API(`observe` / `removeObserver`),让主窗口和状态栏可以同时订阅。文本生成、汇总计算抽成纯函数便于单元测试。

**Tech Stack:** Swift 6.0、AppKit (`NSStatusItem` / `NSMenu` / `Timer`)、Swift Testing、`@MainActor` actor isolation。

**关联 spec:** `docs/superpowers/specs/2026-06-15-statusbar-today-tokens-design.md`

---

## 文件结构

| 类型 | 路径 | 职责 |
|------|------|------|
| 新增 | `TokenWatch/ViewControllers/StatusBarController.swift` | 持有 `NSStatusItem` + `NSMenu` + 刷新 Timer,订阅 ViewModel 状态变化 |
| 新增 | `TokenWatch/ViewControllers/StatusBarTitleBuilder.swift` | 纯函数:从 `[ProviderID: ProviderState]` + today key 计算状态栏文本 |
| 新增 | `TokenWatch/ViewControllers/CompactNumberFormatter.swift` | 纯函数:`Int → "1.2k"/"1.2M"` 缩写 |
| 新增 | `TokenWatch/Assets.xcassets/StatusBarIcon.imageset/` | 状态栏图标资产(Template Image,占位 PNG) |
| 修改 | `TokenWatch/ViewModels/TokenStatsViewModel.swift` | 把单一 `onStateChange` 替换为 `observe(_:)` / `removeObserver(_:)` |
| 修改 | `TokenWatch/ViewController.swift` | 迁移到 `observe` API,在 `deinit` 移除 |
| 修改 | `TokenWatch/AppDelegate.swift` | 创建 `StatusBarController` 并管理生命周期 |
| 新增 | `TokenWatchTests/ViewModels/TokenStatsViewModelObserverTests.swift` | 多订阅 + remove 行为 |
| 新增 | `TokenWatchTests/ViewControllers/CompactNumberFormatterTests.swift` | 缩写边界 |
| 新增 | `TokenWatchTests/ViewControllers/StatusBarTitleBuilderTests.swift` | title 纯函数行为 |

> 测试文件归在 `TokenWatchTests/ViewControllers/` 下与生产代码一致;若该目录不存在,在第一个测试任务里创建。

### ⚠️ Xcode 项目文件索引

TokenWatch 是 `.xcodeproj` 项目,**新增 `.swift` 源文件后必须把它加进对应 target**,否则 `xcodebuild build/test` 找不到符号。每个新增文件的 task 在 build/test 之前都需要执行下述任一方法:

- **方法 A(推荐,无需开 GUI)**:用 `mcp__xcode__XcodeWrite` 工具创建文件,Xcode MCP 会自动把文件加到当前默认 target;
- **方法 B**:在 Xcode 里手动 `File → Add Files to "TokenWatch"…`,生产代码勾 `TokenWatch` target,测试代码勾 `TokenWatchTests` target;
- **方法 C**:用 `xcodeproj` Ruby gem 或 `pbxproj` CLI 编辑 `.pbxproj`(本计划不采用)。

如果某个 task 的 build/test 步骤报 `cannot find type/file in scope`,99% 是文件没加到 target — 回去用方法 A 或 B 处理。

---

### Task 1: 改造 `TokenStatsViewModel` 为多订阅 API

**Files:**
- Modify: `TokenWatch/ViewModels/TokenStatsViewModel.swift`
- Test: `TokenWatchTests/ViewModels/TokenStatsViewModelObserverTests.swift`

**说明**:把目前的单一 `onStateChange` 闭包属性替换为 `observe(_:)` 注册 + `removeObserver(_:)` 取消的多订阅 API。`ViewController` 之后的 task 再迁移过去。

- [ ] **Step 1: 写失败的测试**

创建 `TokenWatchTests/ViewModels/TokenStatsViewModelObserverTests.swift`:

```swift
import Testing
@testable import TokenWatch

@MainActor
struct TokenStatsViewModelObserverTests {

    /// 多个 observer 都能收到通知
    @Test func multipleObserversAllReceiveNotification() async throws {
        let vm = TokenStatsViewModel()

        var firstReceived: [ProviderID] = []
        var secondReceived: [ProviderID] = []

        _ = vm.observe { id in firstReceived.append(id) }
        _ = vm.observe { id in secondReceived.append(id) }

        // 触发未授权路径,会同步 notify 一次
        await vm.loadStats(for: .claude)

        #expect(firstReceived.contains(.claude))
        #expect(secondReceived.contains(.claude))
    }

    /// removeObserver 之后该 observer 不再收到
    @Test func removedObserverStopsReceiving() async throws {
        let vm = TokenStatsViewModel()

        var received: [ProviderID] = []
        let token = vm.observe { id in received.append(id) }

        vm.removeObserver(token)

        await vm.loadStats(for: .claude)

        #expect(received.isEmpty)
    }

    /// 不同 observer 拿到的 token 不同(可独立移除)
    @Test func observeReturnsDistinctTokens() {
        let vm = TokenStatsViewModel()
        let t1 = vm.observe { _ in }
        let t2 = vm.observe { _ in }
        #expect(t1 != t2)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' \
  -only-testing:TokenWatchTests/TokenStatsViewModelObserverTests test
```

预期:编译失败 — `observe` / `removeObserver` 未定义。

- [ ] **Step 3: 修改 `TokenStatsViewModel.swift` 引入多订阅 API**

把现有 `onStateChange` 属性、`notifyStateChange` 方法替换为:

```swift
/// observer 注册凭证;移除 observer 时使用
struct ObservationToken: Hashable, Sendable {
    let id: UUID
}

/// 已注册的 observer。key 为 token,value 为 main-actor 隔离的回调
private var observers: [ObservationToken: @MainActor (ProviderID) -> Void] = [:]

/// 注册状态变更监听
/// - Parameter handler: 任一 provider 状态变化时被调用
/// - Returns: 凭证,后续可用于 removeObserver
@discardableResult
func observe(_ handler: @escaping @MainActor (ProviderID) -> Void) -> ObservationToken {
    let token = ObservationToken(id: UUID())
    observers[token] = handler
    return token
}

/// 取消之前 observe 注册的回调
func removeObserver(_ token: ObservationToken) {
    observers.removeValue(forKey: token)
}

/// 通知所有 observer 指定 provider 状态变更
private func notifyStateChange(_ id: ProviderID) {
    for handler in observers.values {
        handler(id)
    }
}
```

同时**删除** `var onStateChange: (@MainActor (ProviderID) -> Void)?` 属性;`notifyStateChange` 内部从 `onStateChange?(id)` 改为遍历 `observers`(若按上面 patch 整段替换则已完成)。

- [ ] **Step 4: 跑测试确认通过**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' \
  -only-testing:TokenWatchTests/TokenStatsViewModelObserverTests test
```

预期:编译通过,3 个测试全部 PASS。

> 注:此时 `ViewController.swift` 仍引用旧 `onStateChange` 属性,**整体 build 会失败**。下一个 task 修复。

- [ ] **Step 5: 暂不 commit**,合并到 Task 2 一起提交,避免中间状态破坏 build。

---

### Task 2: 迁移 `ViewController` 到新 observer API

**Files:**
- Modify: `TokenWatch/ViewController.swift`

**说明**:`ViewController.bindViewModel()` 当前赋值 `viewModel?.onStateChange = …`;改为 `observe`,持有 token,在 `deinit` 移除。

- [ ] **Step 1: 修改 `ViewController.swift`**

在类内新增属性,改写 `bindViewModel`,并新增 `deinit`:

```swift
/// observer 凭证 — 用于 deinit 时取消订阅,避免 ViewModel 持有失效闭包
private var observerToken: TokenStatsViewModel.ObservationToken?

private func bindViewModel() {
    observerToken = viewModel?.observe { providerID in
        NotificationCenter.default.post(
            name: .providerStateDidChange,
            object: nil,
            userInfo: ["providerID": providerID]
        )
    }
}

deinit {
    if let token = observerToken {
        // ViewModel 由 AppDelegate 强引用、与本类生命周期相近,
        // 仍显式 remove 以避免 storyboard 重建场景下的回调泄漏
        Task { @MainActor [token] in
            (NSApp.delegate as? AppDelegate)?.viewModel.removeObserver(token)
        }
    }
}
```

- [ ] **Step 2: 跑全量测试 + build**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' test
```

预期:编译通过,所有现有测试 + 新增 3 个 observer 测试全 PASS。

- [ ] **Step 3: Commit**

```bash
git add TokenWatch/ViewModels/TokenStatsViewModel.swift \
        TokenWatch/ViewController.swift \
        TokenWatchTests/ViewModels/TokenStatsViewModelObserverTests.swift
git commit -m "refactor(viewmodel): onStateChange 改为多订阅 observe API"
```

---

### Task 3: 实现 `CompactNumberFormatter` 纯函数 + 测试

**Files:**
- Create: `TokenWatch/ViewControllers/CompactNumberFormatter.swift`
- Test: `TokenWatchTests/ViewControllers/CompactNumberFormatterTests.swift`

**说明**:状态栏文本里的 token 缩写。规则:

| 区间 | 输出 |
|------|------|
| `0..<1_000` | `"0"` / `"823"` |
| `1_000..<100_000` | `"1.2k"` / `"99.9k"`(保留一位小数) |
| `100_000..<1_000_000` | `"823k"`(去小数) |
| `1_000_000..<10_000_000` | `"1.2M"` / `"9.9M"`(保留一位小数) |
| `>=10_000_000` | `"12M"` / `"123M"`(去小数) |

负数视作 0(防御)。

- [ ] **Step 1: 写失败的测试**

创建 `TokenWatchTests/ViewControllers/CompactNumberFormatterTests.swift`:

```swift
import Testing
@testable import TokenWatch

struct CompactNumberFormatterTests {

    @Test func zeroAndSmallIntegers() {
        #expect(CompactNumberFormatter.format(0) == "0")
        #expect(CompactNumberFormatter.format(1) == "1")
        #expect(CompactNumberFormatter.format(823) == "823")
        #expect(CompactNumberFormatter.format(999) == "999")
    }

    @Test func thousandsRangeKeepsOneDecimal() {
        #expect(CompactNumberFormatter.format(1_000) == "1.0k")
        #expect(CompactNumberFormatter.format(1_234) == "1.2k")
        #expect(CompactNumberFormatter.format(99_949) == "99.9k")
    }

    @Test func hundredThousandsDropsDecimal() {
        #expect(CompactNumberFormatter.format(100_000) == "100k")
        #expect(CompactNumberFormatter.format(823_456) == "823k")
        #expect(CompactNumberFormatter.format(999_999) == "999k")
    }

    @Test func millionsRangeKeepsOneDecimal() {
        #expect(CompactNumberFormatter.format(1_000_000) == "1.0M")
        #expect(CompactNumberFormatter.format(1_234_567) == "1.2M")
        #expect(CompactNumberFormatter.format(9_949_000) == "9.9M")
    }

    @Test func tenMillionsDropsDecimal() {
        #expect(CompactNumberFormatter.format(10_000_000) == "10M")
        #expect(CompactNumberFormatter.format(12_345_678) == "12M")
        #expect(CompactNumberFormatter.format(123_456_789) == "123M")
    }

    @Test func negativesTreatedAsZero() {
        #expect(CompactNumberFormatter.format(-1) == "0")
        #expect(CompactNumberFormatter.format(-1_000_000) == "0")
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' \
  -only-testing:TokenWatchTests/CompactNumberFormatterTests test
```

预期:编译失败 — `CompactNumberFormatter` 未定义。

- [ ] **Step 3: 实现 `CompactNumberFormatter`**

创建 `TokenWatch/ViewControllers/CompactNumberFormatter.swift`:

```swift
import Foundation

/// 把整数压缩成状态栏可读的短字符串(Locale 中立、无千分位)
///
/// 规则:
/// - 0..<1_000          → "0" / "823"
/// - 1_000..<100_000    → "1.2k" / "99.9k"   (保留一位小数,向下截断)
/// - 100_000..<1_000_000→ "823k"             (去小数)
/// - 1_000_000..<10M    → "1.2M" / "9.9M"    (保留一位小数,向下截断)
/// - >=10_000_000       → "12M" / "123M"     (去小数)
/// - 负数视作 0(防御性输入,不抛错)
enum CompactNumberFormatter {

    /// 把 token 总数压缩成短字符串
    /// - Parameter value: 整数 token 数,负数会被视作 0
    /// - Returns: 状态栏可直接展示的字符串
    static func format(_ value: Int) -> String {
        guard value > 0 else { return "0" }

        if value < 1_000 {
            return String(value)
        }

        if value < 100_000 {
            // 1.0k ~ 99.9k:保留一位小数,向下截断到 0.1k
            let tenths = value / 100              // value / 1_000 * 10
            let whole = tenths / 10
            let frac = tenths % 10
            return "\(whole).\(frac)k"
        }

        if value < 1_000_000 {
            // 100k ~ 999k:去小数,向下截断到 1k
            return "\(value / 1_000)k"
        }

        if value < 10_000_000 {
            // 1.0M ~ 9.9M:保留一位小数
            let tenths = value / 100_000          // value / 1_000_000 * 10
            let whole = tenths / 10
            let frac = tenths % 10
            return "\(whole).\(frac)M"
        }

        // 10M+:去小数
        return "\(value / 1_000_000)M"
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' \
  -only-testing:TokenWatchTests/CompactNumberFormatterTests test
```

预期:编译通过,6 个测试全部 PASS。

- [ ] **Step 5: Commit**

```bash
git add TokenWatch/ViewControllers/CompactNumberFormatter.swift \
        TokenWatchTests/ViewControllers/CompactNumberFormatterTests.swift
git commit -m "feat(statusbar): 新增 CompactNumberFormatter 把 token 数缩成 1.2M/823k"
```

---

### Task 4: 实现 `StatusBarTitleBuilder` 纯函数 + 测试

**Files:**
- Create: `TokenWatch/ViewControllers/StatusBarTitleBuilder.swift`
- Test: `TokenWatchTests/ViewControllers/StatusBarTitleBuilderTests.swift`

**说明**:把 `[ProviderID: ProviderState]` + `todayKey` 算成状态栏文本。优先级:

1. 所有 provider `needsAuthorization == true` → `"—"`
2. 任一 provider `isLoading == true` 且**所有** provider 都没有 `stats` → `"…"`
3. 否则:把每个 provider 的 `stats?.byDay[todayKey]?` 对应的 token 累加(input + output + cacheRead + cacheCreation),再走 `CompactNumberFormatter.format`

> 「所有 provider 都没有 stats」即:`states.values.allSatisfy { $0.stats == nil }`。该条件下首启加载中,显示 `…` 更友好;首次拿到任何数据后,后续刷新即便 isLoading 也直接显示已有汇总数,避免文本闪烁。

- [ ] **Step 1: 写失败的测试**

创建 `TokenWatchTests/ViewControllers/StatusBarTitleBuilderTests.swift`:

```swift
import Testing
@testable import TokenWatch

struct StatusBarTitleBuilderTests {

    private let today = "2026-06-15"

    /// 全部 provider 未授权 → 文本为破折号
    @Test func allUnauthorizedShowsDash() {
        let states: [ProviderID: TokenStatsViewModel.ProviderState] = [
            .claude: .init(stats: nil, isLoading: false, errorMessage: nil, needsAuthorization: true),
            .codex: .init(stats: nil, isLoading: false, errorMessage: nil, needsAuthorization: true),
            .opencode: .init(stats: nil, isLoading: false, errorMessage: nil, needsAuthorization: true),
        ]
        #expect(StatusBarTitleBuilder.build(states: states, todayKey: today) == "—")
    }

    /// 首次启动:授权过但还没数据 + isLoading → 省略号
    @Test func loadingWithNoStatsShowsEllipsis() {
        let states: [ProviderID: TokenStatsViewModel.ProviderState] = [
            .claude: .init(stats: nil, isLoading: true, errorMessage: nil, needsAuthorization: false),
            .codex: .init(stats: nil, isLoading: false, errorMessage: nil, needsAuthorization: false),
            .opencode: .init(stats: nil, isLoading: false, errorMessage: nil, needsAuthorization: false),
        ]
        #expect(StatusBarTitleBuilder.build(states: states, todayKey: today) == "…")
    }

    /// 已经有数据后再刷新,即便 isLoading=true 也展示已有汇总(避免闪烁)
    @Test func loadingWithExistingStatsShowsSum() {
        let stats = makeStats(byDay: [today: makeSummary(input: 1_000, output: 2_000)])
        let states: [ProviderID: TokenStatsViewModel.ProviderState] = [
            .claude: .init(stats: stats, isLoading: true, errorMessage: nil, needsAuthorization: false),
            .codex: .init(stats: nil, isLoading: false, errorMessage: nil, needsAuthorization: false),
            .opencode: .init(stats: nil, isLoading: false, errorMessage: nil, needsAuthorization: false),
        ]
        #expect(StatusBarTitleBuilder.build(states: states, todayKey: today) == "3.0k")
    }

    /// 跨 provider 求和
    @Test func sumsAcrossProviders() {
        let claudeStats = makeStats(byDay: [today: makeSummary(input: 100_000, output: 200_000)])
        let codexStats = makeStats(byDay: [today: makeSummary(input: 50_000, output: 0, cacheRead: 30_000)])
        let opencodeStats = makeStats(byDay: [today: makeSummary(input: 0, output: 20_000, cacheCreation: 10_000)])

        let states: [ProviderID: TokenStatsViewModel.ProviderState] = [
            .claude: .init(stats: claudeStats, isLoading: false, errorMessage: nil, needsAuthorization: false),
            .codex: .init(stats: codexStats, isLoading: false, errorMessage: nil, needsAuthorization: false),
            .opencode: .init(stats: opencodeStats, isLoading: false, errorMessage: nil, needsAuthorization: false),
        ]

        // 100k+200k+50k+30k+20k+10k = 410_000 → "410k"
        #expect(StatusBarTitleBuilder.build(states: states, todayKey: today) == "410k")
    }

    /// 某 provider 的 byDay 没有 today key → 视作 0,其它正常累加
    @Test func missingTodayBucketTreatedAsZero() {
        let claudeStats = makeStats(byDay: [today: makeSummary(input: 1_500, output: 0)])
        let codexStats = makeStats(byDay: ["2026-06-14": makeSummary(input: 999_999, output: 0)])

        let states: [ProviderID: TokenStatsViewModel.ProviderState] = [
            .claude: .init(stats: claudeStats, isLoading: false, errorMessage: nil, needsAuthorization: false),
            .codex: .init(stats: codexStats, isLoading: false, errorMessage: nil, needsAuthorization: false),
            .opencode: .init(stats: nil, isLoading: false, errorMessage: nil, needsAuthorization: true),
        ]
        #expect(StatusBarTitleBuilder.build(states: states, todayKey: today) == "1.5k")
    }

    /// 部分授权部分未授权:已授权部分有数据则展示总和(不显示破折号)
    @Test func partialAuthorizationStillSums() {
        let claudeStats = makeStats(byDay: [today: makeSummary(input: 5_000, output: 5_000)])
        let states: [ProviderID: TokenStatsViewModel.ProviderState] = [
            .claude: .init(stats: claudeStats, isLoading: false, errorMessage: nil, needsAuthorization: false),
            .codex: .init(stats: nil, isLoading: false, errorMessage: nil, needsAuthorization: true),
            .opencode: .init(stats: nil, isLoading: false, errorMessage: nil, needsAuthorization: true),
        ]
        #expect(StatusBarTitleBuilder.build(states: states, todayKey: today) == "10.0k")
    }

    // MARK: - Helpers

    private func makeSummary(
        input: Int = 0,
        output: Int = 0,
        cacheRead: Int = 0,
        cacheCreation: Int = 0
    ) -> UsageSummary {
        UsageSummary(
            inputTokens: input,
            outputTokens: output,
            cacheReadTokens: cacheRead,
            cacheCreationTokens: cacheCreation,
            reasoningTokens: 0,
            totalTokens: input + output + cacheRead + cacheCreation,
            cost: 0,
            entryCount: 0,
            modelBreakdown: [:]
        )
    }

    private func makeStats(byDay: [String: UsageSummary]) -> AggregatedStats {
        AggregatedStats(
            overall: .zero,
            byHour: [:], byDay: byDay, byWeek: [:], byMonth: [:],
            bySession: [:], byModel: [:], byProject: [:],
            dataSourceCount: 1
        )
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' \
  -only-testing:TokenWatchTests/StatusBarTitleBuilderTests test
```

预期:编译失败 — `StatusBarTitleBuilder` 未定义。

- [ ] **Step 3: 实现 `StatusBarTitleBuilder`**

创建 `TokenWatch/ViewControllers/StatusBarTitleBuilder.swift`:

```swift
import Foundation

/// 状态栏文本生成器
///
/// 把 ViewModel 多 provider 的状态 + 今日 key 折成一个短文本,优先级:
/// 1. 全部 provider 未授权 → "—"
/// 2. 任一 provider 加载中,且没有任何 provider 有 stats → "…"
/// 3. 否则:跨 provider 累加 byDay[today] 的 token,经 CompactNumberFormatter 缩写
///
/// 设计原因:抽成纯函数后无需 NSStatusItem 即可单测,跨日切换、首启 loading、
/// 部分授权等组合都能定向覆盖。
enum StatusBarTitleBuilder {

    /// 生成状态栏文本
    /// - Parameters:
    ///   - states: ViewModel 当前所有 provider 的状态快照
    ///   - todayKey: 今日的 byDay key,格式 "yyyy-MM-dd"(与 UsageAggregator 一致)
    /// - Returns: 状态栏可直接展示的字符串
    static func build(
        states: [ProviderID: TokenStatsViewModel.ProviderState],
        todayKey: String
    ) -> String {
        guard !states.isEmpty else { return "—" }

        // 1. 全部未授权
        let allUnauthorized = states.values.allSatisfy { $0.needsAuthorization }
        if allUnauthorized { return "—" }

        // 2. 首启 loading + 全部无数据
        let anyLoading = states.values.contains(where: { $0.isLoading })
        let allEmpty = states.values.allSatisfy { $0.stats == nil }
        if anyLoading && allEmpty { return "…" }

        // 3. 累加每个 provider 今日的 token
        let total = states.values.reduce(0) { acc, state in
            guard let summary = state.stats?.byDay[todayKey] else { return acc }
            return acc
                + summary.inputTokens
                + summary.outputTokens
                + summary.cacheReadTokens
                + summary.cacheCreationTokens
        }

        return CompactNumberFormatter.format(total)
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' \
  -only-testing:TokenWatchTests/StatusBarTitleBuilderTests test
```

预期:编译通过,6 个测试全部 PASS。

- [ ] **Step 5: Commit**

```bash
git add TokenWatch/ViewControllers/StatusBarTitleBuilder.swift \
        TokenWatchTests/ViewControllers/StatusBarTitleBuilderTests.swift
git commit -m "feat(statusbar): 新增 StatusBarTitleBuilder 汇总各 provider 今日 token"
```

---

### Task 5: 添加 `StatusBarIcon` Image Set

**Files:**
- Create: `TokenWatch/Assets.xcassets/StatusBarIcon.imageset/Contents.json`
- Create: `TokenWatch/Assets.xcassets/StatusBarIcon.imageset/icon.png` 等(占位)

**说明**:状态栏图标资产,Render As: Template Image,跟随 menu bar 自动反相。最终 PNG 由用户提供,本任务先放占位 + 元数据。

- [ ] **Step 1: 创建 imageset 目录与 Contents.json**

```bash
mkdir -p TokenWatch/Assets.xcassets/StatusBarIcon.imageset
```

创建 `TokenWatch/Assets.xcassets/StatusBarIcon.imageset/Contents.json`:

```json
{
  "images" : [
    {
      "filename" : "icon.png",
      "idiom" : "universal",
      "scale" : "1x"
    },
    {
      "filename" : "icon@2x.png",
      "idiom" : "universal",
      "scale" : "2x"
    },
    {
      "filename" : "icon@3x.png",
      "idiom" : "universal",
      "scale" : "3x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  },
  "properties" : {
    "template-rendering-intent" : "template"
  }
}
```

- [ ] **Step 2: 放置占位 PNG**

用 `sips` 从已有 AppIcon 临时生成占位灰阶图(开发期使用,正式 PNG 由用户后续替换):

```bash
# 找一张 AppIcon 源图;若不存在则用 Preview 临时画一个 18x18 的纯灰矩形
APPICON=$(ls TokenWatch/Assets.xcassets/AppIcon.appiconset/*.png 2>/dev/null | head -1)
if [ -n "$APPICON" ]; then
  sips -z 18 18 "$APPICON" --out TokenWatch/Assets.xcassets/StatusBarIcon.imageset/icon.png
  sips -z 36 36 "$APPICON" --out TokenWatch/Assets.xcassets/StatusBarIcon.imageset/icon@2x.png
  sips -z 54 54 "$APPICON" --out TokenWatch/Assets.xcassets/StatusBarIcon.imageset/icon@3x.png
else
  echo "AppIcon 不存在,请手动放占位 PNG 后继续"
  exit 1
fi
```

> 注:占位图不会作为 Template 自动反相效果好(彩色 AppIcon 在 template 模式下会被压成纯黑剪影,可接受)。等用户提供真实图后替换三档分辨率即可。

- [ ] **Step 3: 在 Xcode 中确认 Image Set 已识别**

打开 Xcode → 在 Asset Catalog 看到 `StatusBarIcon`,Render As 为 `Template Image`。若 Xcode 因 PBXProject 引用未刷新而看不到,关闭并重开项目即可(Xcode 会自动 fold 新文件夹型 imageset)。

- [ ] **Step 4: Build 校验资产可用**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Debug build
```

预期:Build SUCCEEDED,不报缺资源警告。

- [ ] **Step 5: Commit**

```bash
git add TokenWatch/Assets.xcassets/StatusBarIcon.imageset
git commit -m "chore(assets): 新增 StatusBarIcon imageset(template,占位)"
```

---

### Task 6: 实现 `StatusBarController` + AppDelegate 装配

**Files:**
- Create: `TokenWatch/ViewControllers/StatusBarController.swift`
- Modify: `TokenWatch/AppDelegate.swift`

**说明**:状态栏控制器,持有 `NSStatusItem`、Timer、Menu;订阅 ViewModel 状态变化;`AppDelegate` 创建并管理生命周期。

#### 6.1 `StatusBarController.swift`

- [ ] **Step 1: 创建 `StatusBarController.swift`**

创建 `TokenWatch/ViewControllers/StatusBarController.swift`:

```swift
import AppKit
import Foundation
import os.log

/// macOS 状态栏控制器
///
/// 长驻一个图标 + 文本(今日所有 provider 累加 token 数),
/// 定时(30s)拉刷新,点击弹下拉菜单(打开主窗口 / 立即刷新 / 退出)。
///
/// 设计原则:
/// - 不直接读 JSONL / 不做聚合,完全复用 TokenStatsViewModel.states.byDay
/// - title 计算交给 StatusBarTitleBuilder,本类只负责 AppKit 层装配
@MainActor
final class StatusBarController {

    private static let refreshInterval: TimeInterval = 30
    private static let iconAssetName = "StatusBarIcon"

    private let viewModel: TokenStatsViewModel
    private let statusItem: NSStatusItem
    private var observerToken: TokenStatsViewModel.ObservationToken?
    private var refreshTimer: Timer?
    private var lastRenderedDayKey: String?

    private let logger = Logger(subsystem: "com.xiaoao.TokenWatch", category: "StatusBarController")

    init(viewModel: TokenStatsViewModel) {
        self.viewModel = viewModel
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        configureButton()
        installMenu()
        subscribeToViewModel()
        startRefreshTimer()
        // 立即按当前 ViewModel 状态画一次,避免空标题闪现
        renderTitle()
    }

    deinit {
        // 关闭 Timer 与 status item;observer 在 stop() 中可能已移除
        refreshTimer?.invalidate()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    /// 应用退出时显式关停,确保 Timer 不再持有 self、status item 从 menu bar 摘除
    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        if let token = observerToken {
            viewModel.removeObserver(token)
            observerToken = nil
        }
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    // MARK: - Setup

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(named: Self.iconAssetName)
        button.imagePosition = .imageLeading
        button.title = ""
    }

    private func installMenu() {
        let menu = NSMenu()

        let openItem = NSMenuItem(
            title: "打开 TokenWatch",
            action: #selector(openMainWindow),
            keyEquivalent: "0"
        )
        openItem.target = self
        menu.addItem(openItem)

        let refreshItem = NSMenuItem(
            title: "立即刷新",
            action: #selector(refreshNow),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "退出 TokenWatch",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func subscribeToViewModel() {
        observerToken = viewModel.observe { [weak self] _ in
            self?.renderTitle()
        }
    }

    private func startRefreshTimer() {
        // 用 RunLoop.common 而非默认 mode,避免菜单展开时 Timer 被冻结
        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.handleScheduledRefresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    // MARK: - Refresh

    private func handleScheduledRefresh() {
        // 跨日检测:即便数据没变也强制重绘文本,避免 0 点跨过去仍显示昨天
        let todayKey = Self.todayKey()
        if lastRenderedDayKey != todayKey {
            renderTitle()
        }
        Task { await viewModel.loadAllStats() }
    }

    // MARK: - Render

    private func renderTitle() {
        let todayKey = Self.todayKey()
        let title = StatusBarTitleBuilder.build(states: viewModel.states, todayKey: todayKey)
        statusItem.button?.title = title
        lastRenderedDayKey = todayKey
    }

    /// 与 UsageAggregator.dayKey 保持一致:本地 Calendar + "yyyy-MM-dd"
    static func todayKey(now: Date = Date(), calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: now)
        guard let y = comps.year, let m = comps.month, let d = comps.day else {
            return "unknown"
        }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    // MARK: - Actions

    @objc private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        // 优先从已有窗口里找主窗(默认 windowController),
        // 找不到就 fallback 到第一个 contentVC 是 ViewController 的 window
        let target = NSApp.windows.first(where: { $0.contentViewController is ViewController })
            ?? NSApp.mainWindow
        target?.makeKeyAndOrderFront(nil)
        if target == nil {
            logger.info("openMainWindow: 找不到 ViewController 窗口,跳过(后续版本再处理重建)")
        }
    }

    @objc private func refreshNow() {
        Task { await viewModel.loadAllStats() }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
```

- [ ] **Step 2: 编译确认**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Debug build
```

预期:Build SUCCEEDED。此时还没装到 AppDelegate,运行时还看不到状态栏。

#### 6.2 `AppDelegate` 装配

- [ ] **Step 3: 修改 `AppDelegate.swift`**

```swift
import Cocoa

@main
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    /// ViewModel 实例,协调数据加载和统计计算
    /// `internal`: 让 ViewController 通过 `NSApp.delegate` 拿到同一实例,避免引入 DI 容器
    let viewModel = TokenStatsViewModel()

    /// 状态栏控制器,长驻 menu bar 显示当日 token 数
    /// 在 didFinishLaunching 时创建,terminate 时 stop() 释放 Timer + 摘掉 status item
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // 先建状态栏(订阅 ViewModel),再异步加载,确保首次 onStateChange 能被状态栏接到
        statusBarController = StatusBarController(viewModel: viewModel)

        Task {
            await viewModel.loadAllStats()
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        statusBarController?.stop()
        statusBarController = nil
        SecurityScopedBookmarkManager.shared.stopAccessingAll()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}
```

- [ ] **Step 4: 编译并运行**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Debug build
```

预期:Build SUCCEEDED。

- [ ] **Step 5: 跑全量测试**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' \
  -only-testing:TokenWatchTests test
```

预期:全部测试 PASS。

- [ ] **Step 6: Commit**

```bash
git add TokenWatch/ViewControllers/StatusBarController.swift \
        TokenWatch/AppDelegate.swift
git commit -m "feat(statusbar): 新增 StatusBarController 长驻菜单栏显示当日 token"
```

---

### Task 7: 人工验收

**Files:** 无代码改动。

- [ ] **Step 1: 启动 App**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData/TokenWatch-*/Build/Products/Debug/TokenWatch.app
```

或直接在 Xcode 里 Run。

- [ ] **Step 2: 视觉验收**

- [ ] 状态栏出现 `StatusBarIcon` + 文本(`—` / `…` / `1.2k` 之类)
- [ ] 切换系统深浅色,图标随之反相(template image 已生效)
- [ ] 文本随时间从 `…` 变为具体数字(首次扫描完成)

- [ ] **Step 3: 交互验收**

- [ ] 点击状态栏 → 出现菜单(打开 TokenWatch / 立即刷新 / 退出 TokenWatch)
- [ ] 点「打开 TokenWatch」→ 主窗口前置
- [ ] 关掉主窗口后再点「打开 TokenWatch」→ 主窗口重新前置
- [ ] 点「立即刷新」→ 数字短暂可能保持,扫描完成后变成最新值
- [ ] 点「退出 TokenWatch」→ App 退出,状态栏图标消失

- [ ] **Step 4: 定时刷新验证**

在 Xcode console 看 `TokenStatsViewModel` 的日志,30s 内应看到至少一次 `loadAllStats` 触发的 provider 解析日志。

- [ ] **Step 5: 跨日表现(可选验证)**

把系统时间手动调到第二天,等 ≤30s,观察文本是否从昨天的累计回归到今天的值(若今天还没用过,会变 `0`)。验完恢复时间。

---

## 完成定义

- 全部 task 已 commit
- `xcodebuild test` 全绿,新增至少 15 个单元测试用例(observer 3 + compact 6 + title 6)
- 状态栏图标 + 文本在深浅色下正确显示
- 菜单三个动作(打开主窗口 / 立即刷新 / 退出)行为符合预期
- 已知遗留:`StatusBarIcon` 实际 PNG 仍是 AppIcon 缩放占位,等用户提供正式图后替换
