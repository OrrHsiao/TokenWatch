# 会话页分页栏与滚动条完整展示修复实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 默认 1180 × 840 主窗口中完整展示十条会话、分页栏与横向滚动条，且滚动条不覆盖分页控件。

**Architecture:** 保持 568 pt 的表格内容结构，在 document 底部增加 style-aware 的固定 scroller gutter，让 overlay/legacy 横向滚动条拥有独立区域。表格总高度增加 gutter 后，仅压缩会话页的纵向边距与区块间距，使默认窗口仍无纵向滚动；总览页和横向布局不变。

**Tech Stack:** Swift 6、AppKit、Swift Testing、Xcode 26 / `xcodebuild`

## Global Constraints

- 主窗口默认内容尺寸保持 1180 × 840。
- 会话页保持每页十条、48 pt 行高、44 pt 表头和 44 pt 分页栏。
- 横向滚动条不得覆盖分页栏，且兼容 `.overlay` 与 `.legacy` 样式。
- 小窗口继续允许外层页面纵向滚动。
- 表格独立横向滚动、会话数据排序、聚合和分页模型保持不变。
- 总览页、设置页、侧边栏和会话页水平边距保持不变。

---

### Task 1: 增加横向滚动条 gutter 并收紧会话页纵向预算

**Files:**
- Modify: `TokenWatchTests/ViewControllers/DashboardSessionPaginationTests.swift:33-68`
- Modify: `TokenWatchTests/TokenWatchTests.swift:1135-1146`
- Modify: `TokenWatch/ViewControllers/DashboardViewController.swift:5-20,288-329,919-984`

**Interfaces:**
- Consumes: `MainWindowFactory.contentSize: NSSize`、`NSScroller.scrollerWidth(for:scrollerStyle:)`、`NSScrollView.scrollerStyle`、测试夹具 `makeEntries(count:now:)`。
- Produces: `sessionTableContentHeight`、`sessionTableScrollerGutter`、`sessionTableHeight`、`sessionVerticalInset`、`sessionRowGap` 私有布局常量；不新增公开接口。

- [ ] **Step 1: 写出滚动条覆盖与默认纵向可见性的布局测试**

在 `DashboardSessionPaginationTests.dashboardNextButtonShowsNextSessionPage()` 后加入：

```swift
    @MainActor
    @Test("横向滚动条不覆盖分页栏且默认窗口无需纵向滚动")
    func dashboardScrollerKeepsPaginationAndTenRowsVisible() throws {
        let now = dateTime(2026, 7, 4, hour: 12, minute: 0)
        let languageSettings = zhHansLanguageSettings()
        let controller = DashboardViewController(
            settingsViewController: settingsViewController(languageSettings: languageSettings),
            stateProvider: { [
                .claude: .init(
                    stats: nil,
                    entries: makeEntries(count: 10, now: now),
                    isLoading: false,
                    errorMessage: nil,
                    needsAuthorization: false
                ),
            ] },
            nowProvider: { now },
            calendar: calendar(),
            languageSettings: languageSettings
        )

        controller.loadViewIfNeeded()
        controller.view.setFrameSize(MainWindowFactory.contentSize)
        try button(withIdentifier: "DashboardNav.sessions", in: controller.view).performClick(nil)
        controller.view.layoutSubtreeIfNeeded()

        let pageScrollView = try #require(
            findView(withIdentifier: "DashboardSessionsPageScrollView", in: controller.view) as? NSScrollView
        )
        let pageDocumentView = try #require(pageScrollView.documentView)
        let sessionStack = try #require(
            findView(withIdentifier: "DashboardSessionsPage", in: controller.view)
        )
        let tableScrollView = try #require(
            findView(withIdentifier: "DashboardSessionsTableScrollView", in: controller.view) as? NSScrollView
        )
        let pagination = try #require(
            findView(withIdentifier: "DashboardSessionsPagination", in: controller.view)
        )
        let lastRow = try #require(
            findView(withIdentifier: "DashboardSessionsRow.9", in: controller.view)
        )

        for style in [NSScroller.Style.overlay, .legacy] {
            tableScrollView.scrollerStyle = style
            tableScrollView.autohidesScrollers = false
            tableScrollView.hasHorizontalScroller = true
            tableScrollView.tile()
            controller.view.layoutSubtreeIfNeeded()

            let horizontalScroller = try #require(tableScrollView.horizontalScroller)
            let paginationFrame = pagination.convert(pagination.bounds, to: tableScrollView)
            let scrollerFrame = horizontalScroller.convert(horizontalScroller.bounds, to: tableScrollView)

            #expect((tableScrollView.documentView?.frame.width ?? 0) > tableScrollView.contentView.bounds.width)
            #expect(paginationFrame.intersection(scrollerFrame).height <= 0.5)
        }

        let pageVisibleRect = pageScrollView.documentVisibleRect
        let sessionStackFrame = sessionStack.convert(sessionStack.bounds, to: pageDocumentView)
        let lastRowFrame = lastRow.convert(lastRow.bounds, to: pageDocumentView)
        let paginationFrame = pagination.convert(pagination.bounds, to: pageDocumentView)

        #expect(pageDocumentView.frame.height <= pageVisibleRect.height + 0.5)
        #expect(pageVisibleRect.minY <= sessionStackFrame.minY && pageVisibleRect.maxY >= sessionStackFrame.maxY)
        #expect(pageVisibleRect.minY <= lastRowFrame.minY && pageVisibleRect.maxY >= lastRowFrame.maxY)
        #expect(pageVisibleRect.minY <= paginationFrame.minY && pageVisibleRect.maxY >= paginationFrame.maxY)
        #expect(pageScrollView.hasVerticalScroller)
    }
```

