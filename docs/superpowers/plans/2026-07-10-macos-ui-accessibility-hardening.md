# macOS UI、辅助功能与系统状态加固 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不改变 TokenWatch 现有视觉设计的前提下，让会话表可横向访问、主要操作可键盘聚焦、窗口与热力图具备正确辅助功能语义，并让设置页准确表达 Login Item 四态和稳定的紧凑数字格式。

**Architecture:** 保留现有 AppKit 控制器和自定义按钮架构，在 `DashboardViewController` 内嵌套独立横向滚动区域，在 `MainWindowFactory` 配置逻辑窗口语义，并把 `SMAppService.Status` 映射为小型、可注入测试的领域状态。设置页只消费该领域状态，热力图继续使用纯 `CalendarHeatmapCellStyle` 生成视觉和 accessibility 快照，数字格式继续集中在 `CompactNumberFormatter`。

**Tech Stack:** Swift 6、AppKit、ServiceManagement、Swift Testing、XCTest UI Testing、Xcode 26.5、macOS 15.0+

## Global Constraints

- 保持现有视觉设计，不更换控件体系，不引入 SwiftUI 重写。
- 会话表固定列宽继续保留；表格 document/table 最小宽度必须为 `1108pt`，页面其他区块仍跟随外层垂直滚动。
- `DashboardNavigationButton`、`DashboardRangeButton`、`DashboardSessionButton` 必须恢复键盘聚焦和系统 focus ring；窗口启动时通过 `initialFirstResponder` 避免自动选中操作按钮。主窗口根背景 view 必须以显式 opt-in 方式接受 first responder，其他背景 view 默认仍不接受，且该根 view 继续是非 `NSControl` 的非操作控件。
- 设置页 popup、switch、授权、刷新和 Login Item 操作必须在每次 App 语言刷新时获得可读 accessibility label。
- 热力图 day cell 必须是 `.staticText` accessibility element；placeholder 必须退出 accessibility 树并清除复用残留。
- 窗口逻辑标题必须是 `TokenWatch`，同时保持 `titleVisibility = .hidden`。
- Login Item 状态固定为 `notRegistered / enabled / requiresApproval / unavailable`，分别映射 `SMAppService.Status.notRegistered / enabled / requiresApproval / notFound`；未来未知状态按 `unavailable` 处理。
- `requiresApproval` 不得重复 register；切换到 off 必须 unregister；`unavailable` 不得 register 或 unregister。
- 状态栏使用的 `CompactNumberFormatter.format` 契约保持不变：零为 `0`，`1...999` 为整数，`1_000..<1_000_000` 为一位小数 `k`，`1_000_000` 起为一位小数 `M`。
- Dashboard 的 `formatMillions` 与 `formatHoverTokens` 契约固定为：零为 `0.0M`，`1...999` 为整数，`1_000...99_999` 为一位小数 `k`，`100_000` 起为一位小数 `M`；小数继续向下截断，任意正数不得格式化为零。
- App 继续离线运行，不增加运行时网络请求，不新增第三方依赖。
- 不改变 `.github/workflows/release.yml` 中关闭签名并直接打包的设计；Login Item 注册失败继续通过现有错误日志和状态回读表达。
- 所有行为先由失败测试复现，再写最小实现；每个 task 在定向测试通过后单独提交，commit message 使用中文摘要。
- 沙盒内运行测试必须使用 `-derivedDataPath .build/DerivedData`；app-hosted tests 需要系统 `testmanagerd`，应在沙盒外运行或申请提升权限，`build-for-testing` 不能替代真实测试。
- test 命令统一使用 `CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=-` 的临时 ad-hoc 签名；纯 build/analyze 使用 `CODE_SIGNING_ALLOWED=NO`。

---

## 文件职责

- Modify: `TokenWatch/ViewControllers/CompactNumberFormatter.swift` — 保留状态栏格式，集中实现 Dashboard 紧凑数字规则。
- Modify: `TokenWatch/ViewControllers/DashboardViewController.swift` — 为会话表创建独立横向 scroll view，并恢复 range button 的 focus ring。
- Modify: `TokenWatch/ViewControllers/DashboardButtons.swift` — 恢复三个自定义按钮类的 first responder 能力和默认 focus ring。
- Modify: `TokenWatch/ViewControllers/DashboardAppearance.swift` — 让背景 view 默认拒绝、仅主窗口根 view 显式接受 first responder。
- Modify: `TokenWatch/AppDelegate.swift` — 配置主窗口逻辑标题、隐藏标题显示和初始 responder。
- Modify: `TokenWatch/Services/LoginItemSettings.swift` — 定义 Login Item 四态、可测试 service 边界和系统动作。
- Modify: `TokenWatch/ViewController.swift` — 让主窗口根背景显式 opt in first responder，并渲染设置页四态、监听应用激活、设置本地化 accessibility label。
- Modify: `TokenWatch/Localization/AppStrings.swift` — 增加 Login Item 批准、不可用、打开系统设置文案，并覆盖全部 12 种 App 语言。
- Modify: `TokenWatch/ViewControllers/CalendarHeatmapCollectionViewItem.swift` — 生成并应用日期格 accessibility 快照。
- Modify: `TokenWatch/ViewControllers/StatusPopoverViewController.swift` — 将同一 `Calendar` 传给热力图 item。
- Modify: `TokenWatchTests/ViewControllers/CompactNumberFormatterTests.swift` — 锁定 Dashboard 数字边界和正数不归零。
- Modify: `TokenWatchTests/TokenWatchTests.swift` — 覆盖滚动、窗口、按钮焦点、设置四态、语言刷新和外观隔离。
- Create: `TokenWatchTests/Services/LoginItemSettingsTests.swift` — 覆盖生产 `SMAppService` 映射与动作矩阵。
- Modify: `TokenWatchTests/Localization/AppLanguageSettingsTests.swift` — 锁定三条新文案在全部支持语言中的值。
- Modify: `TokenWatchTests/ViewControllers/CalendarHeatmapCollectionViewItemTests.swift` — 覆盖 day/placeholder 的 accessibility 和复用清理。
- Modify: `TokenWatchUITests/TokenWatchUITests.swift` — 对逻辑窗口标题和会话表横向滚动做端到端 smoke test。
- Do not modify: `TokenWatch.xcodeproj/project.pbxproj` — 工程使用 `PBXFileSystemSynchronizedRootGroup`，新增测试文件会自动进入 test target。

### Task 1: 对齐 Dashboard 紧凑数字格式

**Files:**
- Modify: `TokenWatch/ViewControllers/CompactNumberFormatter.swift:37-62`
- Test: `TokenWatchTests/ViewControllers/CompactNumberFormatterTests.swift:44-51`

**Interfaces:**
- Consumes: 现有 `CompactNumberFormatter.format(_ value: Int) -> String`，该方法不得修改。
- Produces: `CompactNumberFormatter.formatMillions(_ value: Int) -> String` 与 `CompactNumberFormatter.formatHoverTokens(_ value: Int) -> String`，二者共享完全相同的 Dashboard 分段规则。

- [ ] **Step 1: 编写覆盖所有 Dashboard 边界的失败测试**

在 `CompactNumberFormatterTests` 中用以下测试替换现有只覆盖 hover 大数的测试，并保留所有 `format(_:)` 测试：

```swift
@Test func dashboardFormattersUseExpectedBoundaries() {
    let cases: [(value: Int, expected: String)] = [
        (-1, "0.0M"),
        (0, "0.0M"),
        (1, "1"),
        (999, "999"),
        (1_000, "1.0k"),
        (1_234, "1.2k"),
        (99_999, "99.9k"),
        (100_000, "0.1M"),
        (1_234_567, "1.2M"),
    ]

    for item in cases {
        #expect(CompactNumberFormatter.formatMillions(item.value) == item.expected)
        #expect(CompactNumberFormatter.formatHoverTokens(item.value) == item.expected)
    }
}

@Test func positiveDashboardValuesNeverFormatAsZero() {
    for value in [1, 9, 99, 999, 1_001, 10_001, 100_001] {
        let millions = CompactNumberFormatter.formatMillions(value)
        let hover = CompactNumberFormatter.formatHoverTokens(value)

        #expect(!["0", "0.0k", "0.0M"].contains(millions))
        #expect(!["0", "0.0k", "0.0M"].contains(hover))
    }
}
```

- [ ] **Step 2: 运行 formatter suite 并确认 RED**

运行：

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -derivedDataPath .build/DerivedData -only-testing:TokenWatchTests/CompactNumberFormatterTests -skip-testing:TokenWatchUITests CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

预期：FAIL；`formatMillions(1)` 实际为 `0.0M`，`formatHoverTokens(1)` 实际为 `0.0k`。

- [ ] **Step 3: 实现共享 Dashboard formatter，并保持状态栏格式不变**

保持 `format(_:)` 原样，将另外两个方法替换为：

