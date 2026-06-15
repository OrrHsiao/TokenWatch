# 按小时聚合维度实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `AggregatedStats` 上新增 `byHour` 维度,使 UI 能基于 ISO 8601 风格的小时桶
(`"yyyy-MM-ddTHH"`)渲染日视图小时趋势图。

**Architecture:** 扁平多维度 + 稀疏存储 + UI 端补零。`UsageAggregator.aggregate(_:)` 增加一
次 `groupAndAggregate`,新增 `hourKey(...)` helper(与 `dayKey` 共用本地 `Calendar`),
`UsageSummary` 不变,所有现有调用方向后兼容。

**Tech Stack:** Swift 6.0,Swift Testing(`import Testing`),AppKit。

---

## File Structure

| 文件 | 责任 | 改动类型 |
|---|---|---|
| `TokenWatch/Models/UsageAggregation.swift` | `AggregatedStats` 加 `byHour` 字段并更新 `.zero` | 修改 |
| `TokenWatch/Analytics/UsageAggregator.swift` | `aggregate` 多 1 行;新增 `hourKey(from:calendar:)` | 修改 |
| `TokenWatchTests/Analytics/UsageAggregatorTests.swift` | 新增 3 个 test case 覆盖小时聚合 | 修改 |

设计稿:`docs/superpowers/specs/2026-06-15-trend-charts-data-model-design.md`

---

## Task 1:扩展 `AggregatedStats` 数据模型

**Files:**
- Modify: `TokenWatch/Models/UsageAggregation.swift:28-47`

- [ ] **Step 1: 改 `AggregatedStats` 结构体,新增 `byHour` 字段**

把 `AggregatedStats` 整个替换为:

```swift
/// 按多维度聚合的完整统计结果
/// 参考 ccusage 的 daily/weekly/monthly/session 报告结构
struct AggregatedStats: Sendable {
    let overall: UsageSummary
    let byHour: [String: UsageSummary]      // key: "2026-06-13T14"
    let byDay: [String: UsageSummary]       // key: "2026-06-13"
    let byWeek: [String: UsageSummary]      // key: "2026-W24"
    let byMonth: [String: UsageSummary]     // key: "2026-06"
    let bySession: [String: UsageSummary]   // key: sessionID
    let byModel: [String: UsageSummary]     // key: model name
    let byProject: [String: UsageSummary]   // key: cwd / project path
    let dataSourceCount: Int                // 扫描的唯一数据源数

    /// 创建空的统计结果
    static var zero: AggregatedStats {
        AggregatedStats(
            overall: .zero,
            byHour: [:], byDay: [:], byWeek: [:], byMonth: [:],
            bySession: [:], byModel: [:], byProject: [:],
            dataSourceCount: 0
        )
    }
}
```

- [ ] **Step 2: 用 Xcode MCP 增量构建,确认编译错误只出现在 `UsageAggregator.aggregate(_:)`**

由于 `AggregatedStats` 多了一个必填字段,编译应当且仅应当在 `UsageAggregator.swift:42-51`
那个初始化点失败(缺少 `byHour:` 参数)。

Run: `xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Debug build`
Expected: 仅 `UsageAggregator.swift` 报 missing `byHour:` 参数,其他文件编译正常。

- [ ] **Step 3: 不要单独 commit,等聚合器实现完成后再统一 commit**

理由:本步留在工作区里,Task 2 完成后整体提交,避免一个有编译错误的中间提交进入历史。

---

## Task 2:聚合器新增 `byHour` 维度

**Files:**
- Modify: `TokenWatch/Analytics/UsageAggregator.swift:42-52`(初始化部分)
- Modify: `TokenWatch/Analytics/UsageAggregator.swift:122-157`(Date Helpers 区域,新增
  `hourKey`)

- [ ] **Step 1: 在 `aggregate(_:)` 的 `AggregatedStats` 初始化中加入 `byHour`**

把当前的:

```swift
        return AggregatedStats(
            overall: aggregateEntries(entries),
            byDay: groupAndAggregate(entries) { dayKey(from: $0.timestamp, calendar: calendar) },
            byWeek: groupAndAggregate(entries) { weekKey(from: $0.timestamp, calendar: isoCalendar) },
            byMonth: groupAndAggregate(entries) { monthKey(from: $0.timestamp, calendar: calendar) },
            bySession: groupAndAggregate(entries) { $0.sessionID },
            byModel: groupAndAggregate(entries) { $0.model },
            byProject: groupAndAggregate(entries) { $0.cwd ?? "unknown" },
            dataSourceCount: uniqueFiles.count
        )
```

