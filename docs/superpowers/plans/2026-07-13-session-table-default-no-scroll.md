# 会话表格默认窗口双向免滚动 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 默认 `1180 × 840pt` 主窗口下，无需上下或左右滚动即可完整看到会话表格八列、10 条数据行和分页栏。

**Architecture:** 将表格真实 document 高度恢复为 `568pt`，滚动视图外壳继续保留动态 scroller gutter，使 legacy/overlay 都没有内层纵向溢出；使用顶部对齐的 flipped document 保证多余 gutter 固定落在底部。把列宽、列间距和行内边距压缩到默认可视宽度 `880pt`，小窗口仍通过现有独立滚动视图访问溢出内容。

**Tech Stack:** Swift 6、AppKit、Swift Testing、Xcode `xcodebuild`

## Global Constraints

- 默认主窗口内容尺寸保持 `1180 × 840pt`。
- 侧边栏宽度保持 `244pt`，会话页水平边距保持每侧 `28pt`。
- 每页保持 10 条；数据行 `48pt`、表头 `44pt`、分页栏 `44pt`。
- 默认窗口必须同时免除外层纵向滚动与表格横向滚动。
- overlay 与 legacy 两种横向滚动条样式都不能产生内层纵向滚动范围或覆盖分页栏。
- 小于默认尺寸的窗口继续允许外层纵向滚动和表格横向滚动。
- 不改变分页、排序、数据聚合、其他页面布局及会话 ID 完整复制行为。

---

### Task 1: 修复会话表格默认窗口双向溢出

**Files:**
- Modify: `TokenWatch/ViewControllers/DashboardAppearance.swift:175`
- Modify: `TokenWatch/ViewControllers/DashboardViewController.swift:5-28, 938-991, 1139-1260`
- Modify: `TokenWatchTests/ViewControllers/DashboardSessionPaginationTests.swift:69-194`
- Modify: `TokenWatchTests/TokenWatchTests.swift:776-811`

**Interfaces:**
- Consumes: `MainWindowFactory.contentSize == NSSize(width: 1180, height: 840)`、`DashboardSessionsTableScrollView`、`DashboardSessionsTable`、`DashboardSessionsTableHeader`、`DashboardSessionsRow.9`、`DashboardSessionsPagination` 的现有 accessibility identifier。
- Produces: 默认表格 document 宽度 `880pt`、内容高度 `568pt`、外壳高度 `568pt + sessionTableScrollerGutter`；`DashboardSessionTableDocumentView.isFlipped == true`。

- [ ] **Step 1: 把默认双向免滚动行为写成失败测试**

将 `dashboardScrollerKeepsPaginationAndTenRowsVisible()` 的数据量改为 21，并改名为 `dashboardDefaultWindowShowsAllColumnsTenRowsAndPaginationWithoutScrolling()`。在原有查找视图基础上增加表头和分页按钮区域：

```swift
let header = try #require(
    findView(withIdentifier: "DashboardSessionsTableHeader", in: controller.view)
)
let paginationControls = try #require(
    findView(withIdentifier: "DashboardSessionsPaginationControls", in: controller.view)
)
```

fixture 使用 `makeEntries(count: 21, now: now)`，确保第一页 10 行且分页控制包含 1、2、3。对 `.overlay` 与 `.legacy` 分别强制显示横向滚动条并断言 document 在两个方向均没有默认窗口溢出：

```swift
for style in [NSScroller.Style.overlay, .legacy] {
    tableScrollView.scrollerStyle = style
    tableScrollView.autohidesScrollers = false
    tableScrollView.hasHorizontalScroller = true
    tableScrollView.tile()
    controller.view.layoutSubtreeIfNeeded()

    let tableDocumentView = try #require(tableScrollView.documentView)
    let tableVisibleRect = tableScrollView.documentVisibleRect
    let headerFrame = header.convert(header.bounds, to: tableDocumentView)
    let lastRowFrame = lastRow.convert(lastRow.bounds, to: tableDocumentView)
    let paginationFrame = pagination.convert(pagination.bounds, to: tableDocumentView)
    let controlsFrame = paginationControls.convert(paginationControls.bounds, to: tableDocumentView)

    #expect(tableDocumentView.frame.width <= tableScrollView.contentView.bounds.width + 0.5)
    #expect(tableDocumentView.frame.height <= tableScrollView.contentView.bounds.height + 0.5)
    #expect(tableVisibleRect.minX <= headerFrame.minX + 0.5)
    #expect(tableVisibleRect.maxX + 0.5 >= headerFrame.maxX)
    #expect(tableVisibleRect.minY <= headerFrame.minY + 0.5)
    #expect(tableVisibleRect.maxY + 0.5 >= headerFrame.maxY)
    #expect(tableVisibleRect.minY <= lastRowFrame.minY + 0.5)
    #expect(tableVisibleRect.maxY + 0.5 >= lastRowFrame.maxY)
    #expect(tableVisibleRect.minY <= paginationFrame.minY + 0.5)
    #expect(tableVisibleRect.maxY + 0.5 >= paginationFrame.maxY)
    #expect(tableVisibleRect.minX <= controlsFrame.minX + 0.5)
    #expect(tableVisibleRect.maxX + 0.5 >= controlsFrame.maxX)
}
```