```swift
/// 按 Dashboard 约定压缩 token 数；零保留 `0.0M`，正数绝不显示为零。
static func formatMillions(_ value: Int) -> String {
    formatDashboardTokens(value)
}

/// 按 Dashboard hover 约定压缩 token 数，与 `formatMillions` 使用相同边界。
static func formatHoverTokens(_ value: Int) -> String {
    formatDashboardTokens(value)
}

private static func formatDashboardTokens(_ value: Int) -> String {
    guard value > 0 else { return "0.0M" }

    if value < 1_000 {
        return String(value)
    }

    if value < 100_000 {
        let tenths = value / 100
        return "\(tenths / 10).\(tenths % 10)k"
    }

    let tenths = value / 100_000
    return "\(tenths / 10).\(tenths % 10)M"
}
```

- [ ] **Step 4: 运行 formatter 与直接消费者回归并确认 GREEN**

运行：

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -derivedDataPath .build/DerivedData -only-testing:TokenWatchTests/CompactNumberFormatterTests -only-testing:TokenWatchTests/TodayHourlyTokenLineChartViewTests -only-testing:TokenWatchTests/CalendarHeatmapCollectionViewItemTests -skip-testing:TokenWatchUITests CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

预期：PASS；现有零值仍为 `0.0M`，状态栏 `format(_:)` 的 `k/M` 阈值测试保持通过。

- [ ] **Step 5: 提交 formatter 契约**

```bash
git add TokenWatch/ViewControllers/CompactNumberFormatter.swift TokenWatchTests/ViewControllers/CompactNumberFormatterTests.swift
git commit -m "fix(formatter): 对齐 Dashboard 紧凑数字边界"
```

### Task 2: 为会话表增加独立横向滚动

**Files:**
- Modify: `TokenWatch/ViewControllers/DashboardViewController.swift:5-16,27-35,286-325,915-953`
- Test: `TokenWatchTests/TokenWatchTests.swift:618-643,973-984`
- Test: `TokenWatchUITests/TokenWatchUITests.swift:45-60`

**Interfaces:**
- Consumes: 现有 `makeSessionTable() -> NSView` 和固定列宽 `[150, 150, 126, 190, 150, 104, 84, 66]`。
- Produces: `DashboardSessionsPageScrollView` 外层 accessibility identifier、`DashboardSessionsTableScrollView` 内层 identifier、`private static let sessionTableMinimumWidth: CGFloat = 1_108`、`private func makeSessionTableScrollView() -> NSScrollView`。

- [ ] **Step 1: 编写失败的结构测试和 UI 滚动测试**

在 `TokenWatchTests` 中增加：

```swift
@MainActor
@Test func dashboardSessionTableUsesIndependentHorizontalScrollView() throws {
    let viewController = ViewController(languageSettings: zhHansLanguageSettings())
    viewController.loadViewIfNeeded()
    viewController.view.setFrameSize(MainWindowFactory.contentSize)

    let sessionsButton = try #require(viewController.view.button(identifier: "DashboardNav.sessions"))
    _ = sessionsButton.sendAction(sessionsButton.action, to: sessionsButton.target)
    viewController.view.layoutSubtreeIfNeeded()

    let pageScrollView = try #require(
        viewController.view.firstDescendant(identifier: "DashboardSessionsPageScrollView") as? NSScrollView
    )
    let tableScrollView = try #require(
        viewController.view.firstDescendant(identifier: "DashboardSessionsTableScrollView") as? NSScrollView
    )
    let table = try #require(viewController.view.firstDescendant(identifier: "DashboardSessionsTable"))

    #expect(pageScrollView.hasVerticalScroller)
    #expect(!pageScrollView.hasHorizontalScroller)
    #expect(tableScrollView.hasHorizontalScroller)
    #expect(!tableScrollView.hasVerticalScroller)
    #expect(tableScrollView.documentView === table)
    #expect(table.frame.width >= 1_108)
    #expect(table.frame.width > tableScrollView.contentView.bounds.width)
}
```

在 `TokenWatchUITests` 中增加：

```swift
@MainActor
func testSessionTableScrollsHorizontally() throws {
    let app = XCUIApplication()
    app.launchForUITesting()

    let sessionsButton = app.buttons["DashboardNav.sessions"]
    XCTAssertTrue(sessionsButton.waitForExistence(timeout: 5))
    sessionsButton.click()

    let tableScrollView = app.scrollViews["DashboardSessionsTableScrollView"]
    XCTAssertTrue(tableScrollView.waitForExistence(timeout: 5))

    let nextButton = app.buttons["DashboardSessionsPagination.next"]
    XCTAssertTrue(nextButton.waitForExistence(timeout: 5))
    let initialMinX = nextButton.frame.minX

    tableScrollView.scroll(byDeltaX: -400, deltaY: 0)

    XCTAssertLessThan(nextButton.frame.minX, initialMinX)
}
```

- [ ] **Step 2: 运行两个测试并确认 RED**

运行：

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -derivedDataPath .build/DerivedData "-only-testing:TokenWatchTests/TokenWatchTests/dashboardSessionTableUsesIndependentHorizontalScrollView()" -only-testing:TokenWatchUITests/TokenWatchUITests/testSessionTableScrollsHorizontally CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

预期：FAIL；`DashboardSessionsPageScrollView` 与 `DashboardSessionsTableScrollView` 尚不存在，UI 查询无法找到内层 scroll view。

- [ ] **Step 3: 构建具有 1108pt required 最小宽度的嵌套滚动结构**

在 `DashboardViewController` 常量和属性区增加：

```swift
private static let sessionTableMinimumWidth: CGFloat = 1_108
private let sessionTableScrollView = NSScrollView()
```

在 `setupSessionContent()` 配置外层 scroll view 时增加并替换表格安装点：

```swift
sessionScrollView.identifier = NSUserInterfaceItemIdentifier("DashboardSessionsPageScrollView")
sessionScrollView.setAccessibilityIdentifier("DashboardSessionsPageScrollView")
sessionScrollView.hasVerticalScroller = true
sessionScrollView.hasHorizontalScroller = false

addFullWidthArrangedSubview(makeSessionHeaderView(), to: sessionStack)
addFullWidthArrangedSubview(makeSessionMetricRow(), to: sessionStack)
addFullWidthArrangedSubview(makeSessionTableScrollView(), to: sessionStack)
addFullWidthArrangedSubview(sessionStatusLabel, to: sessionStack)
```

在 `makeSessionTable()` 前增加完整 helper：

```swift
private func makeSessionTableScrollView() -> NSScrollView {
    let table = makeSessionTable()
    let clipView = sessionTableScrollView.contentView

    sessionTableScrollView.identifier = NSUserInterfaceItemIdentifier("DashboardSessionsTableScrollView")
    sessionTableScrollView.setAccessibilityIdentifier("DashboardSessionsTableScrollView")
    sessionTableScrollView.drawsBackground = false
    sessionTableScrollView.borderType = .noBorder
    sessionTableScrollView.hasHorizontalScroller = true
    sessionTableScrollView.hasVerticalScroller = false
    sessionTableScrollView.autohidesScrollers = true
    sessionTableScrollView.scrollerStyle = .overlay
    sessionTableScrollView.documentView = table

    table.translatesAutoresizingMaskIntoConstraints = false
    let coverViewportWidth = table.widthAnchor.constraint(greaterThanOrEqualTo: clipView.widthAnchor)

    NSLayoutConstraint.activate([
        sessionTableScrollView.heightAnchor.constraint(equalToConstant: Self.sessionTableHeight),
        table.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
        table.topAnchor.constraint(equalTo: clipView.topAnchor),
        table.widthAnchor.constraint(greaterThanOrEqualToConstant: Self.sessionTableMinimumWidth),
        table.heightAnchor.constraint(equalToConstant: Self.sessionTableHeight),
        coverViewportWidth,
    ])
    return sessionTableScrollView
}
```

不要给 table 增加 required trailing-to-clip constraint；该约束会与 1108pt 最小宽度冲突并重新压缩列。
`coverViewportWidth` 必须保持为单向下界；若改成等宽软约束，窗口 fitting 会把内层 viewport 和整棵 Dashboard 反向撑到 1108pt，导致不再产生横向滚动范围。

- [ ] **Step 4: 运行会话布局、分页、外观和 UI 测试并确认 GREEN**

运行：

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -derivedDataPath .build/DerivedData "-only-testing:TokenWatchTests/TokenWatchTests/dashboardSessionTableUsesIndependentHorizontalScrollView()" "-only-testing:TokenWatchTests/TokenWatchTests/dashboardSessionsNavigationShowsPencilSessionDetailsPage()" "-only-testing:TokenWatchTests/TokenWatchTests/dashboardSessionsTableHeightFitsTenCompactRows()" -only-testing:TokenWatchTests/DashboardSessionPaginationTests -only-testing:TokenWatchUITests/TokenWatchUITests/testSessionTableScrollsHorizontally CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

预期：PASS；内层滚动改变分页 next button 的屏幕 x 坐标，外层标题和指标卡不横向移动。

- [ ] **Step 5: 提交会话表水平访问路径**

```bash
git add TokenWatch/ViewControllers/DashboardViewController.swift TokenWatchTests/TokenWatchTests.swift TokenWatchUITests/TokenWatchUITests.swift
git commit -m "fix(dashboard): 增加会话表横向滚动"
```

