# 状态栏 Popover 日历热力图 — 设计稿

- 日期:2026-06-17
- 关联:`StatusBarController`、`TokenStatsViewModel`、`AggregatedStats`

## 1. 范围与目标

状态栏左键弹出的 `NSPopover` 不再展示空白内容,改为展示当前本地月份的日历热力图。

本次交付:

- 展示本月每天的总 token 消耗热力。
- 不区分 Claude / Codex / OpenCode,跨所有 provider 合并统计。
- 使用 AppKit `NSCollectionView` 渲染日历格子。
- 顶部展示本月总 token 和月份。
- 每个日期格子提供 tooltip,显示日期和当天 token 数。

不在本次范围:

- 切换月份。
- 点击日期展开详情。
- 按 provider / agent 筛选。
- 成本热力图或指标切换。

## 2. 技术选型

采用 **AppKit + `NSCollectionView`**。

原因:

- 项目现有 UI 是 AppKit(`NSStatusItem`、`NSPopover`、`NSViewController`),继续使用 AppKit 能减少桥接层。
- 日历热力图天然是固定数量 item 的网格,`NSCollectionView` 比纯自绘更适合 hover、tooltip、未来点击和可访问性扩展。
- 不引入第三方依赖,避免为了 28 ~ 31 个格子的简单视图增加包管理和样式适配成本。

SwiftUI 方案可行,但不作为本次实现。若用 `NSHostingView + LazyVGrid`,布局代码会更短,但会在当前 AppKit 架构中新增 SwiftUI 桥接、状态同步和测试边界。UIKit 不适用,因为当前是 macOS AppKit 应用,不是 iOS / Catalyst 界面。

## 3. 数据源设计

`AggregatedStats.byMonth` 的结构是:

```swift
let byMonth: [String: UsageSummary] // key: "2026-06"
```

它只返回整个月的汇总 `UsageSummary`,不包含每天的明细,因此不能单独驱动热力图。

数据约定:

- 日历格子使用 `byDay`:按当前月份生成 `yyyy-MM-dd` key,逐日 lookup 并跨 provider 累加 `totalTokens`。
- 顶部本月总 token 优先使用 `byMonth[currentMonthKey]?.totalTokens` 跨 provider 累加。
- 如果某个 provider 没有当前月的 `byMonth` 桶,该 provider 的月总量 fallback 为当前月所有日格子的求和。
- 缺失日期补 0。
- `needsAuthorization`、加载失败或没有 stats 的 provider 在合并时视作 0。

`totalTokens` 口径沿用现有 `UsageSummary.totalTokens`,包含 input、output、cache read、cache creation 和 reasoning,与状态栏数字口径保持一致。

## 4. 组件结构

新增纯逻辑 builder:

```swift
enum CalendarHeatmapBuilder {
    static func build(
        states: [ProviderID: TokenStatsViewModel.ProviderState],
        month: Date,
        now: Date,
        calendar: Calendar
    ) -> CalendarHeatmapSnapshot
}
```

输出:

```swift
struct CalendarHeatmapSnapshot: Sendable, Equatable {
    let monthKey: String
    let monthTitle: String
    let monthTotalTokens: Int
    let weekdaySymbols: [String]
    let cells: [CalendarHeatmapCell]
    let maxDailyTokens: Int
}

enum CalendarHeatmapCell: Sendable, Equatable, Identifiable {
    case placeholder(id: String)
    case day(CalendarHeatmapDay)
}

struct CalendarHeatmapDay: Sendable, Equatable, Identifiable {
    let id: String              // yyyy-MM-dd
    let dateKey: String
    let dayNumber: Int
    let totalTokens: Int
    let intensity: Int          // 0...4
    let isFuture: Bool
}
```

`CalendarHeatmapBuilder` 负责生成完整 collection view 数据:先按 `calendar.firstWeekday` 输出星期标题,再为首周缩进生成 `placeholder` cell,随后输出当前月份从 1 号到最后一天的 `day` cell。后置空白不生成,避免 popover 底部出现无意义行高。

