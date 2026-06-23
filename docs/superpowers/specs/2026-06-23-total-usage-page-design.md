# 总计用量页面设计

**日期**: 2026-06-23
**作者**: TokenWatch
**状态**: 设计已确认,待实现

## 背景与目标

当前侧边栏已经提供跨 provider 的时间窗口入口:`最近 12 个月`、`最近 30 天`、`本日`。用户希望在
`最近 12 个月` 上方新增一个同级别入口 `总计`,用于查看全量跨 provider 的整体消耗。

本次目标:

- 在侧边栏新增 `总计`,位置在 `最近 12 个月` 上方。
- `总计` 打开独立页面,不嵌入 `最近 12 个月` 页面。
- 页面展示消耗的总 token 数、总费用、每种大模型消耗的 token。
- 模型列表按 token 消耗量降序排列,同 token 时按模型名排序。

## 范围

### 本次包含

1. 新增侧边栏全局项 `总计`。
2. 新增 `TotalStatsViewController`,展示跨 provider 全量汇总。
3. 新增纯数据 builder,把 `[ProviderID: ProviderState]` 转成总计页 snapshot。
4. 汇总所有已加载 provider 的 `AggregatedStats.overall` 作为总 token 和总费用。
5. 汇总所有已加载 provider 的 `AggregatedStats.byModel` 作为模型 token 列表。
6. 沿用现有 loading、授权、错误、无数据提示策略。
7. 增加 builder 和页面路由测试。

### 本次不包含

- 时间范围切换。
- 按 provider 下钻。
- 模型费用列表。
- 导出、筛选、搜索或图表交互。
- 扫描、解析、计费表或聚合器底层逻辑改造。

## 信息架构

侧边栏顺序调整为:

```text
Provider 列表
总计
最近 12 个月
最近 30 天
本日
设置
```

顶层路由新增 `SidebarContent.total`。点击 `总计` 时安装 `TotalStatsViewController`。

默认启动选中逻辑保持不变,仍选中第一个 provider。新增 `总计` 只是一个额外全局入口。

## 数据设计

新增总计页 snapshot:

```swift
struct TotalStatsSnapshot: Sendable, Equatable {
    let totalTokens: Int
    let totalCost: Double
    let modelRows: [TotalStatsModelRow]
    let loadedProviderCount: Int
    let loadingProviderCount: Int
    let unauthorizedProviderCount: Int
    let errorMessages: [String]
}

struct TotalStatsModelRow: Sendable, Equatable, Identifiable {
    let modelName: String
    let totalTokens: Int

    var id: String { modelName }
}
```

构建规则:

- 没有 `stats` 的 provider 不参与用量求和。
- 每个已加载 provider:
  - `stats.overall.totalTokens` 累加到 `totalTokens`。
  - `stats.overall.cost` 累加到 `totalCost`。
  - `stats.byModel` 中每个模型的 `totalTokens` 累加到模型总量。
- 模型行过滤掉 `totalTokens <= 0` 的项。
- 模型行排序:先按 `totalTokens` 降序,再按模型名不区分大小写升序。
- loading、未授权、错误计数与现有时间窗口 builder 保持一致。

## UI 设计

`TotalStatsViewController` 使用简洁工具页布局:

1. 顶部标题:`总计`。
2. 辅助文案:`跨 provider 全量汇总`。
3. 摘要区:
   - 总 token 数,使用 `CompactNumberFormatter.formatMillions`。
   - 总费用,使用 USD 格式 `$12.34`。
4. 模型列表:
   - 标题 `模型消耗`。
   - 每行展示模型名和 token 总量。
   - token 总量右对齐,使用等宽数字字体。
   - 模型名过长时中间截断。
5. 状态提示:
   - 放在列表下方,沿用现有文案风格。

页面不需要卡片化外框,保持与现有统计页相近的 AppKit 工具界面风格。

## 状态处理

状态文案策略:

- 所有 provider 都在加载且没有已加载 stats:显示 `正在加载用量数据...`。
- 没有任何已加载 stats 且存在未授权 provider:显示 `请先在设置中授权访问用户目录`。
- 没有任何已加载 stats 且存在错误:显示第一条错误。
- 已加载数据的 `totalTokens == 0`:显示 `总计暂无 token 数据`。
- 已有部分数据且仍有 provider 加载中:显示 `部分数据仍在加载`。
- 已有部分数据且存在 provider 错误:保留数据,显示第一条错误。

## 测试

新增或更新测试:

1. `TotalStatsBuilderTests`
   - 多 provider 总 token 和费用正确求和。
   - 多 provider 同模型 token 正确合并。
   - 模型行按 token 降序排序。
   - 同 token 时按模型名排序。
   - loading、未授权、错误计数正确。
2. `TotalStatsViewControllerTests`
   - 加载后展示标题、说明、总 token、总费用。
   - 展示按 token 排序的模型行。
   - 无数据、未授权、加载中、错误状态展示正确。
3. `TokenWatchTests`
   - 侧边栏顺序包含 `总计`,且位于 `最近 12 个月` 上方。
   - 选择 `总计` 后安装 `TotalStatsViewController`。

## 影响面

| 文件 | 改动 |
|---|---|
| `TokenWatch/ViewController.swift` | 新增侧边栏项和路由 |
| `TokenWatch/ViewControllers/TotalStatsBuilder.swift` | 新增总计页纯数据 builder |
| `TokenWatch/ViewControllers/TotalStatsViewController.swift` | 新增总计页 UI |
| `TokenWatchTests/TokenWatchTests.swift` | 更新侧边栏顺序和路由测试 |
| `TokenWatchTests/ViewControllers/TotalStatsBuilderTests.swift` | 新增 builder 测试 |
| `TokenWatchTests/ViewControllers/TotalStatsViewControllerTests.swift` | 新增页面测试 |
| `TokenWatch.xcodeproj/project.pbxproj` | 添加新增源码和测试文件引用 |

## 验证命令

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/TotalStatsBuilderTests test
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/TotalStatsViewControllerTests test
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests test
```

## 提交建议

实现提交使用:

```text
feat(stats): 新增总计用量页面
```