### Task 3: 恢复按钮键盘焦点与窗口语义

**Files:**
- Modify: `TokenWatch/ViewControllers/DashboardButtons.swift:25-53,133-140,186-228`
- Modify: `TokenWatch/ViewControllers/DashboardAppearance.swift:100-126`
- Modify: `TokenWatch/ViewControllers/DashboardViewController.swift:599-618`
- Modify: `TokenWatch/ViewController.swift:50-56,318-330`
- Modify: `TokenWatch/AppDelegate.swift:156-176`
- Test: `TokenWatchTests/TokenWatchTests.swift:155-169,344-353,594-614`
- Test: `TokenWatchUITests/TokenWatchUITests.swift:16-30`

**Interfaces:**
- Consumes: AppKit 默认 `NSButton.acceptsFirstResponder == true` 与 `NSFocusRingType.default`。
- Produces: `DashboardBackgroundView.init(frame:backgroundColor:acceptsFirstResponder:)` 默认参数为 `false`；`ViewController` 的根背景 view 显式传 `true`；`MainWindowFactory.makeWindowController(languageSettings:) -> NSWindowController` 返回逻辑标题为 `TokenWatch`、视觉标题隐藏、`initialFirstResponder` 指向该非操作根视图且能够实际成为 `window.firstResponder` 的窗口。

- [ ] **Step 1: 替换拒绝焦点的断言并增加真实窗口 responder 测试**

将 `mainWindowFactoryBuildsVisibleMainWindowShape` 替换为完整测试；除了检查配置属性，还必须显示窗口、显式请求根 view 成为 first responder，并读取 `window.firstResponder` 验证结果：

```swift
@MainActor
@Test func mainWindowFactoryBuildsVisibleMainWindowShape() throws {
    let windowController = MainWindowFactory.makeWindowController(
        languageSettings: zhHansLanguageSettings()
    )
    let window = try #require(windowController.window)
    defer { window.close() }
    let rootView = try #require(window.contentViewController?.view)

    #expect(window.title == "TokenWatch")
    #expect(window.titleVisibility == .hidden)
    #expect(window.styleMask.contains(.titled))
    #expect(window.styleMask.contains(.closable))
    #expect(window.styleMask.contains(.miniaturizable))
    #expect(window.styleMask.contains(.resizable))
    #expect(window.isReleasedWhenClosed == false)
    #expect(window.contentViewController is ViewController)
    #expect(window.contentView?.frame.size == MainWindowFactory.contentSize)
    #expect(rootView.acceptsFirstResponder)
    #expect(!(rootView is NSControl))
    #expect(window.initialFirstResponder === rootView)

    let ordinaryBackground = DashboardBackgroundView(
        backgroundColor: DashboardPalette.panelBackground
    )
    #expect(!ordinaryBackground.acceptsFirstResponder)

    windowController.showWindow(nil)
    #expect(window.isVisible)
    #expect(window.makeFirstResponder(rootView))
    #expect(window.firstResponder === rootView)
}
```

用以下测试替换 `dashboardRangeButtonsDoNotBecomeFirstResponderOnStartup`：

```swift
@MainActor
@Test func dashboardActionButtonsSupportKeyboardFocusAndFocusRings() throws {
    let languageSettings = zhHansLanguageSettings()
    let viewController = DashboardViewController(
        settingsViewController: SettingsViewController(
            isAuthorized: { false },
            languageSettings: languageSettings
        ),
        refreshAction: {},
        languageSettings: languageSettings
    )
    viewController.loadViewIfNeeded()
    let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: MainWindowFactory.contentSize),
        styleMask: [.titled],
        backing: .buffered,
        defer: false
    )
    window.contentViewController = viewController

    func assertFocusable(_ identifiers: [String]) throws {
        for identifier in identifiers {
            let button = try #require(viewController.view.button(identifier: identifier))
            #expect(button.acceptsFirstResponder, "\(identifier) must accept keyboard focus")
            #expect(button.focusRingType != .none, "\(identifier) must show a focus ring")
            #expect(window.makeFirstResponder(button), "\(identifier) must become first responder")
            #expect(window.firstResponder === button)
        }
    }

    try assertFocusable([
        "DashboardNav.overview",
        "DashboardNav.sessions",
        "DashboardNav.settings",
        "DashboardRange.day",
        "DashboardRange.sevenDays",
        "DashboardRange.month",
        "DashboardRange.all",
        "DashboardRefreshButton",
    ])

    let sessionsButton = try #require(viewController.view.button(identifier: "DashboardNav.sessions"))
    _ = sessionsButton.sendAction(sessionsButton.action, to: sessionsButton.target)
    try assertFocusable([
        "DashboardSessionsPagination.previous",
        "DashboardSessionsPagination.page.1",
        "DashboardSessionsPagination.next",
    ])

    let settingsButton = try #require(viewController.view.button(identifier: "DashboardNav.settings"))
    _ = settingsButton.sendAction(settingsButton.action, to: settingsButton.target)
    try assertFocusable(["AuthorizationActionButton", "RefreshAllDataButton"])
}
```

在 `dashboardNavigationItemsUsePencilIconSpacing` 中把：

```swift
#expect(button.focusRingType == .none)
```

替换为：

```swift
#expect(button.focusRingType != .none)
```

在 UI 启动测试中把首个窗口查询改为：

```swift
let mainWindow = app.windows["TokenWatch"]
XCTAssertTrue(mainWindow.waitForExistence(timeout: 5))
```

- [ ] **Step 2: 运行窗口与焦点测试并确认 RED**

运行：

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -derivedDataPath .build/DerivedData "-only-testing:TokenWatchTests/TokenWatchTests/mainWindowFactoryBuildsVisibleMainWindowShape()" "-only-testing:TokenWatchTests/TokenWatchTests/dashboardActionButtonsSupportKeyboardFocusAndFocusRings()" "-only-testing:TokenWatchTests/TokenWatchTests/dashboardNavigationItemsUsePencilIconSpacing()" -only-testing:TokenWatchUITests/TokenWatchUITests/testLaunchShowsPencilDashboardOverview CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

预期：FAIL；窗口标题仍为空，根背景 view 与三个按钮类都返回 `acceptsFirstResponder == false`，`window.makeFirstResponder(rootView)` 返回 false，导航和 range/session 控件的 focus ring 为 `.none`。

- [ ] **Step 3: 删除永久焦点拒绝并让主窗口根 view 选择性接受 responder**

在 `DashboardButtons.swift` 中删除三个完整 override：

```swift
override var acceptsFirstResponder: Bool {
    false
}
```

删除 `DashboardNavigationButton` 与 `DashboardSessionButton` 初始化中的：

```swift
focusRingType = .none
```

删除 `DashboardViewController.makeRangeButton(_:)` 和 `SettingsViewController.configureSettingsButton(_:)` 中的：

```swift
button.focusRingType = .none
```

在 `DashboardBackgroundView` 中加入默认关闭的 opt-in；仅显式传 `true` 的背景 view 才接受 first responder：

```swift
private let allowsFirstResponder: Bool

init(
    frame frameRect: NSRect = .zero,
    backgroundColor: NSColor,
    acceptsFirstResponder: Bool = false
) {
    self.backgroundColor = backgroundColor
    self.allowsFirstResponder = acceptsFirstResponder
    super.init(frame: frameRect)
    wantsLayer = true
    updateLayerColors()
}

override var acceptsFirstResponder: Bool {
    allowsFirstResponder
}
```

在 `ViewController.loadView()` 中只让主窗口根背景 opt in：

```swift
override func loadView() {
    view = DashboardBackgroundView(
        frame: NSRect(origin: .zero, size: MainWindowFactory.contentSize),
        backgroundColor: DashboardPalette.appBackground,
        acceptsFirstResponder: true
    )
    view.setAccessibilityIdentifier("DashboardRootView")
}
```

在 `MainWindowFactory.makeWindowController` 中使用同一个内容控制器配置窗口：

```swift
let contentController = ViewController(languageSettings: languageSettings)
window.title = "TokenWatch"
window.titleVisibility = .hidden
window.isReleasedWhenClosed = false
window.contentViewController = contentController
window.initialFirstResponder = contentController.view
window.setContentSize(contentSize)
window.center()
```

- [ ] **Step 4: 运行窗口、焦点、导航和设置操作测试并确认 GREEN**

运行：

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -derivedDataPath .build/DerivedData "-only-testing:TokenWatchTests/TokenWatchTests/mainWindowFactoryBuildsVisibleMainWindowShape()" "-only-testing:TokenWatchTests/TokenWatchTests/dashboardActionButtonsSupportKeyboardFocusAndFocusRings()" "-only-testing:TokenWatchTests/TokenWatchTests/dashboardNavigationItemsUsePencilIconSpacing()" "-only-testing:TokenWatchTests/TokenWatchTests/dashboardRefreshButtonIsStableActionEntry()" -only-testing:TokenWatchUITests/TokenWatchUITests/testLaunchShowsPencilDashboardOverview CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

