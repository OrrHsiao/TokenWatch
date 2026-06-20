# 按月 Token 图表主界面设计

**日期**: 2026-06-20
**作者**: TokenWatch
**状态**: 设计已确认,待实现

## 背景与目标

当前主窗口左侧侧边栏按 provider 展示详情页,最后一项是"设置"。右侧 provider 详情页只展示
本日和累计文字概览,缺少一个跨 provider 的长期用量视角。

本次新增一个全局入口:

- 在主窗口左侧侧边栏的"设置"上方新增"按月"。
- 右侧展示过去 12 个月每月 token 消耗。
- 图表类型采用柱状图,不使用折线图。

选择柱状图的原因:月度 token 是按月汇总的离散总量,柱状图能直接表达每个月独立桶之间的
高低差异。折线图更适合连续时间序列或更细粒度趋势,用于 12 个离散月份会暗示过强的连续变化。

## 范围

### 本次包含

1. 新增侧边栏全局项"按月",顺序为:所有 provider、按月、设置。
2. 新增 `MonthlyStatsViewController`,作为右侧主内容页。
3. 汇总所有已加载 provider 的 `AggregatedStats.byMonth`。
4. 生成以当前月份为终点的过去 12 个月数据点,缺失月份补 0。
5. 使用 AppKit 原生视图实现柱状图,展示每月 `totalTokens`。
6. 处理 loading、未授权、无数据、错误等状态的聚合提示。
7. 增加纯数据 builder 的单元测试和必要的主界面路由测试。

### 本次不包含

- 成本金额图表切换。
- 日/周/月多粒度趋势切换。
- 图表交互下钻、tooltip、缩放或选中态。
- 同比、预算线、均线或预测。
- 数据持久化或缓存层改造。

## 信息架构

左侧侧边栏新增一个全局内容类型:

```swift
private enum SidebarContent: Equatable {
    case provider(ProviderID)
    case monthly
    case settings
}
```

`ProviderSidebarItem` 同步新增 `.monthly`,标题为"按月"。`ProviderSidebarViewController` 暴露
`onSelectMonthly`,点击后由顶层 `ViewController` 安装 `MonthlyStatsViewController`。

默认选中逻辑保持不变:首次打开仍选中第一个 provider。新增"按月"只是额外入口,不改变启动后的
第一屏。

## 数据设计

复用现有聚合结果:

```swift
let byMonth: [String: UsageSummary] // key: "yyyy-MM"
```

新增纯数据构建器:

```swift
struct MonthlyTokenChartSnapshot: Sendable, Equatable {
    let monthBuckets: [MonthlyTokenBucket]
    let totalTokens: Int
    let maxMonthlyTokens: Int
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
    let normalizedHeight: Double
    let isCurrentMonth: Bool
}
```

构建规则:

- `now` 和 `Calendar` 由调用方注入,便于测试。
- 生成从当前月份往前数 11 个月到当前月份的 12 个 month key。
- 每个 provider 若 `state.stats != nil`,累加 `stats.byMonth[monthKey]?.totalTokens ?? 0`。
- `maxMonthlyTokens` 用于计算柱高;全部为 0 时所有柱高为 0。
- `normalizedHeight` 范围为 `0...1`。
- 月份 label 使用短标签,例如 `7月`、`8月`、`1月`。跨年不在每个 X 轴 label 上重复年份,
  需要年份时可在标题或辅助文案中表达"过去 12 个月"。

## UI 设计

`MonthlyStatsViewController` 右侧内容采用简洁工具页布局:

1. 顶部标题:"按月"。
2. 辅助文案:"过去 12 个月,跨 provider 汇总"。
3. 总 token 摘要,使用现有 `CompactNumberFormatter` 或等价格式化逻辑。
4. 柱状图区域:
   - 12 根柱,等宽,按月份从旧到新排列。
   - 当前月份可使用强调色,历史月份使用同一色系的普通状态。
   - X 轴显示月份短标签。
   - Y 轴不需要复杂刻度;保留顶部总量和柱高对比即可。
5. 底部或空态区域展示状态提示。

图表应使用轻量 AppKit 视图实现,不引入第三方图表库。视图只接收
`MonthlyTokenChartSnapshot`,不直接读取 ViewModel。为便于测试,柱子应作为可枚举的子视图或
内部可验证状态存在,而不是把所有信息都隐藏在不可观察的 `draw(_:)` 像素结果里。

## 状态处理

`MonthlyStatsViewController` 订阅现有 `.providerStateDidChange` 通知。任一 provider 状态变化时
重新构建 snapshot 并刷新图表。

状态文案策略:

- 所有 provider 都在加载:显示"正在加载用量数据..."。
- 部分 provider 加载中:仍展示已加载数据,辅助提示"部分数据仍在加载"。
- 没有任何已加载 stats 且存在未授权 provider:显示"请先在设置中授权访问用户目录"。
- 没有任何 token 数据:显示"过去 12 个月暂无 token 数据"。
- 存在 provider 错误:保留图表可用部分,并显示简短错误提示;不因单个 provider 错误隐藏全部数据。

## 测试

新增或更新测试:

1. `MonthlyTokenChartBuilderTests`
   - 生成固定 12 个月窗口,顺序从旧到新。
   - 多 provider 同月 token 正确求和。
   - 缺失月份补 0。
   - 全 0 数据时 `normalizedHeight` 不产生 NaN 或越界。
   - 当前月份标记正确。
   - loading、未授权、错误 provider 计数正确。
2. `TokenWatchTests`
   - 侧边栏标题顺序更新为 provider 列表 + `["按月", "设置"]`。
   - 点击或选择"按月"后安装月度页。
3. `MonthlyTokenChartViewTests`
   - 配置 snapshot 后生成 12 根柱相关子视图或等价的可验证状态。
   - 全 0 数据时柱高保持稳定,不触发布局异常。

## 影响面

| 文件 | 改动 |
|---|---|
| `TokenWatch/ViewController.swift` | 新增侧边栏项、路由和 `MonthlyStatsViewController` 持有 |
| `TokenWatch/ViewControllers/MonthlyTokenChartBuilder.swift` | 新增纯数据 builder |
| `TokenWatch/ViewControllers/MonthlyTokenChartView.swift` | 新增 AppKit 柱状图视图 |
| `TokenWatch/ViewControllers/MonthlyStatsViewController.swift` | 新增月度页面 |
| `TokenWatchTests/TokenWatchTests.swift` | 更新侧边栏顺序和路由测试 |
| `TokenWatchTests/ViewControllers/MonthlyTokenChartBuilderTests.swift` | 新增 builder 测试 |
| `TokenWatch.xcodeproj/project.pbxproj` | 添加新源码和测试文件引用 |

## 验证命令

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/MonthlyTokenChartBuilderTests test
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests test
```

## 提交建议

实现提交使用:

```text
feat(ui): 新增按月 token 消耗图表
```