在 `TokenWatchTests.dashboardSessionsTableHeightFitsTenCompactRows()` 中先将旧的 568 pt
固定值断言改为 style-aware 期望值：

```swift
        let scrollerGutter = max(
            NSScroller.scrollerWidth(for: .regular, scrollerStyle: .overlay),
            NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
        )

        #expect(table.fixedHeightConstant == 568 + scrollerGutter)
```

- [ ] **Step 2: 运行重叠测试并确认有效 RED**

Run:

```bash
xcodebuild -quiet -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' '-only-testing:TokenWatchTests/DashboardSessionPaginationTests/dashboardScrollerKeepsPaginationAndTenRowsVisible()' -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData -enableCodeCoverage NO test
```

Expected: 测试被正常发现并执行，因当前 pagination 与 overlay scroller 相交 17 pt 而
`TEST FAILED`；文档宽度与外层纵向断言不能是失败原因。

- [ ] **Step 3: 增加 document 底部 gutter**

将 `DashboardViewController` 的表格高度常量改为：

```swift
    private static let sessionTableHeaderHeight: CGFloat = 44
    private static let sessionTableRowHeight: CGFloat = 48
    private static let sessionPaginationHeight: CGFloat = 44
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

`makeSessionTableScrollView()` 中的 scroll view 与 document 继续共同使用
`Self.sessionTableHeight`。在 `makeSessionTable()` 中只修改 stack 底部约束：

```swift
            stack.bottomAnchor.constraint(
                equalTo: table.bottomAnchor,
                constant: -Self.sessionTableScrollerGutter
            ),
```

不要设置 `contentInsets`、`scrollerInsets`，不要移动 pagination 与现有 flexible spacer 的
顺序。

- [ ] **Step 4: 验证 gutter 消除覆盖并暴露外层高度回归**

Run Step 2 的同一 focused 命令。

Expected: overlay/legacy 的 pagination 与 scroller 不再相交；测试仍应因外层文档高度超过
默认 840 pt 的可视高度而 FAIL。这是下一步局部纵向压缩的真实 RED，不能修改测试放宽要求。

- [ ] **Step 5: 收紧会话页专属纵向边距与区块间距**

在常量区加入：

```swift
    private static let sessionVerticalInset: CGFloat = 20
    private static let sessionRowGap: CGFloat = 14
```

在 `setupSessionContent()` 中只改会话页的纵向布局：

```swift
        sessionStack.spacing = Self.sessionRowGap
```

```swift
            sessionStack.leadingAnchor.constraint(equalTo: sessionContentView.leadingAnchor, constant: Self.pageInset),
            sessionStack.trailingAnchor.constraint(equalTo: sessionContentView.trailingAnchor, constant: -Self.pageInset),
            sessionStack.topAnchor.constraint(equalTo: sessionContentView.topAnchor, constant: Self.sessionVerticalInset),
            sessionStack.bottomAnchor.constraint(
                lessThanOrEqualTo: sessionContentView.bottomAnchor,
                constant: -Self.sessionVerticalInset
            ),
```

不要修改共用的 `pageInset`、`rowGap`、会话页水平边距、行高、分页大小或主窗口尺寸。

- [ ] **Step 6: 重跑 focused 测试并确认 GREEN**

Run Step 2 的同一 focused 命令。

Expected: `** TEST SUCCEEDED **`；overlay 与 legacy 均无重叠，十行、分页栏和整个会话栈
纵向可见，外层文档高度不超过默认可视高度。

- [ ] **Step 7: 运行会话相关回归测试**

Run:

```bash
xcodebuild -quiet -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' '-only-testing:TokenWatchTests/DashboardSessionPaginationTests' '-only-testing:TokenWatchTests/TokenWatchTests/dashboardSessionsTableHeightFitsTenCompactRows()' '-only-testing:TokenWatchTests/TokenWatchTests/dashboardSessionTableUsesIndependentHorizontalScrollView()' -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData -enableCodeCoverage NO test
```

Expected: 所有选择的会话分页、高度和独立横向滚动测试通过。

- [ ] **Step 8: 运行完整单元测试与 Debug 构建**

Run:

```bash
xcodebuild -quiet -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData -enableCodeCoverage NO test
```

Expected: `** TEST SUCCEEDED **`。

Run:

```bash
xcodebuild -quiet -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Debug -derivedDataPath .build/DerivedData build
```

Expected: `** BUILD SUCCEEDED **`，无新增编译错误或警告。

- [ ] **Step 9: 检查并提交实现**

Run:

```bash
git diff --check
git diff -- TokenWatchTests/ViewControllers/DashboardSessionPaginationTests.swift TokenWatchTests/TokenWatchTests.swift TokenWatch/ViewControllers/DashboardViewController.swift
git status --short
```

Expected: 只有上述测试与会话页布局文件发生实现变更，`git diff --check` 无输出。

Commit:

```bash
git add TokenWatchTests/ViewControllers/DashboardSessionPaginationTests.swift TokenWatchTests/TokenWatchTests.swift TokenWatch/ViewControllers/DashboardViewController.swift
git commit -m "fix(dashboard): 避免滚动条覆盖会话分页栏"
```