预期：PASS；逻辑标题可被 XCUI 查询，标题仍不在 title bar 绘制；主窗口根 view 是可实际成为 `window.firstResponder` 的非操作控件，其他背景 view 仍默认拒绝；按钮保留原视觉布局并接受 first responder。

- [ ] **Step 5: 提交键盘和窗口语义**

```bash
git add TokenWatch/ViewControllers/DashboardButtons.swift TokenWatch/ViewControllers/DashboardAppearance.swift TokenWatch/ViewControllers/DashboardViewController.swift TokenWatch/ViewController.swift TokenWatch/AppDelegate.swift TokenWatchTests/TokenWatchTests.swift TokenWatchUITests/TokenWatchUITests.swift
git commit -m "fix(window): 恢复按钮键盘焦点与窗口语义"
```

### Task 4: 建立 Login Item 四态领域模型并锁定开关映射

**Files:**
- Modify: `TokenWatch/Services/LoginItemSettings.swift:1-37`
- Modify: `TokenWatch/ViewController.swift:378-401`
- Modify: `TokenWatchTests/TokenWatchTests.swift:1593-1648,1928-1949`
- Create: `TokenWatchTests/Services/LoginItemSettingsTests.swift`

**Interfaces:**
- Consumes: `SMAppService.Status`、`SMAppService.register()`、`SMAppService.unregister()`、`SMAppService.openSystemSettingsLoginItems()`。
- Produces: `LoginItemSettingsState`；`LoginItemSettingsControlling.state`、`setEnabled(_:)`、`openSystemSettings()`；内部 `LoginItemServiceControlling` 测试 seam；`SettingsViewController.renderLaunchAtLoginState()` 的基础四态开关映射，其中 `requiresApproval` 为 on/enabled、`unavailable` 为 off/disabled。

- [ ] **Step 1: 编写失败的 service 动作与 requiresApproval/unavailable UI 映射测试**

创建 `TokenWatchTests/Services/LoginItemSettingsTests.swift`：

```swift
import ServiceManagement
import Testing
@testable import TokenWatch

@MainActor
@Suite("LoginItemSettings")
struct LoginItemSettingsTests {
    @Test func mapsEveryServiceManagementStatus() {
        let cases: [(SMAppService.Status, LoginItemSettingsState)] = [
            (.notRegistered, .notRegistered),
            (.enabled, .enabled),
            (.requiresApproval, .requiresApproval),
            (.notFound, .unavailable),
        ]

        for item in cases {
            let service = FakeLoginItemService(status: item.0)
            let settings = LoginItemSettings(service: service)
            #expect(settings.state == item.1)
        }
    }

    @Test func registerAndUnregisterFollowTheFourStateMatrix() throws {
        let notRegistered = FakeLoginItemService(status: .notRegistered)
        let notRegisteredSettings = LoginItemSettings(service: notRegistered)
        try notRegisteredSettings.setEnabled(true)
        try notRegisteredSettings.setEnabled(false)
        #expect(notRegistered.registerCallCount == 1)
        #expect(notRegistered.unregisterCallCount == 0)

        let enabled = FakeLoginItemService(status: .enabled)
        let enabledSettings = LoginItemSettings(service: enabled)
        try enabledSettings.setEnabled(true)
        try enabledSettings.setEnabled(false)
        #expect(enabled.registerCallCount == 0)
        #expect(enabled.unregisterCallCount == 1)

        let requiresApproval = FakeLoginItemService(status: .requiresApproval)
        let requiresApprovalSettings = LoginItemSettings(service: requiresApproval)
        try requiresApprovalSettings.setEnabled(true)
        try requiresApprovalSettings.setEnabled(false)
        #expect(requiresApproval.registerCallCount == 0)
        #expect(requiresApproval.unregisterCallCount == 1)

        let unavailable = FakeLoginItemService(status: .notFound)
        let unavailableSettings = LoginItemSettings(service: unavailable)
        try unavailableSettings.setEnabled(true)
        try unavailableSettings.setEnabled(false)
        #expect(unavailable.registerCallCount == 0)
        #expect(unavailable.unregisterCallCount == 0)
    }

    @Test func opensSystemSettingsThroughAnIndependentAction() {
        let service = FakeLoginItemService(status: .requiresApproval)
        var openCallCount = 0
        let settings = LoginItemSettings(
            service: service,
            openSystemSettingsAction: { openCallCount += 1 }
        )

        settings.openSystemSettings()

        #expect(openCallCount == 1)
        #expect(service.registerCallCount == 0)
        #expect(service.unregisterCallCount == 0)
    }
}

@MainActor
private final class FakeLoginItemService: LoginItemServiceControlling {
    let status: SMAppService.Status
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0

    init(status: SMAppService.Status) {
        self.status = status
    }

    func register() throws {
        registerCallCount += 1
    }

    func unregister() throws {
        unregisterCallCount += 1
    }
}
```

在 `TokenWatchTests.swift` 中增加两个只验证基础开关映射的测试。说明文案、系统设置按钮和激活刷新仍属于 Task 5，不在这里提前断言：

```swift
@MainActor
@Test func settingsMapsRequiresApprovalToEnabledOnSwitch() throws {
    let controller = SettingsViewController(
        isAuthorized: { false },
        loginItemSettings: FakeLoginItemSettings(state: .requiresApproval),
        languageSettings: zhHansLanguageSettings()
    )
    controller.loadViewIfNeeded()

    let toggle = try #require(
        controller.view.switchControl(identifier: "LaunchAtLoginSwitch")
    )
    #expect(toggle.state == .on)
    #expect(toggle.isEnabled)
}

@MainActor
@Test func settingsMapsUnavailableToDisabledOffSwitch() throws {
    let controller = SettingsViewController(
        isAuthorized: { false },
        loginItemSettings: FakeLoginItemSettings(state: .unavailable),
        languageSettings: zhHansLanguageSettings()
    )
    controller.loadViewIfNeeded()

    let toggle = try #require(
        controller.view.switchControl(identifier: "LaunchAtLoginSwitch")
    )
    #expect(toggle.state == .off)
    #expect(!toggle.isEnabled)
}
```

同时先把 `TokenWatchTests.swift` 末尾的 Bool fake 替换为四态 fake，让上述测试与既有开关测试共享同一个 test double：

```swift
@MainActor
private final class FakeLoginItemSettings: LoginItemSettingsControlling {
    enum ToggleError: Error {
        case failed
    }

    private(set) var requestedStates: [Bool] = []
    private(set) var openSystemSettingsCallCount = 0
    var errorToThrow: Error?
    var state: LoginItemSettingsState

    init(state: LoginItemSettingsState) {
        self.state = state
    }

    convenience init(isEnabled: Bool) {
        self.init(state: isEnabled ? .enabled : .notRegistered)
    }

    func setEnabled(_ enabled: Bool) throws {
        requestedStates.append(enabled)
        if let errorToThrow {
            throw errorToThrow
        }
        state = enabled ? .enabled : .notRegistered
    }

    func openSystemSettings() {
        openSystemSettingsCallCount += 1
    }
}
```

- [ ] **Step 2: 运行 service 与基础 UI 映射测试并确认 RED**

运行：

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -derivedDataPath .build/DerivedData -only-testing:TokenWatchTests/LoginItemSettingsTests "-only-testing:TokenWatchTests/TokenWatchTests/settingsMapsRequiresApprovalToEnabledOnSwitch()" "-only-testing:TokenWatchTests/TokenWatchTests/settingsMapsUnavailableToDisabledOffSwitch()" -skip-testing:TokenWatchUITests CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

预期：编译失败；`LoginItemSettingsState`、`LoginItemServiceControlling`、`state` 与 `openSystemSettingsAction` 尚未定义。两个 UI 测试已在生产 `renderLaunchAtLoginState()` 四态映射之前进入 suite，不留到 Task 5 伪装成新 RED。

- [ ] **Step 3: 用四态实现替换仅 Bool 的 service**

将 `LoginItemSettings.swift` 替换为：

```swift
import Foundation
import ServiceManagement

enum LoginItemSettingsState: Sendable, Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case unavailable
}

/// 登录项设置抽象；设置页只消费稳定领域状态，不直接依赖 ServiceManagement。
@MainActor
protocol LoginItemSettingsControlling: AnyObject {
    var state: LoginItemSettingsState { get }

    /// 按当前状态开启或关闭 TokenWatch 登录项。
    func setEnabled(_ enabled: Bool) throws

    /// 打开系统设置的登录项面板，不更改注册状态。
    func openSystemSettings()
}

/// 对 `SMAppService` 的最小测试 seam；生产和测试共享同一动作矩阵。
@MainActor
protocol LoginItemServiceControlling: AnyObject {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemServiceControlling {}

/// 基于 `SMAppService.mainApp` 管理主应用的开机自启动状态。
@MainActor
final class LoginItemSettings: LoginItemSettingsControlling {
    static let shared = LoginItemSettings()

    private let service: any LoginItemServiceControlling
    private let openSystemSettingsAction: @MainActor () -> Void

    init(
        service: any LoginItemServiceControlling = SMAppService.mainApp,
        openSystemSettingsAction: @escaping @MainActor () -> Void = {
            SMAppService.openSystemSettingsLoginItems()
        }
    ) {
        self.service = service
        self.openSystemSettingsAction = openSystemSettingsAction
    }

    var state: LoginItemSettingsState {
        switch service.status {
        case .notRegistered:
            return .notRegistered
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        switch (state, enabled) {
        case (.notRegistered, true):
            try service.register()
        case (.enabled, false), (.requiresApproval, false):
            try service.unregister()
        default:
            return
        }
    }

    func openSystemSettings() {
        openSystemSettingsAction()
    }
}
```

