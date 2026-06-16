# 状态栏刷新仪表盘动画 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 刷新期间让菜单栏 `gauge.with.dots.needle.*percent` 图标循环播放加载动画,刷新结束后恢复真实 token 分档图标。

**Architecture:** 保持 `StatusBarTitleBuilder` 的静态分档逻辑不变,在同一文件新增可单测的 `StatusBarLoadingAnimation` 纯 helper 定义动画帧和 wrap 行为。`StatusBarController` 监听 ViewModel loading 状态,只在 loading 期间启动轻量 timer 替换 `iconView.image`,结束后停止 timer 并复用 `renderTitle()` 恢复静态图标与文本。

**Tech Stack:** Swift 6、AppKit、Swift Testing、SF Symbols。

---

### Task 1: 动画帧纯 helper

**Files:**
- Modify: `TokenWatchTests/ViewControllers/StatusBarTitleBuilderTests.swift`
- Modify: `TokenWatch/ViewControllers/StatusBarTitleBuilder.swift`

- [ ] **Step 1: Write the failing test**

Add these tests before `// MARK: - Helpers` in `TokenWatchTests/ViewControllers/StatusBarTitleBuilderTests.swift`:

```swift
    /// 刷新加载动画使用同一组仪表盘 SF Symbol,按 0 → 100 的方向播放
    @Test func loadingAnimationSymbolNamesUseGaugeNeedleFrames() {
        #expect(StatusBarLoadingAnimation.symbolNames == [
            "gauge.with.dots.needle.0percent",
            "gauge.with.dots.needle.33percent",
            "gauge.with.dots.needle.50percent",
            "gauge.with.dots.needle.67percent",
            "gauge.with.dots.needle.100percent",
        ])
    }

    /// 动画帧索引到末尾后回到第一帧,便于 timer 循环播放
    @Test func loadingAnimationNextFrameIndexWrapsToStart() {
        #expect(StatusBarLoadingAnimation.nextFrameIndex(after: 0) == 1)
        #expect(StatusBarLoadingAnimation.nextFrameIndex(after: 3) == 4)
        #expect(StatusBarLoadingAnimation.nextFrameIndex(after: 4) == 0)
    }
```

- [ ] **Step 2: Run the targeted tests to verify RED**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/StatusBarTitleBuilderTests test
```

Expected: FAIL to compile because `StatusBarLoadingAnimation` is not defined.

- [ ] **Step 3: Add the minimal helper**

Append this enum after `StatusBarTitleBuilder` in `TokenWatch/ViewControllers/StatusBarTitleBuilder.swift`:

```swift
/// 状态栏刷新加载动画帧定义
///
/// 保持为纯 helper,让帧顺序和循环规则可单测;AppKit timer 只负责按索引取图。
enum StatusBarLoadingAnimation {
    static let symbolNames = [
        "gauge.with.dots.needle.0percent",
        "gauge.with.dots.needle.33percent",
        "gauge.with.dots.needle.50percent",
        "gauge.with.dots.needle.67percent",
        "gauge.with.dots.needle.100percent",
    ]

    static func nextFrameIndex(after index: Int) -> Int {
        (index + 1) % symbolNames.count
    }
}
```

- [ ] **Step 4: Run the targeted tests to verify GREEN**

Run the same command as Step 2.

Expected: PASS for `StatusBarTitleBuilderTests`.

### Task 2: 状态栏图标动画接线

**Files:**
- Modify: `TokenWatch/ViewControllers/StatusBarController.swift`

- [ ] **Step 1: Add animation state fields**

Add fields near the existing `lastRenderedSymbolName`:

```swift
    private var loadingAnimationTimer: Timer?
    private var loadingAnimationFrameIndex = 0
    private static let loadingAnimationInterval: TimeInterval = 0.18
```

- [ ] **Step 2: Stop the animation during teardown**

In both `deinit` and `stop()`, invalidate `loadingAnimationTimer` along with `refreshTimer`.

- [ ] **Step 3: Update ViewModel observation**

Replace the observer body with logic that starts animation while any provider is loading, and only renders the static title when all loading has ended:

```swift
            self.syncLoadingAnimationState()
            guard self.viewModel.states.values.allSatisfy({ !$0.isLoading }) else { return }
            self.renderTitle()
```

- [ ] **Step 4: Add animation methods**

Add private methods under `// MARK: - Render`:

```swift
    private func syncLoadingAnimationState() {
        if viewModel.states.values.contains(where: { $0.isLoading }) {
            startLoadingAnimation()
        } else {
            stopLoadingAnimation()
        }
    }

    private func startLoadingAnimation() {
        guard loadingAnimationTimer == nil else { return }
        loadingAnimationFrameIndex = 0
        renderLoadingAnimationFrame()

        let timer = Timer(timeInterval: Self.loadingAnimationInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advanceLoadingAnimationFrame()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        loadingAnimationTimer = timer
    }

    private func stopLoadingAnimation() {
        loadingAnimationTimer?.invalidate()
        loadingAnimationTimer = nil
        loadingAnimationFrameIndex = 0
    }

    private func advanceLoadingAnimationFrame() {
        loadingAnimationFrameIndex = StatusBarLoadingAnimation.nextFrameIndex(after: loadingAnimationFrameIndex)
        renderLoadingAnimationFrame()
    }

    private func renderLoadingAnimationFrame() {
        let symbolName = StatusBarLoadingAnimation.symbolNames[loadingAnimationFrameIndex]
        setIcon(symbolName: symbolName)
    }
```

- [ ] **Step 5: Extract static icon setting**

Extract the repeated `NSImage(systemSymbolName:)` assignment from `renderTitle()` into:

```swift
    private func setIcon(symbolName: String) {
        iconView.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: "TokenWatch"
        )?.withSymbolConfiguration(iconSymbolConfig)
        iconView.image?.isTemplate = true
        lastRenderedSymbolName = symbolName
    }
```

Then `renderTitle()` keeps the existing symbol-name comparison and calls `setIcon(symbolName:)` only when the static tier changes.

- [ ] **Step 6: Run unit tests**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests test
```

Expected: PASS.

- [ ] **Step 7: Build app**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Debug build
```

Expected: BUILD SUCCEEDED.
