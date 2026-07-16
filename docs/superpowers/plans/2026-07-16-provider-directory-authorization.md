# Provider 独立数据目录授权 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 彻底移除首次启动与共享 Home Folder 授权语义，让 Claude Code、Codex 和 opencode 只在用户明确点击后分别选择并读取自己的数据根目录。

**Architecture:** `UsageProvider` 为每个数据源声明独立 bookmark key 和面板文案 key，所选 URL 直接作为 provider 数据根。`SecurityScopedBookmarkManager` 用显式结果类型区分取消、成功和持久化失败，并通过可注入的 resolver、resource accessor 与 panel presenter 验证完整 bookmark 生命周期。`TokenStatsViewModel` 维护 provider 独立的目录状态、授权错误和数据状态；设置页从该状态渲染三行控件。启动协调器只能清理旧 Home 状态并加载数据，接口层面不再具备弹出授权面板的能力。

**Tech Stack:** Swift 6、AppKit `NSOpenPanel`、macOS App Sandbox、security-scoped bookmark、Swift Testing、XCTest UI Testing、OSLog、Xcode 26.5

## Global Constraints

- 本计划必须先于 `2026-07-16-support-page-and-review-deliverables.md` 执行；后者依赖这里最终确定的目录语义和验证结果。
- 保持 `ENABLE_APP_SANDBOX = YES`、`ENABLE_USER_SELECTED_FILES = readonly` 和 `ENABLE_OUTGOING_NETWORK_CONNECTIONS = NO`，不编辑 entitlement 或 `project.pbxproj`。
- 不设置 `NSOpenPanel.directoryURL`，不调用 `homeDirectoryForCurrentUser`，不提供 Home 快捷预设，也不在可见文案中使用 Home Folder、用户目录或共享目录授权语义。
- 最终验收时，`HomeDirectoryBookmark` 和 `TokenWatch.didPromptInitialHomeAuthorization` 只允许作为 `LegacyAuthorizationCleaner` 的遗留清理常量出现；不得恢复、解析、迁移或作为活跃授权 key。Task 1–5 的迁移窗口仅允许未改设置页继续编译所需的既有 `ProviderAuthorization.homeBookmarkKey` 引用：不得新增引用，Task 5 删除启动引用，Task 6 删除设置引用和该 enum。
- 用户取消或重新选择失败时，不改变当前 provider 的 bookmark、stats、entries、fingerprint 或目录状态。
- bookmark 恢复、stale 刷新或 `startAccessingSecurityScopedResource()` 失败时，只清除当前 provider 的 bookmark 和数据；其他 provider 保持可用。
- “未发现数据”以 `entries.isEmpty` 判断，不能以 token 总量为零判断；空数据仍是已选择状态，不是授权失败。
- 同一 provider 正在加载时不得打开授权面板；授权面板处于活动状态时，该 provider 的自动刷新必须跳过，避免旧目录结果覆盖新授权。
- 核心公共方法补充作用、参数和返回值注释；bookmark 保存、恢复、清理及授权状态变化记录简洁日志。
- 每个行为先写失败测试，再写最小实现。macOS app-hosted `test` 若遇到 `testmanagerd` 沙盒限制，必须申请提升权限；`build-for-testing` 只能作为编译检查，不能代替 GREEN。
- 所有测试和构建使用 `-derivedDataPath .build/DerivedData`。提交信息使用中文 `<type>(<scope>): <summary>`，一个 commit 只承载一个 task。

---

## 文件职责

### 生产代码

- `TokenWatch/Providers/UsageProvider.swift`：移除 provider 对共享 Home 配置的依赖，声明独立 bookmark 和面板文案契约；旧 key 常量在 Task 6 最终删除。
- `TokenWatch/Providers/Claude/ClaudeProvider.swift`、`Codex/CodexProvider.swift`、`OpenCode/OpenCodeProvider.swift`：直接读取所选数据根。
- `TokenWatch/Services/BookmarkPersistence.swift`：定义可测试的 bookmark 创建、解析、存储和 security-scope 访问适配层。
- `TokenWatch/Services/SecurityScopedBookmarkManager.swift`：provider-aware 面板、事务式替换、恢复和资源配对释放。
- `TokenWatch/ViewModels/TokenStatsViewModel.swift`：provider 独立目录状态、授权错误、加载与并发门禁。
- `TokenWatch/AppDelegate.swift`：删除首次授权分支；启动只清理遗留状态并加载。
- `TokenWatch/ViewController.swift`：设置页三行数据文件夹控件及 provider 状态绑定。
- `TokenWatch/ViewControllers/DashboardViewController.swift`：移除总览和会话页的 Home Folder 提示。
- `TokenWatch/Localization/AppStrings.swift`：目录状态、按钮、面板、错误和总览提示的 12 语言文案。
- `README.md`、`README.zh-CN.md`：同步安装、首次运行、数据根与隐私说明；Support URL 由后续支持页计划在真实上线后加入，避免本计划独立完成时产生 404 链接。

### 测试代码

- `TokenWatchTests/Providers/ProviderRegistryTests.swift`
- `TokenWatchTests/Services/BookmarkPersistenceTests.swift`
- `TokenWatchTests/Services/SecurityScopedBookmarkManagerTests.swift`
- `TokenWatchTests/ViewModels/TokenStatsViewModelObserverTests.swift`
- `TokenWatchTests/TokenWatchTests.swift`
- `TokenWatchTests/ViewControllers/DashboardSessionPaginationTests.swift`
- `TokenWatchTests/Localization/AppLanguageSettingsTests.swift`
- `TokenWatchUITests/TokenWatchUITests.swift`
- `TokenWatchUITests/TokenWatchUITestsLaunchTests.swift`

`TokenWatch.xcodeproj` 使用 filesystem-synchronized groups，本计划不新增工程引用，也不编辑工程文件。

---

### Task 1: 改成 provider 独立 bookmark 与直接数据根

**Files:**
- Modify: `TokenWatch/Providers/UsageProvider.swift:3-32`
- Modify: `TokenWatch/Providers/Claude/ClaudeProvider.swift:5-23`
- Modify: `TokenWatch/Providers/Codex/CodexProvider.swift:5-38`
- Modify: `TokenWatch/Providers/OpenCode/OpenCodeProvider.swift:5-29`
- Modify: `TokenWatch/Localization/AppStrings.swift:8-148,185-1875`
- Modify: `TokenWatchTests/Providers/ProviderRegistryTests.swift:19-120`
- Modify: `TokenWatchTests/ViewModels/TokenStatsViewModelObserverTests.swift:352-427`

**Interfaces:**
- Produces: `UsageProvider.openPanelMessageKey: AppStringKey`。
- Produces exact bookmark keys: `ClaudeDataDirectoryBookmark`、`CodexDataDirectoryBookmark`、`OpenCodeDataDirectoryBookmark`。
- Changes: `loadEntries(from:)` 的 URL 从 Home 变为用户直接选择的 provider 数据根。

- [ ] **Step 1: 把注册表和根目录测试改成新契约**

在 `ProviderRegistryTests` 删除共享 Home key、共享 Home 文案和 Home 子目录 fixture 测试，写入以下 RED 契约：

```swift
@Test("每个 provider 使用固定且互不相同的 bookmark key")
func bookmarkKeysAreIndependent() {
    let expected: [ProviderID: String] = [
        .claude: "ClaudeDataDirectoryBookmark",
        .codex: "CodexDataDirectoryBookmark",
        .opencode: "OpenCodeDataDirectoryBookmark",
    ]

    #expect(Dictionary(uniqueKeysWithValues: ProviderRegistry.allProviders.map {
        ($0.id, $0.bookmarkKey)
    }) == expected)
}

@Test("provider 面板文案互相独立且没有 Home 语义")
func openPanelMessagesAreProviderSpecificAndAvoidHomeSemantics() {
    let messages = ProviderRegistry.allProviders.map {
        AppStrings.text($0.openPanelMessageKey, language: .en)
    }

    #expect(Set(messages) == [
        "Choose the Claude Code data folder",
        "Choose the Codex data folder",
        "Choose the opencode data folder",
    ])
    #expect(messages.allSatisfy {
        !$0.localizedCaseInsensitiveContains("home")
    })
}
```

把三个既有 fixture 改为直接根：

```swift
@Test("Claude provider 从用户选择的数据根读取 projects")
func claudeLoadsFromSelectedDataRoot() throws {
    let root = try makeTempDataRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let projects = root.appendingPathComponent("projects/-tmp-project", isDirectory: true)
    try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
    try claudeUsageLine.write(
        to: projects.appendingPathComponent("session.jsonl"),
        atomically: true,
        encoding: .utf8
    )

    let entries = try ClaudeProvider().loadEntries(from: root)

    #expect(entries.count == 1)
    #expect(entries.first?.messageId == "claude-msg")
}

@Test("Codex provider 从用户选择的数据根读取 sessions 与根部配置")
func codexLoadsFromSelectedDataRoot() throws {
    let root = try makeTempDataRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let sessions = root.appendingPathComponent("sessions/2026/05/04", isDirectory: true)
    try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
    let file = sessions.appendingPathComponent(
        "rollout-2026-05-04T16-35-18-019df220-aaaa-bbbb-cccc-ddddeeeeffff.jsonl"
    )
    try [codexSessionMeta, codexTurnContext, codexTokenEvent]
        .joined(separator: "\n")
        .write(to: file, atomically: true, encoding: .utf8)
    try "service_tier = \"fast\"\n".write(
        to: root.appendingPathComponent("config.toml"),
        atomically: true,
        encoding: .utf8
    )

    let entries = try CodexProvider().loadEntries(from: root)

    #expect(entries.count == 1)
    #expect(entries.first?.messageId == "019df220-aaaa-bbbb-cccc-ddddeeeeffff:2026-05-04T08:35:59.868Z")
    #expect(entries.first?.usage.serviceTier == "fast")
}

@Test("opencode provider 从用户选择的数据根读取数据库")
func openCodeLoadsFromSelectedDataRoot() throws {
    let root = try makeTempDataRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try buildMiniOpenCodeDB(at: root.appendingPathComponent("opencode.db"))

    let entries = try OpenCodeProvider().loadEntries(from: root)

    #expect(entries.count == 1)
    #expect(entries.first?.messageId == "opencode-msg")
}
```

将 helper `makeTempHome()` 精确替换为：

```swift
private func makeTempDataRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("provider-data-root-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}
```

三个 ViewModel 测试 provider stub 中删除 `let openPanelMessage = "Select a folder"`，逐个加入：

```swift
let openPanelMessageKey: AppStringKey = .claudeDataDirectoryOpenPanelMessage
```

若 stub 的 `id` 可变，则使用下列 computed property，避免把 Codex/opencode fake 错绑为 Claude：

```swift
var openPanelMessageKey: AppStringKey {
    switch id {
    case .claude: .claudeDataDirectoryOpenPanelMessage
    case .codex: .codexDataDirectoryOpenPanelMessage
    case .opencode: .openCodeDataDirectoryOpenPanelMessage
    }
}
```

- [ ] **Step 2: 运行定向测试并确认 RED**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch \
  -destination 'platform=macOS' \
  '-only-testing:TokenWatchTests/ProviderRegistryTests/bookmarkKeysAreIndependent()' \
  '-only-testing:TokenWatchTests/ProviderRegistryTests/openPanelMessagesAreProviderSpecificAndAvoidHomeSemantics()' \
  '-only-testing:TokenWatchTests/ProviderRegistryTests/claudeLoadsFromSelectedDataRoot()' \
  '-only-testing:TokenWatchTests/ProviderRegistryTests/codexLoadsFromSelectedDataRoot()' \
  '-only-testing:TokenWatchTests/ProviderRegistryTests/openCodeLoadsFromSelectedDataRoot()' \
  -skip-testing:TokenWatchUITests \
  -derivedDataPath .build/DerivedData test
```

Expected: FAIL；当前协议没有 `openPanelMessageKey`，key 仍全部为 `HomeDirectoryBookmark`，fixture 没有 `.claude`、`.codex`、`.local/share/opencode` 包装层时旧 provider 读不到数据。

- [ ] **Step 3: 实现新的 provider 契约**

从 `ProviderAuthorization` 删除 `homeAccessMessage`，但暂时保留仅供旧启动/设置代码编译的 `homeBookmarkKey`；三个 provider 从本 Task 起不得再引用它。Task 5 删除启动引用，Task 6 删除设置引用后再删除整个 enum。把协议的 Home 说明改为：

```swift
protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    var displayName: String { get }
    var bookmarkKey: String { get }
    var openPanelMessageKey: AppStringKey { get }
    var hasCacheWriteDimension: Bool { get }
    var hasReasoningDimension: Bool { get }

    /// 从用户直接选择的 provider 数据根目录读取用量。
    /// - Parameter dataRootURL: 已通过当前 provider bookmark 恢复访问的数据根。
    /// - Returns: 解析并去重后的统一用量条目。
    func loadEntries(from dataRootURL: URL) throws -> [ParsedUsageEntry]
}
```

三个 provider 使用下列固定配置：

```swift
// ClaudeProvider
let bookmarkKey = "ClaudeDataDirectoryBookmark"
let openPanelMessageKey: AppStringKey = .claudeDataDirectoryOpenPanelMessage

// CodexProvider
let bookmarkKey = "CodexDataDirectoryBookmark"
let openPanelMessageKey: AppStringKey = .codexDataDirectoryOpenPanelMessage

// OpenCodeProvider
let bookmarkKey = "OpenCodeDataDirectoryBookmark"
let openPanelMessageKey: AppStringKey = .openCodeDataDirectoryOpenPanelMessage
```

三个 loader 不再追加隐藏 Home 子路径：

```swift
// ClaudeProvider.loadEntries
let files = try scanner.scanAllJSONLFiles(in: dataRootURL)
return try parser.parseAllFiles(files, claudeDataRoot: dataRootURL)

// CodexProvider.loadEntries
let files = try scanner.scanAll(in: dataRootURL)
let speed = serviceTierResolver.pricingSpeed(at: dataRootURL)
return try parser.parseAllFiles(files, pricingSpeed: speed)

// OpenCodeProvider.loadEntries
let rows = try scanner.scanAll(in: dataRootURL)
return parser.parseAll(rows)
```

在 `AppStringKey` 增加三个 provider 面板 key；先在全部 12 个表加入对应翻译，Task 6 再一次性增加其余目录 UI key。英文固定为测试中的三句，不能包含 `home` 或 `user directory`。

- [ ] **Step 4: 运行定向测试并确认 GREEN**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch \
  -destination 'platform=macOS' \
  '-only-testing:TokenWatchTests/ProviderRegistryTests/bookmarkKeysAreIndependent()' \
  '-only-testing:TokenWatchTests/ProviderRegistryTests/openPanelMessagesAreProviderSpecificAndAvoidHomeSemantics()' \
  '-only-testing:TokenWatchTests/ProviderRegistryTests/claudeLoadsFromSelectedDataRoot()' \
  '-only-testing:TokenWatchTests/ProviderRegistryTests/codexLoadsFromSelectedDataRoot()' \
  '-only-testing:TokenWatchTests/ProviderRegistryTests/openCodeLoadsFromSelectedDataRoot()' \
  -skip-testing:TokenWatchUITests \
  -derivedDataPath .build/DerivedData test
```

Expected: PASS，`** TEST SUCCEEDED **`。

- [ ] **Step 5: 提交 provider 根目录变更**

```bash
git add TokenWatch/Providers/UsageProvider.swift \
  TokenWatch/Providers/Claude/ClaudeProvider.swift \
  TokenWatch/Providers/Codex/CodexProvider.swift \
  TokenWatch/Providers/OpenCode/OpenCodeProvider.swift \
  TokenWatch/Localization/AppStrings.swift \
  TokenWatchTests/Providers/ProviderRegistryTests.swift \
  TokenWatchTests/ViewModels/TokenStatsViewModelObserverTests.swift
git commit -m "fix(provider): 按数据源使用独立目录根"
```

---

### Task 2: 区分面板取消、成功和持久化失败

**Files:**
- Modify: `TokenWatch/Services/BookmarkPersistence.swift:3-42`
- Modify: `TokenWatch/Services/SecurityScopedBookmarkManager.swift:5-169`
- Modify: `TokenWatch/Localization/AppStrings.swift:8-148,185-1875`
- Modify: `TokenWatch/ViewModels/TokenStatsViewModel.swift:232-246`
- Modify: `TokenWatchTests/Services/BookmarkPersistenceTests.swift:5-92`
- Modify: `TokenWatchTests/Services/SecurityScopedBookmarkManagerTests.swift:25-82`
- Modify: `TokenWatchTests/ViewModels/TokenStatsViewModelObserverTests.swift:458-480`

**Interfaces:**
- Produces: `DirectoryAuthorizationResult.authorized(URL) | .cancelled | .failed`。
- Produces: `DirectoryPanelPresenting.chooseDirectory(for:language:) async -> URL?`。
- Changes: `BookmarkAccessManaging.promptUserToSelectDirectory` 返回显式结果。
- Strengthens: `BookmarkDataStoring.save` 返回 `false` 时必须保留调用前的值。

- [ ] **Step 1: 写入取消、重新选择失败和 provider 面板测试**

在 `BookmarkPersistenceTests` 把原有只使用空 store 的失败测试替换为预置旧数据的事务测试：

```swift
@Test("重新选择时 bookmark 创建失败会保留旧数据")
func reselectionCreationFailureKeepsExistingBookmark() {
    let oldData = Data([1, 2, 3])
    let store = InMemoryBookmarkStore(values: ["bookmark": oldData])
    let manager = SecurityScopedBookmarkManager(
        bookmarkDataCreator: ThrowingBookmarkDataCreator(),
        bookmarkStore: store
    )

    #expect(!manager.persistSelectedDirectory(
        URL(fileURLWithPath: "/replacement", isDirectory: true),
        forKey: "bookmark"
    ))
    #expect(store.data(forKey: "bookmark") == oldData)
}

@Test("重新选择时 bookmark 保存失败会保留旧数据")
func reselectionSaveFailureKeepsExistingBookmark() {
    let oldData = Data([4, 5, 6])
    let store = RejectingBookmarkStore(values: ["bookmark": oldData])
    let manager = SecurityScopedBookmarkManager(
        bookmarkDataCreator: FixedBookmarkDataCreator(data: Data([7, 8, 9])),
        bookmarkStore: store
    )

    #expect(!manager.persistSelectedDirectory(
        URL(fileURLWithPath: "/replacement", isDirectory: true),
        forKey: "bookmark"
    ))
    #expect(store.data(forKey: "bookmark") == oldData)
}
```

在 `SecurityScopedBookmarkManagerTests` 增加：

```swift
@MainActor
@Test("选择目录成功会写入目标 provider key 并返回 URL")
func successfulSelectionPersistsProviderBookmarkAndReturnsURL() async {
    let key = "CodexDataDirectoryBookmark"
    let selectedURL = URL(fileURLWithPath: "/chosen-codex", isDirectory: true)
    let bookmarkData = Data([7, 8, 9])
    let store = ManagerBookmarkStore()
    let presenter = RecordingDirectoryPresenter(selection: selectedURL)
    let manager = SecurityScopedBookmarkManager(
        bookmarkDataCreator: FixedManagerBookmarkDataCreator(data: bookmarkData),
        bookmarkStore: store,
        directoryPresenter: presenter,
        languageProvider: { .en }
    )

    let result = await manager.promptUserToSelectDirectory(
        forProvider: CodexProvider()
    )

    #expect(result == .authorized(selectedURL))
    #expect(store.data(forKey: key) == bookmarkData)
    #expect(presenter.requestedProviderIDs == [.codex])
}

@MainActor
@Test("选择目录后保存失败会返回 failed 并保留旧 bookmark")
func selectedDirectoryPersistenceFailureReturnsFailedAndKeepsOldBookmark() async {
    let key = "ClaudeDataDirectoryBookmark"
    let oldData = Data([1, 2, 3])
    let selectedURL = URL(fileURLWithPath: "/replacement", isDirectory: true)
    let store = RejectingManagerBookmarkStore(values: [key: oldData])
    let manager = SecurityScopedBookmarkManager(
        bookmarkDataCreator: FixedManagerBookmarkDataCreator(data: Data([4, 5, 6])),
        bookmarkStore: store,
        directoryPresenter: RecordingDirectoryPresenter(selection: selectedURL),
        languageProvider: { .en }
    )

    let result = await manager.promptUserToSelectDirectory(
        forProvider: ClaudeProvider()
    )

    #expect(result == .failed)
    #expect(store.data(forKey: key) == oldData)
}

@MainActor
@Test("取消目录面板不会写入或替换 bookmark")
func cancellationDoesNotWriteOrReplaceBookmark() async {
    let key = "ClaudeDataDirectoryBookmark"
    let oldData = Data([1])
    let store = ManagerBookmarkStore(values: [key: oldData])
    let manager = SecurityScopedBookmarkManager(
        bookmarkStore: store,
        directoryPresenter: RecordingDirectoryPresenter(selection: nil),
        languageProvider: { .en }
    )

    let result = await manager.promptUserToSelectDirectory(
        forProvider: ClaudeProvider()
    )

    #expect(result == .cancelled)
    #expect(store.data(forKey: key) == oldData)
}

@MainActor
@Test("面板使用 provider 文案且不改系统初始目录")
func panelConfigurationUsesProviderCopyAndPreservesSystemDirectory() {
    let panel = NSOpenPanel()
    panel.directoryURL = FileManager.default.temporaryDirectory

    SecurityScopedBookmarkManager.configureOpenPanel(
        panel,
        for: CodexProvider(),
        language: .en
    )

    #expect(panel.directoryURL == FileManager.default.temporaryDirectory)
    #expect(panel.message == "Choose the Codex data folder")
    #expect(panel.prompt == "Choose")
    #expect(panel.canChooseDirectories)
    #expect(!panel.canChooseFiles)
    #expect(!panel.allowsMultipleSelection)
    #expect(panel.showsHiddenFiles)
    #expect(panel.treatsFilePackagesAsDirectories)
}
```

删除旧 `openPanelCopyUsesCurrentLanguage()`，并用 provider 参数分别断言 Claude/Codex/opencode 文案；旧 `openPanelConfigurationPreservesSystemDirectory()` 由上面的 provider-aware 测试完整替换。不得留下调用 `openPanelCopy(language:)` 或 `configureOpenPanel(_:language:)` 的旧测试，否则本 Task 的 commit 无法编译。

把 `BookmarkPersistenceTests.swift` 底部的两个 store helper 替换为以下事务式版本；`RejectingBookmarkStore.save` 返回 `false` 且不修改 `values`：

```swift
private final class InMemoryBookmarkStore: BookmarkDataStoring, @unchecked Sendable {
    private var values: [String: Data]

    init(values: [String: Data] = [:]) {
        self.values = values
    }

    func data(forKey key: String) -> Data? { values[key] }

    func save(_ data: Data, forKey key: String) -> Bool {
        values[key] = data
        return true
    }

    func removeData(forKey key: String) { values[key] = nil }
}

private final class RejectingBookmarkStore: BookmarkDataStoring, @unchecked Sendable {
    private var values: [String: Data]

    init(values: [String: Data] = [:]) {
        self.values = values
    }

    func data(forKey key: String) -> Data? { values[key] }
    func save(_ data: Data, forKey key: String) -> Bool { false }
    func removeData(forKey key: String) { values[key] = nil }
}
```