改为:

```swift
        return AggregatedStats(
            overall: aggregateEntries(entries),
            byHour: groupAndAggregate(entries) { hourKey(from: $0.timestamp, calendar: calendar) },
            byDay: groupAndAggregate(entries) { dayKey(from: $0.timestamp, calendar: calendar) },
            byWeek: groupAndAggregate(entries) { weekKey(from: $0.timestamp, calendar: isoCalendar) },
            byMonth: groupAndAggregate(entries) { monthKey(from: $0.timestamp, calendar: calendar) },
            bySession: groupAndAggregate(entries) { $0.sessionID },
            byModel: groupAndAggregate(entries) { $0.model },
            byProject: groupAndAggregate(entries) { $0.cwd ?? "unknown" },
            dataSourceCount: uniqueFiles.count
        )
```

`byHour` 字段顺序与模型定义一致(放在 `overall` 之后、`byDay` 之前),便于 review diff 与
模型定义对应。

- [ ] **Step 2: 在 Date Helpers 区域新增 `hourKey(from:calendar:)`**

在 `weekKey(...)` 函数(`UsageAggregator.swift:150-157`)之后,文件 `}` 闭合之前,追加:

```swift
    /// 生成小时 key,格式: "yyyy-MM-ddTHH"(如 "2026-06-13T14")
    /// 设计原因:与 dayKey 共用同一份本地 Calendar,保证 byHour 的所有 key 都能与
    /// byDay 的 key 通过 prefix("yyyy-MM-dd") 完全匹配,UI 取数零歧义。
    /// 与 ISO 8601 datetime 同款分隔符 'T',字符串字典序即时间序。
    private func hourKey(from date: Date?, calendar: Calendar) -> String {
        guard let date = date else { return "unknown" }
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day,
              let hour = components.hour else {
            return "unknown"
        }
        return String(format: "%04d-%02d-%02dT%02d", year, month, day, hour)
    }
```

- [ ] **Step 3: 用 Xcode MCP 构建,确认全工程编译通过**

Run: `xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Debug build`
Expected: BUILD SUCCEEDED,无 warning。

- [ ] **Step 4: 暂不 commit,等 Task 3 测试通过后统一 commit**

---

## Task 3:为 `byHour` 维度添加测试

**Files:**
- Modify: `TokenWatchTests/Analytics/UsageAggregatorTests.swift`(在"按维度聚合"区域之后、
  "模型细分"区域之前插入新区域)

- [ ] **Step 1: 写第一个失败测试 —— 小时桶分组与 key 格式**

在 `UsageAggregatorTests.swift` 的 `projectAggregation()` 测试(约 177 行)之后、
`MARK: - 模型细分`(约 179 行)之前,插入:

```swift
    // MARK: - 按小时聚合

    @Test("按小时聚合 key 使用 yyyy-MM-ddTHH 格式")
    func hourlyAggregationKeyFormat() {
        // 同一日(2026-06-13)的两条记录,小时不同 → 应进入两个不同的 byHour 桶
        let entries = [
            makeEntry(sessionID: "s1",
                      date: dateTime(2026, 6, 13, 9, 30),
                      model: "m1", input: 100, output: 50),
            makeEntry(sessionID: "s1",
                      date: dateTime(2026, 6, 13, 14, 5),
                      model: "m1", input: 200, output: 100),
        ]

        let stats = aggregator.aggregate(entries)

        #expect(stats.byHour.count == 2)
        #expect(stats.byHour["2026-06-13T09"]?.inputTokens == 100)
        #expect(stats.byHour["2026-06-13T14"]?.inputTokens == 200)
    }
```

注意:这里需要新的 helper `dateTime(_:_:_:_:_:)` 用于精确指定小时/分钟。

- [ ] **Step 2: 在 `Helpers` 区域新增 `dateTime(...)` 辅助函数**

在文件末尾的 `private func date(_:_:_:)` 函数(约 235 行)之后追加:

```swift
    /// 构造带具体小时/分钟的 Date,用于小时聚合测试
    private func dateTime(_ year: Int, _ month: Int, _ day: Int,
                          _ hour: Int, _ minute: Int) -> Date {
        let components = DateComponents(year: year, month: month, day: day,
                                        hour: hour, minute: minute)
        return Calendar.current.date(from: components)!
    }
```

- [ ] **Step 3: 运行测试,确认通过**

使用 Xcode MCP 的 `RunSomeTests`,只跑新测试:

Run: `xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/UsageAggregatorTests/hourlyAggregationKeyFormat test`
Expected: PASS。

- [ ] **Step 4: 写第二个测试 —— 不变量:小时之和等于当日总和**

在第一个新测试之后追加:

```swift
    @Test("byHour 同日各桶之和等于 byDay 该日总桶")
    func hourSumEqualsDay() {
        // 同日 3 条记录落入 3 个不同小时,断言: byDay[day] = sum(byHour where prefix == day)
        let entries = [
            makeEntry(sessionID: "s1",
                      date: dateTime(2026, 6, 13, 0, 15),
                      model: "m1", input: 100, output: 50, cacheRead: 10, cacheCreation: 5),
            makeEntry(sessionID: "s1",
                      date: dateTime(2026, 6, 13, 12, 0),
                      model: "m1", input: 200, output: 100, cacheRead: 20, cacheCreation: 10),
            makeEntry(sessionID: "s2",
                      date: dateTime(2026, 6, 13, 23, 59),
                      model: "m2", input: 300, output: 150, cacheRead: 30, cacheCreation: 15),
        ]

        let stats = aggregator.aggregate(entries)

        let dayKey = "2026-06-13"
        let day = stats.byDay[dayKey]
        #expect(day != nil, "byDay 应该有 \(dayKey) 桶")

        let hourBuckets = stats.byHour.filter { $0.key.hasPrefix("\(dayKey)T") }
        #expect(hourBuckets.count == 3, "三条记录应落入三个独立小时桶")

        let sumInput = hourBuckets.values.reduce(0) { $0 + $1.inputTokens }
        let sumOutput = hourBuckets.values.reduce(0) { $0 + $1.outputTokens }
        let sumCacheRead = hourBuckets.values.reduce(0) { $0 + $1.cacheReadTokens }
        let sumCacheCreation = hourBuckets.values.reduce(0) { $0 + $1.cacheCreationTokens }
        let sumTotal = hourBuckets.values.reduce(0) { $0 + $1.totalTokens }
        let sumEntryCount = hourBuckets.values.reduce(0) { $0 + $1.entryCount }

        #expect(sumInput == day?.inputTokens)
        #expect(sumOutput == day?.outputTokens)
        #expect(sumCacheRead == day?.cacheReadTokens)
        #expect(sumCacheCreation == day?.cacheCreationTokens)
        #expect(sumTotal == day?.totalTokens)
        #expect(sumEntryCount == day?.entryCount)
    }
```

- [ ] **Step 5: 运行第二个测试**

Run: `xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/UsageAggregatorTests/hourSumEqualsDay test`
Expected: PASS。

- [ ] **Step 6: 写第三个测试 —— timestamp 缺失走 "unknown"**

在第二个新测试之后追加:

```swift
    @Test("timestamp 为 nil 的条目落入 byHour['unknown'] 桶,不丢数据")
    func hourlyAggregationHandlesMissingTimestamp() {
        // 一条带 timestamp 的正常记录 + 一条 timestamp 为 nil 的记录
        // 后者必须落入 "unknown" 桶,与 dayKey/monthKey 行为一致
        let entries = [
            makeEntry(sessionID: "s1",
                      date: dateTime(2026, 6, 13, 10, 0),
                      model: "m1", input: 100, output: 50),
            makeEntryWithoutTimestamp(sessionID: "s2",
                                      model: "m1", input: 999, output: 0),
        ]

        let stats = aggregator.aggregate(entries)

        #expect(stats.byHour["2026-06-13T10"]?.inputTokens == 100)
        #expect(stats.byHour["unknown"]?.inputTokens == 999)
    }
```

注意:此测试需要新的 helper,因为现有 `makeEntry` 强制传 `Date`。

- [ ] **Step 7: 在 `Helpers` 区域新增 `makeEntryWithoutTimestamp(...)`**

