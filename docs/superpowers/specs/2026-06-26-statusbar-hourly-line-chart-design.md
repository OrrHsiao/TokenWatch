# 状态栏 Popover 本日小时折线图设计

- 日期:2026-06-26
- 关联:`StatusPopoverViewController`、`MonthlyTokenChartBuilder`、`AggregatedStats.byHour`

## 1. 范围与目标

状态栏左键弹出的 popover 当前包含本日描述、四个摘要卡片、近 22 周 token 热力图。本次在热力图下方增加一张紧凑折线图,展示本日 0 点到 23 点各小时的跨 provider token 用量。

本次包含:

- 在热力图下方展示本日 24 小时 token 用量折线图。
- 跨所有 provider 合并统计,口径沿用 `UsageSummary.totalTokens`。
- 复用已有 `MonthlyTokenChartBuilder.build(period: .today)` 生成小时桶数据。
- 缺失小时补 0,未来小时仍保留在横轴上并显示为 0。
- hover 图表时复用 popover 现有 hover label,展示小时和 token 数。

不在本次范围:

- 成本折线图。
- provider、模型或项目筛选。
- 点击小时下钻详情。
- 主窗口图表改造。
- 数据层聚合重做。

## 2. 方案选择

推荐方案:新增一个 popover 专用的紧凑 Charts 折线图宿主视图。

备选方案:

1. 直接复用 `MonthlyTokenChartView` 并切到 `.today`。优点是代码复用最多;缺点是现有视图是 220pt 起步的柱状图,放进 370pt 宽 popover 会显得过重,也不符合用户明确要求的折线图。
2. 在 `StatusPopoverViewController` 内直接 `draw(_:)`。优点是文件少;缺点是控制器会同时承担布局、数据转换和绘制逻辑,测试边界变差。
3. 新增 `TodayHourlyTokenLineChartView`,内部用 `NSHostingView` 承载 SwiftUI `Chart`。优点是保持 popover 轻量,同时与项目现有图表一样使用系统 Charts 框架;缺点是需要新增一个小型宿主视图和 SwiftUI 图表内容。

采用第 3 个方案。

## 3. 数据流

`StatusPopoverViewController.render()` 在构建热力图 snapshot 后,同时构建本日小时 snapshot:

```swift
let hourlySnapshot = MonthlyTokenChartBuilder.build(
    states: viewModel.states,
    period: .today,
    now: now,
    calendar: calendar,
    language: language
)
```

折线图只消费 `hourlySnapshot.monthBuckets`:

- `monthKey`:小时 key,格式为 `yyyy-MM-ddTHH`。
- `monthLabel`:本地化小时标签,例如 `9时` 或 `9`。
- `totalTokens`:该小时跨 provider token 总量。
- `normalizedHeight`:相对本日最大小时用量的归一化高度。
- `isCurrentMonth`:当前小时高亮。

`MonthlyTokenChartBuilder` 的 `.today` 已保证生成自然日 24 个小时桶,从 00 到 23 排列。未来小时没有真实数据时保持 0。

## 4. UI 设计

Popover 宽度保持 `370`。高度从当前 `236` 增加到可容纳折线图的新高度,避免内容拥挤。

视觉结构自上而下:

1. 本日描述和刷新按钮。
2. 四个摘要卡片。
3. 近 22 周热力图及 hover label。
4. 本日小时折线图。

折线图尺寸:

- 宽度与热力图一致,使用现有 `collectionWidth`。
- 高度约 74pt,适合菜单栏 popover 的轻量预览。
- 上下左右留出内部 padding,避免线条贴边。

绘制规则:

- 背景透明,不使用额外卡片容器。
- 使用系统 Charts 框架绘制,核心 marks 为 `LineMark`,当前小时可叠加 `PointMark`。
- `chartYAxis` 使用少量 `AxisMarks` 与淡网格线,纵轴标签保持紧凑。
- `chartXAxis` 只显示少量关键刻度,如 `0`、`6`、`12`、`18`、`23`,避免 24 个标签拥挤。
- 折线使用系统强调色,图表随系统浅色/暗黑模式适配。
- 数据点数量固定 24。
- 全零数据时保持稳定坐标域和空趋势,不产生 NaN 或跳动。

Hover:

- 图表通过 `chartOverlay` 和 `ChartProxy` 根据鼠标横向位置找到最近小时桶。
- hover 文案格式:`<小时标签> · <token 数>`。
- token 数使用 `CompactNumberFormatter.formatMillions`。
- 鼠标离开时恢复空 hover label。

## 5. 组件边界

新增 `TodayHourlyTokenLineChartView`:

- 继承 `NSView`。
- 内部持有一个 `NSHostingView<AnyView>`。
- SwiftUI 内容使用 `import Charts` 的 `Chart` 渲染折线。
- 对外提供 `configure(with:language:)`。
- 对外提供 `onHoverTextChange: ((String?) -> Void)?`。
- 内部只保存 bucket 快照和当前语言,不读取 `TokenStatsViewModel`。
- 图表内容和 hover 都基于 `MonthlyTokenBucket`。

`StatusPopoverViewController`:

- 新增折线图子视图。
- `render()` 同步配置折线图。
- 约束把折线图放在 collection view 下方。
- 调整 `contentSize` 和底部约束。
- 保留现有热力图 hover 行为。

## 6. 测试策略

使用 Swift Testing 先写失败测试,再实现。

测试覆盖:

1. `TodayHourlyTokenLineChartViewTests`
   - 配置 24 个小时桶后保留 24 个 debug 点。
   - 全零数据时归一化高度稳定为 0。
   - 小时横轴标签只保留少量刻度。
   - 图表视图使用 `NSHostingView<AnyView>` 承载 Charts 内容。
   - hover 某个小时会回传对应 token 文案,离开后回传 nil。
   - 英文语言下 hover 小时标签不带中文 `时`。
2. `StatusPopoverViewControllerTests`
   - popover 加载后包含折线图。
   - 折线图位于热力图下方,宽度与热力图一致。
   - `render()` 使用 `.today` 的 24 小时桶配置折线图。
   - 热力图和折线图都复用同一个 hover label。

验证命令:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/TodayHourlyTokenLineChartViewTests test
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/StatusPopoverViewControllerTests test
```

最后运行完整单元测试目标:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests test
```

## 7. 风险与处理

- Popover 过高:只新增 74pt 左右紧凑图表,并保持宽度不变。
- 24 个小时标签拥挤:横轴只显示关键刻度。
- 未来小时造成误读:按用户确认,未来小时保留在轴上并显示为 0。
- 旧 hover 文案互相覆盖:统一复用现有 hover label,鼠标离开时清空。
- Charts 嵌入 popover 后布局过重:复用项目已引入的系统 Charts,但只渲染 24 个 `LineMark`,宿主高度固定为紧凑尺寸。

## 8. 影响面

| 文件 | 改动 |
|---|---|
| `TokenWatch/ViewControllers/TodayHourlyTokenLineChartView.swift` | 新增紧凑折线图视图 |
| `TokenWatch/ViewControllers/StatusPopoverViewController.swift` | 新增折线图布局与配置 |
| `TokenWatchTests/ViewControllers/TodayHourlyTokenLineChartViewTests.swift` | 新增折线图单元测试 |
| `TokenWatchTests/ViewControllers/StatusPopoverViewControllerTests.swift` | 更新 popover 布局测试 |
| `TokenWatch.xcodeproj/project.pbxproj` | 添加新源码和测试文件引用 |

## 9. 提交建议

实现提交使用:

```text
feat(statusbar): 在弹窗展示本日小时折线图
```