在 `SecurityScopedBookmarkManagerTests.swift` 底部把 `ManagerBookmarkStore` 的 initializer 改为 `init(values: [String: Data] = [:])`，并加入以下完整 fake；Task 3 继续复用这些类型：

```swift
private enum ManagerBookmarkFixtureError: Error {
    case creationFailed
}

private struct FixedManagerBookmarkDataCreator: BookmarkDataCreating {
    let data: Data
    func createBookmarkData(for url: URL) throws -> Data { data }
}

private struct ThrowingManagerBookmarkDataCreator: BookmarkDataCreating {
    func createBookmarkData(for url: URL) throws -> Data {
        throw ManagerBookmarkFixtureError.creationFailed
    }
}

@MainActor
private final class RecordingDirectoryPresenter: DirectoryPanelPresenting {
    let selection: URL?
    private(set) var requestedProviderIDs: [ProviderID] = []

    init(selection: URL?) {
        self.selection = selection
    }

    func chooseDirectory(
        for provider: any UsageProvider,
        language: AppLanguage
    ) async -> URL? {
        requestedProviderIDs.append(provider.id)
        return selection
    }
}

private final class RejectingManagerBookmarkStore: BookmarkDataStoring, @unchecked Sendable {
    private var values: [String: Data]
    private(set) var removedKeys: [String] = []

    init(values: [String: Data] = [:]) {
        self.values = values
    }

    func data(forKey key: String) -> Data? { values[key] }
    func save(_ data: Data, forKey key: String) -> Bool { false }

    func removeData(forKey key: String) {
        values[key] = nil
        removedKeys.append(key)
    }
}
```

- [ ] **Step 2: 运行测试并确认 RED**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch \
  -destination 'platform=macOS' \
  '-only-testing:TokenWatchTests/BookmarkPersistenceTests/reselectionCreationFailureKeepsExistingBookmark()' \
  '-only-testing:TokenWatchTests/BookmarkPersistenceTests/reselectionSaveFailureKeepsExistingBookmark()' \
  '-only-testing:TokenWatchTests/SecurityScopedBookmarkManagerTests/successfulSelectionPersistsProviderBookmarkAndReturnsURL()' \
  '-only-testing:TokenWatchTests/SecurityScopedBookmarkManagerTests/selectedDirectoryPersistenceFailureReturnsFailedAndKeepsOldBookmark()' \
  '-only-testing:TokenWatchTests/SecurityScopedBookmarkManagerTests/cancellationDoesNotWriteOrReplaceBookmark()' \
  '-only-testing:TokenWatchTests/SecurityScopedBookmarkManagerTests/panelConfigurationUsesProviderCopyAndPreservesSystemDirectory()' \
  -skip-testing:TokenWatchUITests \
  -derivedDataPath .build/DerivedData test
```

Expected: FAIL；当前没有显式结果、panel presenter 或 provider-aware 配置接口，保存方法返回 `URL?`。

- [ ] **Step 3: 定义显式授权结果与可注入面板**

在 `SecurityScopedBookmarkManager.swift` 增加：

```swift
enum DirectoryAuthorizationResult: Sendable, Equatable {
    case authorized(URL)
    case cancelled
    case failed
}

@MainActor
protocol DirectoryPanelPresenting: Sendable {
    /// 显示 provider 专属目录面板。
    /// - Returns: 用户确认的目录；取消时返回 nil。
    func chooseDirectory(
        for provider: any UsageProvider,
        language: AppLanguage
    ) async -> URL?
}

@MainActor
struct OpenPanelDirectoryPresenter: DirectoryPanelPresenting {
    func chooseDirectory(
        for provider: any UsageProvider,
        language: AppLanguage
    ) async -> URL? {
        await withCheckedContinuation { continuation in
            let panel = SecurityScopedBookmarkManager.makeOpenPanel(
                for: provider,
                language: language
            )
            panel.begin { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
        }
    }
}
```

将 `BookmarkAccessManaging` 的 prompt 签名改为：

```swift
func promptUserToSelectDirectory(
    forProvider provider: any UsageProvider
) async -> DirectoryAuthorizationResult
```

Manager 增加 stored properties，并把 initializer 精确替换为以下签名；默认分别为 `OpenPanelDirectoryPresenter()` 和当前 app language：

```swift
private let directoryPresenter: any DirectoryPanelPresenting
private let languageProvider: @MainActor () -> AppLanguage

init(
    bookmarkDataCreator: any BookmarkDataCreating = SecurityScopedBookmarkDataCreator(),
    bookmarkStore: any BookmarkDataStoring = UserDefaultsBookmarkStore(),
    directoryPresenter: any DirectoryPanelPresenting = OpenPanelDirectoryPresenter(),
    languageProvider: @escaping @MainActor () -> AppLanguage = {
        AppLanguageSettings.shared.resolvedLanguage
    }
) {
    self.bookmarkDataCreator = bookmarkDataCreator
    self.bookmarkStore = bookmarkStore
    self.directoryPresenter = directoryPresenter
    self.languageProvider = languageProvider
}
```

面板工厂变为：

```swift
nonisolated static func openPanelCopy(
    for provider: any UsageProvider,
    language: AppLanguage
) -> OpenPanelCopy {
    OpenPanelCopy(
        message: AppStrings.text(provider.openPanelMessageKey, language: language),
        prompt: AppStrings.text(.chooseDirectoryPrompt, language: language)
    )
}

static func makeOpenPanel(
    for provider: any UsageProvider,
    language: AppLanguage
) -> NSOpenPanel {
    let panel = NSOpenPanel()
    configureOpenPanel(panel, for: provider, language: language)
    return panel
}

static func configureOpenPanel(
    _ panel: NSOpenPanel,
    for provider: any UsageProvider,
    language: AppLanguage
) {
    let copy = openPanelCopy(for: provider, language: language)
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.message = copy.message
    panel.prompt = copy.prompt
    panel.showsHiddenFiles = true
    panel.treatsFilePackagesAsDirectories = true
}
```

不得设置 `directoryURL`。Prompt 流程实现为：

```swift
func promptUserToSelectDirectory(
    forProvider provider: any UsageProvider
) async -> DirectoryAuthorizationResult {
    guard let url = await directoryPresenter.chooseDirectory(
        for: provider,
        language: languageProvider()
    ) else {
        return .cancelled
    }
    guard persistSelectedDirectory(url, forKey: provider.bookmarkKey) else {
        logger.error("Bookmark 创建或保存失败: \(provider.bookmarkKey)")
        return .failed
    }
    return .authorized(url)
}
```

`persistSelectedDirectory` 返回 `Bool`，使用以下实现；`BookmarkDataStoring.save` 的协议注释写明“返回 false 时不得改变调用前的值”：

```swift
func persistSelectedDirectory(_ url: URL, forKey key: String) -> Bool {
    do {
        let data = try bookmarkDataCreator.createBookmarkData(for: url)
        guard bookmarkStore.save(data, forKey: key) else {
            logger.error("Bookmark 保存验证失败: \(key)")
            return false
        }
        return true
    } catch {
        logger.error("Bookmark 创建失败: \(error.localizedDescription)")
        return false
    }
}
```

`UserDefaultsBookmarkStore.save` 在回读不一致时恢复调用前的对象或删除新值：

```swift
func save(_ data: Data, forKey key: String) -> Bool {
    let previousValue = defaults.object(forKey: key)
    defaults.set(data, forKey: key)
    guard defaults.data(forKey: key) == data else {
        if let previousValue {
            defaults.set(previousValue, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
        return false
    }
    return true
}
```

本 Task 同时在 `AppStringKey` 和全部 12 个语言表增加 `.chooseDirectoryPrompt`；值使用文末本地化矩阵的 “Choose prompt” 列。Task 2 完成时不得等待 Task 6 才提供该 key。

- [ ] **Step 4: 更新所有 BookmarkAccessManaging fake 并确认 GREEN**

将 `TokenStatsViewModelObserverTests.StubBookmarkManager` 的 `promptSucceeds` 替换为 `promptResult`，initializer 默认 `.authorized(rootURL)`，protocol method 直接返回它：

```swift
private let promptResult: DirectoryAuthorizationResult

init(
    rootURL: URL,
    promptResult: DirectoryAuthorizationResult? = nil
) {
    self.rootURL = rootURL
    self.promptResult = promptResult ?? .authorized(rootURL)
}

func promptUserToSelectDirectory(
    forProvider provider: any UsageProvider
) async -> DirectoryAuthorizationResult {
    promptResult
}
```

把原 `promptSucceeds: false` 的测试调用改为 `promptResult: .failed`。为了让本 Task 独立编译，把当前 `TokenStatsViewModel.requestAuthorization` 的 optional binding 临时改为以下 exhaustive switch；Task 4 会删除共享行为：

```swift
switch await bookmarkManager.promptUserToSelectDirectory(forProvider: provider) {
case .authorized:
    markProvidersAuthorized(sharingBookmarkWith: provider)
    logger.info("\(provider.displayName) 用户授权成功")
    await loadAllStats()
    return true
case .cancelled:
    logger.info("\(provider.displayName) 用户取消授权")
    return false
case .failed:
    logger.error("\(provider.displayName) 目录授权保存失败")
    return false
}
```

运行完整 GREEN 命令：

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch \
  -destination 'platform=macOS' \
  '-only-testing:TokenWatchTests/BookmarkPersistenceTests/reselectionCreationFailureKeepsExistingBookmark()' \
  '-only-testing:TokenWatchTests/BookmarkPersistenceTests/reselectionSaveFailureKeepsExistingBookmark()' \
  '-only-testing:TokenWatchTests/SecurityScopedBookmarkManagerTests/successfulSelectionPersistsProviderBookmarkAndReturnsURL()' \
  '-only-testing:TokenWatchTests/SecurityScopedBookmarkManagerTests/selectedDirectoryPersistenceFailureReturnsFailedAndKeepsOldBookmark()' \
  '-only-testing:TokenWatchTests/SecurityScopedBookmarkManagerTests/cancellationDoesNotWriteOrReplaceBookmark()' \
  '-only-testing:TokenWatchTests/SecurityScopedBookmarkManagerTests/panelConfigurationUsesProviderCopyAndPreservesSystemDirectory()' \
  -skip-testing:TokenWatchUITests \
  -derivedDataPath .build/DerivedData test
```

Expected: PASS。

- [ ] **Step 5: 提交面板与持久化语义**

```bash
git add TokenWatch/Services/BookmarkPersistence.swift \
  TokenWatch/Services/SecurityScopedBookmarkManager.swift \
  TokenWatch/Localization/AppStrings.swift \
  TokenWatch/ViewModels/TokenStatsViewModel.swift \
  TokenWatchTests/Services/BookmarkPersistenceTests.swift \
  TokenWatchTests/Services/SecurityScopedBookmarkManagerTests.swift \
  TokenWatchTests/ViewModels/TokenStatsViewModelObserverTests.swift
git commit -m "fix(bookmark): 区分取消并保留旧目录授权"
```

---

### Task 3: 完整验证 bookmark 恢复、stale 刷新和独立释放

**Files:**
- Modify: `TokenWatch/Services/BookmarkPersistence.swift:3-42`
- Modify: `TokenWatch/Services/SecurityScopedBookmarkManager.swift:24-227`
- Modify: `TokenWatchTests/Services/SecurityScopedBookmarkManagerTests.swift:8-82`

**Interfaces:**
- Consumes from Task 2: `DirectoryAuthorizationResult`、`DirectoryPanelPresenting`、`FixedManagerBookmarkDataCreator`、`ThrowingManagerBookmarkDataCreator`、`ManagerBookmarkStore`、`RejectingManagerBookmarkStore`。
- Produces: `BookmarkDataResolving.resolveBookmarkData(_:) -> ResolvedBookmark`。
- Produces: `SecurityScopedResourceAccessing.startAccessing(_:)` / `stopAccessing(_:)`。
- Preserves: `SecurityScopedAccessSessions` 按 bookmark key 计数；即使两个 key 指向同一物理 URL，也按 provider 独立配对。

- [ ] **Step 1: 写入恢复失败和会话隔离测试**

增加以下 RED 测试；fake resolver 按 Data 映射 URL/stale，fake accessor 记录 start/stop：

```swift
@MainActor
@Test("stale bookmark 刷新失败会停止访问且只清除当前 provider")
func staleRefreshFailureStopsAccessAndClearsOnlyCurrentProvider() {
    let claudeKey = "ClaudeDataDirectoryBookmark"
    let codexKey = "CodexDataDirectoryBookmark"
    let store = ManagerBookmarkStore(values: [
        claudeKey: Data([1]),
        codexKey: Data([2]),
    ])
    let url = URL(fileURLWithPath: "/claude", isDirectory: true)
    let accessor = RecordingResourceAccessor(startResult: true)
    let manager = SecurityScopedBookmarkManager(
        bookmarkDataCreator: ThrowingManagerBookmarkDataCreator(),
        bookmarkDataResolver: FixedBookmarkDataResolver(
            result: .init(url: url, isStale: true)
        ),
        bookmarkStore: store,
        resourceAccessor: accessor
    )

    #expect(manager.restoreBookmarkAndAccess(forKey: claudeKey) == nil)
    #expect(!manager.hasBookmark(forKey: claudeKey))
    #expect(manager.hasBookmark(forKey: codexKey))
    #expect(accessor.stoppedURLs == [url])
}

@MainActor
@Test("startAccess 失败只清除请求的 provider bookmark")
func startAccessFailureClearsOnlyRequestedProviderBookmark() {
    let claudeKey = "ClaudeDataDirectoryBookmark"
    let codexKey = "CodexDataDirectoryBookmark"
    let store = ManagerBookmarkStore(values: [
        claudeKey: Data([1]),
        codexKey: Data([2]),
    ])
    let manager = SecurityScopedBookmarkManager(
        bookmarkDataResolver: FixedBookmarkDataResolver(
            result: .init(
                url: URL(fileURLWithPath: "/claude", isDirectory: true),
                isStale: false
            )
        ),
        bookmarkStore: store,
        resourceAccessor: RecordingResourceAccessor(startResult: false)
    )

    #expect(manager.restoreBookmarkAndAccess(forKey: claudeKey) == nil)
    #expect(!manager.hasBookmark(forKey: claudeKey))
    #expect(manager.hasBookmark(forKey: codexKey))
}

@MainActor
@Test("provider bookmark 会话分别恢复并分别释放")
func providerSessionsRestoreAndStopIndependently() {
    let claudeKey = "ClaudeDataDirectoryBookmark"
    let codexKey = "CodexDataDirectoryBookmark"
    let sharedURL = URL(fileURLWithPath: "/shared", isDirectory: true)
    let resolver = MappingBookmarkDataResolver(values: [
        Data([1]): .init(url: sharedURL, isStale: false),
        Data([2]): .init(url: sharedURL, isStale: false),
    ])
    let accessor = RecordingResourceAccessor(startResult: true)
    let manager = SecurityScopedBookmarkManager(
        bookmarkDataResolver: resolver,
        bookmarkStore: ManagerBookmarkStore(values: [
            claudeKey: Data([1]),
            codexKey: Data([2]),
        ]),
        resourceAccessor: accessor
    )

    #expect(manager.restoreBookmarkAndAccess(forKey: claudeKey) == sharedURL)
    #expect(manager.restoreBookmarkAndAccess(forKey: codexKey) == sharedURL)
    #expect(accessor.startedURLs == [sharedURL, sharedURL])
    manager.stopAccessing(forKey: claudeKey)
    #expect(accessor.stoppedURLs == [sharedURL])
    #expect(manager.restoreBookmarkAndAccess(forKey: codexKey) == sharedURL)
    manager.stopAccessing(forKey: codexKey)
    manager.stopAccessing(forKey: codexKey)
    #expect(accessor.stoppedURLs == [sharedURL, sharedURL])
}

@MainActor
@Test("stale bookmark 刷新成功会保存新数据并通过注入 accessor 释放")
func staleRefreshSuccessPersistsFreshDataAndStopsThroughAccessor() {
    let key = "ClaudeDataDirectoryBookmark"
    let staleData = Data([1])
    let freshData = Data([9])
    let url = URL(fileURLWithPath: "/claude", isDirectory: true)
    let store = ManagerBookmarkStore(values: [key: staleData])
    let accessor = RecordingResourceAccessor(startResult: true)
    let manager = SecurityScopedBookmarkManager(
        bookmarkDataCreator: FixedManagerBookmarkDataCreator(data: freshData),
        bookmarkDataResolver: FixedBookmarkDataResolver(
            result: .init(url: url, isStale: true)
        ),
        bookmarkStore: store,
        resourceAccessor: accessor
    )

    #expect(manager.restoreBookmarkAndAccess(forKey: key) == url)
    #expect(store.data(forKey: key) == freshData)
    manager.stopAccessing(forKey: key)
    #expect(accessor.stoppedURLs == [url])
}

@MainActor
@Test("stale bookmark 保存失败会停止访问且只清除当前 provider")
func staleRefreshSaveFailureStopsAccessAndClearsOnlyCurrentProvider() {
    let claudeKey = "ClaudeDataDirectoryBookmark"
    let codexKey = "CodexDataDirectoryBookmark"
    let url = URL(fileURLWithPath: "/claude", isDirectory: true)
    let store = RejectingManagerBookmarkStore(values: [
        claudeKey: Data([1]),
        codexKey: Data([2]),
    ])
    let accessor = RecordingResourceAccessor(startResult: true)
    let manager = SecurityScopedBookmarkManager(
        bookmarkDataCreator: FixedManagerBookmarkDataCreator(data: Data([9])),
        bookmarkDataResolver: FixedBookmarkDataResolver(
            result: .init(url: url, isStale: true)
        ),
        bookmarkStore: store,
        resourceAccessor: accessor
    )

    #expect(manager.restoreBookmarkAndAccess(forKey: claudeKey) == nil)
    #expect(!manager.hasBookmark(forKey: claudeKey))
    #expect(manager.hasBookmark(forKey: codexKey))
    #expect(accessor.stoppedURLs == [url])
}

@MainActor
@Test("stopAccessingAll 使用注入 accessor 且不会重复释放")
func stopAccessingAllUsesInjectedAccessorWithoutDuplicateStops() {
    let claudeKey = "ClaudeDataDirectoryBookmark"
    let codexKey = "CodexDataDirectoryBookmark"
    let claudeURL = URL(fileURLWithPath: "/claude", isDirectory: true)
    let codexURL = URL(fileURLWithPath: "/codex", isDirectory: true)
    let accessor = RecordingResourceAccessor(startResult: true)
    let manager = SecurityScopedBookmarkManager(
        bookmarkDataResolver: MappingBookmarkDataResolver(values: [
            Data([1]): .init(url: claudeURL, isStale: false),
            Data([2]): .init(url: codexURL, isStale: false),
        ]),
        bookmarkStore: ManagerBookmarkStore(values: [
            claudeKey: Data([1]),
            codexKey: Data([2]),
        ]),
        resourceAccessor: accessor
    )

    #expect(manager.restoreBookmarkAndAccess(forKey: claudeKey) == claudeURL)
    #expect(manager.restoreBookmarkAndAccess(forKey: codexKey) == codexURL)
    manager.stopAccessingAll()
    #expect(Set(accessor.stoppedURLs) == Set([claudeURL, codexURL]))
    manager.stopAccessingAll()
    #expect(accessor.stoppedURLs.count == 2)
}
```

在 `SecurityScopedBookmarkManagerTests.swift` 底部加入完整 resolver/accessor fake。Accessor 必须用锁保护，因为生产协议是非隔离 `Sendable`，不能把可变数组裸放进 `@MainActor` fake：

```swift
private enum ManagerBookmarkResolverError: Error {
    case missingFixture
}

private struct FixedBookmarkDataResolver: BookmarkDataResolving {
    let result: ResolvedBookmark

    func resolveBookmarkData(_ data: Data) throws -> ResolvedBookmark {
        result
    }
}

private struct MappingBookmarkDataResolver: BookmarkDataResolving {
    let values: [Data: ResolvedBookmark]

    func resolveBookmarkData(_ data: Data) throws -> ResolvedBookmark {
        guard let result = values[data] else {
            throw ManagerBookmarkResolverError.missingFixture
        }
        return result
    }
}

private final class RecordingResourceAccessor: SecurityScopedResourceAccessing, @unchecked Sendable {
    private let lock = NSLock()
    private let startResult: Bool
    private var recordedStarts: [URL] = []
    private var recordedStops: [URL] = []

    init(startResult: Bool) {
        self.startResult = startResult
    }

    var startedURLs: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return recordedStarts
    }

    var stoppedURLs: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return recordedStops
    }

    func startAccessing(_ url: URL) -> Bool {
        lock.lock()
        recordedStarts.append(url)
        lock.unlock()
        return startResult
    }

    func stopAccessing(_ url: URL) {
        lock.lock()
        recordedStops.append(url)
        lock.unlock()
    }
}
```

- [ ] **Step 2: 运行测试并确认 RED**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch \
  -destination 'platform=macOS' \
  '-only-testing:TokenWatchTests/SecurityScopedBookmarkManagerTests/staleRefreshFailureStopsAccessAndClearsOnlyCurrentProvider()' \
  '-only-testing:TokenWatchTests/SecurityScopedBookmarkManagerTests/staleRefreshSuccessPersistsFreshDataAndStopsThroughAccessor()' \
  '-only-testing:TokenWatchTests/SecurityScopedBookmarkManagerTests/staleRefreshSaveFailureStopsAccessAndClearsOnlyCurrentProvider()' \
  '-only-testing:TokenWatchTests/SecurityScopedBookmarkManagerTests/startAccessFailureClearsOnlyRequestedProviderBookmark()' \
  '-only-testing:TokenWatchTests/SecurityScopedBookmarkManagerTests/providerSessionsRestoreAndStopIndependently()' \
  '-only-testing:TokenWatchTests/SecurityScopedBookmarkManagerTests/stopAccessingAllUsesInjectedAccessorWithoutDuplicateStops()' \
  -skip-testing:TokenWatchUITests \
  -derivedDataPath .build/DerivedData test
```

Expected: FAIL；当前 URL 解析和 security-scope 调用不可注入，且 stale 重建失败仍继续返回 URL。

- [ ] **Step 3: 增加 resolver 与 resource accessor**

在 `BookmarkPersistence.swift` 增加：

```swift
struct ResolvedBookmark: Sendable, Equatable {
    let url: URL
    let isStale: Bool
}

protocol BookmarkDataResolving: Sendable {
    func resolveBookmarkData(_ data: Data) throws -> ResolvedBookmark
}

struct SecurityScopedBookmarkDataResolver: BookmarkDataResolving {
    func resolveBookmarkData(_ data: Data) throws -> ResolvedBookmark {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return ResolvedBookmark(url: url, isStale: isStale)
    }
}

protocol SecurityScopedResourceAccessing: Sendable {
    func startAccessing(_ url: URL) -> Bool
    func stopAccessing(_ url: URL)
}

struct URLSecurityScopedResourceAccessor: SecurityScopedResourceAccessing {
    func startAccessing(_ url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}
```

Manager 增加两个 stored properties，并把 Task 2 initializer 扩展为最终签名：

```swift
private let bookmarkDataResolver: any BookmarkDataResolving
private let resourceAccessor: any SecurityScopedResourceAccessing

init(
    bookmarkDataCreator: any BookmarkDataCreating = SecurityScopedBookmarkDataCreator(),
    bookmarkDataResolver: any BookmarkDataResolving = SecurityScopedBookmarkDataResolver(),
    bookmarkStore: any BookmarkDataStoring = UserDefaultsBookmarkStore(),
    resourceAccessor: any SecurityScopedResourceAccessing = URLSecurityScopedResourceAccessor(),
    directoryPresenter: any DirectoryPanelPresenting = OpenPanelDirectoryPresenter(),
    languageProvider: @escaping @MainActor () -> AppLanguage = {
        AppLanguageSettings.shared.resolvedLanguage
    }
) {
    self.bookmarkDataCreator = bookmarkDataCreator
    self.bookmarkDataResolver = bookmarkDataResolver
    self.bookmarkStore = bookmarkStore
    self.resourceAccessor = resourceAccessor
    self.directoryPresenter = directoryPresenter
    self.languageProvider = languageProvider
}
```

把恢复和释放方法完整替换为：

```swift
func restoreBookmarkAndAccess(forKey key: String) -> URL? {
    if let url = sessions.retainExisting(forKey: key) {
        return url
    }

    guard let data = bookmarkStore.data(forKey: key) else {
        return nil
    }

    let resolved: ResolvedBookmark
    do {
        resolved = try bookmarkDataResolver.resolveBookmarkData(data)
    } catch {
        logger.error("Bookmark 解析失败并清除当前 key: \(key)")
        bookmarkStore.removeData(forKey: key)
        return nil
    }

    guard resourceAccessor.startAccessing(resolved.url) else {
        logger.error("Security-scoped 访问启动失败并清除当前 key: \(key)")
        bookmarkStore.removeData(forKey: key)
        return nil
    }

    if resolved.isStale {
        do {
            let freshData = try bookmarkDataCreator.createBookmarkData(for: resolved.url)
            guard bookmarkStore.save(freshData, forKey: key) else {
                logger.error("过期 Bookmark 重存失败并清除当前 key: \(key)")
                resourceAccessor.stopAccessing(resolved.url)
                bookmarkStore.removeData(forKey: key)
                return nil
            }
        } catch {
            logger.error("过期 Bookmark 重建失败并清除当前 key: \(key)")
            resourceAccessor.stopAccessing(resolved.url)
            bookmarkStore.removeData(forKey: key)
            return nil
        }
    }

    sessions.insert(resolved.url, forKey: key)
    return resolved.url
}

func stopAccessing(forKey key: String) {
    guard let url = sessions.release(forKey: key) else { return }
    resourceAccessor.stopAccessing(url)
}

func stopAccessingAll() {
    for url in sessions.removeAll() {
        resourceAccessor.stopAccessing(url)
    }
}
```

- [ ] **Step 4: 运行 manager 全套测试并确认 GREEN**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch \
  -destination 'platform=macOS' \
  -only-testing:TokenWatchTests/SecurityScopedBookmarkManagerTests \
  -only-testing:TokenWatchTests/BookmarkPersistenceTests \
  -skip-testing:TokenWatchUITests \
  -derivedDataPath .build/DerivedData test
```

Expected: PASS。

- [ ] **Step 5: 提交 bookmark 生命周期修复**

```bash
git add TokenWatch/Services/BookmarkPersistence.swift \
  TokenWatch/Services/SecurityScopedBookmarkManager.swift \
  TokenWatchTests/Services/SecurityScopedBookmarkManagerTests.swift
git commit -m "fix(bookmark): 隔离数据源恢复与过期清理"
```

---

### Task 4: ViewModel 只授权和加载目标 provider

**Files:**
- Modify: TokenWatch/ViewModels/TokenStatsViewModel.swift:5-280
- Modify: TokenWatch/Localization/AppStrings.swift:8-148,185-1875
- Modify: TokenWatchTests/ViewModels/TokenStatsViewModelObserverTests.swift:1-620

**Interfaces:**
- Consumes: DirectoryAuthorizationResult.authorized(URL) | .cancelled | .failed。
- Consumes: BookmarkAccessManaging.hasBookmark(forKey:)、restoreBookmarkAndAccess(forKey:)、stopAccessing(forKey:)。
- Produces: ProviderDirectoryState.notSelected | .selected | .selectedNoData | .needsReselection。
- Adds to ProviderState: directoryState、directoryAuthorizationErrorMessage、isAuthorizing。
- Adds localized keys: errorCannotAccessProviderDirectoryFormat、errorProviderDirectoryAuthorizationFailedFormat。
- Preserves: needsAuthorization 作为现有 Dashboard 聚合契约；所有状态转换通过 setDirectoryState(_:for:) 同步该 Bool。
- Removes: markProvidersAuthorized(sharingBookmarkWith:) 和授权后的 loadAllStats()。
- Concurrency invariant: 同一 provider 的 isAuthorizing 与 ProviderLoadGate 不能同时为 active；授权成功时必须在清除 isAuthorizing 后、任何 await、observer 通知或外部回调之前取得 load gate。

- [ ] **Step 1: 写入独立授权、空数据、恢复失败和双向竞态测试**

在 TokenStatsViewModelObserverTests.swift 顶部增加：

~~~swift
import Dispatch
~~~

删除旧测试 sharedBookmarkAuthorizationUpdatesAllProviders()，保留其余既有 fingerprint、静默刷新和解析错误回归测试。把以下九个测试加入 TokenStatsViewModelObserverTests：

~~~swift
@Test("授权只更新并加载用户选择的 provider")
func authorizationOnlyUpdatesAndLoadsSelectedProvider() async {
    let claudeKey = "ClaudeDataDirectoryBookmark"
    let codexKey = "CodexDataDirectoryBookmark"
    let selectedURL = URL(
        fileURLWithPath: "/chosen-claude",
        isDirectory: true
    )
    let claude = DirectoryTestUsageProvider(
        id: .claude,
        bookmarkKey: claudeKey
    )
    let codex = DirectoryTestUsageProvider(
        id: .codex,
        bookmarkKey: codexKey
    )
    let manager = DirectoryTestBookmarkManager(
        promptResult: .authorized(selectedURL)
    )
    let vm = TokenStatsViewModel(
        providers: [claude, codex],
        bookmarkManager: manager
    )

    #expect(await vm.requestAuthorization(for: .claude))
    #expect(claude.loadCount == 1)
    #expect(codex.loadCount == 0)
    #expect(vm.states[.claude]?.directoryState == .selected)
    #expect(vm.states[.claude]?.needsAuthorization == false)
    #expect(vm.states[.codex]?.directoryState == .notSelected)
    #expect(vm.states[.codex]?.needsAuthorization == true)
    #expect(manager.promptedProviderIDs == [.claude])
    #expect(manager.restoredKeys == [claudeKey])
    #expect(manager.stoppedKeys == [claudeKey])
    #expect(manager.hasBookmark(forKey: claudeKey))
    #expect(!manager.hasBookmark(forKey: codexKey))
}

@Test("取消授权不会改变任一 provider 的持久状态")
func cancelledAuthorizationLeavesProviderStatesUnchanged() async {
    let claude = DirectoryTestUsageProvider(
        id: .claude,
        bookmarkKey: "ClaudeDataDirectoryBookmark"
    )
    let codex = DirectoryTestUsageProvider(
        id: .codex,
        bookmarkKey: "CodexDataDirectoryBookmark"
    )
    let manager = DirectoryTestBookmarkManager(promptResult: .cancelled)
    let vm = TokenStatsViewModel(
        providers: [claude, codex],
        bookmarkManager: manager
    )
    let beforeClaudeState = vm.states[.claude]?.directoryState
    let beforeClaudeNeedsAuthorization =
        vm.states[.claude]?.needsAuthorization
    let beforeClaudeDirectoryError =
        vm.states[.claude]?.directoryAuthorizationErrorMessage
    let beforeCodexState = vm.states[.codex]?.directoryState
    let beforeCodexNeedsAuthorization =
        vm.states[.codex]?.needsAuthorization
    let beforeCodexDirectoryError =
        vm.states[.codex]?.directoryAuthorizationErrorMessage

    #expect(!(await vm.requestAuthorization(for: .claude)))
    #expect(vm.states[.claude]?.directoryState == beforeClaudeState)
    #expect(
        vm.states[.claude]?.needsAuthorization
            == beforeClaudeNeedsAuthorization
    )
    #expect(
        vm.states[.claude]?.directoryAuthorizationErrorMessage
            == beforeClaudeDirectoryError
    )
    #expect(vm.states[.claude]?.stats == nil)
    #expect(vm.states[.claude]?.entries == nil)
    #expect(vm.states[.claude]?.errorMessage == nil)
    #expect(vm.states[.claude]?.isAuthorizing == false)
    #expect(vm.states[.codex]?.directoryState == beforeCodexState)
    #expect(
        vm.states[.codex]?.needsAuthorization
            == beforeCodexNeedsAuthorization
    )
    #expect(
        vm.states[.codex]?.directoryAuthorizationErrorMessage
            == beforeCodexDirectoryError
    )
    #expect(vm.states[.codex]?.stats == nil)
    #expect(vm.states[.codex]?.entries == nil)
    #expect(codex.loadCount == 0)
}