- [ ] **Step 4: 将现有设置消费者迁移到 state 接口**

把 `SettingsViewController.renderLaunchAtLoginState()` 改为不依赖新文案的完整 switch/off/disabled 映射，让 Step 1 已经写入 suite 的两个 UI 测试转绿；Task 5 只在这个已验证的映射上增加说明和系统设置按钮：

```swift
private func renderLaunchAtLoginState() {
    switch loginItemSettings.state {
    case .notRegistered:
        launchAtLoginSwitch.state = .off
        launchAtLoginSwitch.isEnabled = true
    case .enabled, .requiresApproval:
        launchAtLoginSwitch.state = .on
        launchAtLoginSwitch.isEnabled = true
    case .unavailable:
        launchAtLoginSwitch.state = .off
        launchAtLoginSwitch.isEnabled = false
    }
}
```

- [ ] **Step 5: 运行 service、四态 UI 映射和现有设置测试并确认 GREEN**

运行：

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -derivedDataPath .build/DerivedData -only-testing:TokenWatchTests/LoginItemSettingsTests "-only-testing:TokenWatchTests/TokenWatchTests/settingsMapsRequiresApprovalToEnabledOnSwitch()" "-only-testing:TokenWatchTests/TokenWatchTests/settingsMapsUnavailableToDisabledOffSwitch()" "-only-testing:TokenWatchTests/TokenWatchTests/settingsShowsLaunchAtLoginSwitch()" "-only-testing:TokenWatchTests/TokenWatchTests/togglingLaunchAtLoginSwitchUpdatesLoginItemSetting()" "-only-testing:TokenWatchTests/TokenWatchTests/failedLaunchAtLoginToggleRestoresActualState()" -skip-testing:TokenWatchUITests CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

预期：PASS；四个系统状态映射正确，`requiresApproval` 开关为 on/enabled、`unavailable` 为 off/disabled，动作矩阵没有重复 register，也不会对 unavailable 执行系统变更。

- [ ] **Step 6: 提交领域边界和消费者迁移**

```bash
git add TokenWatch/Services/LoginItemSettings.swift TokenWatch/ViewController.swift TokenWatchTests/Services/LoginItemSettingsTests.swift TokenWatchTests/TokenWatchTests.swift
git commit -m "feat(settings): 引入登录项四态模型"
```

### Task 5: 渲染设置页四态、本地化辅助功能与激活刷新

**Files:**
- Modify: `TokenWatch/ViewController.swift:139-477`
- Modify: `TokenWatch/Localization/AppStrings.swift:8-145,170-1837`
- Modify: `TokenWatchTests/TokenWatchTests.swift:987-1019,1533-1802,1928-1949`
- Modify: `TokenWatchTests/Localization/AppLanguageSettingsTests.swift:115-155`

**Interfaces:**
- Consumes: Task 4 的 `LoginItemSettingsState`、`LoginItemSettingsControlling.state/setEnabled/openSystemSettings`，以及已经由失败测试锁定并实现的 `requiresApproval → on/enabled`、`unavailable → off/disabled` 基础开关映射。
- Produces: `LaunchAtLoginStatusLabel`、`OpenLoginItemsSettingsButton` 两个稳定 identifier；在既有四态开关映射上增加批准/不可用说明；`NSApplication.didBecomeActiveNotification` 状态刷新；三个新 `AppStringKey`。

- [ ] **Step 1: 编写失败的状态说明、激活刷新、辅助功能、本地化和外观隔离测试**

在 `TokenWatchTests` 中增加：

```swift
@MainActor
@Test func settingsShowsRequiresApprovalGuidanceAndOpensSystemSettings() throws {
    let loginItemSettings = FakeLoginItemSettings(state: .requiresApproval)
    let controller = SettingsViewController(
        isAuthorized: { false },
        loginItemSettings: loginItemSettings,
        languageSettings: zhHansLanguageSettings()
    )
    controller.loadViewIfNeeded()

    let status = try #require(
        controller.view.firstDescendant(identifier: "LaunchAtLoginStatusLabel") as? NSTextField
    )
    let openButton = try #require(controller.view.button(identifier: "OpenLoginItemsSettingsButton"))

    #expect(status.stringValue == "需要在系统设置中批准开机自启动。")
    #expect(!status.isHidden)
    #expect(!openButton.isHidden)

    _ = openButton.sendAction(openButton.action, to: openButton.target)
    #expect(loginItemSettings.openSystemSettingsCallCount == 1)
    #expect(loginItemSettings.requestedStates.isEmpty)
}

@MainActor
@Test func settingsShowsUnavailableGuidanceAndRefreshesWhenAppBecomesActive() throws {
    let loginItemSettings = FakeLoginItemSettings(state: .unavailable)
    let controller = SettingsViewController(
        isAuthorized: { false },
        loginItemSettings: loginItemSettings,
        languageSettings: zhHansLanguageSettings()
    )
    controller.loadViewIfNeeded()

    let toggle = try #require(controller.view.switchControl(identifier: "LaunchAtLoginSwitch"))
    let status = try #require(
        controller.view.firstDescendant(identifier: "LaunchAtLoginStatusLabel") as? NSTextField
    )
    let openButton = try #require(controller.view.button(identifier: "OpenLoginItemsSettingsButton"))

    #expect(status.stringValue == "当前无法使用开机自启动。")
    #expect(!status.isHidden)
    #expect(openButton.isHidden)

    loginItemSettings.state = .enabled
    NotificationCenter.default.post(
        name: NSApplication.didBecomeActiveNotification,
        object: NSApp
    )

    #expect(toggle.state == .on)
    #expect(toggle.isEnabled)
    #expect(status.isHidden)
}

@MainActor
@Test func settingsRefreshesLocalizedAccessibilityLabels() throws {
    try withTemporaryDefaults { defaults in
        let languageSettings = AppLanguageSettings(
            defaults: defaults,
            preferredLanguagesProvider: { ["zh-Hans"] }
        )
        let controller = SettingsViewController(
            isAuthorized: { false },
            loginItemSettings: FakeLoginItemSettings(state: .notRegistered),
            autoRefreshSettings: AutoRefreshSettings(defaults: defaults),
            languageSettings: languageSettings
        )
        controller.loadViewIfNeeded()

        let autoRefresh = try #require(controller.view.popUpButton(identifier: "AutoRefreshIntervalPopUpButton"))
        let launchAtLogin = try #require(controller.view.switchControl(identifier: "LaunchAtLoginSwitch"))
        let language = try #require(controller.view.popUpButton(identifier: "LanguagePreferencePopUpButton"))
        let authorize = try #require(controller.view.button(identifier: "AuthorizationActionButton"))
        let refresh = try #require(controller.view.button(identifier: "RefreshAllDataButton"))
        let openSettings = try #require(controller.view.button(identifier: "OpenLoginItemsSettingsButton"))

        #expect(autoRefresh.accessibilityLabel() == "自动刷新间隔")
        #expect(launchAtLogin.accessibilityLabel() == "开机自启动")
        #expect(language.accessibilityLabel() == "语言")
        #expect(authorize.accessibilityLabel() == "去授权")
        #expect(refresh.accessibilityLabel() == "刷新全部数据")
        #expect(openSettings.accessibilityLabel() == "打开登录项设置")

        languageSettings.selectedPreference = .en

        #expect(autoRefresh.accessibilityLabel() == "Auto Refresh Interval")
        #expect(launchAtLogin.accessibilityLabel() == "Launch at Login")
        #expect(language.accessibilityLabel() == "Language")
        #expect(authorize.accessibilityLabel() == "Authorize")
        #expect(refresh.accessibilityLabel() == "Refresh All Data")
        #expect(openSettings.accessibilityLabel() == "Open Login Items Settings")
    }
}
```

在 `settingsPageReappliesLightColorsWhenOpenedAfterAppearanceOverride` 中，用明确未授权的设置控制器替换读取真实 bookmark 的 `ViewController` 构造：

```swift
let languageSettings = zhHansLanguageSettings()
let settingsViewController = SettingsViewController(
    isAuthorized: { false },
    languageSettings: languageSettings
)
let viewController = DashboardViewController(
    settingsViewController: settingsViewController,
    refreshAction: {},
    languageSettings: languageSettings
)
```

并增加已授权中性色测试：

