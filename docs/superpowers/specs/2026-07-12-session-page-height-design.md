# 会话页十行与分页栏完整展示修复设计

## 背景与根因

用户在未缩放的主窗口中打开会话页时，横向滚动条覆盖了分页栏底部，分页按钮与范围文案不能
完整显示。原始截图尺寸为 2332 × 1722、144 DPI，对应默认主窗口量级；截图中的表格横向
滚动条明确压在 44 pt 分页栏上。

最初将问题归因于外层页面高度余量不足，但十条会话的 AppKit 布局探针否定了这个假设：
默认 1180 × 840 内容尺寸下，外层 `sessionStack` 的纵向范围为 28...812，完整位于
0...840 可视区内。真实问题位于内层 `sessionTableScrollView`：

- 表格文档高度为 568 pt（44 pt 表头、10 × 48 pt 数据行、44 pt 分页栏）；
- 横向滚动视图也固定为 568 pt；
- regular overlay 横向滚动条高度为 17 pt；
- 分页栏范围为 524...568，滚动条范围为 551...568，二者重叠 17 pt。

仅增高滚动视图会让分页栏和滚动条一起移动，重叠保持不变；`contentInsets` 与
`scrollerInsets` 也不会为 overlay scroller 创建独立内容空间。AppKit SDK 头文件说明
`contentInsets` 影响 scroll view 子视图平铺，`scrollerInsets` 只控制滚动条距边缘的
内缩，二者都不是 overlay 滚动条 gutter API。

## 目标

- 横向滚动条强制显示时，不覆盖会话分页栏的任何部分。
- 默认 1180 × 840 窗口中，十条会话、分页栏与滚动条全部完整可见，无需纵向滚动。
- 保持每页十条、48 pt 行高、44 pt 表头和 44 pt 分页栏。
- 保持表格独立横向滚动，兼容 overlay 与 legacy 两种滚动条样式。
- 窗口缩小时继续允许外层页面纵向滚动。

## 非目标

- 不增大主窗口默认尺寸。
- 不降低会话行高或减少每页条数。
- 不把分页栏移出表格文档，也不改变分页交互。
- 不调整总览页、设置页或侧边栏的间距。
- 不改动会话解析、聚合、成本计算、排序和分页模型。

## 方案

### 表格文档底部 gutter

保留现有 568 pt 表格内容高度，增加一个由当前 regular scroller 样式宽度决定的固定底部
gutter：

```swift
private static let sessionTableContentHeight = sessionTableHeaderHeight
    + CGFloat(sessionPageSize) * sessionTableRowHeight
    + sessionPaginationHeight
private static let sessionTableScrollerGutter = max(
    NSScroller.scrollerWidth(for: .regular, scrollerStyle: .overlay),
    NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
)
private static let sessionTableHeight = sessionTableContentHeight
    + sessionTableScrollerGutter
```

本机 macOS 26.5 SDK 中 regular overlay 与 legacy 都是 17 pt，因此表格与内层滚动视图
总高度为 585 pt。表格内部仍按 `[header, rows, flexible spacer, pagination]` 排列，但
stack 底部改为距离 table 底部 17 pt：

```swift
stack.bottomAnchor.constraint(
    equalTo: table.bottomAnchor,
    constant: -Self.sessionTableScrollerGutter
)
```

固定 gutter 位于 pagination 之后，专门承接 overlay scroller。现有 flexible spacer 仍在
pagination 之前，因此不足十行时分页栏仍固定在内容区底部，不会紧跟最后一条数据。

### 外层会话页高度预算

新增 gutter 后，若保留当前 28 pt 页边距和 18 pt 区块间距，固定预算会增至 845 pt，
重新造成默认窗口需要少量纵向滚动。因此仅对会话页采用已批准的局部紧凑常量：上下边距
20 pt，标题、指标区和表格之间间距 14 pt。

最终预算为：

`64 + 104 + 585 + 2 × 14 + 2 × 20 = 821 pt`

默认 840 pt 高度仍有 19 pt 余量；总览页继续使用原有 `pageInset = 28` 与
`rowGap = 18`。

## 已排除方案

- 只将 scroll view 增高 17 pt：实测 pagination 与 scroller 同步移动，仍重叠 17 pt。
- `contentInsets.bottom = 17` 加增高：实测 `documentVisibleRect` 扩大，但覆盖保持不变；
  AppKit 还产生 layout-recursion 警告。
- `scrollerInsets`：只改变滚动条距边缘的位置，正 inset 会把滚动条进一步推向内容。
- 将 pagination 移出 document view：能规避重叠，但会改变现有分页与表格一起横向移动的
  结构，改动面明显更大。
- 降低行高或增大默认窗口：分别损害可读性和小屏幕适配，不符合验收标准。

## 测试设计

在 `DashboardSessionPaginationTests` 增加真实布局回归：

1. 构造当天十条会话并按 `MainWindowFactory.contentSize` 完成布局。
2. 强制显示横向滚动条，分别验证 `.overlay` 与 `.legacy` 样式。
3. 将 pagination 与 horizontal scroller frame 转换到同一 scroll view 坐标系，断言交集
   高度不超过 0.5 pt。
4. 确认表格文档宽度仍大于 viewport，证明测试确实处于横向滚动场景。
5. 确认第十行、分页栏和整个 `sessionStack` 的纵向范围位于外层可视区，且默认窗口没有
   纵向滚动范围。
6. 更新现有固定高度断言为 style-aware 的 568 pt 内容高度加 gutter。

按 TDD 分两段推进：

1. 新增重叠测试，在当前代码上确认 pagination 与 scroller 相交而 RED。
2. 加入文档 gutter，使重叠断言变绿；此时外层高度保护应暴露 845 pt 的回归。
3. 改用会话页局部 20/14 pt 常量，使默认高度保护恢复 GREEN。
4. 运行会话分页测试、独立横向滚动测试、完整单元测试和 Debug 构建。

## 风险与控制

当无需横向滚动且 scroller 自动隐藏时，17 pt gutter 仍作为稳定空白保留。这避免滚动条
出现或系统偏好变化时页面跳动，代价可控。gutter 使用 style-aware API 取 overlay 与
legacy 的较大值，避免依赖已弃用的无参数 `scrollerWidth`。如果未来更改 scroller
`controlSize` 或使用自定义 `NSScroller`，应同步更新该布局度量及回归测试。

本次没有数据、持久化或异常流程变更，不需要迁移和新增日志。