@Test("重新选择失败保留旧授权和旧数据")
func failedReselectionPreservesOldAuthorizationAndData() async {
    let key = "ClaudeDataDirectoryBookmark"
    let provider = DirectoryTestUsageProvider(
        id: .claude,
        bookmarkKey: key
    )
    let manager = DirectoryTestBookmarkManager(
        promptResult: .failed,
        authorizedRoots: [
            key: URL(fileURLWithPath: "/claude", isDirectory: true),
        ]
    )
    let vm = TokenStatsViewModel(
        languageSettings: directoryTestEnglishLanguageSettings(),
        providers: [provider],
        bookmarkManager: manager
    )
    await vm.loadStats(for: .claude)
    let oldTotalTokens =
        vm.states[.claude]?.stats?.overall.totalTokens
    let oldEntries = vm.states[.claude]?.entries
    let oldDirectoryState = vm.states[.claude]?.directoryState

    #expect(!(await vm.requestAuthorization(for: .claude)))
    #expect(vm.states[.claude]?.directoryState == oldDirectoryState)
    #expect(vm.states[.claude]?.directoryState == .selected)
    #expect(vm.states[.claude]?.needsAuthorization == false)
    #expect(
        vm.states[.claude]?.stats?.overall.totalTokens
            == oldTotalTokens
    )
    #expect(vm.states[.claude]?.entries == oldEntries)
    #expect(vm.states[.claude]?.errorMessage == nil)
    #expect(
        vm.states[.claude]?.directoryAuthorizationErrorMessage
            == TokenStatsViewModel.authorizationFailedMessage(
                providerName: "Claude Code",
                language: .en
            )
    )
    #expect(manager.hasBookmark(forKey: key))
    #expect(provider.loadCount == 1)
    #expect(manager.restoredKeys == [key])
    #expect(manager.stoppedKeys == [key])
}

@Test("空目录仍保持已选择并显示无数据状态")
func selectedDirectoryWithoutEntriesRemainsAuthorized() async {
    let key = "OpenCodeDataDirectoryBookmark"
    let provider = DirectoryTestUsageProvider(
        id: .opencode,
        bookmarkKey: key,
        entries: []
    )
    let manager = DirectoryTestBookmarkManager(
        authorizedRoots: [
            key: URL(fileURLWithPath: "/opencode", isDirectory: true),
        ]
    )
    let vm = TokenStatsViewModel(
        providers: [provider],
        bookmarkManager: manager
    )

    await vm.loadStats(for: .opencode)

    #expect(
        vm.states[.opencode]?.directoryState == .selectedNoData
    )
    #expect(vm.states[.opencode]?.needsAuthorization == false)
    #expect(vm.states[.opencode]?.entries == [])
    #expect(
        vm.states[.opencode]?.stats?.overall.entryCount == 0
    )
    #expect(vm.states[.opencode]?.errorMessage == nil)
    #expect(
        vm.states[.opencode]?.directoryAuthorizationErrorMessage
            == nil
    )
}

@Test("恢复失败只清除当前 provider 数据")
func restoreFailureClearsOnlyCurrentProviderData() async {
    let claudeKey = "ClaudeDataDirectoryBookmark"
    let codexKey = "CodexDataDirectoryBookmark"
    let claude = DirectoryTestUsageProvider(
        id: .claude,
        bookmarkKey: claudeKey
    )
    let codex = DirectoryTestUsageProvider(
        id: .codex,
        bookmarkKey: codexKey
    )
    let manager = DirectoryTestBookmarkManager(
        authorizedRoots: [
            claudeKey: URL(
                fileURLWithPath: "/claude",
                isDirectory: true
            ),
            codexKey: URL(
                fileURLWithPath: "/codex",
                isDirectory: true
            ),
        ]
    )
    let vm = TokenStatsViewModel(
        languageSettings: directoryTestEnglishLanguageSettings(),
        providers: [claude, codex],
        bookmarkManager: manager
    )
    await vm.loadStats(for: .claude)
    await vm.loadStats(for: .codex)
    let oldCodexTotalTokens =
        vm.states[.codex]?.stats?.overall.totalTokens
    let oldCodexEntries = vm.states[.codex]?.entries

    manager.failRestoration(forKey: claudeKey)
    await vm.loadStats(for: .claude)

    #expect(
        vm.states[.claude]?.directoryState == .needsReselection
    )
    #expect(vm.states[.claude]?.needsAuthorization == true)
    #expect(vm.states[.claude]?.stats == nil)
    #expect(vm.states[.claude]?.entries == nil)
    #expect(vm.states[.claude]?.lastRefreshedAt == nil)
    #expect(vm.states[.claude]?.errorMessage == nil)
    #expect(
        vm.states[.claude]?.directoryAuthorizationErrorMessage
            == TokenStatsViewModel.cannotAccessDataDirectoryMessage(
                providerName: "Claude Code",
                language: .en
            )
    )
    #expect(!manager.hasBookmark(forKey: claudeKey))
    #expect(manager.hasBookmark(forKey: codexKey))
    #expect(vm.states[.codex]?.directoryState == .selected)
    #expect(vm.states[.codex]?.needsAuthorization == false)
    #expect(
        vm.states[.codex]?.stats?.overall.totalTokens
            == oldCodexTotalTokens
    )
    #expect(vm.states[.codex]?.entries == oldCodexEntries)
    #expect(
        vm.states[.codex]?.directoryAuthorizationErrorMessage
            == nil
    )
    #expect(claude.loadCount == 1)
    #expect(codex.loadCount == 1)
}

@Test("恢复失败后的下一次静默加载保持需要重新选择")
func subsequentSilentLoadPreservesNeedsReselectionAfterRestoreFailure()
    async
{
    let key = "ClaudeDataDirectoryBookmark"
    let provider = DirectoryTestUsageProvider(
        id: .claude,
        bookmarkKey: key
    )
    let manager = DirectoryTestBookmarkManager(
        authorizedRoots: [
            key: URL(fileURLWithPath: "/claude", isDirectory: true),
        ]
    )
    manager.failRestoration(forKey: key)
    let vm = TokenStatsViewModel(
        providers: [provider],
        bookmarkManager: manager
    )
    var received: [ProviderID] = []
    _ = vm.observe { received.append($0) }

    await vm.loadStats(for: .claude)
    let originalDirectoryError =
        vm.states[.claude]?.directoryAuthorizationErrorMessage
    received.removeAll()

    await vm.loadStats(
        for: .claude,
        mode: .silentIfUnchanged
    )

    #expect(
        vm.states[.claude]?.directoryState == .needsReselection
    )
    #expect(vm.states[.claude]?.needsAuthorization == true)
    #expect(
        vm.states[.claude]?.directoryAuthorizationErrorMessage
            == originalDirectoryError
    )
    #expect(originalDirectoryError != nil)
    #expect(vm.states[.claude]?.stats == nil)
    #expect(vm.states[.claude]?.entries == nil)
    #expect(vm.states[.claude]?.errorMessage == nil)
    #expect(manager.restoredKeys == [key])
    #expect(received.isEmpty)
}

@Test("bookmark 恢复成功但 parser 失败仍保持目录已选择")
func parserFailureAfterSuccessfulRestoreKeepsDirectorySelected()
    async
{
    let key = "CodexDataDirectoryBookmark"
    let provider = DirectoryTestUsageProvider(
        id: .codex,
        bookmarkKey: key,
        throwsOnLoad: true
    )
    let manager = DirectoryTestBookmarkManager(
        authorizedRoots: [
            key: URL(fileURLWithPath: "/codex", isDirectory: true),
        ]
    )
    let vm = TokenStatsViewModel(
        providers: [provider],
        bookmarkManager: manager
    )

    await vm.loadStats(for: .codex)

    #expect(vm.states[.codex]?.directoryState == .selected)
    #expect(vm.states[.codex]?.needsAuthorization == false)
    #expect(
        vm.states[.codex]?.directoryAuthorizationErrorMessage
            == nil
    )
    #expect(
        vm.states[.codex]?.errorMessage?
            .contains("stub load failed") == true
    )
    #expect(vm.states[.codex]?.stats == nil)
    #expect(vm.states[.codex]?.entries == nil)
    #expect(vm.states[.codex]?.lastRefreshedAt != nil)
    #expect(manager.restoredKeys == [key])
    #expect(manager.stoppedKeys == [key])
}

@Test("同一 provider 的授权和加载不会重叠", .timeLimit(.minutes(1)))
func authorizationAndLoadingDoNotOverlapForSameProvider() async {
    let authorizationKey = "ClaudeDataDirectoryBookmark"
    let authorizationProvider = DirectoryTestUsageProvider(
        id: .claude,
        bookmarkKey: authorizationKey
    )
    let authorizationManager = DirectoryTestBookmarkManager(
        promptResult: .cancelled,
        suspendsPrompt: true
    )
    let authorizationVM = TokenStatsViewModel(
        providers: [authorizationProvider],
        bookmarkManager: authorizationManager
    )

    let authorizationTask = Task { @MainActor in
        await authorizationVM.requestAuthorization(for: .claude)
    }
    await authorizationManager.waitUntilPromptStarts()
    #expect(
        authorizationVM.states[.claude]?.isAuthorizing == true
    )

    await authorizationVM.loadStats(for: .claude)

    #expect(authorizationProvider.loadCount == 0)
    #expect(authorizationManager.restoredKeys.isEmpty)
    authorizationManager.resumePrompt(with: .cancelled)
    #expect(await authorizationTask.value == false)
    #expect(
        authorizationVM.states[.claude]?.isAuthorizing == false
    )

    let loadingKey = "CodexDataDirectoryBookmark"
    let loadingProvider = DirectoryTestUsageProvider(
        id: .codex,
        bookmarkKey: loadingKey,
        suspendsLoads: true
    )
    let loadingManager = DirectoryTestBookmarkManager(
        promptResult: .failed,
        authorizedRoots: [
            loadingKey: URL(
                fileURLWithPath: "/codex",
                isDirectory: true
            ),
        ]
    )
    let loadingVM = TokenStatsViewModel(
        providers: [loadingProvider],
        bookmarkManager: loadingManager
    )

    let loadTask = Task { @MainActor in
        await loadingVM.loadStats(for: .codex)
    }
    await loadingProvider.waitUntilLoadStarts()
    #expect(loadingVM.states[.codex]?.isLoading == true)

    #expect(
        !(await loadingVM.requestAuthorization(for: .codex))
    )
    #expect(loadingManager.promptedProviderIDs.isEmpty)

    loadingProvider.resumeLoad()
    await loadTask.value
    #expect(loadingProvider.loadCount == 1)
    #expect(loadingVM.states[.codex]?.directoryState == .selected)
}

@Test("授权成功交接给加载门禁时不会发布空闲窗口", .timeLimit(.minutes(1)))
func successfulAuthorizationHandoffNeverPublishesIdleGap() async {
    let key = "ClaudeDataDirectoryBookmark"
    let provider = DirectoryTestUsageProvider(
        id: .claude,
        bookmarkKey: key,
        suspendsLoads: true
    )
    let manager = DirectoryTestBookmarkManager(
        promptResult: .authorized(
            URL(fileURLWithPath: "/claude", isDirectory: true)
        )
    )
    let vm = TokenStatsViewModel(
        providers: [provider],
        bookmarkManager: manager
    )
    var publishedTransitions: [String] = []
    _ = vm.observe { id in
        guard id == .claude, let state = vm.states[id] else { return }
        publishedTransitions.append(
            "authorizing=\(state.isAuthorizing),loading=\(state.isLoading)"
        )
    }

    let authorizationTask = Task { @MainActor in
        await vm.requestAuthorization(for: .claude)
    }
    await provider.waitUntilLoadStarts()

    #expect(publishedTransitions.contains(
        "authorizing=true,loading=false"
    ))
    #expect(publishedTransitions.contains(
        "authorizing=false,loading=true"
    ))
    #expect(!publishedTransitions.contains(
        "authorizing=false,loading=false"
    ))

    provider.resumeLoad()
    #expect(await authorizationTask.value)
}
~~~

把既有 localizedErrorMessagesUseAppStrings() 完整替换为：

~~~swift
@Test("目录和加载错误按当前语言生成")
func localizedErrorMessagesUseAppStrings() {
    let error = StubLocalizedError(description: "disk read failed")

    #expect(
        TokenStatsViewModel.cannotAccessDataDirectoryMessage(
            providerName: "Claude Code",
            language: .zhHans
        )
            == "无法访问 Claude Code 数据文件夹，请再次选择。"
    )
    #expect(
        TokenStatsViewModel.cannotAccessDataDirectoryMessage(
            providerName: "Claude Code",
            language: .en
        )
            == "Cannot access the Claude Code data folder. Please choose it again."
    )
    #expect(
        TokenStatsViewModel.authorizationFailedMessage(
            providerName: "Claude Code",
            language: .zhHans
        )
            == "无法保存 Claude Code 数据文件夹的访问权限，请重新选择。"
    )
    #expect(
        TokenStatsViewModel.authorizationFailedMessage(
            providerName: "Claude Code",
            language: .en
        )
            == "Could not save access to the Claude Code data folder. Please choose again."
    )
    #expect(
        TokenStatsViewModel.loadFailedMessage(
            error: error,
            language: .zhHans
        ) == "数据加载失败: disk read failed"
    )
    #expect(
        TokenStatsViewModel.loadFailedMessage(
            error: error,
            language: .en
        ) == "Data load failed: disk read failed"
    )
}
~~~

