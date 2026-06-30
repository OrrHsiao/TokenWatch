# 最近会话明细设计

**日期**: 2026-06-30
**作者**: TokenWatch
**状态**: 设计已确认,待实现

## 背景与目标

当前数据源 provider 会扫描并解析 Claude Code、Codex、opencode 的用量记录,统一产出
`ParsedUsageEntry`。聚合层已有 `AggregatedStats.bySession`,但它只保留
`sessionID -> UsageSummary`,缺少最近时间、provider、项目路径、首次时间等会话列表需要的字段。

本次目标是整理并实现"最近明细"的数据口径:最近明细展示按最近活跃排序的会话列表。无论筛选条件是
本日、最近 7 天、最近 30 天还是其他时间窗口,列表行粒度始终是一行一个会话,筛选只改变参与统计的
entry 范围。

## 范围

### 本次包含

1. 定义最近明细的行粒度、筛选规则和排序规则。
2. 基于现有 `ParsedUsageEntry` 和计费结果派生最近会话行。
3. 明确主列表字段和可展开字段。
4. 新增纯数据 builder,用于把指定时间窗口内的 entries 转为最近会话列表。
5. 为未来 UI 提供稳定 snapshot,不直接依赖 `AggregatedStats.bySession`。

### 本次不包含

- 解析会话标题、用户 prompt、assistant 文本或完整对话内容。
- 从原始 Claude/Codex/opencode 文件读取更多非 token 字段。
- 导出、搜索、分页、复制菜单或会话跳转。
- 修改现有 token 计费规则。
- 把最近明细与 provider 详情页混合展示。

## 数据口径

最近明细的数据来源是当前已能拿到的 `ParsedUsageEntry`:

- `sessionID`
- `timestamp`
- `model`
- `cwd`
- `agentId`
- `usage`
- `isSubagent`
- `provider`
- `upstreamProviderID`
- `upstreamCost`

行唯一键使用 `provider + sessionID`,避免不同 provider 的 session ID 碰撞。展示时仍以
`sessionID` 作为主要标识,provider 单独成列。

筛选规则:

1. 先按当前筛选窗口过滤 `ParsedUsageEntry`。
2. 丢弃 `timestamp == nil` 且无法判定是否在窗口内的 entry。
3. 将剩余 entry 按 `(provider, sessionID)` 分组。
4. 每组聚合为一个最近会话行。

这个规则意味着一个跨天会话在"本日"筛选下只展示今天窗口内的 token 和成本;同一个会话在"最近 7 天"
下会展示最近 7 天内的 token 和成本,不是该会话全生命周期总量。

## 快照结构

新增最近会话列表 snapshot:

```swift
struct RecentSessionDetailsSnapshot: Sendable, Equatable {
    let rows: [RecentSessionRow]
    let totalSessionCount: Int
    let totalTokens: Int
    let totalCost: Double
    let loadedProviderCount: Int
    let loadingProviderCount: Int
    let unauthorizedProviderCount: Int
    let errorMessages: [String]
}

struct RecentSessionRow: Sendable, Equatable, Identifiable {
    let id: String                 // "\(provider.rawValue):\(sessionID)"
    let provider: ProviderID
    let sessionID: String
    let projectPath: String?
    let primaryModel: String
    let additionalModelCount: Int
    let firstActiveAt: Date?
    let lastActiveAt: Date?
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheCreationTokens: Int
    let reasoningTokens: Int
    let totalTokens: Int
    let cost: Double
    let entryCount: Int
    let modelBreakdown: [String: UsageSummary]
    let upstreamProviderIDs: [String]
    let isSubagentIncluded: Bool
}
```

`primaryModel` 取当前窗口内 token 最大的模型。若模型 token 相同,按模型名升序稳定取第一个。
`additionalModelCount` 表示除主模型外还有多少个模型。

`projectPath` 优先取该会话最近一条有值 entry 的 `cwd`;若都没有值,显示为空或 `unknown`。
`upstreamProviderIDs` 仅 opencode 通常有值,按名称升序去重。

## 主列表字段

最近明细主表展示以下列:

| 列 | 数据来源 | 展示规则 |
|---|---|---|
| 最近时间 | `lastActiveAt` | 主排序字段,按本地时间显示 |
| 会话 ID | `sessionID` | 中间截断,tooltip/复制时用完整值 |
| 工具 | `provider` | Claude / Codex / opencode |
| 项目 | `projectPath` | 路径过长时中间截断,缺失显示 `unknown` |
| 主模型 | `primaryModel + additionalModelCount` | 多模型时显示如 `gpt-5 +2` |
| 总 Token | `totalTokens` | 使用千位分隔或紧凑格式 |
| 成本 | `cost` | USD,保留 4 位或沿用现有页面格式 |
| 记录数 | `entryCount` | assistant usage 记录条数 |

主表不展示 `recordUUID`、`messageId`、`requestId`、`dedupKey`、单条 `upstreamCost`,这些属于解析和去重内部字段。

## 展开字段

未来如果支持展开行或详情面板,展示以下字段:

- 首次时间: `firstActiveAt`
- 会话跨度: `lastActiveAt - firstActiveAt`
- Input Tokens
- Output Tokens
- Cached Read Tokens
- Cache Creation Tokens
- Reasoning Tokens
- 模型分布: `modelBreakdown`
- 是否包含 subagent: `isSubagentIncluded`
- opencode 上游 provider: `upstreamProviderIDs`

## 排序规则

最近明细默认排序:

1. `lastActiveAt` 倒序。
2. 同时间按 `totalTokens` 倒序。
3. 再按 `provider.rawValue` 升序。
4. 再按 `sessionID` 升序。

没有 `lastActiveAt` 的行默认不进入窗口。如果未来支持无时间 entry 的全量视图,这些行排在最后。

## 架构设计

新增 `RecentSessionDetailsBuilder`,职责类似现有 `TotalStatsBuilder` 和 `MonthlyTokenChartBuilder`:

```swift
enum RecentSessionDetailsBuilder {
    static func build(
        states: [ProviderID: TokenStatsViewModel.ProviderState],
        period: UsageStatsPeriod,
        now: Date,
        calendar: Calendar
    ) -> RecentSessionDetailsSnapshot
}
```

因为 `AggregatedStats.bySession` 缺少最近时间和项目等字段,`ProviderState` 需要保留最近一次解析后的
`entries` 快照,或保留等价的轻量明细源。推荐在 `TokenStatsViewModel` 成功加载 provider 后保存
`entries`:

```swift
struct ProviderState: Sendable {
    var stats: AggregatedStats?
    var entries: [ParsedUsageEntry]?
    var isLoading = false
    var errorMessage: String?
    var needsAuthorization = true
}
```

这个改动最小,也避免在 provider/parser 层重复设计会话模型。UI 层只消费 builder 输出的 snapshot,不直接遍历
entries。

## 时间窗口

最近明细复用 `UsageStatsPeriod` 的时间窗口概念:

- `.today`: 本地自然日 00:00 到下一自然日 00:00,使用 `[start, end)` 半开区间。
- `.recent30Days`: 包含今天在内向前回溯 30 个自然日,结束边界为下一自然日 00:00。
- `.recent12Months`: 包含当前月在内向前回溯 12 个自然月,结束边界为下一自然月 00:00。

若新增"最近 7 天",应作为 `UsageStatsPeriod` 的新 case 或最近明细自己的 filter case。推荐扩展
`UsageStatsPeriod`,让图表和明细共享相同窗口定义。

## 状态处理

状态文案沿用现有汇总页策略:

- 没有任何已加载 provider 且仍在加载:显示加载状态。
- 没有任何已加载 provider 且未授权:提示授权用户目录。
- 没有任何已加载 provider 且有错误:显示第一条错误。
- 已加载但窗口内无会话:显示当前筛选窗口暂无会话明细。
- 已有部分数据且仍有 provider 加载中:保留列表,显示部分数据仍在加载。
- 已有部分数据且存在 provider 错误:保留列表,显示第一条错误。

## 测试

新增或更新测试:

1. `RecentSessionDetailsBuilderTests`
   - 按 `(provider, sessionID)` 聚合,不同 provider 同 sessionID 不混并。
   - 本日、最近 7 天、最近 30 天窗口只统计窗口内 entry。
   - 同一 session 跨天时,本日只统计本日 token。
   - `lastActiveAt` 倒序、同时间 token 倒序、再按 provider/sessionID 稳定排序。
   - `primaryModel` 取 token 最大模型,同 token 时按模型名稳定排序。
   - `projectPath` 取最近非空 cwd。
   - `isSubagentIncluded` 和 `upstreamProviderIDs` 正确派生。
2. `TokenStatsViewModelObserverTests`
   - 成功加载后 `ProviderState.entries` 与 `stats` 同步更新。
   - unchanged 刷新不误清空已有 entries。
   - 加载失败不覆盖已有可用 entries。
3. UI 测试或 ViewController 单测
   - 最近明细区展示主列表字段。
   - 空数据、加载、未授权、错误状态展示正确。

## 影响面

| 文件 | 改动 |
|---|---|
| `TokenWatch/ViewModels/TokenStatsViewModel.swift` | `ProviderState` 增加 entries 快照 |
| `TokenWatch/ViewControllers/RecentSessionDetailsBuilder.swift` | 新增最近会话明细 builder |
| `TokenWatch/ViewControllers/MonthlyStatsViewController.swift` | 在时间窗口页展示最近明细区或接入其 snapshot |
| `TokenWatch/ViewControllers/MonthlyTokenChartBuilder.swift` | 可能扩展 `UsageStatsPeriod.recent7Days` |
| `TokenWatch/Localization/AppStrings.swift` | 增加最近明细相关文案 |
| `TokenWatchTests/ViewControllers/RecentSessionDetailsBuilderTests.swift` | 新增 builder 测试 |
| `TokenWatchTests/ViewModels/TokenStatsViewModelObserverTests.swift` | 覆盖 entries 状态更新 |

## 验证命令

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/RecentSessionDetailsBuilderTests test
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/TokenStatsViewModelObserverTests test
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests test
```

## 提交建议

实现提交使用:

```text
feat(stats): 新增最近会话明细
```
