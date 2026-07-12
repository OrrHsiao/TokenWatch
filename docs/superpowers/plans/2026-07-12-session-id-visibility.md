# 会话列表会话 ID 可见性修复实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让主界面会话列表稳定显示缩略会话 ID，同时保留复制完整 ID 的现有交互。

**Architecture:** 保持 `ParsedUsageEntry` 到 `RecentSessionRow` 的数据链不变，只修正 `makeSessionIDCell` 的局部 Auto Layout 约束。测试在现有 AppKit 控制器测试中检查内部标题控件的真实布局宽度，避免只验证 `NSButton.title` 属性而漏掉视觉回归。

**Tech Stack:** Swift 6、AppKit、Swift Testing、Xcode 26 / `xcodebuild`

## Global Constraints

- 会话 ID 继续显示为现有缩略格式，例如 `019df220...eeefff`。
- tooltip、辅助功能标签和点击复制完整 ID 的行为保持不变。
- 不修改会话数据解析、聚合、排序、分页或横向滚动逻辑。
- 不重写 `DashboardSessionButton.intrinsicContentSize`，也不拆分 ID 文本与复制按钮。
- macOS 测试使用 `-derivedDataPath .build/DerivedData`；完整 app-hosted 测试需在沙盒外运行。

---

### Task 1: 修复会话 ID 单元格布局并增加回归覆盖

**Files:**
- Modify: `TokenWatchTests/ViewControllers/DashboardSessionPaginationTests.swift:76-123`
- Modify: `TokenWatch/ViewControllers/DashboardViewController.swift:1284-1323`

**Interfaces:**
- Consumes: `RecentSessionRow.sessionID: String`、`DashboardViewController.makeSessionIDCell(_:rowIndex:width:)`、测试辅助方法 `textField(withString:in:)`。
- Produces: 不新增公开接口；`DashboardSessionsCopy.<row>` 按钮铺满会话 ID 单元格，并让内部缩略 ID `NSTextField` 获得足够显示宽度。

- [ ] **Step 1: 写出会失败的真实布局断言**

在 `dashboardSessionRowDisplaysCompactIDCopiesFullIDAndCleansProject()` 中复用现有长 ID，显式保存缩略值并定位内部标题控件：

```swift
let fullSessionID = "019df220-aaaa-bbbb-cccc-ddddeeeeffff"
let compactSessionID = "019df220...eeefff"
```

在取得 `row` 与 `copyButton` 后加入：

```swift
let sessionIDLabel = try textField(withString: compactSessionID, in: row)

#expect(copyButton.title == compactSessionID)
#expect(sessionIDLabel.frame.width >= sessionIDLabel.fittingSize.width)
```

保留原有完整 ID 不直接出现在普通标签中、复制图标存在、点击后剪贴板得到完整 ID 等断言。该新增断言验证用户实际能看到文本，而不是只验证按钮模型保存了标题。

- [ ] **Step 2: 运行单条测试并确认 RED**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' '-only-testing:TokenWatchTests/DashboardSessionPaginationTests/dashboardSessionRowDisplaysCompactIDCopiesFullIDAndCleansProject()' -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData test
```

Expected: `dashboardSessionRowDisplaysCompactIDCopiesFullIDAndCleansProject()` 因 `sessionIDLabel.frame.width` 小于 `sessionIDLabel.fittingSize.width` 而 FAIL；不能接受编译错误、签名错误或测试未被发现作为 RED 证据。

- [ ] **Step 3: 实现最小布局修复**

在 `makeSessionIDCell` 的约束数组中只修改复制按钮尾部约束：

```swift
NSLayoutConstraint.activate([
    cell.widthAnchor.constraint(equalToConstant: width),
    copyButton.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
    copyButton.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
    copyButton.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
    copyButton.heightAnchor.constraint(equalToConstant: 24),
])
```

不要改变缩略算法、按钮样式、图标、tooltip、辅助功能标识或复制 action。

- [ ] **Step 4: 重跑单条测试并确认 GREEN**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' '-only-testing:TokenWatchTests/DashboardSessionPaginationTests/dashboardSessionRowDisplaysCompactIDCopiesFullIDAndCleansProject()' -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData test
```

Expected: `** TEST SUCCEEDED **`；缩略 ID 布局断言、复制图标和完整 ID 剪贴板断言全部通过。

- [ ] **Step 5: 运行会话列表相关测试**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' '-only-testing:TokenWatchTests/DashboardSessionPaginationTests' -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData test
```

Expected: `DashboardSessionPaginationTests` 全部通过，分页、日期过滤、横向滚动布局与复制行为没有回归。

- [ ] **Step 6: 运行完整单元测试和 Debug 构建**

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

- [ ] **Step 7: 检查变更并提交实现**

Run:

```bash
git diff --check
git diff -- TokenWatchTests/ViewControllers/DashboardSessionPaginationTests.swift TokenWatch/ViewControllers/DashboardViewController.swift
git status --short
```

Expected: 只有上述测试与生产文件发生实现变更，`git diff --check` 无输出。

Commit:

```bash
git add TokenWatchTests/ViewControllers/DashboardSessionPaginationTests.swift TokenWatch/ViewControllers/DashboardViewController.swift
git commit -m "fix(dashboard): 修复会话 ID 列文本不可见"
```
