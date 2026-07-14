# 会话页刷新态免滚动 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 消除默认窗口首次加载和手动刷新期间临时出现的会话页纵向与横向滚动范围。

**Architecture:** 保留既有 `1180×840` 窗口和 `880pt` 表格布局，仅在任一 provider 加载时让表格外部的 `sessionStatusLabel` 不参与 `sessionStack` 布局。加载反馈继续由侧边栏和刷新按钮承担；用真实控制器状态与通知链覆盖首次加载和手动刷新两种路径。

**Tech Stack:** Swift 6、AppKit、Swift Testing、Xcode `xcodebuild`

## Global Constraints

- 默认窗口保持 `1180×840`。
- 不调整侧边栏宽度、页面边距、列宽、行高、分页或表格高度。
- 首次加载和手动刷新期间，默认窗口都不得产生会话页纵向或表格横向滚动范围。
- overlay 和 legacy 两种 scroller style 均必须通过布局验证。
- 加载完成后，现有空数据、授权和错误提示行为不变。
- 小窗口仍保留必要的纵向和横向滚动能力。
- 不改变 provider 加载、会话聚合、排序、分页和完整 ID 复制行为。

---

### Task 1: 隐藏刷新态外部状态行并锁定双向免滚动行为

**Files:**
- Modify: `TokenWatch/ViewControllers/DashboardViewController.swift:1609-1628`
- Test: `TokenWatchTests/ViewControllers/DashboardSessionPaginationTests.swift:69-214`

**Interfaces:**
- Consumes: `RecentSessionDetailsSnapshot.loadingProviderCount: Int`、现有 `.providerStateDidChange` 通知、`DashboardSessionsPageScrollView` 和 `DashboardSessionsTableScrollView` accessibility identifier。
- Produces: 无新公共接口；`renderSessionPage(states:)` 在加载期间保持 `sessionStatusLabel.isHidden == true`。

- [ ] **Step 1: 添加首次加载和手动刷新失败测试**

在 `dashboardDefaultWindowShowsAllColumnsTenRowsAndPaginationWithoutScrolling()` 后加入以下两个测试：

```swift
@MainActor
@Test("首次加载时默认会话页不产生双向滚动范围")
func dashboardInitialLoadingDoesNotExposeSessionScrollRanges() throws {
    let now = dateTime(2026, 7, 4, hour: 12, minute: 0)
    let languageSettings = zhHansLanguageSettings()
    let loadingState = TokenStatsViewModel.ProviderState(
        stats: nil,
        entries: nil,
        isLoading: true,
        errorMessage: nil,
        needsAuthorization: false
    )
    let controller = DashboardViewController(
        settingsViewController: settingsViewController(languageSettings: languageSettings),
        stateProvider: { [
            .claude: loadingState,
            .codex: loadingState,
            .opencode: loadingState,
        ] },
        nowProvider: { now },
        calendar: calendar(),
        languageSettings: languageSettings
    )

    controller.loadViewIfNeeded()
    controller.view.setFrameSize(MainWindowFactory.contentSize)
    try button(withIdentifier: "DashboardNav.sessions", in: controller.view).performClick(nil)
    controller.view.layoutSubtreeIfNeeded()

    let loadingLabel = try textField(withString: "正在加载用量数据...", in: controller.view)
    try expectDefaultSessionViewportWithoutScrollRanges(
        in: controller,
        hiddenStatusLabel: loadingLabel,
        visibleRowIdentifier: "DashboardSessionsRow.0"
    )
}

@MainActor
@Test("手动刷新保留数据时默认会话页不产生双向滚动范围")
func dashboardInteractiveRefreshKeepsSessionViewportStable() throws {
    let now = dateTime(2026, 7, 4, hour: 12, minute: 0)
    let languageSettings = zhHansLanguageSettings()
    var states: [ProviderID: TokenStatsViewModel.ProviderState] = [
        .claude: .init(
            stats: nil,
            entries: makeEntries(count: 21, now: now),
            isLoading: false,
            errorMessage: nil,
            needsAuthorization: false
        ),
    ]
    let controller = DashboardViewController(
        settingsViewController: settingsViewController(languageSettings: languageSettings),
        stateProvider: { states },
        nowProvider: { now },
        calendar: calendar(),
        languageSettings: languageSettings
    )

    controller.loadViewIfNeeded()
    controller.view.setFrameSize(MainWindowFactory.contentSize)
    try button(withIdentifier: "DashboardNav.sessions", in: controller.view).performClick(nil)

    states[.claude]?.isLoading = true
    NotificationCenter.default.post(name: .providerStateDidChange, object: ProviderID.claude)
    controller.view.layoutSubtreeIfNeeded()

    let partialLoadingLabel = try textField(withString: "部分数据仍在加载", in: controller.view)
    try expectDefaultSessionViewportWithoutScrollRanges(
        in: controller,
        hiddenStatusLabel: partialLoadingLabel,
        visibleRowIdentifier: "DashboardSessionsRow.9"
    )
}
```