AppKit 层新增:

- `StatusPopoverViewController`:popover 内容控制器,持有 summary label、weekday header 和 `NSCollectionView`。
- `CalendarHeatmapCollectionViewItem`:单个日期格子 item,渲染日期数字、背景色和 tooltip。

`StatusBarController.configurePopover()` 改为创建 `StatusPopoverViewController(viewModel:)`,不再使用 `EmptyStatusPopoverView`。

## 5. 布局与视觉

Popover 建议尺寸从当前 `280 x 180` 调整到约 `300 x 260`,容纳标题、星期行和 7 列网格。

视觉层级:

1. 顶部:月份标题,例如 `2026 年 6 月`。
2. 顶部副信息:本月总 token,使用 `CompactNumberFormatter` 缩写。
3. 星期标题:按 `Calendar.current.firstWeekday` 生成,与本地日历一致。
4. 日期格子:固定正方形,7 列,间距 4px 左右。

颜色:

- 0 token:系统 separator / control background 的弱色。
- 1~4 档:绿色递进,暗黑模式用 `NSColor` 动态色适配。
- 未来日期:通过 builder 的 `now` 参数判断;弱化显示,强度固定为 0,tooltip 仍显示日期和 0 tokens。

强度分档:

- `maxDailyTokens == 0` 时所有非未来日期 intensity 为 0。
- token 为 0 时 intensity 为 0。
- token 大于 0 时按 `ceil(Double(tokens) / Double(maxDailyTokens) * 4)` 得到 1...4。

## 6. 刷新与状态

`StatusPopoverViewController` 注册 `TokenStatsViewModel.observe`,任一 provider 状态变化后重建 snapshot 并 reload collection view。

现有 30 秒刷新逻辑保持不变。状态栏数字和 popover 热力图共享同一个 `TokenStatsViewModel.states` 数据源,避免额外扫描。

加载中处理:

- 有旧 stats 时继续展示旧热力图,避免刷新闪烁。
- 首次加载且没有任何 stats 时展示空热力图和 `0` 总量。
- 授权缺失或错误状态不在热力图里单独展示,由主窗口 provider tab 继续承担授权和错误说明。

## 7. 测试策略

单元测试重点覆盖纯逻辑 builder:

1. 当前月日期范围:给定 2026-06 任意日期,生成 30 个 day cell。
2. 跨 provider 合并:多个 provider 同一天的 `byDay` 汇总相加。
3. 缺失日期补 0:没有 `byDay` 桶的日期仍存在且 token 为 0。
4. `byMonth` 用于月总量:存在 current month bucket 时优先用 `byMonth` 跨 provider 求和。
5. `byMonth` 缺失 fallback:缺失月桶时用当前月 `byDay` 求和。
6. 强度分档:0、低值、中值、最大值映射到 0...4。
7. 首周缩进:按 `calendar.firstWeekday` 生成正确数量的 placeholder cell。
8. 未来日期弱化:未来日期 token 视作 0,`isFuture == true`。

AppKit 层通过构建验证 API 合法;如后续需要交互测试,再补 UI test 覆盖 popover 展示。

## 8. 影响面

| 文件 | 改动 |
|---|---|
| `TokenWatch/ViewControllers/StatusBarController.swift` | popover 内容改为热力图 VC |
| `TokenWatch/ViewControllers/StatusPopoverViewController.swift` | 新增 popover 内容控制器 |
| `TokenWatch/ViewControllers/CalendarHeatmapBuilder.swift` | 新增纯逻辑数据 builder |
| `TokenWatch/ViewControllers/CalendarHeatmapCollectionViewItem.swift` | 新增 collection view item |
| `TokenWatchTests/ViewControllers/CalendarHeatmapBuilderTests.swift` | 新增 builder 单元测试 |

## 9. 提交规范

按项目约定:

- `docs(statusbar): 添加日历热力图设计`
- `feat(statusbar): 在弹窗展示本月 token 热力图`