```swift
@MainActor
@Test func settingsAuthorizedButtonUsesNeutralLightColors() throws {
    let appearance = try #require(NSAppearance(named: .aqua))
    let controller = SettingsViewController(
        isAuthorized: { true },
        languageSettings: zhHansLanguageSettings()
    )
    appearance.performAsCurrentDrawingAppearance {
        controller.loadViewIfNeeded()
    }

    let button = try #require(controller.view.button(identifier: "AuthorizationActionButton"))
    #expect(!button.isEnabled)
    #expect(rgbHex(try #require(button.layer?.backgroundColor)) == 0xFFFFFF)
    #expect(rgbHex(try #require(button.layer?.borderColor)) == 0xD8DEE8)
    #expect(try rgbHex(try #require(button.contentTintColor), appearance: .aqua) == 0x6B7280)
}
```

在 `AppLanguageSettingsTests` 中增加全部语言的明确文案断言：

```swift
@Test func loginItemStatusStringsCoverEverySupportedLanguage() {
    let expected: [AppLanguage: (approval: String, unavailable: String, open: String)] = [
        .zhHans: ("需要在系统设置中批准开机自启动。", "当前无法使用开机自启动。", "打开登录项设置"),
        .zhHant: ("需要在「系統設定」中核准登入時啟動。", "目前無法使用登入時啟動。", "打開登入項目設定"),
        .en: ("Approval is required in System Settings to launch at login.", "Launch at login is currently unavailable.", "Open Login Items Settings"),
        .ja: ("ログイン時に起動するには、システム設定での承認が必要です。", "現在、ログイン時の起動は利用できません。", "ログイン項目設定を開く"),
        .ko: ("로그인 시 실행하려면 시스템 설정에서 승인이 필요합니다.", "현재 로그인 시 실행을 사용할 수 없습니다.", "로그인 항목 설정 열기"),
        .es: ("Se requiere aprobación en Ajustes del Sistema para iniciar al iniciar sesión.", "El inicio al iniciar sesión no está disponible actualmente.", "Abrir ajustes de ítems de inicio"),
        .de: ("Für den Start bei der Anmeldung ist eine Genehmigung in den Systemeinstellungen erforderlich.", "Der Start bei der Anmeldung ist derzeit nicht verfügbar.", "Anmeldeobjekteinstellungen öffnen"),
        .fr: ("L’approbation dans Réglages Système est requise pour le lancement à l’ouverture de session.", "Le lancement à l’ouverture de session est actuellement indisponible.", "Ouvrir les réglages des éléments d’ouverture"),
        .ptBR: ("É necessária aprovação nos Ajustes do Sistema para iniciar ao entrar.", "A inicialização ao entrar não está disponível no momento.", "Abrir ajustes de itens de início"),
        .it: ("Per l’avvio al login è necessaria l’approvazione in Impostazioni di Sistema.", "L’avvio al login non è attualmente disponibile.", "Apri le impostazioni degli elementi login"),
        .nl: ("Voor starten bij inloggen is goedkeuring in Systeeminstellingen vereist.", "Starten bij inloggen is momenteel niet beschikbaar.", "Instellingen voor inlogonderdelen openen"),
        .pl: ("Uruchamianie przy logowaniu wymaga zatwierdzenia w Ustawieniach systemowych.", "Uruchamianie przy logowaniu jest obecnie niedostępne.", "Otwórz ustawienia rzeczy otwieranych"),
    ]

    #expect(expected.count == AppLanguage.allCases.count)
    for (language, value) in expected {
        #expect(AppStrings.text(.settingsLaunchAtLoginRequiresApproval, language: language) == value.approval)
        #expect(AppStrings.text(.settingsLaunchAtLoginUnavailable, language: language) == value.unavailable)
        #expect(AppStrings.text(.settingsOpenLoginItemsSettings, language: language) == value.open)
    }
}
```

- [ ] **Step 2: 运行 Task 5 新增行为测试并确认 RED**

运行：

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -derivedDataPath .build/DerivedData "-only-testing:TokenWatchTests/TokenWatchTests/settingsShowsRequiresApprovalGuidanceAndOpensSystemSettings()" "-only-testing:TokenWatchTests/TokenWatchTests/settingsShowsUnavailableGuidanceAndRefreshesWhenAppBecomesActive()" "-only-testing:TokenWatchTests/TokenWatchTests/settingsRefreshesLocalizedAccessibilityLabels()" "-only-testing:TokenWatchTests/TokenWatchTests/settingsPageReappliesLightColorsWhenOpenedAfterAppearanceOverride()" "-only-testing:TokenWatchTests/TokenWatchTests/settingsAuthorizedButtonUsesNeutralLightColors()" "-only-testing:TokenWatchTests/AppLanguageSettingsTests/loginItemStatusStringsCoverEverySupportedLanguage()" -skip-testing:TokenWatchUITests CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

预期：编译失败；Task 4 的两个基础开关映射测试已经是 GREEN，本次 RED 只来自尚不存在的新 identifier、状态说明、独立系统设置操作、激活刷新和三个 `AppStringKey`。

- [ ] **Step 3: 增加三个本地化 key 及全部翻译**

在 `AppStringKey` 的 settings 区域增加：

```swift
case settingsLaunchAtLoginRequiresApproval
case settingsLaunchAtLoginUnavailable
case settingsOpenLoginItemsSettings
```

在 12 个表中分别加入以下实际条目：

```swift
// zhHans
.settingsLaunchAtLoginRequiresApproval: "需要在系统设置中批准开机自启动。",
.settingsLaunchAtLoginUnavailable: "当前无法使用开机自启动。",
.settingsOpenLoginItemsSettings: "打开登录项设置",

// zhHant
.settingsLaunchAtLoginRequiresApproval: "需要在「系統設定」中核准登入時啟動。",
.settingsLaunchAtLoginUnavailable: "目前無法使用登入時啟動。",
.settingsOpenLoginItemsSettings: "打開登入項目設定",

// en
.settingsLaunchAtLoginRequiresApproval: "Approval is required in System Settings to launch at login.",
.settingsLaunchAtLoginUnavailable: "Launch at login is currently unavailable.",
.settingsOpenLoginItemsSettings: "Open Login Items Settings",

// ja
.settingsLaunchAtLoginRequiresApproval: "ログイン時に起動するには、システム設定での承認が必要です。",
.settingsLaunchAtLoginUnavailable: "現在、ログイン時の起動は利用できません。",
.settingsOpenLoginItemsSettings: "ログイン項目設定を開く",

// ko
.settingsLaunchAtLoginRequiresApproval: "로그인 시 실행하려면 시스템 설정에서 승인이 필요합니다.",
.settingsLaunchAtLoginUnavailable: "현재 로그인 시 실행을 사용할 수 없습니다.",
.settingsOpenLoginItemsSettings: "로그인 항목 설정 열기",

// es
.settingsLaunchAtLoginRequiresApproval: "Se requiere aprobación en Ajustes del Sistema para iniciar al iniciar sesión.",
.settingsLaunchAtLoginUnavailable: "El inicio al iniciar sesión no está disponible actualmente.",
.settingsOpenLoginItemsSettings: "Abrir ajustes de ítems de inicio",

// de
.settingsLaunchAtLoginRequiresApproval: "Für den Start bei der Anmeldung ist eine Genehmigung in den Systemeinstellungen erforderlich.",
.settingsLaunchAtLoginUnavailable: "Der Start bei der Anmeldung ist derzeit nicht verfügbar.",
.settingsOpenLoginItemsSettings: "Anmeldeobjekteinstellungen öffnen",

// fr
.settingsLaunchAtLoginRequiresApproval: "L’approbation dans Réglages Système est requise pour le lancement à l’ouverture de session.",
.settingsLaunchAtLoginUnavailable: "Le lancement à l’ouverture de session est actuellement indisponible.",
.settingsOpenLoginItemsSettings: "Ouvrir les réglages des éléments d’ouverture",

// ptBR
.settingsLaunchAtLoginRequiresApproval: "É necessária aprovação nos Ajustes do Sistema para iniciar ao entrar.",
.settingsLaunchAtLoginUnavailable: "A inicialização ao entrar não está disponível no momento.",
.settingsOpenLoginItemsSettings: "Abrir ajustes de itens de início",

// it
.settingsLaunchAtLoginRequiresApproval: "Per l’avvio al login è necessaria l’approvazione in Impostazioni di Sistema.",
.settingsLaunchAtLoginUnavailable: "L’avvio al login non è attualmente disponibile.",
.settingsOpenLoginItemsSettings: "Apri le impostazioni degli elementi login",

// nl
.settingsLaunchAtLoginRequiresApproval: "Voor starten bij inloggen is goedkeuring in Systeeminstellingen vereist.",
.settingsLaunchAtLoginUnavailable: "Starten bij inloggen is momenteel niet beschikbaar.",
.settingsOpenLoginItemsSettings: "Instellingen voor inlogonderdelen openen",

// pl
.settingsLaunchAtLoginRequiresApproval: "Uruchamianie przy logowaniu wymaga zatwierdzenia w Ustawieniach systemowych.",
.settingsLaunchAtLoginUnavailable: "Uruchamianie przy logowaniu jest obecnie niedostępne.",
.settingsOpenLoginItemsSettings: "Otwórz ustawienia rzeczy otwieranych",
```