在测试文件的 helper 区域、`button(withIdentifier:in:)` 之前加入完整布局断言 helper：

```swift
@MainActor
private func expectDefaultSessionViewportWithoutScrollRanges(
    in controller: DashboardViewController,
    hiddenStatusLabel: NSTextField,
    visibleRowIdentifier: String
) throws {
    let pageScrollView = try #require(
        findView(withIdentifier: "DashboardSessionsPageScrollView", in: controller.view) as? NSScrollView
    )
    let pageDocumentView = try #require(pageScrollView.documentView)
    let tableScrollView = try #require(
        findView(withIdentifier: "DashboardSessionsTableScrollView", in: controller.view) as? NSScrollView
    )
    let tableDocumentView = try #require(tableScrollView.documentView)
    let header = try #require(
        findView(withIdentifier: "DashboardSessionsTableHeader", in: controller.view)
    )
    let visibleRow = try #require(
        findView(withIdentifier: visibleRowIdentifier, in: controller.view)
    )
    let pagination = try #require(
        findView(withIdentifier: "DashboardSessionsPagination", in: controller.view)
    )

    #expect(hiddenStatusLabel.isHidden)

    for style in [NSScroller.Style.overlay, .legacy] {
        pageScrollView.scrollerStyle = style
        tableScrollView.scrollerStyle = style
        pageScrollView.autohidesScrollers = true
        tableScrollView.autohidesScrollers = true
        pageScrollView.tile()
        tableScrollView.tile()
        controller.view.layoutSubtreeIfNeeded()

        let pageVisibleRect = pageScrollView.documentVisibleRect
        let tableVisibleRect = tableScrollView.documentVisibleRect
        let headerFrame = header.convert(header.bounds, to: tableDocumentView)
        let rowFrame = visibleRow.convert(visibleRow.bounds, to: tableDocumentView)
        let paginationFrame = pagination.convert(pagination.bounds, to: tableDocumentView)

        #expect(pageDocumentView.frame.height <= pageVisibleRect.height + 0.5)
        #expect(tableDocumentView.frame.width <= tableVisibleRect.width + 0.5)
        #expect(tableVisibleRect.minY <= headerFrame.minY + 0.5)
        #expect(tableVisibleRect.maxY + 0.5 >= headerFrame.maxY)
        #expect(tableVisibleRect.minY <= rowFrame.minY + 0.5)
        #expect(tableVisibleRect.maxY + 0.5 >= rowFrame.maxY)
        #expect(tableVisibleRect.minY <= paginationFrame.minY + 0.5)
        #expect(tableVisibleRect.maxY + 0.5 >= paginationFrame.maxY)
    }
}
```

- [ ] **Step 2: 运行聚焦测试并确认 RED**

Run:

```bash
xcodebuild -quiet -project TokenWatch.xcodeproj -scheme TokenWatch \
  -destination 'platform=macOS' \
  '-only-testing:TokenWatchTests/DashboardSessionPaginationTests/dashboardInitialLoadingDoesNotExposeSessionScrollRanges()' \
  '-only-testing:TokenWatchTests/DashboardSessionPaginationTests/dashboardInteractiveRefreshKeepsSessionViewportStable()' \
  -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData \
  -enableCodeCoverage NO test
```