在测试文件底部、现有 StubBookmarkManager 之前加入以下完整 helper。它们只供本 Task 的目录状态和竞态测试使用，不替换既有静默刷新测试所使用的 StubUsageProvider、MutableUsageProvider、FailingAfterFirstLoadProvider 和 StubBookmarkManager：

~~~swift
@MainActor
private func directoryTestEnglishLanguageSettings() -> AppLanguageSettings {
    let suite = "DirectoryViewModelLanguage-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    return AppLanguageSettings(
        defaults: defaults,
        preferredLanguagesProvider: { ["en"] }
    )
}

private final class DirectoryTestUsageProvider:
    UsageProvider,
    @unchecked Sendable
{
    let id: ProviderID
    let displayName: String
    let bookmarkKey: String
    let hasCacheWriteDimension = true
    let hasReasoningDimension = false

    var openPanelMessageKey: AppStringKey {
        switch id {
        case .claude:
            .claudeDataDirectoryOpenPanelMessage
        case .codex:
            .codexDataDirectoryOpenPanelMessage
        case .opencode:
            .openCodeDataDirectoryOpenPanelMessage
        }
    }

    private let entries: [ParsedUsageEntry]
    private let throwsOnLoad: Bool
    private let suspendsLoads: Bool
    private let lock = NSLock()
    private var recordedLoadCount = 0
    private let loadRelease = DispatchSemaphore(value: 0)
    private let loadStartedStream: AsyncStream<Void>
    private let loadStartedContinuation:
        AsyncStream<Void>.Continuation

    init(
        id: ProviderID,
        bookmarkKey: String,
        entries: [ParsedUsageEntry]? = nil,
        throwsOnLoad: Bool = false,
        suspendsLoads: Bool = false
    ) {
        self.id = id
        self.bookmarkKey = bookmarkKey
        self.entries = entries ?? [
            makeEntry(
                id: id,
                usage: makeUsage(
                    cacheCreation5m: 0,
                    cacheCreation1h: 0
                )
            ),
        ]
        self.throwsOnLoad = throwsOnLoad
        self.suspendsLoads = suspendsLoads
        self.displayName = switch id {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .opencode: "opencode"
        }

        let signal = AsyncStream<Void>.makeStream()
        loadStartedStream = signal.stream
        loadStartedContinuation = signal.continuation
    }

    var loadCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return recordedLoadCount
    }

    func loadEntries(
        from dataRootURL: URL
    ) throws -> [ParsedUsageEntry] {
        lock.lock()
        recordedLoadCount += 1
        lock.unlock()

        loadStartedContinuation.yield(())
        if suspendsLoads {
            loadRelease.wait()
        }
        if throwsOnLoad {
            throw StubLoadError()
        }
        return entries
    }

    func waitUntilLoadStarts() async {
        var iterator = loadStartedStream.makeAsyncIterator()
        _ = await iterator.next()
    }

    func resumeLoad() {
        loadRelease.signal()
    }
}

@MainActor
private final class DirectoryTestBookmarkManager:
    BookmarkAccessManaging
{
    private let promptResult: DirectoryAuthorizationResult
    private let suspendsPrompt: Bool
    private var authorizedRoots: [String: URL]
    private var restoreFailureKeys: Set<String> = []
    private var promptContinuation:
        CheckedContinuation<DirectoryAuthorizationResult, Never>?
    private let promptStartedStream: AsyncStream<Void>
    private let promptStartedContinuation:
        AsyncStream<Void>.Continuation

    private(set) var promptedProviderIDs: [ProviderID] = []
    private(set) var restoredKeys: [String] = []
    private(set) var stoppedKeys: [String] = []

    init(
        promptResult: DirectoryAuthorizationResult = .cancelled,
        authorizedRoots: [String: URL] = [:],
        suspendsPrompt: Bool = false
    ) {
        self.promptResult = promptResult
        self.authorizedRoots = authorizedRoots
        self.suspendsPrompt = suspendsPrompt

        let signal = AsyncStream<Void>.makeStream()
        promptStartedStream = signal.stream
        promptStartedContinuation = signal.continuation
    }

    func hasBookmark(forKey key: String) -> Bool {
        authorizedRoots[key] != nil
    }

    func promptUserToSelectDirectory(
        forProvider provider: any UsageProvider
    ) async -> DirectoryAuthorizationResult {
        promptedProviderIDs.append(provider.id)

        let result: DirectoryAuthorizationResult
        if suspendsPrompt {
            result = await withCheckedContinuation { continuation in
                promptContinuation = continuation
                promptStartedContinuation.yield(())
            }
        } else {
            promptStartedContinuation.yield(())
            result = promptResult
        }

        if case .authorized(let url) = result {
            authorizedRoots[provider.bookmarkKey] = url
        }
        return result
    }

    func restoreBookmarkAndAccess(forKey key: String) -> URL? {
        restoredKeys.append(key)
        guard let url = authorizedRoots[key] else {
            return nil
        }
        if restoreFailureKeys.contains(key) {
            // 模拟 Task 3 的生产语义：恢复失败会删除当前 key。
            authorizedRoots.removeValue(forKey: key)
            return nil
        }
        return url
    }

    func stopAccessing(forKey key: String) {
        stoppedKeys.append(key)
    }

    func failRestoration(forKey key: String) {
        restoreFailureKeys.insert(key)
    }

    func waitUntilPromptStarts() async {
        var iterator = promptStartedStream.makeAsyncIterator()
        _ = await iterator.next()
    }

    func resumePrompt(
        with result: DirectoryAuthorizationResult
    ) {
        guard let continuation = promptContinuation else {
            preconditionFailure(
                "resumePrompt 必须在目录 prompt 已开始后调用"
            )
        }
        promptContinuation = nil
        continuation.resume(returning: result)
    }
}
~~~

- [ ] **Step 2: 运行定向测试并确认 RED**

~~~bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch \
  -destination 'platform=macOS' \
  '-only-testing:TokenWatchTests/TokenStatsViewModelObserverTests/authorizationOnlyUpdatesAndLoadsSelectedProvider()' \
  '-only-testing:TokenWatchTests/TokenStatsViewModelObserverTests/cancelledAuthorizationLeavesProviderStatesUnchanged()' \
  '-only-testing:TokenWatchTests/TokenStatsViewModelObserverTests/failedReselectionPreservesOldAuthorizationAndData()' \
  '-only-testing:TokenWatchTests/TokenStatsViewModelObserverTests/selectedDirectoryWithoutEntriesRemainsAuthorized()' \
  '-only-testing:TokenWatchTests/TokenStatsViewModelObserverTests/restoreFailureClearsOnlyCurrentProviderData()' \
  '-only-testing:TokenWatchTests/TokenStatsViewModelObserverTests/subsequentSilentLoadPreservesNeedsReselectionAfterRestoreFailure()' \
  '-only-testing:TokenWatchTests/TokenStatsViewModelObserverTests/parserFailureAfterSuccessfulRestoreKeepsDirectorySelected()' \
  '-only-testing:TokenWatchTests/TokenStatsViewModelObserverTests/authorizationAndLoadingDoNotOverlapForSameProvider()' \
  '-only-testing:TokenWatchTests/TokenStatsViewModelObserverTests/successfulAuthorizationHandoffNeverPublishesIdleGap()' \
  '-only-testing:TokenWatchTests/TokenStatsViewModelObserverTests/localizedErrorMessagesUseAppStrings()' \
  -skip-testing:TokenWatchUITests \
  -derivedDataPath .build/DerivedData test
~~~

Expected: FAIL；当前没有 provider 独立目录状态，授权仍调用 loadAllStats()，恢复失败只写共享 Home 错误，且授权与加载没有双向门禁。

- [ ] **Step 3: 增加 provider 目录状态与完整错误本地化**

在 TokenStatsViewModel 之前增加：

~~~swift
enum ProviderDirectoryState: Sendable, Equatable {
    case notSelected
    case selected
    case selectedNoData
    case needsReselection

    var needsAuthorization: Bool {
        self == .notSelected || self == .needsReselection
    }
}
~~~

在 ProviderState 末尾增加默认字段，保留既有具名初始化调用：

~~~swift
var directoryState: ProviderDirectoryState = .notSelected
var directoryAuthorizationErrorMessage: String?
var isAuthorizing = false
~~~

删除 cannotAccessHomeMessage(language:)，加入：

~~~swift
nonisolated static func cannotAccessDataDirectoryMessage(
    providerName: String,
    language: AppLanguage
) -> String {
    String(
        format: AppStrings.text(
            .errorCannotAccessProviderDirectoryFormat,
            language: language
        ),
        providerName
    )
}

nonisolated static func authorizationFailedMessage(
    providerName: String,
    language: AppLanguage
) -> String {
    String(
        format: AppStrings.text(
            .errorProviderDirectoryAuthorizationFailedFormat,
            language: language
        ),
        providerName
    )
}
~~~

在 AppStringKey 增加：

~~~swift
case errorCannotAccessProviderDirectoryFormat
case errorProviderDirectoryAuthorizationFailedFormat
~~~

在 12 个语言表分别加入以下精确值；每个字符串必须且只能包含一个 %@：

~~~swift
// zhHans
.errorCannotAccessProviderDirectoryFormat:
    "无法访问 %@ 数据文件夹，请再次选择。",
.errorProviderDirectoryAuthorizationFailedFormat:
    "无法保存 %@ 数据文件夹的访问权限，请重新选择。",

// zhHant
.errorCannotAccessProviderDirectoryFormat:
    "無法存取已選擇的 %@ 資料檔案夾，請重新選擇",
.errorProviderDirectoryAuthorizationFailedFormat:
    "無法儲存 %@ 資料檔案夾的存取權限，請再試一次",

// en
.errorCannotAccessProviderDirectoryFormat:
    "Cannot access the %@ data folder. Please choose it again.",
.errorProviderDirectoryAuthorizationFailedFormat:
    "Could not save access to the %@ data folder. Please choose again.",

// ja
.errorCannotAccessProviderDirectoryFormat:
    "選択した %@ のデータフォルダにアクセスできません。もう一度選択してください",
.errorProviderDirectoryAuthorizationFailedFormat:
    "%@ のデータフォルダへのアクセス権を保存できませんでした。もう一度お試しください",

// ko
.errorCannotAccessProviderDirectoryFormat:
    "선택한 %@ 데이터 폴더에 접근할 수 없습니다. 다시 선택하세요",
.errorProviderDirectoryAuthorizationFailedFormat:
    "%@ 데이터 폴더 접근 권한을 저장하지 못했습니다. 다시 시도하세요",

// es
.errorCannotAccessProviderDirectoryFormat:
    "No se puede acceder a la carpeta de datos seleccionada para %@. Vuelve a elegirla",
.errorProviderDirectoryAuthorizationFailedFormat:
    "No se pudo guardar el acceso a la carpeta de datos de %@. Inténtalo de nuevo",

// de
.errorCannotAccessProviderDirectoryFormat:
    "Auf den ausgewählten Datenordner von %@ kann nicht zugegriffen werden. Wähle ihn erneut aus",
.errorProviderDirectoryAuthorizationFailedFormat:
    "Der Zugriff auf den Datenordner von %@ konnte nicht gespeichert werden. Versuche es erneut",

// fr
.errorCannotAccessProviderDirectoryFormat:
    "Impossible d'accéder au dossier de données sélectionné pour %@. Choisissez-le à nouveau",
.errorProviderDirectoryAuthorizationFailedFormat:
    "Impossible d'enregistrer l'accès au dossier de données de %@. Réessayez",

// ptBR
.errorCannotAccessProviderDirectoryFormat:
    "Não foi possível acessar a pasta de dados selecionada para %@. Escolha-a novamente",
.errorProviderDirectoryAuthorizationFailedFormat:
    "Não foi possível salvar o acesso à pasta de dados de %@. Tente novamente",

// it
.errorCannotAccessProviderDirectoryFormat:
    "Impossibile accedere alla cartella dati selezionata per %@. Selezionala di nuovo",
.errorProviderDirectoryAuthorizationFailedFormat:
    "Impossibile salvare l'accesso alla cartella dati di %@. Riprova",

// nl
.errorCannotAccessProviderDirectoryFormat:
    "De geselecteerde gegevensmap voor %@ is niet toegankelijk. Kies deze opnieuw",
.errorProviderDirectoryAuthorizationFailedFormat:
    "Toegang tot de gegevensmap van %@ kon niet worden opgeslagen. Probeer het opnieuw",

// pl
.errorCannotAccessProviderDirectoryFormat:
    "Nie można uzyskać dostępu do folderu danych wybranego dla %@. Wybierz go ponownie",
.errorProviderDirectoryAuthorizationFailedFormat:
    "Nie udało się zapisać dostępu do folderu danych dla %@. Spróbuj ponownie",
~~~

- [ ] **Step 4: 用单一状态转换与精确加载分支实现 provider 隔离**

在 TokenStatsViewModel 中加入以下 helper：

~~~swift
private func setDirectoryState(
    _ directoryState: ProviderDirectoryState,
    for id: ProviderID
) {
    states[id]?.directoryState = directoryState
    states[id]?.needsAuthorization =
        directoryState.needsAuthorization
}

/// 清除仅属于一个 provider 的解析结果。
/// - Returns: 清理前是否存在需要通知 UI 的数据或刷新时间。
@discardableResult
private func clearProviderData(for id: ProviderID) -> Bool {
    let hadData = states[id]?.stats != nil
        || states[id]?.entries != nil
        || entryFingerprints[id] != nil
        || states[id]?.lastRefreshedAt != nil

    states[id]?.stats = nil
    states[id]?.entries = nil
    states[id]?.lastRefreshedAt = nil
    entryFingerprints.removeValue(forKey: id)
    return hadData
}
~~~

把现有 loadStats(for:mode:) 完整替换为以下入口和执行方法：

~~~swift
/// 加载指定 provider 的统计。
/// 授权面板活动时跳过加载；取得 gate 后才允许开始 bookmark 恢复。
func loadStats(
    for id: ProviderID,
    mode: LoadMode = .interactive
) async {
    guard let provider = provider(for: id) else {
        return
    }
    guard states[id]?.isAuthorizing != true else {
        logger.info(
            "\(provider.displayName) 正在选择数据目录,跳过刷新"
        )
        return
    }
    guard loadGate.enter(id) else {
        logger.info(
            "\(provider.displayName) 已在刷新中,跳过重复请求"
        )
        return
    }

    await performLoad(for: provider, mode: mode)
}

/// 执行已取得 provider load gate 的完整加载。
/// 所有 return 路径都由 defer 释放 gate。
private func performLoad(
    for provider: any UsageProvider,
    mode: LoadMode
) async {
    let id = provider.id
    defer { loadGate.leave(id) }

    let sendsLoadingNotifications = mode == .interactive
    if sendsLoadingNotifications {
        states[id]?.isLoading = true
        states[id]?.errorMessage = nil
        notifyStateChange(id)
    }

    guard bookmarkManager.hasBookmark(
        forKey: provider.bookmarkKey
    ) else {
        let previousDirectoryState =
            states[id]?.directoryState
        let previousDirectoryError =
            states[id]?.directoryAuthorizationErrorMessage
        let previousLoadError = states[id]?.errorMessage
        let wasLoading = states[id]?.isLoading == true
        let clearedData = clearProviderData(for: id)

        states[id]?.errorMessage = nil
        states[id]?.isLoading = false

        if previousDirectoryState == .needsReselection {
            // restore 失败已删除 bookmark；静默刷新不能把该状态
            // 和 provider-specific 错误降级为普通未选择。
            setDirectoryState(.needsReselection, for: id)
        } else {
            setDirectoryState(.notSelected, for: id)
            states[id]?.directoryAuthorizationErrorMessage = nil
        }

        logger.info(
            "\(provider.displayName) 尚未选择数据目录"
        )

        let shouldNotify = sendsLoadingNotifications
            || clearedData
            || wasLoading
            || previousLoadError != nil
            || previousDirectoryState
                != states[id]?.directoryState
            || previousDirectoryError
                != states[id]?
                    .directoryAuthorizationErrorMessage
        if shouldNotify {
            notifyStateChange(id)
        }
        return
    }

    guard let rootURL =
        bookmarkManager.restoreBookmarkAndAccess(
            forKey: provider.bookmarkKey
        )
    else {
        let message =
            Self.cannotAccessDataDirectoryMessage(
                providerName: provider.displayName,
                language: languageSettings.resolvedLanguage
            )
        let previousDirectoryState =
            states[id]?.directoryState
        let previousDirectoryError =
            states[id]?.directoryAuthorizationErrorMessage
        let previousLoadError = states[id]?.errorMessage
        let wasLoading = states[id]?.isLoading == true
        let clearedData = clearProviderData(for: id)

        setDirectoryState(.needsReselection, for: id)
        states[id]?.directoryAuthorizationErrorMessage =
            message
        states[id]?.errorMessage = nil
        states[id]?.isLoading = false

        logger.error(
            "\(provider.displayName) Bookmark 恢复失败"
        )

        let shouldNotify = sendsLoadingNotifications
            || clearedData
            || wasLoading
            || previousLoadError != nil
            || previousDirectoryState
                != states[id]?.directoryState
            || previousDirectoryError != message
        if shouldNotify {
            notifyStateChange(id)
        }
        return
    }
    defer {
        bookmarkManager.stopAccessing(
            forKey: provider.bookmarkKey
        )
    }

    // bookmark 可恢复即表示目录仍已选择；parser 失败不能把
    // 该状态改回未选择或 needsReselection。
    let restoredDirectoryPresentationChanged =
        states[id]?.directoryState != .selected
        || states[id]?.needsAuthorization != false
        || states[id]?
            .directoryAuthorizationErrorMessage != nil
    setDirectoryState(.selected, for: id)
    states[id]?.directoryAuthorizationErrorMessage = nil

    let aggregator = self.aggregator
    let logger = self.logger
    let providerCopy = provider
    let previousFingerprint = entryFingerprints[id]
    let canReuseExistingStats =
        states[id]?.stats != nil
        && states[id]?.errorMessage == nil

    let result: Result<ProviderLoadResult, Error> =
        await Task.detached(priority: .userInitiated) {
            do {
                let entries = try providerCopy.loadEntries(
                    from: rootURL
                )
                logger.info(
                    "\(providerCopy.displayName) 解析得 \(entries.count) 条记录"
                )
                let fingerprint =
                    UsageEntriesFingerprint.make(
                        from: entries
                    )
                if canReuseExistingStats,
                   previousFingerprint == fingerprint {
                    return .success(
                        .unchanged(
                            entryCount: entries.count
                        )
                    )
                }

                let stats = aggregator.aggregate(entries)
                return .success(
                    .loaded(
                        stats: stats,
                        entries: entries,
                        fingerprint: fingerprint,
                        entryCount: entries.count
                    )
                )
            } catch {
                return .failure(error)
            }
        }.value

    switch result {
    case .success(
        .loaded(
            let stats,
            let entries,
            let fingerprint,
            _
        )
    ):
        entryFingerprints[id] = fingerprint
        states[id]?.stats = stats
        states[id]?.entries = entries
        setDirectoryState(
            entries.isEmpty ? .selectedNoData : .selected,
            for: id
        )
        states[id]?.directoryAuthorizationErrorMessage =
            nil
        states[id]?.errorMessage = nil
        states[id]?.lastRefreshedAt = nowProvider()
        states[id]?.isLoading = false
        notifyStateChange(id)

    case .success(.unchanged(let entryCount)):
        let targetDirectoryState:
            ProviderDirectoryState =
                entryCount == 0
                ? .selectedNoData
                : .selected
        let shouldNotify = sendsLoadingNotifications
            || restoredDirectoryPresentationChanged
            || states[id]?.directoryState
                != targetDirectoryState
            || states[id]?
                .directoryAuthorizationErrorMessage != nil
            || states[id]?.errorMessage != nil
            || states[id]?.isLoading == true

        setDirectoryState(
            targetDirectoryState,
            for: id
        )
        states[id]?.directoryAuthorizationErrorMessage =
            nil
        states[id]?.errorMessage = nil
        states[id]?.lastRefreshedAt = nowProvider()
        states[id]?.isLoading = false
        if shouldNotify {
            notifyStateChange(id)
        }

    case .failure(let error):
        let message = Self.loadFailedMessage(
            error: error,
            language: languageSettings.resolvedLanguage
        )
        let shouldNotify = sendsLoadingNotifications
            || restoredDirectoryPresentationChanged
            || states[id]?.errorMessage != message
            || states[id]?.isLoading == true

        // stats、entries 与 fingerprint 保留最后一次成功值；
        // bookmark 已成功恢复，所以目录状态保持 selected。
        setDirectoryState(.selected, for: id)
        states[id]?.directoryAuthorizationErrorMessage =
            nil
        states[id]?.errorMessage = message
        states[id]?.lastRefreshedAt = nowProvider()
        states[id]?.isLoading = false
        logger.error(
            "\(provider.displayName) 加载失败: \(error.localizedDescription)"
        )
        if shouldNotify {
            notifyStateChange(id)
        }
    }
}
~~~

删除 markProvidersAuthorized(sharingBookmarkWith:)，把 requestAuthorization(for:) 完整替换为：

~~~swift
/// 为指定 provider 显示数据目录选择面板。
/// - Parameter id: 唯一 provider 标识。
/// - Returns: bookmark 成功保存时返回 true；取消、保存失败、
///   provider 不存在或已有同 provider 目录操作时返回 false。
@discardableResult
func requestAuthorization(
    for id: ProviderID
) async -> Bool {
    guard let provider = provider(for: id) else {
        return false
    }
    guard !loadGate.isActive(id),
          states[id]?.isAuthorizing != true
    else {
        logger.info(
            "\(provider.displayName) 正在执行目录操作,跳过重复授权"
        )
        return false
    }

    states[id]?.isAuthorizing = true
    notifyStateChange(id)

    let result =
        await bookmarkManager.promptUserToSelectDirectory(
            forProvider: provider
        )

    switch result {
    case .cancelled:
        states[id]?.isAuthorizing = false
        logger.info(
            "\(provider.displayName) 用户取消目录选择"
        )
        notifyStateChange(id)
        return false

    case .failed:
        states[id]?.isAuthorizing = false
        states[id]?.directoryAuthorizationErrorMessage =
            Self.authorizationFailedMessage(
                providerName: provider.displayName,
                language: languageSettings.resolvedLanguage
            )
        logger.error(
            "\(provider.displayName) 目录授权保存失败"
        )
        notifyStateChange(id)
        return false

    case .authorized(_):
        states[id]?.isAuthorizing = false
        states[id]?.directoryAuthorizationErrorMessage =
            nil
        setDirectoryState(.selected, for: id)

        // 从 isAuthorizing 切到 load gate 的过程必须保持原子：
        // 此处之前没有 observer 回调，此处也不能插入 await。
        guard loadGate.enter(id) else {
            logger.error(
                "\(provider.displayName) 授权成功后未能取得加载门禁"
            )
            notifyStateChange(id)
            return true
        }

        logger.info(
            "\(provider.displayName) 用户授权成功"
        )
        await performLoad(
            for: provider,
            mode: .interactive
        )
        return true
    }
}
~~~