- [ ] **Step 4: 在已验证的四态开关映射上增加说明、激活刷新和 AX label**

在 `SettingsViewController` 属性区增加：

```swift
private let launchAtLoginStatusLabel = NSTextField(labelWithString: "")
private let openLoginItemsSettingsButton = DashboardRangeButton(title: "", target: nil, action: nil)
```

在 `viewDidLoad()` 中订阅应用激活：

```swift
setupSubviews()
subscribeToLanguageSettings()
NotificationCenter.default.addObserver(
    self,
    selector: #selector(applicationDidBecomeActive(_:)),
    name: NSApplication.didBecomeActiveNotification,
    object: nil
)
renderAuthorizationState()
renderLaunchAtLoginState()
```

在 `setupSubviews()` 配置新控件：

```swift
launchAtLoginStatusLabel.font = .systemFont(ofSize: 12)
launchAtLoginStatusLabel.textColor = DashboardPalette.secondaryText
launchAtLoginStatusLabel.maximumNumberOfLines = 0
launchAtLoginStatusLabel.lineBreakMode = .byWordWrapping
launchAtLoginStatusLabel.identifier = NSUserInterfaceItemIdentifier("LaunchAtLoginStatusLabel")
launchAtLoginStatusLabel.setAccessibilityIdentifier("LaunchAtLoginStatusLabel")

configureSettingsButton(openLoginItemsSettingsButton)
openLoginItemsSettingsButton.identifier = NSUserInterfaceItemIdentifier("OpenLoginItemsSettingsButton")
openLoginItemsSettingsButton.setAccessibilityIdentifier("OpenLoginItemsSettingsButton")
openLoginItemsSettingsButton.target = self
openLoginItemsSettingsButton.action = #selector(openLoginItemsSettingsButtonClicked)
```

用垂直组包住现有 launch row、状态和独立操作：

```swift
let launchAtLoginControlRow = NSStackView(views: [launchAtLoginLabel, launchAtLoginSwitch])
launchAtLoginControlRow.orientation = .horizontal
launchAtLoginControlRow.alignment = .centerY
launchAtLoginControlRow.spacing = 8

let launchAtLoginSettingsStack = NSStackView(views: [
    launchAtLoginControlRow,
    launchAtLoginStatusLabel,
    openLoginItemsSettingsButton,
])
launchAtLoginSettingsStack.orientation = .vertical
launchAtLoginSettingsStack.alignment = .leading
launchAtLoginSettingsStack.spacing = 8
```

在 `contentStack` 中用 `launchAtLoginSettingsStack` 替换旧 `launchAtLoginStack`，并扩展 Task 4 已验证的 `renderLaunchAtLoginState()`：保留原开关 state/enabled 映射，只增加状态文案和独立系统设置操作的可见性。

```swift
private func renderLaunchAtLoginState() {
    let statusKey: AppStringKey?
    let showsOpenSettings: Bool

    switch loginItemSettings.state {
    case .notRegistered:
        launchAtLoginSwitch.state = .off
        launchAtLoginSwitch.isEnabled = true
        statusKey = nil
        showsOpenSettings = false
    case .enabled:
        launchAtLoginSwitch.state = .on
        launchAtLoginSwitch.isEnabled = true
        statusKey = nil
        showsOpenSettings = false
    case .requiresApproval:
        launchAtLoginSwitch.state = .on
        launchAtLoginSwitch.isEnabled = true
        statusKey = .settingsLaunchAtLoginRequiresApproval
        showsOpenSettings = true
    case .unavailable:
        launchAtLoginSwitch.state = .off
        launchAtLoginSwitch.isEnabled = false
        statusKey = .settingsLaunchAtLoginUnavailable
        showsOpenSettings = false
    }

    if let statusKey {
        launchAtLoginStatusLabel.stringValue = AppStrings.text(
            statusKey,
            language: languageSettings.resolvedLanguage
        )
        launchAtLoginStatusLabel.isHidden = false
    } else {
        launchAtLoginStatusLabel.stringValue = ""
        launchAtLoginStatusLabel.isHidden = true
    }
    openLoginItemsSettingsButton.isHidden = !showsOpenSettings
}
```

增加两个 selector：

```swift
@objc private func openLoginItemsSettingsButtonClicked() {
    loginItemSettings.openSystemSettings()
}

@objc private func applicationDidBecomeActive(_ notification: Notification) {
    renderLaunchAtLoginState()
}
```

保留现有 toggle 的错误日志，但确保不可用控件不会调用 service：

```swift
@objc private func launchAtLoginSwitchChanged() {
    guard launchAtLoginSwitch.isEnabled else {
        renderLaunchAtLoginState()
        return
    }

    do {
        try loginItemSettings.setEnabled(launchAtLoginSwitch.state == .on)
    } catch {
        NSLog("TokenWatch failed to update launch-at-login setting: \(error)")
    }
    renderLaunchAtLoginState()
}
```

在 `applySettingsButtonStyle` 中让所有授权、刷新和系统设置按钮随标题同步 AX label：

```swift
button.title = title
button.setAccessibilityLabel(title)
button.setDashboardLayerColors(backgroundColor: backgroundColor, borderColor: borderColor)
```

在 `reloadLocalizedText()` 中加入：

```swift
autoRefreshIntervalPopUpButton.setAccessibilityLabel(
    AppStrings.text(.settingsAutoRefreshInterval, language: language)
)
launchAtLoginSwitch.setAccessibilityLabel(
    AppStrings.text(.settingsLaunchAtLogin, language: language)
)
languagePopUpButton.setAccessibilityLabel(
    AppStrings.text(.settingsLanguage, language: language)
)
applySettingsButtonStyle(
    openLoginItemsSettingsButton,
    title: AppStrings.text(.settingsOpenLoginItemsSettings, language: language),
    backgroundColor: DashboardPalette.panelBackground,
    borderColor: DashboardPalette.border,
    textColor: DashboardPalette.primaryText
)
renderAuthorizationState()
renderLaunchAtLoginState()
```

在 `deinit` 的 main-actor 清理中增加：

```swift
NotificationCenter.default.removeObserver(self)
```

- [ ] **Step 5: 运行设置、service、本地化、外观和 UI 测试并确认 GREEN**

运行：

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -derivedDataPath .build/DerivedData -only-testing:TokenWatchTests/LoginItemSettingsTests -only-testing:TokenWatchTests/AppLanguageSettingsTests "-only-testing:TokenWatchTests/TokenWatchTests/settingsMapsRequiresApprovalToEnabledOnSwitch()" "-only-testing:TokenWatchTests/TokenWatchTests/settingsMapsUnavailableToDisabledOffSwitch()" "-only-testing:TokenWatchTests/TokenWatchTests/settingsShowsRequiresApprovalGuidanceAndOpensSystemSettings()" "-only-testing:TokenWatchTests/TokenWatchTests/settingsShowsUnavailableGuidanceAndRefreshesWhenAppBecomesActive()" "-only-testing:TokenWatchTests/TokenWatchTests/settingsRefreshesLocalizedAccessibilityLabels()" "-only-testing:TokenWatchTests/TokenWatchTests/settingsPageReappliesLightColorsWhenOpenedAfterAppearanceOverride()" "-only-testing:TokenWatchTests/TokenWatchTests/settingsAuthorizedButtonUsesNeutralLightColors()" "-only-testing:TokenWatchTests/TokenWatchTests/togglingLaunchAtLoginSwitchUpdatesLoginItemSetting()" "-only-testing:TokenWatchTests/TokenWatchTests/failedLaunchAtLoginToggleRestoresActualState()" -only-testing:TokenWatchUITests/TokenWatchUITests/testSettingsPageExposesActionControls CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

预期：PASS；Task 4 的 requiresApproval/unavailable 基础开关映射继续通过，Task 5 新增的说明与系统设置操作正确，打开系统设置时 register 调用数保持零，didBecomeActive 后 switch 立即反映 fake 的新状态，真实 `HomeDirectoryBookmark` 不再影响外观测试。

- [ ] **Step 6: 提交设置状态、本地化、辅助功能和确定性外观覆盖**

```bash
git add TokenWatch/ViewController.swift TokenWatch/Localization/AppStrings.swift TokenWatchTests/TokenWatchTests.swift TokenWatchTests/Localization/AppLanguageSettingsTests.swift
git commit -m "fix(settings): 补齐登录项状态与辅助功能"
```

### Task 6: 为热力图日期格增加本地化 accessibility 语义

**Files:**
- Modify: `TokenWatch/ViewControllers/CalendarHeatmapCollectionViewItem.swift:4-96`
- Modify: `TokenWatch/ViewControllers/StatusPopoverViewController.swift:687-704`
- Test: `TokenWatchTests/ViewControllers/CalendarHeatmapCollectionViewItemTests.swift:8-266`

