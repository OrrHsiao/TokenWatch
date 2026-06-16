# 状态栏左键 Popover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 左键点击 TokenWatch 菜单栏状态项时显示空 `NSPopover`,右键或 Control-click 继续显示原有菜单。

**Architecture:** `StatusBarController` 改用 `NSStatusBarButton` 的 `target/action` 分发点击事件,不再把菜单直接挂到 `statusItem.menu`。新增一个可单测的 `StatusBarClickAction` 纯 helper 负责把 `NSEvent.EventType` 和 modifier flags 转成交互意图;AppKit 展示逻辑仍集中在 `StatusBarController` 内。Popover 内容使用一个空 `NSViewController`,根视图背景色为 `NSColor.windowBackgroundColor`,由系统自动适配暗黑模式。

**Tech Stack:** Swift 6、AppKit、Swift Testing、NSPopover、NSStatusItem。

---

### Task 1: 状态栏点击事件分流

**Files:**
- Create: `TokenWatchTests/ViewControllers/StatusBarControllerTests.swift`
- Modify: `TokenWatch/ViewControllers/StatusBarController.swift`

- [ ] **Step 1: Write the failing test**

Create `TokenWatchTests/ViewControllers/StatusBarControllerTests.swift`:

```swift
import AppKit
import Testing
@testable import TokenWatch

struct StatusBarControllerTests {

    /// 普通左键用于切换 popover。
    @Test func leftMouseUpTogglesPopover() {
        #expect(StatusBarClickAction.resolve(
            eventType: .leftMouseUp,
            modifierFlags: []
        ) == .togglePopover)
    }

    /// 右键保留原状态栏菜单入口。
    @Test func rightMouseUpShowsMenu() {
        #expect(StatusBarClickAction.resolve(
            eventType: .rightMouseUp,
            modifierFlags: []
        ) == .showMenu)
    }

    /// macOS 惯例:Control-click 视作辅助点击,同样显示菜单。
    @Test func controlLeftClickShowsMenu() {
        #expect(StatusBarClickAction.resolve(
            eventType: .leftMouseUp,
            modifierFlags: [.control]
        ) == .showMenu)
    }
}
```

- [ ] **Step 2: Run targeted tests to verify RED**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/StatusBarControllerTests test
```

Expected: FAIL to compile because `StatusBarClickAction` is not defined.

- [ ] **Step 3: Add the minimal click action helper**

Append this enum after `StatusBarController` in `TokenWatch/ViewControllers/StatusBarController.swift`:

```swift
/// 状态栏按钮点击后的交互意图。
///
/// 抽成纯 helper,避免单元测试依赖真实 `NSStatusItem` 或鼠标事件对象。
enum StatusBarClickAction {
    case togglePopover
    case showMenu

    static func resolve(
        eventType: NSEvent.EventType,
        modifierFlags: NSEvent.ModifierFlags
    ) -> StatusBarClickAction {
        if eventType == .rightMouseUp || modifierFlags.contains(.control) {
            return .showMenu
        }
        return .togglePopover
    }
}
```

- [ ] **Step 4: Run targeted tests to verify GREEN**

Run the same command as Step 2.

Expected: PASS for `StatusBarControllerTests`.

### Task 2: 接入 NSPopover 与右键菜单

**Files:**
- Modify: `TokenWatch/ViewControllers/StatusBarController.swift`

- [ ] **Step 1: Add UI state fields**

Add fields near `statusItem`:

```swift
    private let popover = NSPopover()
    private let statusMenu = NSMenu()
```

- [ ] **Step 2: Configure status button action**

In `configureButton()`, after clearing `button.image` and `button.title`, add:

```swift
        button.target = self
        button.action = #selector(handleStatusItemClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
```

- [ ] **Step 3: Configure the empty popover**

Add this method under `// MARK: - Setup`:

```swift
    private func configurePopover() {
        let contentSize = NSSize(width: 280, height: 180)
        let contentViewController = NSViewController()
        contentViewController.view = EmptyStatusPopoverView(frame: NSRect(origin: .zero, size: contentSize))
        contentViewController.preferredContentSize = contentSize

        popover.behavior = .transient
        popover.contentSize = contentSize
        popover.contentViewController = contentViewController
    }
```

Call it from `init(viewModel:)` after `configureButton()`:

```swift
        configurePopover()
```

- [ ] **Step 4: Keep the menu as an explicit property**

Replace `private func installMenu()` with:

```swift
    private func installMenu() {
        let openItem = NSMenuItem(
            title: "打开 TokenWatch",
            action: #selector(openMainWindow),
            keyEquivalent: "0"
        )
        openItem.target = self
        statusMenu.addItem(openItem)

        let refreshItem = NSMenuItem(
            title: "立即刷新",
            action: #selector(refreshNow),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        statusMenu.addItem(refreshItem)

        statusMenu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "退出 TokenWatch",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        statusMenu.addItem(quitItem)
    }
```

- [ ] **Step 5: Add click handling actions**

Add under `// MARK: - Actions` before `openMainWindow()`:

```swift
    @objc private func handleStatusItemClick() {
        guard let event = NSApp.currentEvent else {
            togglePopover()
            return
        }

        switch StatusBarClickAction.resolve(
            eventType: event.type,
            modifierFlags: event.modifierFlags
        ) {
        case .togglePopover:
            togglePopover()
        case .showMenu:
            showStatusMenu()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func showStatusMenu() {
        guard let button = statusItem.button else { return }
        popover.performClose(nil)
        statusMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
    }
```

- [ ] **Step 6: Add the empty popover view**

Append this class after `StatusBarClickAction` in `TokenWatch/ViewControllers/StatusBarController.swift`:

```swift
/// 空状态栏 popover 根视图。
///
/// 使用系统窗口背景色,让浅色和暗黑模式都由 AppKit 自动适配。
final class EmptyStatusPopoverView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("EmptyStatusPopoverView 不支持 storyboard 初始化")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }
}
```

- [ ] **Step 7: Run unit tests**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests test
```

Expected: PASS.

- [ ] **Step 8: Build app**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Debug build
```

Expected: BUILD SUCCEEDED.