为 ProviderLoadGate 增加只读查询：

~~~swift
func isActive(_ id: ProviderID) -> Bool {
    activeProviderIDs.contains(id)
}
~~~

- [ ] **Step 5: 运行 ViewModel suite 并确认 GREEN**

~~~bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch \
  -destination 'platform=macOS' \
  -only-testing:TokenWatchTests/TokenStatsViewModelObserverTests \
  -skip-testing:TokenWatchUITests \
  -derivedDataPath .build/DerivedData test
~~~

Expected: PASS，输出 ** TEST SUCCEEDED **。既有静默刷新测试必须继续证明数据未变化时不重新聚合、不通知 UI；既有 parser 失败测试必须继续保留最后一次成功的 entries。

- [ ] **Step 6: 做 Home/shared 状态静态检查**

~~~bash
! rg -n \
  'cannotAccessHomeMessage|markProvidersAuthorized|loadAllStats\\(\\)' \
  TokenWatch/ViewModels/TokenStatsViewModel.swift \
  TokenWatchTests/ViewModels/TokenStatsViewModelObserverTests.swift
~~~

Expected: 无输出，exit code 0。

~~~bash
rg -n \
  'ProviderDirectoryState|directoryAuthorizationErrorMessage|isAuthorizing|loadGate\\.isActive' \
  TokenWatch/ViewModels/TokenStatsViewModel.swift
~~~

Expected: 四个模式均有匹配。

- [ ] **Step 7: 提交独立 ViewModel 状态**

~~~bash
git add TokenWatch/ViewModels/TokenStatsViewModel.swift \
  TokenWatch/Localization/AppStrings.swift \
  TokenWatchTests/ViewModels/TokenStatsViewModelObserverTests.swift
git commit -m "fix(viewmodel): 隔离数据源目录授权状态"
~~~

---

### Task 5: 启动只清理遗留 Home 状态并加载数据

**Files:**
- Modify: `TokenWatch/AppDelegate.swift:13-14,38-70,151-154,190-217`
- Modify: `TokenWatchTests/TokenWatchTests.swift:15-109`
- Modify: `TokenWatchUITests/TokenWatchUITests.swift:107-125`

**Interfaces:**
- Produces: `LegacyAuthorizationCleaner.removeLegacyState(from:)`。
- Replaces: `AppLaunchAuthorizationCoordinator` with `AppLaunchDataCoordinator`，后者没有任何授权 prompt closure。
- Removes all reads of `TokenWatch.didPromptInitialHomeAuthorization`。

- [ ] **Step 1: 用“清理后加载”测试替换四个首次弹窗测试**

```swift
@MainActor
@Test("启动只清理遗留授权再加载数据")
func startupOnlyCleansLegacyStateThenLoadsStats() async {
    var events: [String] = []
    let coordinator = AppLaunchDataCoordinator(
        clearLegacyAuthorization: { events.append("cleanup") },
        loadAllStats: { events.append("load") }
    )

    await coordinator.performStartupWork()

    #expect(events == ["cleanup", "load"])
}

@MainActor
@Test("遗留清理不影响新 provider bookmark 和其他偏好")
func legacyCleanupPreservesProviderBookmarksAndOtherPreferences() throws {
    let suiteName = "LegacyAuthorizationCleaner-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(Data([1]), forKey: "HomeDirectoryBookmark")
    defaults.set(true, forKey: "TokenWatch.didPromptInitialHomeAuthorization")
    defaults.set(Data([2]), forKey: "ClaudeDataDirectoryBookmark")
    defaults.set(Data([3]), forKey: "CodexDataDirectoryBookmark")
    defaults.set(Data([4]), forKey: "OpenCodeDataDirectoryBookmark")
    defaults.set("minutes5", forKey: "TokenWatch.autoRefreshInterval")
    defaults.set("en", forKey: AppLanguageSettings.storageKey)

    LegacyAuthorizationCleaner.removeLegacyState(from: defaults)

    #expect(defaults.object(forKey: "HomeDirectoryBookmark") == nil)
    #expect(defaults.object(forKey: "TokenWatch.didPromptInitialHomeAuthorization") == nil)
    #expect(defaults.data(forKey: "ClaudeDataDirectoryBookmark") == Data([2]))
    #expect(defaults.data(forKey: "CodexDataDirectoryBookmark") == Data([3]))
    #expect(defaults.data(forKey: "OpenCodeDataDirectoryBookmark") == Data([4]))
    #expect(defaults.string(forKey: "TokenWatch.autoRefreshInterval") == "minutes5")
    #expect(defaults.string(forKey: AppLanguageSettings.storageKey) == "en")
}
```

- [ ] **Step 2: 运行定向测试并确认 RED**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch \
  -destination 'platform=macOS' \
  '-only-testing:TokenWatchTests/TokenWatchTests/startupOnlyCleansLegacyStateThenLoadsStats()' \
  '-only-testing:TokenWatchTests/TokenWatchTests/legacyCleanupPreservesProviderBookmarksAndOtherPreferences()' \
  -skip-testing:TokenWatchUITests \
  -derivedDataPath .build/DerivedData test
```

Expected: FAIL；新协调器和 cleaner 尚不存在。

- [ ] **Step 3: 实现无法弹窗的启动协调器**

在 `AppDelegate.swift` 的 `import Cocoa` 后加入 `import os.log`。删除 `initialAuthorizationPromptedKey`、`hasPromptedInitialAuthorization()` 和整个 `AppLaunchAuthorizationCoordinator`。增加：

```swift
enum LegacyAuthorizationCleaner {
    static let homeBookmarkKey = "HomeDirectoryBookmark"
    static let initialPromptKey = "TokenWatch.didPromptInitialHomeAuthorization"
    private static let logger = Logger(
        subsystem: "com.xiaoao.TokenWatch",
        category: "LegacyAuthorizationCleaner"
    )

    /// 删除旧共享 Home 授权状态，不迁移也不触碰 provider 独立 bookmark。
    /// - Parameter defaults: 保存遗留键的偏好域。
    static func removeLegacyState(from defaults: UserDefaults) {
        let removedLegacyState = defaults.object(forKey: homeBookmarkKey) != nil
            || defaults.object(forKey: initialPromptKey) != nil
        defaults.removeObject(forKey: homeBookmarkKey)
        defaults.removeObject(forKey: initialPromptKey)
        if removedLegacyState {
            logger.info("已清理旧 Home 目录授权状态")
        }
    }
}

@MainActor
struct AppLaunchDataCoordinator {
    let clearLegacyAuthorization: () -> Void
    let loadAllStats: () async -> Void

    /// 执行无交互启动流程：先清理旧授权，再按现有 provider 状态加载。
    func performStartupWork() async {
        clearLegacyAuthorization()
        await loadAllStats()
    }
}
```

`applicationDidFinishLaunching` 的 Task 只能构造：

```swift
let coordinator = AppLaunchDataCoordinator(
    clearLegacyAuthorization: {
        LegacyAuthorizationCleaner.removeLegacyState(from: .standard)
    },
    loadAllStats: { [viewModel] in
        await viewModel.loadAllStats()
    }
)
await coordinator.performStartupWork()
```

不得留下 `hasBookmark`、`requestInitialAuthorization` 或任何 provider prompt 调用。

- [ ] **Step 4: 从 UI helper 删除审核路径跳过参数**

从 `launchForUITesting` 删除：

```swift
"-TokenWatch.didPromptInitialHomeAuthorization", "YES",
```

为避免宿主 app 容器中的历史 bookmark 污染测试，显式用 argument domain 覆盖三个新 key 为非 Data：

```swift
launchArguments += [
    "-ClaudeDataDirectoryBookmark", "absent",
    "-CodexDataDirectoryBookmark", "absent",
    "-OpenCodeDataDirectoryBookmark", "absent",
    "-TokenWatch.languagePreference", languagePreference,
    "-TokenWatch.openMainWindowOnLaunch", "YES",
]
```

- [ ] **Step 5: 运行启动测试、编译 UI test target 并提交**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch \
  -destination 'platform=macOS' \
  '-only-testing:TokenWatchTests/TokenWatchTests/startupOnlyCleansLegacyStateThenLoadsStats()' \
  '-only-testing:TokenWatchTests/TokenWatchTests/legacyCleanupPreservesProviderBookmarksAndOtherPreferences()' \
  -skip-testing:TokenWatchUITests \
  -derivedDataPath .build/DerivedData test

xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData build-for-testing
```

Expected: 第一条 `** TEST SUCCEEDED **`；第二条 `** TEST BUILD SUCCEEDED **`，证明本 Task 修改的 UI helper 也能编译。

```bash
git add TokenWatch/AppDelegate.swift \
  TokenWatchTests/TokenWatchTests.swift \
  TokenWatchUITests/TokenWatchUITests.swift
git commit -m "fix(launch): 移除首次启动目录弹窗"
```

---

### Task 6: 设置页展示三个独立目录行并移除 Home 可见文案

**Files:**
- Modify: `TokenWatch/ViewController.swift:140-573`
- Modify: `TokenWatch/ViewControllers/DashboardViewController.swift:1946-1992`
- Modify: `TokenWatch/Providers/UsageProvider.swift:3-32`
- Modify: `TokenWatch/Localization/AppStrings.swift:8-148,185-1875`
- Modify: `TokenWatchTests/TokenWatchTests.swift:229-2100`
- Verify: `TokenWatchTests/ViewControllers/DashboardSessionPaginationTests.swift:635-645`
- Modify: `TokenWatchTests/Localization/AppLanguageSettingsTests.swift:115-179`

**Interfaces:**
- Produces stable identifiers: `ProviderDirectoryRow.<provider-id>`、`ProviderDirectoryName.<provider-id>`、`ProviderDirectoryStatus.<provider-id>`、`ProviderDirectoryAction.<provider-id>`。
- Produces: `ProviderDirectoryRowModel.make(provider:state:language:)` as the single pure rendering decision.
- Adds: `SettingsViewController.minimumContentHeight = 540`。
- Changes Settings designated initializer to accept provider list, state provider and async authorization action; retains a compatibility convenience initializer for unrelated visual tests.
- Adds: `performDirectoryAuthorization(forButtonTag:) async -> Bool`，测试可等待完整 tag-to-provider 路由，不依赖未结构化 `Task` 的时序。
- Notification rule: `.providerStateDidChange` 只重绘 `userInfo["providerID"]` 指定的行；语言变化与 `viewWillAppear` 才重绘全部行。

- [ ] **Step 1: 写三行状态、操作路由和显式本地化测试**

在 `TokenWatchTests.swift` 增加：

```swift
@MainActor
@Test("设置页显示三个 provider 独立目录控件")
func settingsShowsIndependentProviderDirectoryRows() throws {
    let states: [ProviderID: TokenStatsViewModel.ProviderState] = [
        .claude: .init(
            stats: nil,
            entries: nil,
            isLoading: false,
            errorMessage: nil,
            needsAuthorization: true,
            directoryState: .notSelected
        ),
        .codex: .init(
            stats: nil,
            entries: [],
            isLoading: false,
            errorMessage: nil,
            needsAuthorization: false,
            directoryState: .selectedNoData
        ),
        .opencode: .init(
            stats: nil,
            entries: nil,
            isLoading: false,
            errorMessage: nil,
            needsAuthorization: true,
            directoryState: .needsReselection
        ),
    ]
    let controller = SettingsViewController(
        providers: ProviderRegistry.allProviders,
        providerState: { states[$0] },
        authorizationAction: { _ in false },
        languageSettings: zhHansLanguageSettings()
    )
    controller.loadViewIfNeeded()

    #expect((controller.view.firstDescendant(identifier: "ProviderDirectoryStatus.claude") as? NSTextField)?.stringValue == "未选择")
    #expect(controller.view.button(identifier: "ProviderDirectoryAction.claude")?.title == "选择文件夹")
    #expect((controller.view.firstDescendant(identifier: "ProviderDirectoryStatus.codex") as? NSTextField)?.stringValue == "所选文件夹中未发现数据")
    #expect(controller.view.button(identifier: "ProviderDirectoryAction.codex")?.title == "重新选择")
    #expect((controller.view.firstDescendant(identifier: "ProviderDirectoryStatus.opencode") as? NSTextField)?.stringValue == "需要重新选择")
    #expect(controller.view.button(identifier: "ProviderDirectoryAction.opencode")?.title == "再次选择")
}

@MainActor
@Test("三个目录按钮均把正确 provider 传给授权动作并可等待完成")
func settingsDirectoryButtonsRouteProviderID() async throws {
    let providers = ProviderRegistry.allProviders
    let expectedResults: [ProviderID: Bool] = [
        .claude: true,
        .codex: false,
        .opencode: true,
    ]
    var requested: [ProviderID] = []
    let controller = SettingsViewController(
        providers: providers,
        providerState: { _ in .init(stats: nil, entries: nil) },
        authorizationAction: { id in
            requested.append(id)
            return expectedResults[id] ?? false
        },
        languageSettings: zhHansLanguageSettings()
    )
    controller.loadViewIfNeeded()

    var completedResults: [Bool] = []
    for provider in providers {
        let button = try #require(controller.view.button(
            identifier: "ProviderDirectoryAction.\(provider.id.rawValue)"
        ))
        completedResults.append(
            await controller.performDirectoryAuthorization(
                forButtonTag: button.tag
            )
        )
    }

    #expect(requested == providers.map { $0.id })
    #expect(completedResults == [true, false, true])

    #expect(!(await controller.performDirectoryAuthorization(forButtonTag: -1)))
    #expect(requested == providers.map { $0.id })
}
```

再加入以下完整测试：

```swift
@MainActor
@Test("provider 通知只读取并刷新指定目录行")
func settingsDirectoryRowsRefreshAfterProviderNotification() throws {
    var states = Dictionary(uniqueKeysWithValues: ProviderID.allCases.map {
        ($0, TokenStatsViewModel.ProviderState(stats: nil, entries: nil))
    })
    var requestedStateIDs: [ProviderID] = []
    let controller = SettingsViewController(
        providers: ProviderRegistry.allProviders,
        providerState: {
            requestedStateIDs.append($0)
            return states[$0]
        },
        authorizationAction: { _ in false },
        languageSettings: zhHansLanguageSettings()
    )
    controller.loadViewIfNeeded()
    requestedStateIDs.removeAll()
    let codexLabel = try #require(
        controller.view.firstDescendant(identifier: "ProviderDirectoryStatus.codex") as? NSTextField
    )
    let codexTextBefore = codexLabel.stringValue

    states[.claude]?.directoryState = .selected
    states[.claude]?.needsAuthorization = false
    NotificationCenter.default.post(
        name: .providerStateDidChange,
        object: nil,
        userInfo: ["providerID": ProviderID.claude]
    )

    #expect((controller.view.firstDescendant(
        identifier: "ProviderDirectoryStatus.claude"
    ) as? NSTextField)?.stringValue == "已选择")
    #expect(codexLabel.stringValue == codexTextBefore)
    #expect(requestedStateIDs == [.claude])

    requestedStateIDs.removeAll()
    NotificationCenter.default.post(
        name: .providerStateDidChange,
        object: nil
    )
    #expect(requestedStateIDs.isEmpty)
}

@MainActor
@Test("加载或授权期间只禁用对应 provider 按钮")
func settingsKeepsDirectoryButtonsDisabledDuringLoadOrAuthorization() throws {
    let states: [ProviderID: TokenStatsViewModel.ProviderState] = [
        .claude: .init(stats: nil, entries: nil, isLoading: true),
        .codex: .init(stats: nil, entries: nil, isAuthorizing: true),
        .opencode: .init(stats: nil, entries: nil),
    ]
    let controller = SettingsViewController(
        providers: ProviderRegistry.allProviders,
        providerState: { states[$0] },
        authorizationAction: { _ in false },
        languageSettings: zhHansLanguageSettings()
    )
    controller.loadViewIfNeeded()

    #expect(controller.view.button(identifier: "ProviderDirectoryAction.claude")?.isEnabled == false)
    #expect(controller.view.button(identifier: "ProviderDirectoryAction.codex")?.isEnabled == false)
    #expect(controller.view.button(identifier: "ProviderDirectoryAction.opencode")?.isEnabled == true)
}

@MainActor
@Test("总览只在全部无数据时提示选择文件夹")
func dashboardEmptyStateRequestsDataFolderSelection() throws {
    let languageSettings = zhHansLanguageSettings()
    let allUnselected = DashboardViewController(
        settingsViewController: SettingsViewController(
            isAuthorized: { false },
            languageSettings: languageSettings
        ),
        stateProvider: {
            Dictionary(uniqueKeysWithValues: ProviderID.allCases.map {
                ($0, TokenStatsViewModel.ProviderState(stats: nil, entries: nil))
            })
        },
        refreshAction: {},
        languageSettings: languageSettings
    )
    allUnselected.loadViewIfNeeded()
    #expect(allUnselected.view.visibleTextValues().contains(
        "请在设置中选择一个或多个数据文件夹"
    ))

    let partialData = DashboardViewController(
        settingsViewController: SettingsViewController(
            isAuthorized: { false },
            languageSettings: languageSettings
        ),
        stateProvider: { [
            .claude: .init(
                stats: makeDashboardStats(
                    byDay: ["2026-07-16": makeDashboardSummary(total: 1_000)]
                ),
                entries: [],
                needsAuthorization: false,
                directoryState: .selected
            ),
            .codex: .init(stats: nil, entries: nil),
            .opencode: .init(stats: nil, entries: nil),
        ] },
        refreshAction: {},
        languageSettings: languageSettings
    )
    partialData.loadViewIfNeeded()
    #expect(!partialData.view.visibleTextValues().contains(
        "请在设置中选择一个或多个数据文件夹"
    ))
}

@MainActor
@Test("设置三行目录控件和既有设置项在最小高度内不裁切")
func settingsProviderRowsFitMinimumHeight() throws {
    let controller = SettingsViewController(
        providerState: { _ in .init(stats: nil, entries: nil) },
        authorizationAction: { _ in false },
        languageSettings: zhHansLanguageSettings()
    )
    controller.loadViewIfNeeded()
    controller.view.frame = NSRect(
        x: 0,
        y: 0,
        width: 480,
        height: SettingsViewController.minimumContentHeight
    )
    controller.view.layoutSubtreeIfNeeded()

    #expect(
        controller.view.frame.height
            == SettingsViewController.minimumContentHeight
    )
    let panel = try #require(controller.view.firstDescendant(identifier: "SettingsPanel"))
    #expect(controller.view.bounds.contains(panel.frame))
    for identifier in [
        "ProviderDirectoryStatus.claude",
        "ProviderDirectoryStatus.codex",
        "ProviderDirectoryStatus.opencode",
        "ProviderDirectoryAction.claude",
        "ProviderDirectoryAction.codex",
        "ProviderDirectoryAction.opencode",
        "AutoRefreshIntervalPopUpButton",
        "LaunchAtLoginSwitch",
        "LanguagePreferencePopUpButton",
        "RefreshAllDataButton",
    ] {
        let control = try #require(controller.view.firstDescendant(identifier: identifier))
        #expect(controller.view.bounds.contains(control.convert(control.bounds, to: controller.view)))
    }
}

@MainActor
@Test("设置三行目录控件保持水平布局")
func settingsProviderDirectoryRowsUseHorizontalLayout() throws {
    let controller = SettingsViewController(
        isAuthorized: { false },
        languageSettings: zhHansLanguageSettings()
    )
    controller.loadViewIfNeeded()

    for id in ProviderID.allCases {
        let row = try #require(
            controller.view.firstDescendant(
                identifier: "ProviderDirectoryRow.\(id.rawValue)"
            ) as? NSStackView
        )
        let name = try #require(
            controller.view.firstDescendant(
                identifier: "ProviderDirectoryName.\(id.rawValue)"
            )
        )
        let status = try #require(
            controller.view.firstDescendant(
                identifier: "ProviderDirectoryStatus.\(id.rawValue)"
            )
        )
        let action = try #require(
            controller.view.button(
                identifier: "ProviderDirectoryAction.\(id.rawValue)"
            )
        )

        #expect(row.orientation == .horizontal)
        #expect(row.arrangedSubviews.contains(name))
        #expect(row.arrangedSubviews.contains(status))
        #expect(row.arrangedSubviews.contains(action))
    }
}
```

在 `AppLanguageSettingsTests` 增加以下完整测试。必须对 `AppLanguage.allCases` 的每种语言逐 key 核对显式期望值，不能只依赖现有英文 fallback/非空测试：