**Interfaces:**
- Consumes: Task 1 的 `CompactNumberFormatter.formatHoverTokens(_:)`、现有 `AppLanguage.localeIdentifier`、现有 `AppStrings.text(.statusBarTokenUnit, language:)` 和 `StatusPopoverViewController.calendar`。
- Produces: `CalendarHeatmapCellStyle.make(for:language:calendar:)`、`CalendarHeatmapCollectionViewItem.configure(with:language:calendar:)`；day cell 的 `.staticText` role、本地化日期 label 和带 token 单位的 value。

- [ ] **Step 1: 编写失败的 day 与 placeholder 辅助功能测试**

在 `CalendarHeatmapCollectionViewItemTests` 中增加：

```swift
@MainActor
@Test("day cell 暴露本地化日期和 token 辅助功能语义")
func dayCellExposesLocalizedAccessibilitySemantics() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let date = try #require(calendar.date(from: DateComponents(
        year: 2026,
        month: 6,
        day: 10
    )))
    let day = CalendarHeatmapDay(
        id: "2026-06-10",
        date: date,
        dateKey: "2026-06-10",
        dayNumber: 10,
        totalTokens: 12_345,
        intensity: 3,
        isToday: false,
        isFuture: false
    )
    let item = CalendarHeatmapCollectionViewItem()
    item.loadView()

    item.configure(with: .day(day), language: .en, calendar: calendar)

    #expect(item.view.isAccessibilityElement())
    #expect(item.view.accessibilityRole() == .staticText)
    #expect(item.view.accessibilityLabel() == "June 10, 2026")
    #expect(item.view.accessibilityValue() as? String == "12.3k Tokens")

    item.configure(with: .day(day), language: .zhHans, calendar: calendar)
    #expect(item.view.accessibilityLabel() == "2026年6月10日")
    #expect(item.view.accessibilityValue() as? String == "12.3k Tokens")
}

@MainActor
@Test("placeholder 退出辅助功能树并清除复用残留")
func placeholderClearsReusedAccessibilityState() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let date = try #require(calendar.date(from: DateComponents(
        year: 2026,
        month: 6,
        day: 10
    )))
    let day = CalendarHeatmapDay(
        id: "2026-06-10",
        date: date,
        dateKey: "2026-06-10",
        dayNumber: 10,
        totalTokens: 12_345,
        intensity: 3,
        isToday: false,
        isFuture: false
    )
    let item = CalendarHeatmapCollectionViewItem()
    item.loadView()
    item.configure(with: .day(day), language: .en, calendar: calendar)

    item.configure(with: .placeholder(id: "p0"), language: .en, calendar: calendar)

    #expect(!item.view.isAccessibilityElement())
    #expect(item.view.accessibilityRole() == nil)
    #expect(item.view.accessibilityLabel() == nil)
    #expect(item.view.accessibilityValue() == nil)
    #expect(item.view.isHidden)
}
```

- [ ] **Step 2: 运行 heatmap item suite 并确认 RED**

运行：

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -derivedDataPath .build/DerivedData -only-testing:TokenWatchTests/CalendarHeatmapCollectionViewItemTests -skip-testing:TokenWatchUITests CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

预期：编译失败；`make/configure` 尚无 `calendar` 参数，day view 也没有显式 accessibility role、label 或 value。

- [ ] **Step 3: 为纯 cell style 增加辅助功能字段和本地化日期格式**

把 `CalendarHeatmapCellStyle` 扩展为以下字段和 factory：

```swift
struct CalendarHeatmapCellStyle: Equatable {
    let title: String
    let toolTip: String?
    let isHidden: Bool
    let alpha: CGFloat
    let intensity: Int
    let isAccessibilityElement: Bool
    let accessibilityLabel: String?
    let accessibilityValue: String?

    static func make(
        for cell: CalendarHeatmapCell,
        language: AppLanguage = .zhHans,
        calendar: Calendar = .current
    ) -> CalendarHeatmapCellStyle {
        switch cell {
        case .placeholder:
            return CalendarHeatmapCellStyle(
                title: "",
                toolTip: nil,
                isHidden: true,
                alpha: 0,
                intensity: 0,
                isAccessibilityElement: false,
                accessibilityLabel: nil,
                accessibilityValue: nil
            )
        case .day(let day):
            let formattedTokens = CompactNumberFormatter.formatHoverTokens(day.totalTokens)
            let tokenUnit = AppStrings.text(.statusBarTokenUnit, language: language)
            return CalendarHeatmapCellStyle(
                title: "",
                toolTip: "\(day.dateKey) · \(formattedTokens)",
                isHidden: false,
                alpha: day.isFuture ? 0.45 : 1.0,
                intensity: day.intensity,
                isAccessibilityElement: true,
                accessibilityLabel: localizedDate(
                    day.date,
                    language: language,
                    calendar: calendar
                ),
                accessibilityValue: "\(formattedTokens) \(tokenUnit)"
            )
        }
    }

    private static func localizedDate(
        _ date: Date,
        language: AppLanguage,
        calendar: Calendar
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.localeIdentifier)
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
```

- [ ] **Step 4: 在 item 复用时应用并清理辅助功能状态**

将 item 的 configure 签名和 accessibility 应用改为：

```swift
func configure(
    with cell: CalendarHeatmapCell,
    language: AppLanguage = .zhHans,
    calendar: Calendar = .current
) {
    let style = CalendarHeatmapCellStyle.make(
        for: cell,
        language: language,
        calendar: calendar
    )
    dayLabel.stringValue = style.title
    view.toolTip = style.toolTip
    view.isHidden = style.isHidden
    view.alphaValue = style.alpha
    cellView.heatmapBackgroundColor = CalendarHeatmapGitHubPalette.color(forIntensity: style.intensity)
    cellView.hoverText = style.toolTip

    view.setAccessibilityElement(style.isAccessibilityElement)
    if style.isAccessibilityElement {
        view.setAccessibilityRole(.staticText)
        view.setAccessibilityLabel(style.accessibilityLabel)
        view.setAccessibilityValue(style.accessibilityValue)
    } else {
        view.setAccessibilityRole(nil)
        view.setAccessibilityLabel(nil)
        view.setAccessibilityValue(nil)
    }

    if style.toolTip == nil {
        onHoverTextChange?(nil)
    }
}
```

在 `StatusPopoverViewController.collectionView(_:itemForRepresentedObjectAt:)` 中传入控制器已有 calendar：

```swift
heatmapItem.configure(
    with: cell,
    language: languageSettings.resolvedLanguage,
    calendar: calendar
)
```

- [ ] **Step 5: 运行 heatmap、popover 语言、hover 和紧凑数字回归并确认 GREEN**

运行：

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -derivedDataPath .build/DerivedData -only-testing:TokenWatchTests/CalendarHeatmapCollectionViewItemTests -only-testing:TokenWatchTests/StatusPopoverViewControllerTests -only-testing:TokenWatchTests/CompactNumberFormatterTests -skip-testing:TokenWatchUITests CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

预期：PASS；day cell 的日期随 App 语言变化，value 含 token 单位，placeholder 在 day→placeholder 复用后不留下 AX role、label 或 value，原 tooltip/hover 视觉文案保持通过。

- [ ] **Step 6: 提交 heatmap 辅助功能语义**

```bash
git add TokenWatch/ViewControllers/CalendarHeatmapCollectionViewItem.swift TokenWatch/ViewControllers/StatusPopoverViewController.swift TokenWatchTests/ViewControllers/CalendarHeatmapCollectionViewItemTests.swift
git commit -m "fix(heatmap): 补齐日期格辅助功能语义"
```

## 最终验证

完成六个 task 后按以下顺序验证；每条命令都必须观察退出码和最终 summary，不能用 `build-for-testing` 代替 test：

1. 全部 unit tests：

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -derivedDataPath .build/DerivedData -only-testing:TokenWatchTests -skip-testing:TokenWatchUITests CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: `TokenWatchTests` 全部 PASS。

2. 全部 UI tests：

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -derivedDataPath .build/DerivedData -only-testing:TokenWatchUITests CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: `TokenWatchUITests` 全部 PASS；窗口可通过 `TokenWatch` 查询，会话表横向 gesture 改变 document 子控件位置。

3. Debug 与 Release 构建：

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Debug -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Release -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

Expected: 两种 configuration 均 `BUILD SUCCEEDED`；Release 无签名继续按已确认设计处理。

4. Universal `arm64 + x86_64` 构建：

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Release -arch arm64 -arch x86_64 ONLY_ACTIVE_ARCH=NO -derivedDataPath .build/DerivedData-Universal CODE_SIGNING_ALLOWED=NO build
```

Expected: `BUILD SUCCEEDED`，产物同时包含 `arm64` 与 `x86_64` slice。

5. 静态分析：

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Debug -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO analyze
```

Expected: `ANALYZE SUCCEEDED`，没有本轮新增 warning。

6. 最终范围检查：

```bash
git status --short
git diff --check
```

Expected: `git diff --check` 无输出，`TokenWatch.xcodeproj/project.pbxproj` 未被修改；若协调者尚未单独提交本计划，`git status --short` 只允许显示 `docs/superpowers/plans/2026-07-10-macos-ui-accessibility-hardening.md`，不得残留实现文件修改。
