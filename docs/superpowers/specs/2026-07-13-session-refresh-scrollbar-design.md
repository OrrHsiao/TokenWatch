# 会话页刷新态免滚动设计

## 背景

默认 `1180×840` 窗口在数据稳定后，已经可以完整展示会话表格的 8 列、10 行和分页栏。但在应用首次加载或手动刷新期间，会话页仍会同时出现外层纵向滚动条和表格横向滚动条；刷新完成后两者消失。

## 根因

会话页稳定状态的最低内容高度为 `821pt`。任一 provider 加载时，表格下方的 `sessionStatusLabel` 会显示“正在加载”或“部分数据仍在加载”等状态，并额外引入一行文字高度和 `14pt` 栈间距，使内容高度达到约 `850pt`，超过默认 `840pt` 视口约 `10pt`，形成真实纵向滚动范围。

表格在默认窗口中的可用宽度正好是 `880pt`。legacy 纵向 scroller 出现后占用 `17pt` 宽度，使表格视口缩至约 `863pt`，而 document 仍至少为 `880pt`，因此级联产生横向滚动范围。

## 目标

- 首次加载期间，默认窗口的会话页不出现纵向或横向滚动范围。
- 手动刷新期间，即使保留已有会话数据，默认窗口也不出现纵向或横向滚动范围。
- 刷新状态仍可从侧边栏“上次本地扫描”和刷新按钮获得。
- 加载结束后，现有空数据、授权和错误状态提示行为不变。
- 小窗口仍保留必要的纵向和横向滚动能力。

## 非目标

- 不修改默认窗口 `1180×840` 尺寸。
- 不调整侧边栏宽度、页面边距、列宽、行高、分页或表格高度。
- 不改变 provider 加载、会话聚合、排序和复制行为。
- 不重构通用滚动视图或引入新的状态组件。

## 设计

`renderSessionPage(states:)` 继续按现有规则计算 `sessionStatusLabel` 文案，但只在没有 provider 加载且文案非空时显示：

```swift
let isLoading = snapshot.loadingProviderCount > 0
sessionStatusLabel.isHidden = isLoading || sessionStatusLabel.stringValue.isEmpty
```

这样处理后：

- 首次加载且暂无会话时，表格内现有“暂无会话”行继续占据固定表格区域；侧边栏显示正在更新，外部状态行不参与页面布局。
- 手动刷新且已有会话时，现有表格内容保持可见；侧边栏显示正在更新，外部“部分数据仍在加载”状态行不参与页面布局。
- 所有 provider 加载完成后，空数据、授权或错误文案仍按现有规则显示；正常有数据时状态行继续隐藏。

该方案直接消除刷新态新增的页面高度，外层纵向 scroller 不再出现，表格视口也不会被级联压窄，因此无需修改既有 `880pt` 表格宽度策略。

## 测试设计

在 `DashboardSessionPaginationTests` 增加两项真实控制器布局测试：

1. 首次加载：所有 provider 均为 `isLoading == true`、无 entries。
2. 手动刷新：先提供 21 条稳定数据，再将 provider 状态切换为 `isLoading == true`，通过 `.providerStateDidChange` 触发现有渲染链。

两项测试均在默认 `1180×840` 尺寸下验证：

- 加载状态行隐藏，不参与 `sessionStack` 高度。
- overlay 和 legacy 两种 scroller style 下，页面 document 高度不超过可见高度。
- 表格 document 宽度不超过可见宽度。
- 表头、数据或空行及分页栏仍处于可见区域。

保留现有小窗口测试，确保尺寸不足时仍能滚动到底部并访问分页栏；完整单元测试用于确认分页、排序、复制和其他页面没有回归。

## 真实应用验收

使用最终 Debug 构建分别验证：

- 冷启动后在“正在更新本地记录”期间立即打开会话页。
- 数据稳定后手动点击刷新，再立即打开会话页。

两个场景都必须在不执行滚动的情况下完整显示表格与分页，并且 `DashboardSessionsPageScrollView` 不暴露 `Scroll Up/Down`，`DashboardSessionsTableScrollView` 不暴露 `Scroll Left/Right`。