```swift
@Test
func directoryAuthorizationStringsCoverEverySupportedLanguage() {
    let keys: [AppStringKey] = [
        .settingsDataFoldersTitle,
        .settingsDescription,
        .settingsDirectoryNotSelected,
        .settingsDirectorySelected,
        .settingsDirectoryNeedsReselection,
        .settingsDirectoryNoData,
        .settingsChooseDirectory,
        .settingsReselectDirectory,
        .settingsChooseAgain,
        .claudeDataDirectoryOpenPanelMessage,
        .codexDataDirectoryOpenPanelMessage,
        .openCodeDataDirectoryOpenPanelMessage,
        .chooseDirectoryPrompt,
        .statusNeedsDataDirectorySelection,
        .errorCannotAccessProviderDirectoryFormat,
        .errorProviderDirectoryAuthorizationFailedFormat,
    ]

    let expected: [AppLanguage: [String]] = [
        .zhHans: [
            "数据文件夹",
            "选择各数据源的数据文件夹并管理数据刷新。",
            "未选择",
            "已选择",
            "需要重新选择",
            "所选文件夹中未发现数据",
            "选择文件夹",
            "重新选择",
            "再次选择",
            "选择 Claude Code 数据文件夹",
            "选择 Codex 数据文件夹",
            "选择 opencode 数据文件夹",
            "选择",
            "请在设置中选择一个或多个数据文件夹",
            "无法访问 %@ 数据文件夹，请再次选择。",
            "无法保存 %@ 数据文件夹的访问权限，请重新选择。",
        ],
        .zhHant: [
            "資料檔案夾",
            "選擇各資料來源的資料檔案夾並管理資料重新整理。",
            "未選擇",
            "已選擇",
            "需要重新選擇",
            "找不到資料",
            "選擇檔案夾",
            "重新選擇",
            "再次選擇",
            "請選擇包含 Claude Code 資料的檔案夾。",
            "請選擇包含 Codex 資料的檔案夾。",
            "請選擇包含 opencode 資料的檔案夾。",
            "選擇",
            "請在設定中選擇一個或多個資料檔案夾",
            "無法存取已選擇的 %@ 資料檔案夾，請重新選擇",
            "無法儲存 %@ 資料檔案夾的存取權限，請再試一次",
        ],
        .en: [
            "Data Folders",
            "Choose provider data folders and manage data refresh.",
            "Not selected",
            "Selected",
            "Needs reselection",
            "No data found in the selected folder",
            "Choose Folder",
            "Reselect",
            "Choose Again",
            "Choose the Claude Code data folder",
            "Choose the Codex data folder",
            "Choose the opencode data folder",
            "Choose",
            "Choose one or more data folders in Settings",
            "Cannot access the %@ data folder. Please choose it again.",
            "Could not save access to the %@ data folder. Please choose again.",
        ],
        .ja: [
            "データフォルダ",
            "各データソースのデータフォルダを選択し、データ更新を管理します。",
            "未選択",
            "選択済み",
            "再選択が必要です",
            "データが見つかりません",
            "フォルダを選択",
            "フォルダを変更",
            "もう一度選択",
            "Claude Code のデータを含むフォルダを選択してください。",
            "Codex のデータを含むフォルダを選択してください。",
            "opencode のデータを含むフォルダを選択してください。",
            "選択",
            "設定で1つ以上のデータフォルダを選択してください",
            "選択した %@ のデータフォルダにアクセスできません。もう一度選択してください",
            "%@ のデータフォルダへのアクセス権を保存できませんでした。もう一度お試しください",
        ],
        .ko: [
            "데이터 폴더",
            "각 데이터 소스의 데이터 폴더를 선택하고 데이터 새로 고침을 관리합니다.",
            "선택 안 함",
            "선택됨",
            "다시 선택해야 함",
            "데이터를 찾을 수 없음",
            "폴더 선택",
            "폴더 변경",
            "다시 선택",
            "Claude Code 데이터가 포함된 폴더를 선택하세요.",
            "Codex 데이터가 포함된 폴더를 선택하세요.",
            "opencode 데이터가 포함된 폴더를 선택하세요.",
            "선택",
            "설정에서 하나 이상의 데이터 폴더를 선택하세요",
            "선택한 %@ 데이터 폴더에 접근할 수 없습니다. 다시 선택하세요",
            "%@ 데이터 폴더 접근 권한을 저장하지 못했습니다. 다시 시도하세요",
        ],
        .es: [
            "Carpetas de datos",
            "Elige las carpetas de datos de cada fuente y gestiona la actualización de datos.",
            "Sin seleccionar",
            "Seleccionada",
            "Debe volver a seleccionarse",
            "No se encontraron datos",
            "Elegir carpeta",
            "Cambiar carpeta",
            "Elegir de nuevo",
            "Elige la carpeta que contiene los datos de Claude Code.",
            "Elige la carpeta que contiene los datos de Codex.",
            "Elige la carpeta que contiene los datos de opencode.",
            "Elegir",
            "Selecciona una o varias carpetas de datos en Configuración",
            "No se puede acceder a la carpeta de datos seleccionada para %@. Vuelve a elegirla",
            "No se pudo guardar el acceso a la carpeta de datos de %@. Inténtalo de nuevo",
        ],
        .de: [
            "Datenordner",
            "Wähle die Datenordner der einzelnen Quellen aus und verwalte die Datenaktualisierung.",
            "Nicht ausgewählt",
            "Ausgewählt",
            "Erneute Auswahl erforderlich",
            "Keine Daten gefunden",
            "Ordner auswählen",
            "Ordner ändern",
            "Erneut auswählen",
            "Wähle den Ordner aus, der die Daten von Claude Code enthält.",
            "Wähle den Ordner aus, der die Daten von Codex enthält.",
            "Wähle den Ordner aus, der die Daten von opencode enthält.",
            "Auswählen",
            "Wähle in den Einstellungen mindestens einen Datenordner aus",
            "Auf den ausgewählten Datenordner von %@ kann nicht zugegriffen werden. Wähle ihn erneut aus",
            "Der Zugriff auf den Datenordner von %@ konnte nicht gespeichert werden. Versuche es erneut",
        ],
        .fr: [
            "Dossiers de données",
            "Choisissez les dossiers de données de chaque source et gérez l’actualisation des données.",
            "Non sélectionné",
            "Sélectionné",
            "Nouvelle sélection requise",
            "Aucune donnée trouvée",
            "Choisir un dossier",
            "Changer de dossier",
            "Choisir à nouveau",
            "Choisissez le dossier contenant les données de Claude Code.",
            "Choisissez le dossier contenant les données de Codex.",
            "Choisissez le dossier contenant les données d'opencode.",
            "Choisir",
            "Sélectionnez un ou plusieurs dossiers de données dans Paramètres",
            "Impossible d'accéder au dossier de données sélectionné pour %@. Choisissez-le à nouveau",
            "Impossible d'enregistrer l'accès au dossier de données de %@. Réessayez",
        ],
        .ptBR: [
            "Pastas de dados",
            "Escolha as pastas de dados de cada fonte e gerencie a atualização dos dados.",
            "Não selecionada",
            "Selecionada",
            "Nova seleção necessária",
            "Nenhum dado encontrado",
            "Escolher pasta",
            "Alterar pasta",
            "Escolher novamente",
            "Escolha a pasta que contém os dados do Claude Code.",
            "Escolha a pasta que contém os dados do Codex.",
            "Escolha a pasta que contém os dados do opencode.",
            "Escolher",
            "Selecione uma ou mais pastas de dados em Configurações",
            "Não foi possível acessar a pasta de dados selecionada para %@. Escolha-a novamente",
            "Não foi possível salvar o acesso à pasta de dados de %@. Tente novamente",
        ],
        .it: [
            "Cartelle dati",
            "Scegli le cartelle dati di ogni origine e gestisci l’aggiornamento dei dati.",
            "Non selezionata",
            "Selezionata",
            "Nuova selezione necessaria",
            "Nessun dato trovato",
            "Scegli cartella",
            "Cambia cartella",
            "Scegli di nuovo",
            "Scegli la cartella contenente i dati di Claude Code.",
            "Scegli la cartella contenente i dati di Codex.",
            "Scegli la cartella contenente i dati di opencode.",
            "Scegli",
            "Seleziona una o più cartelle dati in Impostazioni",
            "Impossibile accedere alla cartella dati selezionata per %@. Selezionala di nuovo",
            "Impossibile salvare l'accesso alla cartella dati di %@. Riprova",
        ],
        .nl: [
            "Gegevensmappen",
            "Kies de gegevensmappen per bron en beheer het vernieuwen van gegevens.",
            "Niet geselecteerd",
            "Geselecteerd",
            "Opnieuw selecteren vereist",
            "Geen gegevens gevonden",
            "Map kiezen",
            "Map wijzigen",
            "Opnieuw kiezen",
            "Kies de map met de gegevens van Claude Code.",
            "Kies de map met de gegevens van Codex.",
            "Kies de map met de gegevens van opencode.",
            "Kiezen",
            "Selecteer een of meer gegevensmappen in Instellingen",
            "De geselecteerde gegevensmap voor %@ is niet toegankelijk. Kies deze opnieuw",
            "Toegang tot de gegevensmap van %@ kon niet worden opgeslagen. Probeer het opnieuw",
        ],
        .pl: [
            "Foldery danych",
            "Wybierz foldery danych dla poszczególnych źródeł i zarządzaj odświeżaniem danych.",
            "Nie wybrano",
            "Wybrano",
            "Wymaga ponownego wyboru",
            "Nie znaleziono danych",
            "Wybierz folder",
            "Zmień folder",
            "Wybierz ponownie",
            "Wybierz folder zawierający dane Claude Code.",
            "Wybierz folder zawierający dane Codex.",
            "Wybierz folder zawierający dane opencode.",
            "Wybierz",
            "Wybierz co najmniej jeden folder danych w Ustawieniach",
            "Nie można uzyskać dostępu do folderu danych wybranego dla %@. Wybierz go ponownie",
            "Nie udało się zapisać dostępu do folderu danych dla %@. Spróbuj ponownie",
        ],
    ]

    #expect(keys.allSatisfy { AppStringKey.allCases.contains($0) })
    #expect(expected.count == AppLanguage.allCases.count)
    for language in AppLanguage.allCases {
        #expect(expected[language] != nil)
        if let expectedValues = expected[language] {
            #expect(
                keys.map { AppStrings.text($0, language: language) }
                    == expectedValues
            )
        }
    }

    let formatKeys: [AppStringKey] = [
        .errorCannotAccessProviderDirectoryFormat,
        .errorProviderDirectoryAuthorizationFailedFormat,
    ]
    for language in AppLanguage.allCases {
        for key in formatKeys {
            let format = AppStrings.text(key, language: language)
            #expect(
                format.components(separatedBy: "%@").count == 2,
                "\(key) must contain exactly one provider token in \(language)"
            )
            for providerName in ["Claude Code", "Codex", "opencode"] {
                #expect(String(format: format, providerName).contains(providerName))
            }
        }
    }
}
```

- [ ] **Step 2: 运行设置与本地化测试并确认 RED**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch \
  -destination 'platform=macOS' \
  '-only-testing:TokenWatchTests/TokenWatchTests/settingsShowsIndependentProviderDirectoryRows()' \
  '-only-testing:TokenWatchTests/TokenWatchTests/settingsDirectoryButtonsRouteProviderID()' \
  '-only-testing:TokenWatchTests/TokenWatchTests/settingsDirectoryRowsRefreshAfterProviderNotification()' \
  '-only-testing:TokenWatchTests/TokenWatchTests/settingsKeepsDirectoryButtonsDisabledDuringLoadOrAuthorization()' \
  '-only-testing:TokenWatchTests/TokenWatchTests/settingsProviderDirectoryRowsUseHorizontalLayout()' \
  '-only-testing:TokenWatchTests/TokenWatchTests/dashboardEmptyStateRequestsDataFolderSelection()' \
  '-only-testing:TokenWatchTests/TokenWatchTests/settingsProviderRowsFitMinimumHeight()' \
  '-only-testing:TokenWatchTests/AppLanguageSettingsTests/directoryAuthorizationStringsCoverEverySupportedLanguage()' \
  -skip-testing:TokenWatchUITests \
  -derivedDataPath .build/DerivedData test
```

Expected: FAIL；三行 UI、状态模型和新增 key 尚不存在。

- [ ] **Step 3: 实现纯行模型和三行布局**

在 `ViewController.swift`、`SettingsViewController` 前增加：

```swift
enum ProviderDirectoryActionStyle: Sendable, Equatable {
    case primary
    case neutral
}

struct ProviderDirectoryRowModel: Sendable, Equatable {
    let providerID: ProviderID
    let providerName: String
    let statusText: String
    let actionTitle: String
    let actionStyle: ProviderDirectoryActionStyle
    let isActionEnabled: Bool

    /// 根据单一 provider 状态生成设置行，不读取共享 bookmark 或其他 provider。
    static func make(
        provider: any UsageProvider,
        state: TokenStatsViewModel.ProviderState,
        language: AppLanguage
    ) -> ProviderDirectoryRowModel {
        let statusText: String
        if let error = state.directoryAuthorizationErrorMessage {
            statusText = error
        } else {
            let key: AppStringKey
            switch state.directoryState {
            case .notSelected: key = .settingsDirectoryNotSelected
            case .selected: key = .settingsDirectorySelected
            case .selectedNoData: key = .settingsDirectoryNoData
            case .needsReselection: key = .settingsDirectoryNeedsReselection
            }
            statusText = AppStrings.text(key, language: language)
        }

        let actionKey: AppStringKey
        let actionStyle: ProviderDirectoryActionStyle
        switch state.directoryState {
        case .notSelected:
            actionKey = .settingsChooseDirectory
            actionStyle = .primary
        case .selected, .selectedNoData:
            actionKey = .settingsReselectDirectory
            actionStyle = .neutral
        case .needsReselection:
            actionKey = .settingsChooseAgain
            actionStyle = .primary
        }

        return ProviderDirectoryRowModel(
            providerID: provider.id,
            providerName: provider.displayName,
            statusText: statusText,
            actionTitle: AppStrings.text(actionKey, language: language),
            actionStyle: actionStyle,
            isActionEnabled: !state.isLoading && !state.isAuthorizing
        )
    }
}
```

删除 `authorizationTitleLabel`、`authorizationActionButton` 和 `isAuthorized` stored property。`SettingsViewController` 的完整 stored-property 区域改为：

```swift
final class SettingsViewController: NSViewController {
    static let minimumContentHeight: CGFloat = 540

    private struct ProviderDirectoryRowViews {
        let nameLabel: NSTextField
        let statusLabel: NSTextField
        let actionButton: DashboardRangeButton
    }

    private let titleLabel = NSTextField(labelWithString: "")
    private let descriptionLabel = NSTextField(labelWithString: "")
    private let dataFoldersTitleLabel = NSTextField(labelWithString: "")
    private let providerDirectoryStack = NSStackView()
    private let refreshButton = DashboardRangeButton(title: "", target: nil, action: nil)
    private let autoRefreshIntervalLabel = NSTextField(labelWithString: "")
    private let autoRefreshIntervalPopUpButton = SettingsPopUpButton()
    private let launchAtLoginLabel = NSTextField(labelWithString: "")
    private let launchAtLoginSwitch = NSSwitch(frame: .zero)
    private let launchAtLoginStatusLabel = NSTextField(labelWithString: "")
    private let openLoginItemsSettingsButton = DashboardRangeButton(
        title: "",
        target: nil,
        action: nil
    )
    private let languageLabel = NSTextField(labelWithString: "")
    private let languagePopUpButton = SettingsPopUpButton()

    private let providers: [any UsageProvider]
    private let providerState:
        @MainActor (ProviderID) -> TokenStatsViewModel.ProviderState?
    private let authorizationAction:
        @MainActor (ProviderID) async -> Bool
    private let loginItemSettings: LoginItemSettingsControlling
    private let autoRefreshSettings: AutoRefreshSettings
    private let languageSettings: AppLanguageSettings

    private var providerDirectoryRows:
        [ProviderID: ProviderDirectoryRowViews] = [:]
    private var languageSettingsObserverToken:
        AppLanguageSettings.ObservationToken?