Expected: FAIL，两个状态标签当前均为可见；页面 document 约 `850pt`、可见高度约 `840pt`。legacy 下表格 document 约 `880pt`、可见宽度约 `863pt`。失败必须来自布局行为断言，不得是编译、fixture 或 identifier 错误。

- [ ] **Step 3: 实现最小生产修复**

将 `renderSessionPage(states:)` 末尾的状态行显隐逻辑改为：

```swift
sessionStatusLabel.stringValue = sessionStatusText(
    snapshot: snapshot,
    totalProviderCount: states.count
)
// 加载反馈已由侧边栏提供；避免额外状态行撑高默认视口并级联压窄表格。
let hasLoadingProvider = snapshot.loadingProviderCount > 0
sessionStatusLabel.isHidden = hasLoadingProvider || sessionStatusLabel.stringValue.isEmpty
```

不得修改窗口尺寸、会话表格常量、`sessionStatusText` 的非加载状态分支或滚动视图结构。

- [ ] **Step 4: 重跑聚焦测试并确认 GREEN**

Run: 使用 Step 2 完全相同的命令。

Expected: PASS，2 tests、0 failures；首次加载与手动刷新在 overlay/legacy 下均无实际双向滚动范围。

- [ ] **Step 5: 运行会话页回归测试**

Run:

```bash
xcodebuild -quiet -project TokenWatch.xcodeproj -scheme TokenWatch \
  -destination 'platform=macOS' \
  '-only-testing:TokenWatchTests/DashboardSessionPaginationTests' \
  '-only-testing:TokenWatchTests/TokenWatchTests/dashboardSessionTableUsesIndependentHorizontalScrollView()' \
  '-only-testing:TokenWatchTests/TokenWatchTests/dashboardSessionsTableHeightFitsTenCompactRows()' \
  -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData \
  -enableCodeCoverage NO test
```

Expected: PASS；稳定态默认无滚动、小窗口仍可纵向滚动、窄窗口仍可横向滚动，分页和复制测试保持通过。

- [ ] **Step 6: 运行完整验证**

Run unit tests:

```bash
xcodebuild -quiet -project TokenWatch.xcodeproj -scheme TokenWatch \
  -destination 'platform=macOS' -only-testing:TokenWatchTests \
  -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData \
  -enableCodeCoverage NO test
```

Expected: 当前完整 `TokenWatchTests` 全部通过，0 failures。

Run Debug build:

```bash
xcodebuild -quiet -project TokenWatch.xcodeproj -scheme TokenWatch \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData build
```

Expected: exit code `0`。

- [ ] **Step 7: 真实 Debug 应用复验两条刷新路径**

1. 冷启动最终 Debug 构建，在侧边栏显示“正在更新本地记录”时立即打开会话页。
2. 等待扫描完成，回到总览点击“立即刷新”，再立即打开会话页。
3. 两个场景都不得执行滚动。
4. Accessibility tree 必须包含表头、空行或 10 条数据及完整分页；`DashboardSessionsPageScrollView` 不得暴露 `Scroll Up/Down`，`DashboardSessionsTableScrollView` 不得暴露 `Scroll Left/Right`。

- [ ] **Step 8: 检查范围并提交**

Run:

```bash
git diff --check
git status --short
```

Expected: 仅以下两个实现文件发生变化，且 `git diff --check` 无输出：

- `TokenWatch/ViewControllers/DashboardViewController.swift`
- `TokenWatchTests/ViewControllers/DashboardSessionPaginationTests.swift`

Commit:

```bash
git add TokenWatch/ViewControllers/DashboardViewController.swift \
  TokenWatchTests/ViewControllers/DashboardSessionPaginationTests.swift
git commit -m "fix(dashboard): 消除会话页刷新态双向滚动"
```

