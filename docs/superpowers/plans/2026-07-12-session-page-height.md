# 会话页十行免滚动修复实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 默认 1180 × 840 主窗口中完整展示十条会话及分页栏，同时保留小窗口纵向滚动行为。

**Architecture:** 保持会话表格的十行分页、48 pt 行高和内层横向滚动结构不变，只为会话页设置局部上下边距与区块间距。回归测试从外层会话滚动视图的 `documentVisibleRect` 验证第十行和分页栏在初始位置完整可见。

**Tech Stack:** Swift 6、AppKit、Swift Testing、Xcode 26 / `xcodebuild`

## Global Constraints

- 主窗口默认内容尺寸保持 1180 × 840。
- 会话页保持每页十条、48 pt 行高、44 pt 表头和 44 pt 分页栏。
- 小窗口继续允许外层页面纵向滚动。
- 表格独立横向滚动、会话数据排序、聚合和分页模型保持不变。
- 总览页、设置页和侧边栏的间距保持不变。

---

### Task 1: 压缩会话页局部垂直间距并增加布局回归覆盖

**Files:**
- Modify: `TokenWatchTests/ViewControllers/DashboardSessionPaginationTests.swift:33-68`
- Modify: `TokenWatch/ViewControllers/DashboardViewController.swift:5-18,288-329`

**Interfaces:**
- Consumes: `MainWindowFactory.contentSize: NSSize`、`DashboardViewController`、`NSScrollView.documentVisibleRect`、测试夹具 `makeEntries(count:now:)`。
- Produces: `DashboardViewController` 内部常量 `sessionPageInset: CGFloat = 20` 和 `sessionRowGap: CGFloat = 14`；不新增公开接口。

- [ ] **Step 1: 写出默认窗口十行与分页栏完整可见的失败测试**

在 `dashboardNextButtonShowsNextSessionPage()` 后加入：

```swift
    @MainActor
    @Test("默认窗口完整展示十条会话及分页栏且保留纵向滚动能力")
    func dashboardDefaultWindowShowsTenSessionsWithoutVerticalScroll() throws {
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
        let documentView = try #require(pageScrollView.documentView)
        let lastRow = try #require(
            findView(withIdentifier: "DashboardSessionsRow.9", in: controller.view)
        )
        let pagination = try #require(
            findView(withIdentifier: "DashboardSessionsPagination", in: controller.view)
        )
        let visibleRect = pageScrollView.documentVisibleRect
        let lastRowFrame = lastRow.convert(lastRow.bounds, to: documentView)
        let paginationFrame = pagination.convert(pagination.bounds, to: documentView)

        #expect(pageScrollView.hasVerticalScroller)
        #expect(visibleRect.contains(lastRowFrame))
        #expect(visibleRect.contains(paginationFrame))
    }
```

- [ ] **Step 2: 运行单条测试并确认 RED**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' '-only-testing:TokenWatchTests/DashboardSessionPaginationTests/dashboardDefaultWindowShowsTenSessionsWithoutVerticalScroll()' -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData test
```

Expected: 测试被正常发现并运行，因当前会话页初始 `documentVisibleRect` 不能完整包含第十行或分页栏而 FAIL；不能把编译错误、签名错误或测试未发现当作 RED。

- [ ] **Step 3: 实现会话页局部间距的最小修改**

在 `DashboardViewController` 的布局常量中加入：

```swift
    private static let sessionPageInset: CGFloat = 20
    private static let sessionRowGap: CGFloat = 14
```

只在 `setupSessionContent()` 中改用会话页常量：

```swift
        sessionStack.translatesAutoresizingMaskIntoConstraints = false
        sessionStack.orientation = .vertical
        sessionStack.alignment = .leading
        sessionStack.spacing = Self.sessionRowGap
```

```swift
            sessionStack.leadingAnchor.constraint(
                equalTo: sessionContentView.leadingAnchor,
                constant: Self.sessionPageInset
            ),
            sessionStack.trailingAnchor.constraint(
                equalTo: sessionContentView.trailingAnchor,
                constant: -Self.sessionPageInset
            ),
            sessionStack.topAnchor.constraint(
                equalTo: sessionContentView.topAnchor,
                constant: Self.sessionPageInset
            ),
            sessionStack.bottomAnchor.constraint(
                lessThanOrEqualTo: sessionContentView.bottomAnchor,
                constant: -Self.sessionPageInset
            ),
```

不要修改共用的 `pageInset`、`rowGap`、`sessionTableRowHeight`、`sessionPageSize` 或主窗口尺寸。

- [ ] **Step 4: 重跑单条测试并确认 GREEN**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' '-only-testing:TokenWatchTests/DashboardSessionPaginationTests/dashboardDefaultWindowShowsTenSessionsWithoutVerticalScroll()' -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData test
```

Expected: `** TEST SUCCEEDED **`；第十行与分页栏都完整位于初始可视区域，且外层纵向滚动能力仍启用。

- [ ] **Step 5: 运行会话页相关测试**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' '-only-testing:TokenWatchTests/DashboardSessionPaginationTests' -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData test
```

Expected: `DashboardSessionPaginationTests` 全部通过，分页、日期过滤、复制会话 ID 和布局断言没有回归。

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' '-only-testing:TokenWatchTests/TokenWatchTests/dashboardSessionTableUsesIndependentHorizontalScrollView()' -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData test
```

Expected: `** TEST SUCCEEDED **`；表格仍独立横向滚动，外层页面仍只负责纵向滚动。

- [ ] **Step 6: 运行完整单元测试与 Debug 构建**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData test
```

Expected: `** TEST SUCCEEDED **`。

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Debug -derivedDataPath .build/DerivedData build
```

Expected: `** BUILD SUCCEEDED **`，无新增编译错误或警告。

- [ ] **Step 7: 检查并提交实现**

Run:

```bash
git diff --check
git diff -- TokenWatchTests/ViewControllers/DashboardSessionPaginationTests.swift TokenWatch/ViewControllers/DashboardViewController.swift
git status --short
```

Expected: 只有测试与会话页布局文件发生实现变更，`git diff --check` 无输出。

Commit:

```bash
git add TokenWatchTests/ViewControllers/DashboardSessionPaginationTests.swift TokenWatch/ViewControllers/DashboardViewController.swift
git commit -m "fix(dashboard): 完整展示十条会话"
```