    private var viewModel: TokenStatsViewModel? {
        (NSApp.delegate as? AppDelegate)?.viewModel
    }
```

Designated initializer 完整改为：

```swift
init(
    providers: [any UsageProvider] = ProviderRegistry.allProviders,
    providerState: @escaping @MainActor (ProviderID) -> TokenStatsViewModel.ProviderState? = { id in
        (NSApp.delegate as? AppDelegate)?.viewModel.states[id]
    },
    authorizationAction: @escaping @MainActor (ProviderID) async -> Bool = { id in
        guard let viewModel = (NSApp.delegate as? AppDelegate)?.viewModel else {
            return false
        }
        return await viewModel.requestAuthorization(for: id)
    },
    loginItemSettings: LoginItemSettingsControlling = LoginItemSettings.shared,
    autoRefreshSettings: AutoRefreshSettings = .shared,
    languageSettings: AppLanguageSettings = .shared
) {
    self.providers = providers
    self.providerState = providerState
    self.authorizationAction = authorizationAction
    self.loginItemSettings = loginItemSettings
    self.autoRefreshSettings = autoRefreshSettings
    self.languageSettings = languageSettings
    super.init(nibName: nil, bundle: nil)
}
```

保留以下 compatibility convenience initializer，仅供不关心 provider 状态的既有外观测试；`isAuthorized` **不得有默认值**，否则会与所有参数都有默认值的 designated initializer 在 `SettingsViewController()` 调用处产生重载歧义。它为三个 provider 返回统一 `.selected` 或 `.notSelected` state。删除生产路径对共享 bookmark key 的读取。

```swift
convenience init(
    isAuthorized: @escaping @MainActor () -> Bool,
    loginItemSettings: LoginItemSettingsControlling = LoginItemSettings.shared,
    autoRefreshSettings: AutoRefreshSettings = .shared,
    languageSettings: AppLanguageSettings = .shared
) {
    self.init(
        providers: ProviderRegistry.allProviders,
        providerState: { _ in
            let authorized = isAuthorized()
            return .init(
                stats: nil,
                entries: nil,
                needsAuthorization: !authorized,
                directoryState: authorized ? .selected : .notSelected
            )
        },
        authorizationAction: { _ in false },
        loginItemSettings: loginItemSettings,
        autoRefreshSettings: autoRefreshSettings,
        languageSettings: languageSettings
    )
}
```

现有 `convenience init(isAuthorized:defaults:)` 继续转调上面的 compatibility initializer，并把 coder initializer 改为：

```swift
required init?(coder: NSCoder) {
    fatalError("SettingsViewController 必须使用代码 initializer 构造")
}
```

生命周期完整改为：

```swift
override func loadView() {
    view = DashboardBackgroundView(
        frame: NSRect(
            x: 0,
            y: 0,
            width: 480,
            height: Self.minimumContentHeight
        ),
        backgroundColor: DashboardPalette.appBackground
    )
}

override func viewDidLoad() {
    super.viewDidLoad()
    setupSubviews()
    subscribeToLanguageSettings()
    NotificationCenter.default.addObserver(
        self,
        selector: #selector(applicationDidBecomeActive(_:)),
        name: NSApplication.didBecomeActiveNotification,
        object: nil
    )
    NotificationCenter.default.addObserver(
        self,
        selector: #selector(providerStateDidChange(_:)),
        name: .providerStateDidChange,
        object: nil
    )
    renderAllDirectoryRows()
    renderLaunchAtLoginState()
}

override func viewWillAppear() {
    super.viewWillAppear()
    renderAllDirectoryRows()
    renderLaunchAtLoginState()
}
```

在 `setupSubviews()` 删除旧 `authorizationTitleLabel` 配置、`authorizationActionButton` 配置和 `authorizationStack`。加入：

```swift
dataFoldersTitleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
dataFoldersTitleLabel.textColor = DashboardPalette.primaryText
dataFoldersTitleLabel.identifier = NSUserInterfaceItemIdentifier(
    "DataFoldersTitleLabel"
)
dataFoldersTitleLabel.setAccessibilityIdentifier("DataFoldersTitleLabel")

configureProviderDirectoryRows()
```

增加完整 row construction；button tag 必须来自注入 `providers` 的稳定索引：

```swift
/// 依照注入 providers 的稳定顺序建立目录设置行。
private func configureProviderDirectoryRows() {
    providerDirectoryStack.orientation = .vertical
    providerDirectoryStack.alignment = .fill
    providerDirectoryStack.distribution = .fill
    providerDirectoryStack.spacing = 8

    for (index, provider) in providers.enumerated() {
        let nameLabel = NSTextField(labelWithString: provider.displayName)
        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        nameLabel.textColor = DashboardPalette.primaryText
        nameLabel.identifier = NSUserInterfaceItemIdentifier(
            "ProviderDirectoryName.\(provider.id.rawValue)"
        )
        nameLabel.setAccessibilityIdentifier(
            "ProviderDirectoryName.\(provider.id.rawValue)"
        )
        nameLabel.setContentHuggingPriority(.required, for: .horizontal)
        nameLabel.setContentCompressionResistancePriority(
            .required,
            for: .horizontal
        )
        nameLabel.widthAnchor.constraint(
            greaterThanOrEqualToConstant: 88
        ).isActive = true

        let statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = DashboardPalette.secondaryText
        statusLabel.maximumNumberOfLines = 0
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.identifier = NSUserInterfaceItemIdentifier(
            "ProviderDirectoryStatus.\(provider.id.rawValue)"
        )
        statusLabel.setAccessibilityIdentifier(
            "ProviderDirectoryStatus.\(provider.id.rawValue)"
        )
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        statusLabel.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )

        let actionButton = DashboardRangeButton(
            title: "",
            target: nil,
            action: nil
        )
        configureSettingsButton(actionButton)
        actionButton.identifier = NSUserInterfaceItemIdentifier(
            "ProviderDirectoryAction.\(provider.id.rawValue)"
        )
        actionButton.setAccessibilityIdentifier(
            "ProviderDirectoryAction.\(provider.id.rawValue)"
        )
        actionButton.target = self
        actionButton.action = #selector(directoryAuthorizationButtonClicked(_:))
        actionButton.tag = index
        actionButton.setContentHuggingPriority(.required, for: .horizontal)
        actionButton.setContentCompressionResistancePriority(
            .required,
            for: .horizontal
        )
        actionButton.widthAnchor.constraint(
            greaterThanOrEqualToConstant: 92
        ).isActive = true

        let row = NSStackView(views: [nameLabel, statusLabel, actionButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.identifier = NSUserInterfaceItemIdentifier(
            "ProviderDirectoryRow.\(provider.id.rawValue)"
        )
        row.setAccessibilityIdentifier(
            "ProviderDirectoryRow.\(provider.id.rawValue)"
        )
        row.heightAnchor.constraint(
            greaterThanOrEqualToConstant: 36
        ).isActive = true

        providerDirectoryRows[provider.id] = ProviderDirectoryRowViews(
            nameLabel: nameLabel,
            statusLabel: statusLabel,
            actionButton: actionButton
        )
        providerDirectoryStack.addArrangedSubview(row)
    }
}
```

`contentStack` 精确顺序改为：

```swift
let contentStack = NSStackView(views: [
    titleLabel,
    descriptionLabel,
    dataFoldersTitleLabel,
    providerDirectoryStack,
    autoRefreshIntervalStack,
    launchAtLoginSettingsStack,
    languageStack,
    buttonStack,
])
contentStack.translatesAutoresizingMaskIntoConstraints = false
contentStack.orientation = .vertical
contentStack.alignment = .leading
contentStack.spacing = 12
```

panel 改为完整宽度并加入底部不越界约束：

```swift
NSLayoutConstraint.activate([
    panel.leadingAnchor.constraint(
        equalTo: view.leadingAnchor,
        constant: 28
    ),
    panel.trailingAnchor.constraint(
        equalTo: view.trailingAnchor,
        constant: -28
    ),
    panel.topAnchor.constraint(
        equalTo: view.topAnchor,
        constant: 28
    ),
    panel.bottomAnchor.constraint(
        lessThanOrEqualTo: view.bottomAnchor,
        constant: -28
    ),
    contentStack.leadingAnchor.constraint(
        equalTo: panel.leadingAnchor,
        constant: 24
    ),
    contentStack.trailingAnchor.constraint(
        equalTo: panel.trailingAnchor,
        constant: -24
    ),
    contentStack.topAnchor.constraint(
        equalTo: panel.topAnchor,
        constant: 24
    ),
    contentStack.bottomAnchor.constraint(
        equalTo: panel.bottomAnchor,
        constant: -24
    ),
    descriptionLabel.widthAnchor.constraint(
        equalTo: contentStack.widthAnchor
    ),
    providerDirectoryStack.widthAnchor.constraint(
        equalTo: contentStack.widthAnchor
    ),
])
```

删除 `renderAuthorizationState()`、`authorizationActionButtonClicked()` 和旧 `requestAuthorization()`，增加：

```swift
private func renderAllDirectoryRows() {
    for provider in providers {
        renderDirectoryRow(for: provider.id)
    }
}

/// 只读取并重绘指定 provider；不得查询其他 providerState。
private func renderDirectoryRow(for id: ProviderID) {
    guard
        let provider = providers.first(where: { $0.id == id }),
        let row = providerDirectoryRows[id]
    else {
        return
    }

    let state = providerState(id)
        ?? TokenStatsViewModel.ProviderState(stats: nil, entries: nil)
    let model = ProviderDirectoryRowModel.make(
        provider: provider,
        state: state,
        language: languageSettings.resolvedLanguage
    )

    row.nameLabel.stringValue = model.providerName
    row.statusLabel.stringValue = model.statusText
    row.statusLabel.setAccessibilityLabel(
        "\(model.providerName), \(model.statusText)"
    )
    row.actionButton.isEnabled = model.isActionEnabled

    switch model.actionStyle {
    case .primary:
        applySettingsButtonStyle(
            row.actionButton,
            title: model.actionTitle,
            backgroundColor: DashboardPalette.accent,
            borderColor: DashboardPalette.accent,
            textColor: DashboardPalette.rangeSelectedText
        )
    case .neutral:
        applySettingsButtonStyle(
            row.actionButton,
            title: model.actionTitle,
            backgroundColor: DashboardPalette.panelBackground,
            borderColor: DashboardPalette.border,
            textColor: DashboardPalette.primaryText
        )
    }
    row.actionButton.setAccessibilityLabel(
        "\(model.providerName), \(model.actionTitle)"
    )
}

@objc private func providerStateDidChange(_ notification: Notification) {
    guard let id = notification.userInfo?["providerID"] as? ProviderID else {
        return
    }
    renderDirectoryRow(for: id)
}

@objc private func directoryAuthorizationButtonClicked(_ sender: NSButton) {
    let tag = sender.tag
    Task { @MainActor [weak self] in
        guard let self else { return }
        _ = await performDirectoryAuthorization(forButtonTag: tag)
    }
}

/// 完成一次 button tag 到 provider 的授权路由。
/// - Parameter tag: `configureProviderDirectoryRows` 写入的 provider 索引。
/// - Returns: provider 不存在时为 false；否则原样返回授权动作结果。
@discardableResult
func performDirectoryAuthorization(forButtonTag tag: Int) async -> Bool {
    guard providers.indices.contains(tag) else {
        return false
    }
    let id = providers[tag].id
    let result = await authorizationAction(id)
    renderDirectoryRow(for: id)
    return result
}
```

`reloadLocalizedText()` 完整改为：

```swift
func reloadLocalizedText() {
    let language = languageSettings.resolvedLanguage
    titleLabel.stringValue = AppStrings.text(.settingsTitle, language: language)
    descriptionLabel.stringValue = AppStrings.text(
        .settingsDescription,
        language: language
    )
    dataFoldersTitleLabel.stringValue = AppStrings.text(
        .settingsDataFoldersTitle,
        language: language
    )

    applySettingsButtonStyle(
        refreshButton,
        title: AppStrings.text(.settingsRefreshAllData, language: language),
        backgroundColor: DashboardPalette.panelBackground,
        borderColor: DashboardPalette.border,
        textColor: DashboardPalette.primaryText
    )
    autoRefreshIntervalLabel.stringValue = AppStrings.text(
        .settingsAutoRefreshInterval,
        language: language
    )
    autoRefreshIntervalPopUpButton.setAccessibilityLabel(
        AppStrings.text(.settingsAutoRefreshInterval, language: language)
    )
    launchAtLoginLabel.stringValue = AppStrings.text(
        .settingsLaunchAtLogin,
        language: language
    )
    launchAtLoginSwitch.setAccessibilityLabel(
        AppStrings.text(.settingsLaunchAtLogin, language: language)
    )
    languageLabel.stringValue = AppStrings.text(
        .settingsLanguage,
        language: language
    )
    languagePopUpButton.setAccessibilityLabel(
        AppStrings.text(.settingsLanguage, language: language)
    )
    applySettingsButtonStyle(
        openLoginItemsSettingsButton,
        title: AppStrings.text(
            .settingsOpenLoginItemsSettings,
            language: language
        ),
        backgroundColor: DashboardPalette.panelBackground,
        borderColor: DashboardPalette.border,
        textColor: DashboardPalette.primaryText
    )
    reloadAutoRefreshIntervalPopUp(language: language)
    reloadLanguagePopUp(language: language)
    renderAllDirectoryRows()
    renderLaunchAtLoginState()
}
```

保留现有 deinit，但确认它完整清理两个 NotificationCenter selector 和语言观察者：

```swift
deinit {
    MainActor.assumeIsolated {
        NotificationCenter.default.removeObserver(self)
        if let token = languageSettingsObserverToken {
            languageSettings.removeObserver(token)
        }
    }
}
```

- [ ] **Step 4: 替换 Dashboard 和全部语言的 Home 文案**

删除下列旧 key 及全部 12 语言表值：

```text
settingsAuthorizationTitle
settingsAuthorize
settingsAuthorizeDirectory
statusNeedsHomeAuthorization
homeAccessMessage
authorizeAccessPrompt
errorCannotAccessHome
```

此时 `AppDelegate` 已不再使用旧 key，设置页也已删除共享 bookmark 查询；一并删除 `UsageProvider.swift` 中临时保留到本 Task 的整个 `ProviderAuthorization` enum。

保留仍由 Dashboard provider 状态使用的 `settingsAuthorized`。Task 1 已加入三个 provider 面板 key，Task 2 已加入 `.chooseDirectoryPrompt`，Task 4 已加入两个 error format key；本 Task 加入其余 9 个 key、更新既有 `.settingsDescription`，并确认 Step 1 列出的 16 个 key 全部存在。英文固定值：

```text
Data Folders
Choose provider data folders and manage data refresh.
Not selected
Selected
Needs reselection
No data found in the selected folder
Choose Folder
Reselect
Choose Again
Choose the Claude Code data folder
Choose the Codex data folder
Choose the opencode data folder
Choose
Choose one or more data folders in Settings
Cannot access the %@ data folder. Please choose it again.
Could not save access to the %@ data folder. Please choose again.
```

简体中文固定值：

```text
数据文件夹
选择各数据源的数据文件夹并管理数据刷新。
未选择
已选择
需要重新选择
所选文件夹中未发现数据
选择文件夹
重新选择
再次选择
选择 Claude Code 数据文件夹
选择 Codex 数据文件夹
选择 opencode 数据文件夹
选择
请在设置中选择一个或多个数据文件夹
无法访问 %@ 数据文件夹，请再次选择。
无法保存 %@ 数据文件夹的访问权限，请重新选择。
```

其余十种语言使用本任务末尾“本地化矩阵”中的固定值。`DashboardViewController.sessionStatusText` 与 `statusText` 改用 `.statusNeedsDataDirectorySelection`，并保留条件 `loadedProviderCount == 0 && unauthorizedProviderCount > 0`。一个 provider 已加载、另两个未选择时必须继续显示已有部分数据，不得显示全局选择提示；`dashboardEmptyStateRequestsDataFolderSelection()` 锁定该行为。

同时把既有 `.settingsDescription` 从“通用访问权限”语义改为文末矩阵中的 provider 数据文件夹语义；该 key 不新增，但 12 个语言表都必须显式更新并纳入同一完整语言测试。

- [ ] **Step 5: 更新既有 Settings 测试并确认 GREEN**

把依赖 `AuthorizationActionButton` 和“通用访问权限/去授权”的断言改为三个稳定标识；与 provider 无关的 appearance/login/language 测试继续走 compatibility initializer。`DashboardSessionPaginationTests.settingsViewController` 同样保持 compatibility initializer。

逐项执行以下替换：

1. 把 `settingsAuthorizedButtonUsesNeutralLightColors()` 完整替换为：

```swift
@MainActor
@Test func settingsSelectedDirectoryButtonUsesNeutralLightColors() throws {
    let appearance = try #require(NSAppearance(named: .aqua))
    let controller = SettingsViewController(
        isAuthorized: { true },
        languageSettings: zhHansLanguageSettings()
    )
    appearance.performAsCurrentDrawingAppearance {
        controller.loadViewIfNeeded()
    }

    let button = try #require(
        controller.view.button(identifier: "ProviderDirectoryAction.claude")
    )
    #expect(button.title == "重新选择")
    #expect(button.isEnabled)
    #expect(rgbHex(try #require(button.layer?.backgroundColor)) == 0xFFFFFF)
    #expect(rgbHex(try #require(button.layer?.borderColor)) == 0xD8DEE8)
    #expect(
        try rgbHex(
            try #require(button.contentTintColor),
            appearance: .aqua
        ) == 0x111827
    )
}
```

2. 把 `mainMenuSettingsCommandShowsSettingsActions()` 完整替换为：

```swift
@MainActor
@Test func mainMenuSettingsCommandShowsProviderDirectoryActions() throws {
    let viewController = ViewController(
        languageSettings: zhHansLanguageSettings()
    )
    viewController.loadViewIfNeeded()

    viewController.showSettingsFromMainMenu(nil)

    let mainContent = try #require(
        viewController.view.firstDescendant(identifier: "DashboardMainContent")
    )
    for id in ProviderID.allCases {
        #expect(
            mainContent.firstDescendant(
                identifier: "ProviderDirectoryAction.\(id.rawValue)"
            ) != nil
        )
    }
    #expect(
        mainContent.firstDescendant(identifier: "RefreshAllDataButton") != nil
    )
    #expect(
        mainContent.firstDescendant(identifier: "PrivacyPolicyButton") == nil
    )
}
```

3. 把 `settingsAuthorizationRowReflectsExistingAuthorization()` 完整替换为：

```swift
@MainActor
@Test func settingsDirectoryRowsReflectExistingSelections() throws {
    let controller = SettingsViewController(
        isAuthorized: { true },
        languageSettings: zhHansLanguageSettings()
    )
    controller.loadViewIfNeeded()

    for id in ProviderID.allCases {
        let status = try #require(
            controller.view.firstDescendant(
                identifier: "ProviderDirectoryStatus.\(id.rawValue)"
            ) as? NSTextField
        )
        let action = try #require(
            controller.view.button(
                identifier: "ProviderDirectoryAction.\(id.rawValue)"
            )
        )
        #expect(status.stringValue == "已选择")
        #expect(action.title == "重新选择")
        #expect(action.isEnabled)
    }
}
```

4. 删除 `settingsAuthorizationRowUsesHorizontalSettingLayout()`；Step 1 的 `settingsProviderDirectoryRowsUseHorizontalLayout()` 完整取代它。

5. 把 `settingsControlsExposeStableAccessibilityIdentifiers()` 完整替换为：

```swift
@MainActor
@Test func settingsControlsExposeStableAccessibilityIdentifiers() throws {
    try withTemporaryDefaults { defaults in
        let controller = SettingsViewController(
            isAuthorized: { false },
            autoRefreshSettings: AutoRefreshSettings(defaults: defaults),
            languageSettings: zhHansLanguageSettings(defaults: defaults)
        )
        controller.loadViewIfNeeded()

        for id in ProviderID.allCases {
            let statusIdentifier = "ProviderDirectoryStatus.\(id.rawValue)"
            let actionIdentifier = "ProviderDirectoryAction.\(id.rawValue)"
            let status = try #require(
                controller.view.firstDescendant(identifier: statusIdentifier)
            )
            let action = try #require(
                controller.view.button(identifier: actionIdentifier)
            )
            #expect(status.accessibilityIdentifier() == statusIdentifier)
            #expect(action.accessibilityIdentifier() == actionIdentifier)
        }

        let refresh = try #require(
            controller.view.button(identifier: "RefreshAllDataButton")
        )
        #expect(refresh.accessibilityIdentifier() == "RefreshAllDataButton")
        #expect(controller.view.button(identifier: "PrivacyPolicyButton") == nil)

        let autoRefresh = try #require(
            controller.view.popUpButton(
                identifier: "AutoRefreshIntervalPopUpButton"
            )
        )
        #expect(
            autoRefresh.accessibilityIdentifier()
                == "AutoRefreshIntervalPopUpButton"
        )

        let launchAtLogin = try #require(
            controller.view.switchControl(identifier: "LaunchAtLoginSwitch")
        )
        #expect(
            launchAtLogin.accessibilityIdentifier() == "LaunchAtLoginSwitch"
        )

        let language = try #require(
            controller.view.popUpButton(
                identifier: "LanguagePreferencePopUpButton"
            )
        )
        #expect(
            language.accessibilityIdentifier()
                == "LanguagePreferencePopUpButton"
        )
    }
}
```

6. 把 `settingsPageUsesPencilLightColors()` 完整替换为：

```swift
@MainActor
@Test func settingsPageUsesPencilLightColors() throws {
    try withTemporaryDefaults { defaults in
        let appearance = try #require(NSAppearance(named: .aqua))
        let controller = SettingsViewController(
            isAuthorized: { false },
            autoRefreshSettings: AutoRefreshSettings(defaults: defaults),
            languageSettings: zhHansLanguageSettings(defaults: defaults)
        )
        appearance.performAsCurrentDrawingAppearance {
            controller.loadViewIfNeeded()
        }

        let panel = try #require(
            controller.view.firstDescendant(identifier: "SettingsPanel")
        )
        let title = try #require(
            controller.view.textField(stringValue: "设置")
        )
        let description = try #require(
            controller.view.textField(
                stringValue: "选择各数据源的数据文件夹并管理数据刷新。"
            )
        )
        let dataFoldersTitle = try #require(
            controller.view.firstDescendant(
                identifier: "DataFoldersTitleLabel"
            ) as? NSTextField
        )
        let action = try #require(
            controller.view.button(identifier: "ProviderDirectoryAction.claude")
        )
        let refresh = try #require(
            controller.view.button(identifier: "RefreshAllDataButton")
        )
        let autoRefresh = try #require(
            controller.view.popUpButton(
                identifier: "AutoRefreshIntervalPopUpButton"
            )
        )
        let language = try #require(
            controller.view.popUpButton(
                identifier: "LanguagePreferencePopUpButton"
            )
        )

        #expect(
            rgbHex(try #require(controller.view.layer?.backgroundColor))
                == 0xF4F6FA
        )
        #expect(rgbHex(try #require(panel.layer?.backgroundColor)) == 0xFFFFFF)
        #expect(rgbHex(try #require(panel.layer?.borderColor)) == 0xD8DEE8)
        #expect(
            try rgbHex(try #require(title.textColor), appearance: .aqua)
                == 0x111827
        )
        #expect(
            try rgbHex(try #require(description.textColor), appearance: .aqua)
                == 0x6B7280
        )
        #expect(
            try rgbHex(
                try #require(dataFoldersTitle.textColor),
                appearance: .aqua
            ) == 0x111827
        )
        #expect(rgbHex(try #require(action.layer?.backgroundColor)) == 0x2563EB)
        #expect(rgbHex(try #require(action.layer?.borderColor)) == 0x2563EB)
        #expect(
            try rgbHex(
                try #require(action.contentTintColor),
                appearance: .aqua
            ) == 0xFFFFFF
        )
        #expect(rgbHex(try #require(refresh.layer?.backgroundColor)) == 0xFFFFFF)
        #expect(rgbHex(try #require(refresh.layer?.borderColor)) == 0xD8DEE8)
        #expect(
            rgbHex(try #require(autoRefresh.layer?.backgroundColor)) == 0xFFFFFF
        )
        #expect(rgbHex(try #require(autoRefresh.layer?.borderColor)) == 0xD8DEE8)
        #expect(rgbHex(try #require(language.layer?.backgroundColor)) == 0xFFFFFF)
        #expect(rgbHex(try #require(language.layer?.borderColor)) == 0xD8DEE8)
    }
}
```

另完成三处残余迁移：

- `settingsPageReappliesLightColorsWhenOpenedAfterAppearanceOverride()` 只把查询行精确替换为下列代码，其余 light-color 断言保持不变：

```swift
let authorizeButton = try #require(
    viewController.view.button(
        identifier: "ProviderDirectoryAction.claude"
    )
)
```

- 把 `settingsRefreshesLocalizedAccessibilityLabels()` 完整替换为：

```swift
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

        let autoRefresh = try #require(controller.view.popUpButton(
            identifier: "AutoRefreshIntervalPopUpButton"
        ))
        let launchAtLogin = try #require(controller.view.switchControl(
            identifier: "LaunchAtLoginSwitch"
        ))
        let language = try #require(controller.view.popUpButton(
            identifier: "LanguagePreferencePopUpButton"
        ))
        let claude = try #require(controller.view.button(
            identifier: "ProviderDirectoryAction.claude"
        ))
        let codex = try #require(controller.view.button(
            identifier: "ProviderDirectoryAction.codex"
        ))
        let opencode = try #require(controller.view.button(
            identifier: "ProviderDirectoryAction.opencode"
        ))
        let refresh = try #require(controller.view.button(
            identifier: "RefreshAllDataButton"
        ))
        let openSettings = try #require(controller.view.button(
            identifier: "OpenLoginItemsSettingsButton"
        ))

        #expect(autoRefresh.accessibilityLabel() == "自动刷新间隔")
        #expect(launchAtLogin.accessibilityLabel() == "开机自启动")
        #expect(language.accessibilityLabel() == "语言")
        #expect(claude.accessibilityLabel() == "Claude Code, 选择文件夹")
        #expect(codex.accessibilityLabel() == "Codex, 选择文件夹")
        #expect(opencode.accessibilityLabel() == "opencode, 选择文件夹")
        #expect(refresh.accessibilityLabel() == "刷新全部数据")
        #expect(openSettings.accessibilityLabel() == "打开登录项设置")

        languageSettings.selectedPreference = .en

        #expect(autoRefresh.accessibilityLabel() == "Auto Refresh Interval")
        #expect(launchAtLogin.accessibilityLabel() == "Launch at Login")
        #expect(language.accessibilityLabel() == "Language")
        #expect(claude.accessibilityLabel() == "Claude Code, Choose Folder")
        #expect(codex.accessibilityLabel() == "Codex, Choose Folder")
        #expect(opencode.accessibilityLabel() == "opencode, Choose Folder")
        #expect(refresh.accessibilityLabel() == "Refresh All Data")
        #expect(openSettings.accessibilityLabel() == "Open Login Items Settings")
    }
}
```

- 键盘焦点测试的最后一条旧断言替换为：

```swift
let providerDirectoryButtons = try ProviderID.allCases.map { id in
    try #require(
        viewController.view.button(
            identifier: "ProviderDirectoryAction.\(id.rawValue)"
        )
    )
}
for button in providerDirectoryButtons {
    let identifier = try #require(button.identifier?.rawValue)
    if button.isEnabled {
        try assertFocusable([identifier])
    } else {
        assertDisabledAndRejectsKeyboardFocus([button])
    }
}
try assertFocusable(["RefreshAllDataButton"])
```

```bash
! rg -n 'AuthorizationActionButton|通用访问权限|去授权' TokenWatchTests

! rg -n \
  'settingsAuthorizationTitle|settingsAuthorizeDirectory|settingsAuthorize\b|statusNeedsHomeAuthorization|homeAccessMessage|authorizeAccessPrompt|errorCannotAccessHome|ProviderAuthorization' \
  TokenWatch TokenWatchTests
```

Expected after the test updates: 两条命令均零匹配。`settingsAuthorized` 与“已授权”仍是 Dashboard 数据源状态的合法文案，不要删除其独立测试。

先运行定向 GREEN 命令：

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch \
  -destination 'platform=macOS' \
  '-only-testing:TokenWatchTests/TokenWatchTests/settingsShowsIndependentProviderDirectoryRows()' \
  '-only-testing:TokenWatchTests/TokenWatchTests/settingsDirectoryButtonsRouteProviderID()' \
  '-only-testing:TokenWatchTests/TokenWatchTests/settingsDirectoryRowsRefreshAfterProviderNotification()' \
  '-only-testing:TokenWatchTests/TokenWatchTests/settingsKeepsDirectoryButtonsDisabledDuringLoadOrAuthorization()' \
  '-only-testing:TokenWatchTests/TokenWatchTests/settingsProviderDirectoryRowsUseHorizontalLayout()' \
  '-only-testing:TokenWatchTests/TokenWatchTests/settingsProviderRowsFitMinimumHeight()' \
  '-only-testing:TokenWatchTests/TokenWatchTests/dashboardEmptyStateRequestsDataFolderSelection()' \
  '-only-testing:TokenWatchTests/TokenWatchTests/settingsSelectedDirectoryButtonUsesNeutralLightColors()' \
  '-only-testing:TokenWatchTests/TokenWatchTests/mainMenuSettingsCommandShowsProviderDirectoryActions()' \
  '-only-testing:TokenWatchTests/TokenWatchTests/settingsDirectoryRowsReflectExistingSelections()' \
  '-only-testing:TokenWatchTests/TokenWatchTests/settingsControlsExposeStableAccessibilityIdentifiers()' \
  '-only-testing:TokenWatchTests/TokenWatchTests/settingsPageUsesPencilLightColors()' \
  '-only-testing:TokenWatchTests/AppLanguageSettingsTests/directoryAuthorizationStringsCoverEverySupportedLanguage()' \
  -skip-testing:TokenWatchUITests \
  -derivedDataPath .build/DerivedData test
```

Expected: PASS。然后运行完整相关 suites：

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch \
  -destination 'platform=macOS' \
  -only-testing:TokenWatchTests/TokenWatchTests \
  -only-testing:TokenWatchTests/AppLanguageSettingsTests \
  -only-testing:TokenWatchTests/DashboardSessionPaginationTests \
  -skip-testing:TokenWatchUITests \
  -derivedDataPath .build/DerivedData test
```

Expected: PASS；不得把零匹配测试当成 GREEN。

- [ ] **Step 6: 提交设置页与可见文案**

```bash
git add TokenWatch/ViewController.swift \
  TokenWatch/ViewControllers/DashboardViewController.swift \
  TokenWatch/Providers/UsageProvider.swift \
  TokenWatch/Localization/AppStrings.swift \
  TokenWatchTests/TokenWatchTests.swift \
  TokenWatchTests/Localization/AppLanguageSettingsTests.swift
git commit -m "fix(settings): 分别选择数据源文件夹"
```

---

### Task 7: 覆盖真实审核启动路径、同步 README 并完成验证

**Files:**
- Modify: `TokenWatchUITests/TokenWatchUITests.swift:16-125`
- Modify: `TokenWatchUITests/TokenWatchUITestsLaunchTests.swift:20-31`
- Modify: `README.md:42-84,112-146`
- Modify: `README.zh-CN.md:42-84,112-146`

- [ ] **Step 1: 写全新启动不弹窗和三行设置验收 UI 测试**

在 `TokenWatchUITests.swift` 增加：

```swift
@MainActor
func testFreshLaunchDoesNotPresentAuthorizationPanel() throws {
    let app = XCUIApplication()
    app.launchForUITesting(languagePreference: "en")

    XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
    let panelService = XCUIApplication(
        bundleIdentifier: "com.apple.appkit.xpc.openAndSavePanelService"
    )
    XCTAssertFalse(panelService.windows.firstMatch.waitForExistence(timeout: 2))
    XCTAssertTrue(app.staticTexts["Usage Overview"].exists)
}