保留外层 `pageDocumentView.frame.height <= pageVisibleRect.height + 0.5`、会话栈、第 10 行和分页栏可见断言。

同步改写 `dashboardSessionTableUsesIndependentHorizontalScrollView()`：默认宽度断言 document 与 clip 等宽；将窗口缩至 `1160pt` 后断言 document 保持至少 `880pt` 且大于 clip；再放大至 `1500pt` 后断言 document 重新贴合 clip。

```swift
#expect(abs(table.frame.width - tableScrollView.contentView.bounds.width) < 1)

viewController.view.setFrameSize(NSSize(width: 1_160, height: MainWindowFactory.contentSize.height))
viewController.view.layoutSubtreeIfNeeded()
#expect(table.frame.width >= 880)
#expect(table.frame.width > tableScrollView.contentView.bounds.width)

viewController.view.setFrameSize(NSSize(width: 1_500, height: MainWindowFactory.contentSize.height))
viewController.view.layoutSubtreeIfNeeded()
#expect(abs(table.frame.width - tableScrollView.contentView.bounds.width) < 1)
```

- [ ] **Step 2: 运行测试并确认 RED 原因正确**

Run:

```bash
xcodebuild -quiet -project TokenWatch.xcodeproj -scheme TokenWatch \
  -destination 'platform=macOS' \
  '-only-testing:TokenWatchTests/DashboardSessionPaginationTests/dashboardDefaultWindowShowsAllColumnsTenRowsAndPaginationWithoutScrolling()' \
  '-only-testing:TokenWatchTests/TokenWatchTests/dashboardSessionTableUsesIndependentHorizontalScrollView()' \
  -skip-testing:TokenWatchUITests \
  -derivedDataPath .build/DerivedData -enableCodeCoverage NO test
```

Expected: FAIL。默认 document 宽 `1,108pt` 大于约 `880pt` clip；legacy 下 document 高 `585pt` 大于约 `568pt` clip。失败不得来自 fixture、identifier 或编译错误。

- [ ] **Step 3: 写最小生产实现**

在 `DashboardAppearance.swift` 中允许会话表格建立专用子类，其他调用保持原行为：

```swift
class DashboardRoundedView: NSView, DashboardAppearanceRefreshable {
```

在 `DashboardViewController.swift` 中增加顶部对齐 document：

```swift
private final class DashboardSessionTableDocumentView: DashboardRoundedView {
    /// AppKit 在 document 小于 overlay clip 时默认底部对齐；翻转坐标确保 17pt gutter 留在底部而不裁表头。
    override var isFlipped: Bool { true }
}
```

将表格宽度常量改为：

```swift
private static let sessionTableColumnWidths: [CGFloat] = [120, 150, 84, 132, 116, 86, 76, 68]
private static let sessionTableMinimumWidth: CGFloat = 880
private static let sessionTableColumnSpacing: CGFloat = 4
private static let sessionTableHorizontalPadding: CGFloat = 10
```

滚动视图外壳继续使用 `sessionTableHeight`，但 document 与内部 stack 只使用 `sessionTableContentHeight`：

```swift
sessionTableScrollView.heightAnchor.constraint(equalToConstant: Self.sessionTableHeight)
table.heightAnchor.constraint(equalToConstant: Self.sessionTableContentHeight)
```

`makeSessionTable()` 改用 `DashboardSessionTableDocumentView`，并移除 document 内部的 gutter：

