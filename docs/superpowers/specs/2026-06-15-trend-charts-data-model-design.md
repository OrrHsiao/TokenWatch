# 趋势图表数据模型扩展设计

**日期**: 2026-06-15
**作者**: TokenWatch
**状态**: 设计已确认,待实现

## 背景与目标

当前 `AggregatedStats` 在按日 / 按周 / 按月维度下,每个时间桶只携带该周期的总览
(`UsageSummary`),无法支撑 UI 在选中具体日 / 周 / 月时再渲染一张"该周期内更细粒度的趋势
图"。

UI 侧需求:

- 按**日**统计 → 展示该日**每小时**的使用趋势(24 个数据点)
- 按**周**统计 → 展示该周**每日**的使用趋势(7 个数据点,周一 ~ 周日)
- 按**月**统计 → 展示该月**每日**的使用趋势(28 ~ 31 个数据点)

每张趋势图的主指标,UI 端可在 `totalTokens` 与 `cost` 之间切换。

## 设计方案

### 总体策略

采用**扁平多维度 + UI 端补零**:

- 在 `AggregatedStats` 上**新增一个独立维度** `byHour: [String: UsageSummary]`,与已有的
  `byDay` / `byWeek` / `byMonth` 平级。
- 周/月趋势图所需的"每日数据"**直接复用** `byDay`,不重复存储。
- 数据层保持**稀疏**(只输出有数据的桶),UI 端按"日历视野"自行补 `UsageSummary.zero`。
- `UsageSummary` 已经同时携带 `totalTokens` 和 `cost`,**主指标切换由 UI 在渲染时选择字段**,
  数据层无需分两套结构。

### 为什么不嵌套(`byDay: [String: DailyStats]`)?

考虑过将"细粒度趋势"嵌套到父桶里:

```swift
struct DailyStats { let summary: UsageSummary; let byHour: [String: UsageSummary] }
let byDay: [String: DailyStats]
```

但被否决,原因:

1. **冗余**:周视图、月视图都需要"该周/月的每日趋势",若把 `byDay` 嵌入 `WeeklyStats` /
   `MonthlyStats` 内部,同一份数据会被分别存储多次。
2. **改动面大**:现有所有访问 `stats.byDay[...]` 的调用点(`ProviderStatsViewController` 等)
   都得改签名。
3. **语义增益小**:UI 取小时趋势的真实流程是"先选中某日 → 再查询小时数据",从平级 `byHour`
   做一次前缀过滤即可,无需把 24 个桶强绑在 `DailyStats` 上。

## 数据模型变更

文件:`TokenWatch/Models/UsageAggregation.swift`

