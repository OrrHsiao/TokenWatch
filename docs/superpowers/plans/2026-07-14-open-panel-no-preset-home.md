# 文件选择器取消预设用户目录实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 取消 TokenWatch 对 `NSOpenPanel` 初始目录的预设，让用户通过标准目录选择器主动选择授权位置。

**Architecture:** 将授权面板创建和配置集中到 `SecurityScopedBookmarkManager.makeOpenPanel(language:)` 和 `configureOpenPanel(_:language:)`，由测试验证 TokenWatch 的配置过程不会覆盖系统管理的 `directoryURL`。删除 `UsageProvider` 及三个实现中失去用途的默认目录属性，不改变共享 bookmark、扫描路径或授权时机。

**Tech Stack:** Swift、AppKit `NSOpenPanel`、Swift Testing、Xcode/macOS App Sandbox

## Global Constraints

- 保留现有 App Sandbox、只读 User Selected Files 和 security-scoped bookmark 流程。
- 不拆分 Claude、Codex、OpenCode 的共享 Home Folder bookmark。
- 不修改首次启动授权时机、界面文案、数据扫描路径或历史 bookmark 兼容性。
- 核心公共方法必须有说明作用、参数和返回值的注释。

---

### Task 1: 取消授权面板的初始目录预设

**Files:**
- Modify: `TokenWatchTests/Services/SecurityScopedBookmarkManagerTests.swift`
- Modify: `TokenWatchTests/Providers/ProviderRegistryTests.swift:25-29,50-54`
- Modify: `TokenWatchTests/ViewModels/TokenStatsViewModelObserverTests.swift:352-403`
- Modify: `TokenWatch/Services/SecurityScopedBookmarkManager.swift:93-141`
- Modify: `TokenWatch/Providers/UsageProvider.swift:3-25`
- Modify: `TokenWatch/Providers/Claude/ClaudeProvider.swift:5-11`
- Modify: `TokenWatch/Providers/Codex/CodexProvider.swift:5-11`
- Modify: `TokenWatch/Providers/OpenCode/OpenCodeProvider.swift:5-12`

**Interfaces:**
- Consumes: `AppLanguage`、`AppLanguageSettings.shared.resolvedLanguage`、`UsageProvider.bookmarkKey`。
- Produces: `@MainActor static func makeOpenPanel(language: AppLanguage) -> NSOpenPanel` 和 `@MainActor static func configureOpenPanel(_:language:)`，配置目录单选面板但不覆盖系统管理的 `directoryURL`。

- [x] **Step 1: 写入失败测试**

在 `SecurityScopedBookmarkManagerTests` 顶部添加 `import AppKit`，并添加：

```swift
@MainActor
@Test("授权面板配置不覆盖系统初始目录")
func openPanelConfigurationPreservesSystemDirectory() {
    let panel = NSOpenPanel()
    panel.directoryURL = FileManager.default.temporaryDirectory

    SecurityScopedBookmarkManager.configureOpenPanel(panel, language: .en)

    #expect(panel.directoryURL == FileManager.default.temporaryDirectory)
    #expect(panel.canChooseDirectories)
    #expect(!panel.canChooseFiles)
    #expect(!panel.allowsMultipleSelection)
}
```

- [x] **Step 2: 运行目标测试并确认 RED**

运行：

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:'TokenWatchTests/SecurityScopedBookmarkManagerTests/openPanelConfigurationPreservesSystemDirectory()' -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData test
```

预期：编译失败，提示 `SecurityScopedBookmarkManager` 没有 `configureOpenPanel` 成员；失败原因必须是待实现接口缺失。

- [x] **Step 3: 实现最小面板工厂**

在 `SecurityScopedBookmarkManager` 中保留 `openPanelCopy(language:)`，并在其后添加：

```swift
/// 创建未预设初始目录的标准授权面板。
/// - Parameter language: 面板提示文案使用的语言。
/// - Returns: 仅允许用户单选目录的 `NSOpenPanel`。
static func makeOpenPanel(language: AppLanguage) -> NSOpenPanel {
    let panel = NSOpenPanel()
    configureOpenPanel(panel, language: language)
    return panel
}

/// 配置标准授权面板，不覆盖系统管理的初始目录。
/// - Parameters:
///   - panel: 待配置的目录选择面板。
///   - language: 面板提示文案使用的语言。
static func configureOpenPanel(_ panel: NSOpenPanel, language: AppLanguage) {
    let copy = openPanelCopy(language: language)
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.message = copy.message
    panel.prompt = copy.prompt
    panel.showsHiddenFiles = true
    panel.treatsFilePackagesAsDirectories = true
}
```

将 `promptUserToSelectDirectory(forProvider:)` 的面板初始化替换为：

```swift
let panel = Self.makeOpenPanel(language: AppLanguageSettings.shared.resolvedLanguage)
```

并删除该方法内计算 `provider.defaultDirectoryPath`、检查目录和设置 `panel.directoryURL` 的代码。将方法注释改为“通过 NSOpenPanel 让用户主动选择授权目录”。

- [x] **Step 4: 删除失去用途的默认目录接口**

从 `ProviderAuthorization` 删除：

```swift
static let homeDirectoryPath = FileManager.default.homeDirectoryForCurrentUser.path
```

从 `UsageProvider` 删除：

```swift
/// NSOpenPanel 默认定位目录（绝对路径）
var defaultDirectoryPath: String { get }
```

并从 `ClaudeProvider`、`CodexProvider`、`OpenCodeProvider` 各删除：

```swift
let defaultDirectoryPath = ProviderAuthorization.homeDirectoryPath
```

从 `ProviderRegistryTests` 删除验证旧默认目录接口的 `defaultDirectoriesUseHomeDirectory()` 和 `openCodeDefaultDirectory()`；保留共享 bookmark、授权提示和各 provider 扫描 Home Folder 子目录的测试。

从 `TokenStatsViewModelObserverTests` 的三个 `UsageProvider` stub 删除失去协议用途的 `defaultDirectoryPath` 存储属性。

- [x] **Step 5: 运行目标测试并确认 GREEN**

运行：

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:'TokenWatchTests/SecurityScopedBookmarkManagerTests/openPanelConfigurationPreservesSystemDirectory()' -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData test
```

预期：目标测试通过，`** TEST SUCCEEDED **`。

- [x] **Step 6: 运行全部单元测试**

运行：

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData test
```

预期：全部单元测试通过，`** TEST SUCCEEDED **`。

- [x] **Step 7: 执行静态检查与 Release 构建**

运行：

```bash
rg -n "directoryURL\\s*=" TokenWatch
rg -n "defaultDirectoryPath|homeDirectoryPath" TokenWatch TokenWatchTests
```

预期：无匹配。

运行：

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Release -derivedDataPath .build/DerivedData build
```

预期：构建成功，`** BUILD SUCCEEDED **`。

- [x] **Step 8: 提交实现**

```bash
git add TokenWatchTests/Services/SecurityScopedBookmarkManagerTests.swift TokenWatchTests/Providers/ProviderRegistryTests.swift TokenWatchTests/ViewModels/TokenStatsViewModelObserverTests.swift TokenWatch/Services/SecurityScopedBookmarkManager.swift TokenWatch/Providers/UsageProvider.swift TokenWatch/Providers/Claude/ClaudeProvider.swift TokenWatch/Providers/Codex/CodexProvider.swift TokenWatch/Providers/OpenCode/OpenCodeProvider.swift
git commit -m "fix(sandbox): 取消授权面板预设用户目录"
```