```swift
let table = DashboardSessionTableDocumentView(
    backgroundColor: DashboardPalette.panelBackground,
    cornerRadius: 8,
    borderColor: DashboardPalette.border,
    borderWidth: 1
)

NSLayoutConstraint.activate([
    table.heightAnchor.constraint(equalToConstant: Self.sessionTableContentHeight),
    stack.leadingAnchor.constraint(equalTo: table.leadingAnchor),
    stack.trailingAnchor.constraint(equalTo: table.trailingAnchor),
    stack.topAnchor.constraint(equalTo: table.topAnchor),
    stack.bottomAnchor.constraint(equalTo: table.bottomAnchor),
])
```

`makeSessionTableRowContainer()` 使用紧凑间距和内边距：

```swift
content.spacing = Self.sessionTableColumnSpacing

NSLayoutConstraint.activate([
    row.heightAnchor.constraint(equalToConstant: height),
    content.leadingAnchor.constraint(
        equalTo: row.leadingAnchor,
        constant: Self.sessionTableHorizontalPadding
    ),
    content.trailingAnchor.constraint(
        lessThanOrEqualTo: row.trailingAnchor,
        constant: -Self.sessionTableHorizontalPadding
    ),
    content.centerYAnchor.constraint(equalTo: row.centerYAnchor),
])
```

- [ ] **Step 4: 重跑聚焦测试并确认 GREEN**

Run: Step 2 的同一条 `xcodebuild` 命令。

Expected: PASS。默认宽度无横向范围；overlay/legacy 均无内层纵向范围；缩至 `1160pt` 后独立横向范围仍存在。

- [ ] **Step 5: 运行会话页相关回归测试**

Run:

```bash
xcodebuild -quiet -project TokenWatch.xcodeproj -scheme TokenWatch \
  -destination 'platform=macOS' \
  '-only-testing:TokenWatchTests/DashboardSessionPaginationTests' \
  '-only-testing:TokenWatchTests/TokenWatchTests/dashboardSessionsNavigationShowsPencilSessionDetailsPage()' \
  '-only-testing:TokenWatchTests/TokenWatchTests/dashboardSessionsPageRendersSelectedDaySessionRowsAndSummaries()' \
  '-only-testing:TokenWatchTests/TokenWatchTests/dashboardSessionDataRowsUseCompactItemHeight()' \
  '-only-testing:TokenWatchTests/TokenWatchTests/dashboardSessionsTableHeightFitsTenCompactRows()' \
  '-only-testing:TokenWatchTests/TokenWatchTests/dashboardSessionTableUsesIndependentHorizontalScrollView()' \
  -skip-testing:TokenWatchUITests \
  -derivedDataPath .build/DerivedData -enableCodeCoverage NO test
```

Expected: 全部 PASS；不得出现 Auto Layout 冲突或 AppKit layout recursion 警告。

- [ ] **Step 6: 运行完整单元测试与 Debug 构建**

Run:

```bash
xcodebuild -quiet -project TokenWatch.xcodeproj -scheme TokenWatch \
  -destination 'platform=macOS' -only-testing:TokenWatchTests \
  -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData \
  -enableCodeCoverage NO test

xcodebuild -quiet -project TokenWatch.xcodeproj -scheme TokenWatch \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData build
```

Expected: 完整单元测试 0 failure、0 skipped；Debug build exit code 0。

- [ ] **Step 7: 真实 Debug App 初始状态复验**

启动 `.build/DerivedData/Build/Products/Debug/AI Token Watch.app`，等待本地扫描完成后直接进入会话页，不执行滚动。确认：

- Accessibility tree 中外层 `DashboardSessionsPageScrollView` 没有 `Scroll Up/Scroll Down` 动作。
- 内层 `DashboardSessionsTableScrollView` 在默认窗口没有可用的 `Scroll Left/Scroll Right` 范围。
- 截图同时包含完整八列表头、10 条数据行和完整分页栏。

- [ ] **Step 8: 检查差异并提交**

Run:

```bash
git diff --check
git status --short
git diff -- TokenWatch/ViewControllers/DashboardAppearance.swift \
  TokenWatch/ViewControllers/DashboardViewController.swift \
  TokenWatchTests/ViewControllers/DashboardSessionPaginationTests.swift \
  TokenWatchTests/TokenWatchTests.swift
```

Expected: 只有计划内四个文件，`git diff --check` 无输出。

Commit:

```bash
git add TokenWatch/ViewControllers/DashboardAppearance.swift \
  TokenWatch/ViewControllers/DashboardViewController.swift \
  TokenWatchTests/ViewControllers/DashboardSessionPaginationTests.swift \
  TokenWatchTests/TokenWatchTests.swift
git commit -m "fix(dashboard): 消除会话表格默认双向滚动"
```
