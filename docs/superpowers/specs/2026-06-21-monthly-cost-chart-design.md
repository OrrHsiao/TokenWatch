# 按月费用柱状图设计

**日期**: 2026-06-21
**作者**: TokenWatch
**状态**: 设计已确认,待实现

## 背景与目标

当前"按月"页面已经展示过去 12 个月跨 provider 汇总的 token 消耗柱状图。`AggregatedStats.byMonth`
中的 `UsageSummary` 已包含 `totalTokens` 和 `cost`,因此费用视图可以复用现有月度聚合结果,
不需要改扫描、解析或计费层。

本次目标是在按月统计页新增一张费用柱状图:

- 保留现有 token 柱状图。
- 在同一页面新增过去 12 个月每月费用的柱状图。
- 费用单位使用 USD。
- token 与费用分别按各自最大值计算柱高,避免不同单位共享比例造成误读。

## 范围

### 本次包含

1. 扩展按月 snapshot,为每个月增加 `totalCost` 和费用柱高归一化值。
2. 统计过去 12 个月跨 provider 的月度费用总额。
3. 在按月页新增总费用摘要,例如 `$12.34`。
4. 在现有 token 图下方新增费用柱状图。
5. 费用图保持 12 根柱,按月份从旧到新排列,当前月份使用强调色。
6. 费用图 tooltip 展示月份和金额,例如 `2026-06 · $1.23`。
7. 增加 builder、view、页面层测试,覆盖费用聚合与渲染。

### 本次不包含

- 替换现有 token 柱状图。
- token / 费用切换控件。
- token 与费用双轴同图。
- 按 provider 拆分费用柱。
- 预算线、同比、预测或下钻交互。
- 计费表、扫描器、解析器或聚合器底层逻辑改造。

## 推荐方案

采用"两张独立柱状图"方案:

1. 第一张图继续展示每月 token 消耗。
2. 第二张图展示每月费用。
3. 两张图共用相同的 12 个月窗口和月份 label。
4. 两张图各自使用独立最大值计算 `normalizedHeight`。

选择该方案的原因:

- 同时可见 token 消耗规模和实际花费,不需要额外点击切换。
- token 与 USD 属于不同单位,拆成两张图能避免双轴图的误读。
- 复用现有按月页面和 `byMonth` 数据,改动范围清晰。
- 不引入第三方图表库,保持 AppKit 原生实现。

## 数据设计

扩展现有数据结构,保持旧字段兼容:

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

构建规则:

- `MonthlyTokenChartBuilder.build` 继续以 `now` 所在月份为终点生成过去 12 个月窗口。
- 对每个已加载 provider,按月累加 `stats.byMonth[monthKey]?.totalTokens ?? 0`。
- 同时累加 `stats.byMonth[monthKey]?.cost ?? 0`。
- `totalTokens` 为 12 个月 token 合计。
- `totalCost` 为 12 个月费用合计。
- `maxMonthlyTokens` 只用于 token 图柱高。
- `maxMonthlyCost` 只用于费用图柱高。
- 全零费用时所有费用柱高为 0,不产生 NaN 或无穷值。
- 费用值保留 `Double`,只在 UI 层格式化为货币字符串。

## UI 设计

`MonthlyStatsViewController` 结构调整为:

1. 顶部标题:"按月"。
2. 辅助文案:"过去 12 个月,跨 provider 汇总"。
3. 摘要区:
   - token 总量,继续使用 `CompactNumberFormatter`,例如 `1.2M tokens`。
   - 费用总额,使用 USD 货币格式,例如 `$12.34`。
4. token 图区域:
   - 保留现有 `MonthlyTokenChartView` 行为和视觉。
5. 费用图区域:
   - 新增独立费用图视图。
   - 使用同样的月份 label。
   - 当前月份使用 `.controlAccentColor`,历史月份使用与 token 图区分的系统色。
   - tooltip 展示完整月份 key 和费用金额。
6. 状态提示:
   - 复用现有 loading、授权、错误、无数据文案。

页面空态判断仍以 token 数据为主:

- 如果过去 12 个月 token 总量为 0,显示"过去 12 个月暂无 token 数据"。
- 如果有 token 但费用为 0,仍展示费用图,柱高为 0,不额外显示错误。

## 组件设计

为降低风险,新增费用图视图而不是大规模泛化现有 token 图:

```swift
final class MonthlyCostChartView: NSView {
    func configure(with snapshot: MonthlyTokenChartSnapshot)
}
```

`MonthlyCostChartView` 与 `MonthlyTokenChartView` 使用相同的布局模式:

- 内部使用水平 `NSStackView`。
- 每月一列,柱子加月份 label。
- 提供测试可读的 debug 状态,例如 `debugBarCount`、`debugNormalizedHeights`、`debugMonthLabels`。
- 单根费用柱使用确定 intrinsic size,避免动态内容导致布局抖动。

如果实现过程中发现 token 图和费用图重复明显,只允许提取小型私有 helper,不做跨文件大重构。

## 状态处理

沿用现有 `MonthlyStatsViewController.statusText` 策略:

- 所有 provider 都在加载:显示"正在加载用量数据..."。
- 没有已加载 stats 且存在未授权 provider:显示"请先在设置中授权访问用户目录"。
- 存在错误且没有可展示数据时优先显示错误。
- 已有部分数据且仍有 provider 加载中:显示"部分数据仍在加载"。
- 过去 12 个月 token 总量为 0:显示"过去 12 个月暂无 token 数据"。

费用图不新增单独错误状态。费用来自同一个 `UsageSummary.cost`,如果模型没有价格且没有 upstream cost,
则该部分费用按现有聚合逻辑为 0。

## 测试

新增或更新测试:

1. `MonthlyTokenChartBuilderTests`
   - 多 provider 同月费用正确求和。
   - 缺失月份费用补 0。
   - `totalCost` 和 `maxMonthlyCost` 正确。
   - 费用归一化柱高在 `0...1`。
   - 全零费用时费用柱高稳定为 0。
2. `MonthlyCostChartViewTests`
   - 配置 snapshot 后渲染 12 根费用柱。
   - 月份 label 与 snapshot 一致。
   - debug 高度使用 clamp 后的稳定值。
   - 重复配置会替换旧柱子。
3. `MonthlyStatsViewControllerTests`
   - 页面展示总费用摘要。
   - 页面同时包含 token 图和费用图。
   - token 有数据但费用为 0 时仍渲染费用图。

## 影响面

| 文件 | 改动 |
|---|---|
| `TokenWatch/ViewControllers/MonthlyTokenChartBuilder.swift` | snapshot 和 bucket 增加费用字段,构建费用汇总 |
| `TokenWatch/ViewControllers/MonthlyStatsViewController.swift` | 新增费用摘要和费用图布局 |
| `TokenWatch/ViewControllers/MonthlyCostChartView.swift` | 新增费用柱状图视图 |
| `TokenWatchTests/ViewControllers/MonthlyTokenChartBuilderTests.swift` | 增加费用聚合测试 |
| `TokenWatchTests/ViewControllers/MonthlyCostChartViewTests.swift` | 新增费用图视图测试 |
| `TokenWatchTests/ViewControllers/MonthlyStatsViewControllerTests.swift` | 增加页面费用展示测试 |
| `TokenWatch.xcodeproj/project.pbxproj` | 添加新增源码和测试文件引用 |

## 验证命令

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/MonthlyTokenChartBuilderTests test
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/MonthlyCostChartViewTests test
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/MonthlyStatsViewControllerTests test
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests test
```

## 提交建议

实现提交使用:

```text
feat(ui): 新增按月费用柱状图
```