在 `private func dateTime(...)` 之前(即 `makeEntry` 之后)追加:

```swift
    /// 构造 timestamp 为 nil 的条目,用于验证聚合器对缺失时间戳的兜底
    private func makeEntryWithoutTimestamp(
        sessionID: String,
        model: String,
        input: Int,
        output: Int,
        cwd: String = "/test"
    ) -> ParsedUsageEntry {
        let id = UUID().uuidString
        return ParsedUsageEntry(
            recordUUID: id,
            messageId: id,
            requestId: nil,
            sessionID: sessionID,
            timestamp: nil,
            model: model,
            cwd: cwd,
            agentId: nil,
            usage: TokenUsage(
                inputTokens: input,
                cacheCreationInputTokens: 0,
                cacheReadInputTokens: 0,
                outputTokens: output,
                serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
                serviceTier: "standard",
                cacheCreation: CacheCreation(ephemeral1hInputTokens: 0, ephemeral5mInputTokens: 0),
                inferenceGeo: "",
                iterations: [],
                speed: "standard"
            ),
            isSubagent: false,
            provider: .claude
        )
    }
```

- [ ] **Step 8: 运行第三个测试**

Run: `xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/UsageAggregatorTests/hourlyAggregationHandlesMissingTimestamp test`
Expected: PASS。

- [ ] **Step 9: 跑全量单元测试,确保未破坏现有行为**

Run: `xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests test`
Expected: 全部 PASS,包括既有的 `dailyAggregation` / `weeklyAggregation` /
`weeklyAggregationFollowsISO8601` / `weeklyKeyMatchesISOWeekNumber` /
`sessionAggregation` / `projectAggregation` / `modelBreakdownIncluded` 等。

---

## Task 4:统一提交

**Files:** 上述三个文件全部一次性提交。

- [ ] **Step 1: 检查工作区改动**

Run: `git status` && `git diff --stat`
Expected: 仅看到以下三个文件被修改:
- `TokenWatch/Models/UsageAggregation.swift`
- `TokenWatch/Analytics/UsageAggregator.swift`
- `TokenWatchTests/Analytics/UsageAggregatorTests.swift`

不应有任何无关文件改动。如有,先 `git checkout -- <file>` 还原。

- [ ] **Step 2: 提交(遵循 Conventional Commits + 中文描述,见 CLAUDE.md)**

```bash
git add TokenWatch/Models/UsageAggregation.swift \
        TokenWatch/Analytics/UsageAggregator.swift \
        TokenWatchTests/Analytics/UsageAggregatorTests.swift
git commit -m "feat(analytics): 新增按小时聚合维度,支撑日视图小时趋势图"
```

- [ ] **Step 3: 验证提交**

Run: `git log -1 --stat`
Expected: HEAD commit 包含上述三个文件,message 为
`feat(analytics): 新增按小时聚合维度,支撑日视图小时趋势图`。

---

## 自检对照(写完计划后已执行)

- ✅ **Spec 覆盖**:
  - 数据模型新增 `byHour` → Task 1
  - `hourKey` helper + 聚合器接入 → Task 2
  - 三类测试(分组 / 不变量 / unknown 兜底)→ Task 3
  - UI 取数约定不在本次代码改动范围(spec 显式声明)
- ✅ **占位符扫描**:无 TBD/TODO/"add error handling"。
- ✅ **类型一致性**:
  - 字段名 `byHour` 在模型、聚合器初始化、测试中拼写一致。
  - `hourKey(from:calendar:)` 签名与 `dayKey` / `monthKey` / `weekKey` 同形。
  - 测试 helper `dateTime(...)` / `makeEntryWithoutTimestamp(...)` 在使用前定义。
  - `ParsedUsageEntry` 的字段(`recordUUID`/`messageId`/`requestId`/`sessionID`/
    `timestamp`/`model`/`cwd`/`agentId`/`usage`/`isSubagent`/`provider`)以及 `TokenUsage`
    构造参数(`inputTokens`/`cacheCreationInputTokens`/`cacheReadInputTokens`/
    `outputTokens`/`serverToolUse`/`serviceTier`/`cacheCreation`/`inferenceGeo`/
    `iterations`/`speed`),完全沿用现有 `makeEntry` 中的同款参数,确保 helper 复制粘贴后
    可直接编译。