```swift
struct AggregatedStats: Sendable {
    let overall: UsageSummary
    let byHour: [String: UsageSummary]      // 新增 key: "2026-06-13T14"
    let byDay: [String: UsageSummary]       // key: "2026-06-13"
    let byWeek: [String: UsageSummary]      // key: "2026-W24"
    let byMonth: [String: UsageSummary]     // key: "2026-06"
    let bySession: [String: UsageSummary]
    let byModel: [String: UsageSummary]
    let byProject: [String: UsageSummary]
    let dataSourceCount: Int

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

### Hour key 规范

- 格式:`"yyyy-MM-ddTHH"`(ISO 8601 datetime 风格,无分钟)
- 例:`"2026-06-13T14"`
- 时区:本地 `Calendar.current.timeZone`,与现有 `dayKey` / `monthKey` 一致
- 时间戳缺失:沿用现有约定,落入 `"unknown"` 桶,不丢数据

### 与 `byDay` 的语义关系

`byDay["2026-06-13"]` 等于 `byHour` 中所有 key 以 `"2026-06-13T"` 开头的桶在 token / cost
等所有标量字段上的算术和。该等价关系作为不变量,可在测试中断言。

## 聚合器实现

文件:`TokenWatch/Analytics/UsageAggregator.swift`

`aggregate(_:)` 入口新增一行:

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

新增 helper:

```swift
/// 生成小时 key,格式: "yyyy-MM-ddTHH"
/// 设计原因:与 dayKey 共用同一份本地 Calendar,保证 byHour 的所有前缀
/// 都能与 byDay 的 key 完全匹配(prefix("yyyy-MM-dd") 关系无歧义)
private func hourKey(from date: Date?, calendar: Calendar) -> String {
    guard let date = date else { return "unknown" }
    let c = calendar.dateComponents([.year, .month, .day, .hour], from: date)
    guard let y = c.year, let m = c.month, let d = c.day, let h = c.hour else {
        return "unknown"
    }
    return String(format: "%04d-%02d-%02dT%02d", y, m, d, h)
}
```

性能影响:仅对 `entries` 多遍历一次以构建 `byHour`,与现有 `byDay` / `byWeek` / `byMonth` /
`bySession` / `byModel` / `byProject` 同级线性开销,可忽略。

## UI 取数约定

数据层稀疏 + UI 补零的契约:

| 视图 | 父桶 lookup | 趋势数据来源 | X 轴范围 | 缺失桶处理 |
|---|---|---|---|---|
| 日视图 | `stats.byDay["2026-06-13"]` | `stats.byHour`,`key.hasPrefix("2026-06-13T")` | 0 ~ 23 共 24 点 | 填 `UsageSummary.zero` |
| 周视图 | `stats.byWeek["2026-W24"]` | `stats.byDay`,从周首日推出该周 7 个 dayKey 直接 lookup | 周一 ~ 周日共 7 点 | 填 `UsageSummary.zero` |
| 月视图 | `stats.byMonth["2026-06"]` | `stats.byDay`,`key.hasPrefix("2026-06-")` | 当月第 1 ~ 末日(28 ~ 31 点) | 填 `UsageSummary.zero` |

注意:

- 周视图必须按 ISO 8601 周(周一起点)推算 dayKey,与 `weekKey` 的日历规则保持一致,否则会
  漏/多取 1 天。复用 `UsageAggregator` 内部那份 `isoCalendar` 的等价配置即可。
- 月视图末日:用 `Calendar.range(of: .day, in: .month, for:)` 计算,避免硬编码 28 / 30 / 31。

### 主指标切换

UI 端定义:

```swift
enum TrendMetric {
    case totalTokens
    case cost
}
```

渲染时同一份桶数据按当前枚举选 `summary.totalTokens` 或 `summary.cost`。数据层不参与切换。

### 未来时间裁剪

- **日视图**:当查看的是"今天"时,只渲染到当前小时(含),其余仍补 0 但 UI 可视觉上灰化或截断;
  非今天则完整 24 点。
- **月视图**:同理,当查看本月时未来日期保留为 0,折线不应中断。
- 该裁剪由 UI 决定,不在数据层处理。

## 测试

文件:`TokenWatchTests/Analytics/UsageAggregatorTests.swift`

新增 case:

1. **`hourlyAggregation`** —— 同一日不同小时的多条 entry,验证 `byHour` 桶数量、key 格式
   (`"yyyy-MM-ddTHH"`)、各桶 token 求和正确。
2. **`hourSumEqualsDay`(不变量)** —— 同日多个 entry 落入若干小时桶,断言"所有该日小时桶的
   `totalTokens` 之和 == `byDay[dayKey]?.totalTokens`",防止后续重构破坏 prefix 关系。
3. **`hourKeyTimezoneStability`** —— 与 `dayKey` 共用 `Calendar.current` 的隐含约束,通过
   "构造一条 timestamp 后再解析其 hour key"的方式间接验证(避免引入跨时区伪造工具)。

不修改:已有 `byDay` / `byWeek` / `byMonth` 等测试断言无需改写。

## 不在本次范围

- UI 视图(图表组件、日/周/月切换控件)
- `TrendMetric` 枚举的具体定义位置
- 跨时区切换时桶重计算的策略

这些将在后续 PR(实现 UI 时)再处理。本次仅交付数据层契约。

## 影响面

| 文件 | 改动 |
|---|---|
| `TokenWatch/Models/UsageAggregation.swift` | 新增字段 `byHour`,更新 `.zero` |
| `TokenWatch/Analytics/UsageAggregator.swift` | 新增 `hourKey(...)`,`aggregate(_:)` 多 1 行 |
| `TokenWatchTests/Analytics/UsageAggregatorTests.swift` | 新增 3 个 test case |
| `ProviderStatsViewController.swift` 等现有调用方 | **无需改动**(向后兼容) |

## 提交规范

按 CLAUDE.md 约定:

- `feat(analytics): 新增按小时聚合维度,支撑日视图小时趋势图`