@MainActor
func testSettingsExposeThreeProviderDirectoryControls() throws {
    let app = XCUIApplication()
    app.launchForUITesting(languagePreference: "en")
    let settings = app.buttons["DashboardNav.settings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 5))
    settings.click()

    for id in ["claude", "codex", "opencode"] {
        XCTAssertTrue(app.staticTexts["ProviderDirectoryStatus.\(id)"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["ProviderDirectoryAction.\(id)"].exists)
    }
}

@MainActor
func testCancellingOneProviderPanelLeavesAllRowsUnselected() throws {
    let app = XCUIApplication()
    app.launchForUITesting(languagePreference: "en")
    app.buttons["DashboardNav.settings"].click()
    let claudeButton = app.buttons["ProviderDirectoryAction.claude"]
    XCTAssertTrue(claudeButton.waitForExistence(timeout: 5))
    claudeButton.click()

    let panelService = XCUIApplication(
        bundleIdentifier: "com.apple.appkit.xpc.openAndSavePanelService"
    )
    XCTAssertTrue(panelService.windows.firstMatch.waitForExistence(timeout: 5))
    XCTAssertEqual(panelService.windows.count, 1)
    XCTAssertTrue(panelService.staticTexts["Choose the Claude Code data folder"].exists)
    panelService.typeKey(.escape, modifierFlags: [])
    XCTAssertFalse(panelService.windows.firstMatch.waitForExistence(timeout: 2))

    for (id, providerName) in [
        ("claude", "Claude Code"),
        ("codex", "Codex"),
        ("opencode", "opencode"),
    ] {
        XCTAssertEqual(
            app.staticTexts["ProviderDirectoryStatus.\(id)"].label,
            "\(providerName), Not selected"
        )
    }
}
```

删除旧 `testSettingsPageExposesActionControls()`；上面的 `testSettingsExposeThreeProviderDirectoryControls()` 完整取代它。把 `TokenWatchUITestsLaunchTests.testLaunch` 完整替换为：

```swift
@MainActor
func testLaunch() throws {
    let app = XCUIApplication()
    app.launchForUITesting(languagePreference: "en")

    XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Usage Overview"].waitForExistence(timeout: 5))
    let panelService = XCUIApplication(
        bundleIdentifier: "com.apple.appkit.xpc.openAndSavePanelService"
    )
    XCTAssertFalse(panelService.windows.firstMatch.waitForExistence(timeout: 2))

    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "Launch Screen"
    attachment.lifetime = .keepAlways
    add(attachment)
}
```

- [ ] **Step 2: 运行 UI 验收测试并确认 GREEN**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch \
  -destination 'platform=macOS' \
  '-only-testing:TokenWatchUITests/TokenWatchUITests/testFreshLaunchDoesNotPresentAuthorizationPanel' \
  '-only-testing:TokenWatchUITests/TokenWatchUITests/testSettingsExposeThreeProviderDirectoryControls' \
  '-only-testing:TokenWatchUITests/TokenWatchUITests/testCancellingOneProviderPanelLeavesAllRowsUnselected' \
  '-only-testing:TokenWatchUITests/TokenWatchUITestsLaunchTests/testLaunch' \
  -derivedDataPath .build/DerivedData test
```

Expected: `** TEST SUCCEEDED **`。这些是 Task 5（无交互启动）与 Task 6（稳定 AX identifiers）的跨进程验收覆盖；对应生产行为已经由各自的 RED unit tests 驱动完成，因此本 Task 不再虚构一个新的 RED 阶段。若失败，先按失败归属回到 Task 5 或 Task 6 的实现与测试范围修复，再重跑本命令；本 Task 的提交边界只包含 UI 验收测试和 README。

- [ ] **Step 3: 同步 README，不再指导用户授权 Home**

把英文 README 的 `Supported Sources`、`Privacy`、`Install`、`First Run` 和 Architecture 首段替换为以下精确正文；不要在本 Task 提前加入尚未由后续支持页计划发布的 `/support/` 或邮箱链接：

```markdown
## Supported Sources

AI Token Watch never opens a file picker automatically at launch. In **Settings**, use the **Data Folders** section to choose only the providers you use.

| Source | Folder selected by the user | Data read inside that folder |
| --- | --- | --- |
| Claude Code | Claude Code data folder | `projects/**/*.jsonl` |
| Codex | Codex data folder | `sessions/**/rollout-*.jsonl`, `archived_sessions/**`, and optional `config.toml` |
| opencode | opencode data folder | `opencode.db` |

Each provider stores an independent read-only security-scoped bookmark. Leaving one provider unselected does not block selected providers.

## Privacy

AI Token Watch is designed as a local-only utility.

- It reads a provider folder only after you explicitly choose that folder in the standard macOS open panel.
- It stores one security-scoped bookmark per selected provider in `UserDefaults` so it can reopen that folder later.
- It does not upload usage records, project paths, prompts, responses, or pricing data.
- It does not include analytics or telemetry.

The app may display local project paths from the agent logs because those paths are part of the source data. See the [Privacy Policy](https://orrhsiao.github.io/TokenWatch/privacy/).

## Install

Download the latest packaged app from the [GitHub Releases page](https://github.com/OrrHsiao/TokenWatch/releases):

1. Download `AI-Token-Watch-macOS-universal.zip` from the latest release.
2. Unzip the archive.
3. Move `AI Token Watch.app` to `/Applications`.
4. Open AI Token Watch. Launch does not open a file picker.
5. Open **Settings** and, in **Data Folders**, choose the folder for each provider you use.

If macOS says `AI Token Watch.app is damaged and can't be opened. You should move it to the Trash.`, confirm that the app came from the official AI Token Watch release page, then go to **System Settings > Privacy & Security**. In the Security section, click **Open Anyway** for AI Token Watch, then open AI Token Watch again and choose **Open** when prompted.

To build from source instead:

1. Clone the repository.
2. Open `TokenWatch.xcodeproj` in Xcode.
3. Select the `TokenWatch` scheme.
4. Build and run on macOS.
5. Open **Settings** and choose provider folders in **Data Folders**.

## First Run

AI Token Watch does not request access at launch. Open **Settings**, find **Data Folders**, and choose each provider's data folder with the standard macOS folder picker. You can cancel without changing that provider's existing selection or data.

Selected providers load independently. An unselected provider shows that its folder has not been selected; an empty selected folder shows that no data was found. You can refresh manually from the window or menu bar popover, and change automatic refresh intervals in Settings.
```

Architecture 第一段精确替换为：

```markdown
Each provider owns its scanner, parser, selected data-root contract, and read-only security-scoped bookmark, then emits shared `ParsedUsageEntry` values. `PricingEngine` and `UsageAggregator` turn those entries into summaries that are rendered by AppKit view controllers. Provider authorization and loading states remain independent in `TokenStatsViewModel`.
```

把中文 README 的对应五处替换为：

```markdown
## 支持的数据源

AI Token Watch 启动时绝不会自动打开文件选择器。请在**设置**的**数据文件夹**区域中，只选择你实际使用的数据源。

| 数据源 | 用户选择的文件夹 | 在该文件夹内读取的数据 |
| --- | --- | --- |
| Claude Code | Claude Code 数据文件夹 | `projects/**/*.jsonl` |
| Codex | Codex 数据文件夹 | `sessions/**/rollout-*.jsonl`、`archived_sessions/**` 和可选的 `config.toml` |
| opencode | opencode 数据文件夹 | `opencode.db` |

每个数据源分别保存一个只读 security-scoped bookmark。某个数据源未选择，不会阻止其他已选择的数据源工作。

## 隐私

AI Token Watch 被设计为只在本地运行的工具。

- 只有在你通过标准 macOS 打开面板明确选择某个数据源文件夹后，它才会读取该文件夹。
- 它会在 `UserDefaults` 中为每个已选择的数据源分别保存 security-scoped bookmark，便于下次重新打开同一文件夹。
- 它不会上传使用记录、项目路径、prompt、response 或价格数据。
- 它不包含 analytics 或 telemetry。

由于本地 agent 日志中本身可能包含项目路径，应用界面里也可能展示这些本地路径。详见[隐私政策](https://orrhsiao.github.io/TokenWatch/privacy/)。

## 安装

推荐从 [GitHub Releases 页面](https://github.com/OrrHsiao/TokenWatch/releases)下载最新安装包：

1. 在最新 release 中下载 `AI-Token-Watch-macOS-universal.zip`。
2. 解压压缩包。
3. 将 `AI Token Watch.app` 移动到 `/Applications`。
4. 打开 AI Token Watch；启动过程不会弹出文件选择器。
5. 打开**设置**，在**数据文件夹**区域为你使用的每个数据源选择文件夹。

如果 macOS 提示 `AI Token Watch.app 已损坏，无法打开。你应该将它移到废纸篓。`，请先确认应用来自官方 AI Token Watch release 页面，然后打开**系统设置 > 隐私与安全性**。在“安全性”区域为 AI Token Watch 点击“仍要打开”，之后重新打开 AI Token Watch，并在提示时选择“打开”。

如果你想从源码构建：

1. Clone 本仓库。
2. 用 Xcode 打开 `TokenWatch.xcodeproj`。
3. 选择 `TokenWatch` scheme。
4. 在 macOS 上构建并运行。
5. 打开**设置**，在**数据文件夹**区域选择数据源文件夹。

## 首次运行

AI Token Watch 启动时不会请求文件访问权限。请打开**设置**，找到**数据文件夹**，通过标准 macOS 文件夹选择器选择各数据源的数据文件夹。取消选择不会改变该数据源已有的文件夹或数据。

已选择的数据源会独立加载。未选择的数据源会显示尚未选择文件夹；已选择但为空的文件夹会显示未发现数据。你可以在主窗口或菜单栏弹窗里手动刷新，也可以在设置中调整自动刷新间隔。
```

中文 Architecture 第一段精确替换为：

```markdown
每个 provider 都拥有自己的 scanner、parser、所选数据根契约和只读 security-scoped bookmark，然后输出统一的 `ParsedUsageEntry`。`PricingEngine` 和 `UsageAggregator` 会把这些 entry 汇总成统计结果，再由 AppKit view controller 渲染。`TokenStatsViewModel` 会让各 provider 的授权和加载状态保持独立。
```

删除以下旧句及其同义表达：

```text
authorize access to your user directory when prompted
user-directory access once
folders under your home directory
授权访问你的用户目录
请求一次用户目录访问权限
home 目录下受支持的 provider 文件夹
```

- [ ] **Step 4: 执行静态审核检查**

```bash
! rg -n 'directoryURL\s*=|homeDirectoryForCurrentUser' TokenWatch
```

Expected: no matches。

```bash
ruby -e '
expected = {
  "HomeDirectoryBookmark" => ["TokenWatch/AppDelegate.swift"],
  "TokenWatch.didPromptInitialHomeAuthorization" => ["TokenWatch/AppDelegate.swift"],
}
files = Dir["TokenWatch/**/*.swift"]
expected.each do |needle, expected_files|
  hits = files.select { |path| File.read(path).include?(needle) }
  abort "unexpected #{needle} hits: #{hits.inspect}" unless hits == expected_files
  count = File.read(expected_files.fetch(0)).scan(needle).length
  abort "expected one #{needle}, got #{count}" unless count == 1
end
'
```

Expected: only the two string constants in `LegacyAuthorizationCleaner`；无其他命中。

```bash
! rg -n 'settingsAuthorizeDirectory|homeAccessMessage|statusNeedsHomeAuthorization|errorCannotAccessHome|wants to access your home folder|授权访问用户目录|使用者目錄|ホームフォルダ|홈 폴더|carpeta de inicio|Home-Ordner|dossier personnel|pasta inicial|cartella home|thuismap|folderu domowego|Authorize Home Folder' TokenWatch
```

Expected: no matches。

```bash
! rg -n 'appendingPathComponent\("\.claude"|appendingPathComponent\("\.codex"|appendingPathComponent\("\.local"' \
  TokenWatch/Providers/Claude/ClaudeProvider.swift \
  TokenWatch/Providers/Codex/CodexProvider.swift \
  TokenWatch/Providers/OpenCode/OpenCodeProvider.swift
```

Expected: no matches。

```bash
ruby -e '
text = File.read("TokenWatch.xcodeproj/project.pbxproj")
[
  "ENABLE_APP_SANDBOX = YES;",
  "ENABLE_OUTGOING_NETWORK_CONNECTIONS = NO;",
  "ENABLE_USER_SELECTED_FILES = readonly;",
].each do |setting|
  count = text.scan(setting).length
  abort "#{setting} count=#{count}, expected 2" unless count == 2
end
'
```

Expected: each setting appears exactly twice, once for Debug and once for Release。

- [ ] **Step 5: 运行完整测试与 Debug/Release 构建**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch \
  -destination 'platform=macOS' \
  -only-testing:TokenWatchTests \
  -skip-testing:TokenWatchUITests \
  -derivedDataPath .build/DerivedData test

xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch \
  -destination 'platform=macOS' \
  -only-testing:TokenWatchUITests \
  -derivedDataPath .build/DerivedData test

xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch \
  -configuration Debug \
  -derivedDataPath .build/DerivedData build

xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch \
  -configuration Release \
  -derivedDataPath .build/DerivedData build
```

Expected: 两套测试均 `** TEST SUCCEEDED **`，两种构建均 `** BUILD SUCCEEDED **`。保留命令输出或 `.xcresult` 作为后续 Review Notes 的事实依据。

- [ ] **Step 6: 提交 UI 测试与 README**

```bash
git add TokenWatchUITests/TokenWatchUITests.swift \
  TokenWatchUITests/TokenWatchUITestsLaunchTests.swift \
  README.md README.zh-CN.md
git commit -m "test(review): 覆盖无弹窗目录选择流程"
```

---

## 本地化矩阵

Task 6 必须把下表每个值直接写入对应语言表，并由 `directoryAuthorizationStringsCoverEverySupportedLanguage()` 明确逐项断言。实现者不得让非英语表从英语回落。

### 设置状态

| Language | `settingsDataFoldersTitle` | `settingsDirectoryNotSelected` | `settingsDirectorySelected` | `settingsDirectoryNeedsReselection` | `settingsDirectoryNoData` |
| --- | --- | --- | --- | --- | --- |
| zhHans | 数据文件夹 | 未选择 | 已选择 | 需要重新选择 | 所选文件夹中未发现数据 |
| zhHant | 資料檔案夾 | 未選擇 | 已選擇 | 需要重新選擇 | 找不到資料 |
| en | Data Folders | Not selected | Selected | Needs reselection | No data found in the selected folder |
| ja | データフォルダ | 未選択 | 選択済み | 再選択が必要です | データが見つかりません |
| ko | 데이터 폴더 | 선택 안 함 | 선택됨 | 다시 선택해야 함 | 데이터를 찾을 수 없음 |
| es | Carpetas de datos | Sin seleccionar | Seleccionada | Debe volver a seleccionarse | No se encontraron datos |
| de | Datenordner | Nicht ausgewählt | Ausgewählt | Erneute Auswahl erforderlich | Keine Daten gefunden |
| fr | Dossiers de données | Non sélectionné | Sélectionné | Nouvelle sélection requise | Aucune donnée trouvée |
| ptBR | Pastas de dados | Não selecionada | Selecionada | Nova seleção necessária | Nenhum dado encontrado |
| it | Cartelle dati | Non selezionata | Selezionata | Nuova selezione necessaria | Nessun dato trovato |
| nl | Gegevensmappen | Niet geselecteerd | Geselecteerd | Opnieuw selecteren vereist | Geen gegevens gevonden |
| pl | Foldery danych | Nie wybrano | Wybrano | Wymaga ponownego wyboru | Nie znaleziono danych |

### 设置说明

| Language | `settingsDescription` |
| --- | --- |
| zhHans | 选择各数据源的数据文件夹并管理数据刷新。 |
| zhHant | 選擇各資料來源的資料檔案夾並管理資料重新整理。 |
| en | Choose provider data folders and manage data refresh. |
| ja | 各データソースのデータフォルダを選択し、データ更新を管理します。 |
| ko | 각 데이터 소스의 데이터 폴더를 선택하고 데이터 새로 고침을 관리합니다. |
| es | Elige las carpetas de datos de cada fuente y gestiona la actualización de datos. |
| de | Wähle die Datenordner der einzelnen Quellen aus und verwalte die Datenaktualisierung. |
| fr | Choisissez les dossiers de données de chaque source et gérez l’actualisation des données. |
| ptBR | Escolha as pastas de dados de cada fonte e gerencie a atualização dos dados. |
| it | Scegli le cartelle dati di ogni origine e gestisci l’aggiornamento dei dati. |
| nl | Kies de gegevensmappen per bron en beheer het vernieuwen van gegevens. |
| pl | Wybierz foldery danych dla poszczególnych źródeł i zarządzaj odświeżaniem danych. |

### 操作按钮

| Language | `settingsChooseDirectory` | `settingsReselectDirectory` | `settingsChooseAgain` |
| --- | --- | --- | --- |
| zhHans | 选择文件夹 | 重新选择 | 再次选择 |
| zhHant | 選擇檔案夾 | 重新選擇 | 再次選擇 |
| en | Choose Folder | Reselect | Choose Again |
| ja | フォルダを選択 | フォルダを変更 | もう一度選択 |
| ko | 폴더 선택 | 폴더 변경 | 다시 선택 |
| es | Elegir carpeta | Cambiar carpeta | Elegir de nuevo |
| de | Ordner auswählen | Ordner ändern | Erneut auswählen |
| fr | Choisir un dossier | Changer de dossier | Choisir à nouveau |
| ptBR | Escolher pasta | Alterar pasta | Escolher novamente |
| it | Scegli cartella | Cambia cartella | Scegli di nuovo |
| nl | Map kiezen | Map wijzigen | Opnieuw kiezen |
| pl | Wybierz folder | Zmień folder | Wybierz ponownie |

### 标准面板

| Language | `claudeDataDirectoryOpenPanelMessage` | `codexDataDirectoryOpenPanelMessage` | `openCodeDataDirectoryOpenPanelMessage` | `chooseDirectoryPrompt` |
| --- | --- | --- | --- | --- |
| zhHans | 选择 Claude Code 数据文件夹 | 选择 Codex 数据文件夹 | 选择 opencode 数据文件夹 | 选择 |
| zhHant | 請選擇包含 Claude Code 資料的檔案夾。 | 請選擇包含 Codex 資料的檔案夾。 | 請選擇包含 opencode 資料的檔案夾。 | 選擇 |
| en | Choose the Claude Code data folder | Choose the Codex data folder | Choose the opencode data folder | Choose |
| ja | Claude Code のデータを含むフォルダを選択してください。 | Codex のデータを含むフォルダを選択してください。 | opencode のデータを含むフォルダを選択してください。 | 選択 |
| ko | Claude Code 데이터가 포함된 폴더를 선택하세요. | Codex 데이터가 포함된 폴더를 선택하세요. | opencode 데이터가 포함된 폴더를 선택하세요. | 선택 |
| es | Elige la carpeta que contiene los datos de Claude Code. | Elige la carpeta que contiene los datos de Codex. | Elige la carpeta que contiene los datos de opencode. | Elegir |
| de | Wähle den Ordner aus, der die Daten von Claude Code enthält. | Wähle den Ordner aus, der die Daten von Codex enthält. | Wähle den Ordner aus, der die Daten von opencode enthält. | Auswählen |
| fr | Choisissez le dossier contenant les données de Claude Code. | Choisissez le dossier contenant les données de Codex. | Choisissez le dossier contenant les données d'opencode. | Choisir |
| ptBR | Escolha a pasta que contém os dados do Claude Code. | Escolha a pasta que contém os dados do Codex. | Escolha a pasta que contém os dados do opencode. | Escolher |
| it | Scegli la cartella contenente i dati di Claude Code. | Scegli la cartella contenente i dati di Codex. | Scegli la cartella contenente i dati di opencode. | Scegli |
| nl | Kies de map met de gegevens van Claude Code. | Kies de map met de gegevens van Codex. | Kies de map met de gegevens van opencode. | Kiezen |
| pl | Wybierz folder zawierający dane Claude Code. | Wybierz folder zawierający dane Codex. | Wybierz folder zawierający dane opencode. | Wybierz |

### 总览与错误格式

| Language | `statusNeedsDataDirectorySelection` | `errorCannotAccessProviderDirectoryFormat` | `errorProviderDirectoryAuthorizationFailedFormat` |
| --- | --- | --- | --- |
| zhHans | 请在设置中选择一个或多个数据文件夹 | 无法访问 %@ 数据文件夹，请再次选择。 | 无法保存 %@ 数据文件夹的访问权限，请重新选择。 |
| zhHant | 請在設定中選擇一個或多個資料檔案夾 | 無法存取已選擇的 %@ 資料檔案夾，請重新選擇 | 無法儲存 %@ 資料檔案夾的存取權限，請再試一次 |
| en | Choose one or more data folders in Settings | Cannot access the %@ data folder. Please choose it again. | Could not save access to the %@ data folder. Please choose again. |
| ja | 設定で1つ以上のデータフォルダを選択してください | 選択した %@ のデータフォルダにアクセスできません。もう一度選択してください | %@ のデータフォルダへのアクセス権を保存できませんでした。もう一度お試しください |
| ko | 설정에서 하나 이상의 데이터 폴더를 선택하세요 | 선택한 %@ 데이터 폴더에 접근할 수 없습니다. 다시 선택하세요 | %@ 데이터 폴더 접근 권한을 저장하지 못했습니다. 다시 시도하세요 |
| es | Selecciona una o varias carpetas de datos en Configuración | No se puede acceder a la carpeta de datos seleccionada para %@. Vuelve a elegirla | No se pudo guardar el acceso a la carpeta de datos de %@. Inténtalo de nuevo |
| de | Wähle in den Einstellungen mindestens einen Datenordner aus | Auf den ausgewählten Datenordner von %@ kann nicht zugegriffen werden. Wähle ihn erneut aus | Der Zugriff auf den Datenordner von %@ konnte nicht gespeichert werden. Versuche es erneut |
| fr | Sélectionnez un ou plusieurs dossiers de données dans Paramètres | Impossible d'accéder au dossier de données sélectionné pour %@. Choisissez-le à nouveau | Impossible d'enregistrer l'accès au dossier de données de %@. Réessayez |
| ptBR | Selecione uma ou mais pastas de dados em Configurações | Não foi possível acessar a pasta de dados selecionada para %@. Escolha-a novamente | Não foi possível salvar o acesso à pasta de dados de %@. Tente novamente |
| it | Seleziona una o più cartelle dati in Impostazioni | Impossibile accedere alla cartella dati selezionata per %@. Selezionala di nuovo | Impossibile salvare l'accesso alla cartella dati di %@. Riprova |
| nl | Selecteer een of meer gegevensmappen in Instellingen | De geselecteerde gegevensmap voor %@ is niet toegankelijk. Kies deze opnieuw | Toegang tot de gegevensmap van %@ kon niet worden opgeslagen. Probeer het opnieuw |
| pl | Wybierz co najmniej jeden folder danych w Ustawieniach | Nie można uzyskać dostępu do folderu danych wybranego dla %@. Wybierz go ponownie | Nie udało się zapisać dostępu do folderu danych dla %@. Spróbuj ponownie |

每个错误格式必须保留且只保留一个 `%@` provider 占位符。格式测试要分别传入 `Claude Code`、`Codex` 和 `opencode`，确认不会丢失名称或触发格式异常。
