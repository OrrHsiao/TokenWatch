# Codex Provider 接入实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在现有 Claude Code 统计能力之上引入 OpenAI Codex 数据源,同时把多 provider 抽象层立起来,为后续 Gemini 等 provider 铺路。

**Architecture:** 采纳 ccusage 的 Parser-level adapter 模式 — 每个 provider 拥有独立的扫描器 + 解析器,产出统一的 `ParsedUsageEntry`,后续 PricingEngine / UsageAggregator 全部共享。UI 改为 `NSTabViewController`,每个 provider 一个 Tab,授权与状态相互独立。

**Tech Stack:** Swift 6 / AppKit / Cocoa / Swift Testing(单元测试)/ XCTest(UI 测试)/ Security-Scoped Bookmarks(Sandbox)

**前置说明:**
- Xcode 工程使用 `PBXFileSystemSynchronizedRootGroup` 自动同步源码目录,新增 / 移动 / 删除文件无需手动改 `project.pbxproj`,**移动文件即生效**。
- 项目根目录:`/Users/orrhsiao/Desktop/Code/TokenWatch`
- 源码根:`TokenWatch/`,测试根:`TokenWatchTests/`
- 已建好分支 `feat/codex-provider`,spec 已 commit。
- 构建命令:`xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Debug build`
- 测试命令:`xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests test`
- 优先使用 Xcode MCP 进行构建与测试。

---

## 任务总览

| # | 任务 | 提交 message |
|---|------|-------------|
| 1 | Claude 代码迁入 `Providers/Claude/`,纯改文件位置 | `refactor(providers): 将 Claude 相关代码迁入 Providers/Claude/` |
| 2 | 引入 `ProviderID` / `UsageProvider` / `ProviderRegistry` | `feat(providers): 引入 UsageProvider 协议与 ProviderRegistry` |
| 3 | `SecurityScopedBookmarkManager` 多 key 化 | `feat(bookmark): SecurityScopedBookmarkManager 多 key 化` |
| 4 | Codex 数据模型 `CodexRecord` + 单元测试 | `feat(codex): 添加 CodexRecord 数据模型` |
| 5 | `CodexRolloutScanner` + 单元测试 | `feat(codex): 添加 CodexRolloutScanner` |
| 6 | `CodexRolloutParser` + 单元测试 | `feat(codex): 添加 CodexRolloutParser 与去重` |
| 7 | `CodexProvider` 装配 | `feat(codex): 添加 CodexProvider 装配 Scanner+Parser` |
| 8 | `PricingTable` 新增 GPT-5 系列 | `feat(pricing): PricingTable 新增 OpenAI GPT-5 系列定价` |
| 9 | `TokenStatsViewModel` 改为 per-provider 状态 | `feat(viewmodel): TokenStatsViewModel 改为 per-provider 状态` |
| 10 | UI 改 `NSTabViewController` + `ProviderStatsViewController` | `feat(ui): 主视图改 NSTabViewController + ProviderStatsViewController` |
| 11 | README 更新多 provider 说明 | `docs(readme): 更新多 provider 架构说明` |

---

## Task 1: 将 Claude 相关代码迁入 Providers/Claude/

**Files:**
- Move: `TokenWatch/Models/ClaudeRecord.swift` → `TokenWatch/Providers/Claude/ClaudeRecord.swift`
- Move: `TokenWatch/Models/ClaudeMessage.swift` → `TokenWatch/Providers/Claude/ClaudeMessage.swift`
- Move: `TokenWatch/Services/JSONLScanner.swift` → `TokenWatch/Providers/Claude/ClaudeJSONLScanner.swift`
- Move: `TokenWatch/Services/JSONLParser.swift` → `TokenWatch/Providers/Claude/ClaudeJSONLParser.swift`
- Modify(rename type): `JSONLScanner` → `ClaudeJSONLScanner`,`JSONLParser` → `ClaudeJSONLParser`,`JSONLFileInfo` → `ClaudeJSONLFileInfo`
- Modify: `TokenWatch/ViewModels/TokenStatsViewModel.swift` 把对 `JSONLScanner()` / `JSONLParser()` 的引用改为新名
- Move(test): `TokenWatchTests/Services/JSONLScannerTests.swift` → `TokenWatchTests/Providers/Claude/ClaudeJSONLScannerTests.swift`
- Move(test): `TokenWatchTests/Services/JSONLParserTests.swift` → `TokenWatchTests/Providers/Claude/ClaudeJSONLParserTests.swift`
- Modify(test): `TokenWatchTests/Services/JSONLParserTests.swift` 内对类型的引用同步改名

> **设计原因:** `Providers/Claude/` 把 Claude provider 自有的所有数据/扫描/解析代码归并一处,与未来 `Providers/Codex/` 平行;改名加 `Claude` 前缀消除 `JSONLScanner` 这种泛化名(将来 Codex 的 rollout 也是 JSONL,但语义不同)。这一步不改任何逻辑,只动文件位置和类型名。

- [ ] **Step 1: 创建 Providers/Claude/ 目录并移动 Claude 相关文件**

```bash
cd /Users/orrhsiao/Desktop/Code/TokenWatch
mkdir -p TokenWatch/Providers/Claude
git mv TokenWatch/Models/ClaudeRecord.swift TokenWatch/Providers/Claude/ClaudeRecord.swift
git mv TokenWatch/Models/ClaudeMessage.swift TokenWatch/Providers/Claude/ClaudeMessage.swift
git mv TokenWatch/Services/JSONLScanner.swift TokenWatch/Providers/Claude/ClaudeJSONLScanner.swift
git mv TokenWatch/Services/JSONLParser.swift TokenWatch/Providers/Claude/ClaudeJSONLParser.swift
mkdir -p TokenWatchTests/Providers/Claude
git mv TokenWatchTests/Services/JSONLScannerTests.swift TokenWatchTests/Providers/Claude/ClaudeJSONLScannerTests.swift
git mv TokenWatchTests/Services/JSONLParserTests.swift TokenWatchTests/Providers/Claude/ClaudeJSONLParserTests.swift
```

- [ ] **Step 2: 把类型名加 Claude 前缀**

打开 `TokenWatch/Providers/Claude/ClaudeJSONLScanner.swift`,把所有 `JSONLScanner` 改为 `ClaudeJSONLScanner`,`JSONLFileInfo` 改为 `ClaudeJSONLFileInfo`。

打开 `TokenWatch/Providers/Claude/ClaudeJSONLParser.swift`,把所有 `JSONLParser` 改为 `ClaudeJSONLParser`,`JSONLFileInfo` 改为 `ClaudeJSONLFileInfo`。

- [ ] **Step 3: 更新 TokenStatsViewModel 引用**

修改 `TokenWatch/ViewModels/TokenStatsViewModel.swift`:

```swift
private let scanner = ClaudeJSONLScanner()
private let parser = ClaudeJSONLParser()
```

- [ ] **Step 4: 更新测试文件引用**

`TokenWatchTests/Providers/Claude/ClaudeJSONLScannerTests.swift` 与 `ClaudeJSONLParserTests.swift` 内所有 `JSONLScanner`/`JSONLParser`/`JSONLFileInfo` 引用同步改名。

- [ ] **Step 5: 构建并跑全量测试**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests test
```

Expected: 现有 47 个测试全绿,无任何失败。

- [ ] **Step 6: 提交**

```bash
git add -A
git commit -m "refactor(providers): 将 Claude 相关代码迁入 Providers/Claude/"
```

---

## Task 2: 引入 UsageProvider 协议与 ProviderRegistry

**Files:**
- Create: `TokenWatch/Providers/ProviderID.swift`
- Create: `TokenWatch/Providers/UsageProvider.swift`
- Create: `TokenWatch/Providers/ProviderRegistry.swift`
- Modify: `TokenWatch/Models/ParsedUsageEntry.swift`(添加 `provider: ProviderID` 字段)
- Create: `TokenWatch/Providers/Claude/ClaudeProvider.swift`(`UsageProvider` 实现,装配现有 Scanner+Parser)
- Modify: `TokenWatch/Providers/Claude/ClaudeJSONLParser.swift`(在 `ParsedUsageEntry` 初始化里填 `provider: .claude`)
- Modify: `TokenWatchTests/Models/TokenUsageDecodingTests.swift`(8 处 `ParsedUsageEntry` 构造补 `provider:`)
- Modify: `TokenWatchTests/Analytics/UsageAggregatorTests.swift`(1 处构造工厂方法补 `provider:`)
- Modify: `TokenWatchTests/Providers/Claude/ClaudeJSONLParserTests.swift`(4 处构造补 `provider:`)
- Create: `TokenWatchTests/Providers/ProviderRegistryTests.swift`

> **设计原因:** 把每个 provider 的扫描+解析能力抽象到 `UsageProvider` 协议背后,`ProviderRegistry.allProviders` 给 ViewModel 一个统一遍历入口。`ParsedUsageEntry.provider` 主要用于将来若做跨 provider 合并视图时区分来源,本期 UI 走 Tab,所以这字段先记录、不展示。

- [ ] **Step 1: 创建 ProviderID**

写入 `TokenWatch/Providers/ProviderID.swift`:

```swift
import Foundation

/// 数据源标识 — 与 UI Tab、Bookmark key 一一对应
/// 新增 provider 在此加 case,然后在 ProviderRegistry.allProviders 注册即可
enum ProviderID: String, Sendable, CaseIterable, Hashable, Codable {
    case claude
    case codex
}
```

- [ ] **Step 2: 创建 UsageProvider 协议**

写入 `TokenWatch/Providers/UsageProvider.swift`:

```swift
import Foundation

/// 抽象的数据源 provider
/// 职责:扫描自己的目录、解析自己的 JSONL 格式、产出统一的 ParsedUsageEntry
/// 不关心 Bookmark / 聚合 / 定价 — 这些在共享层完成
///
/// 设计参考 ccusage `adapter/` 模式:per-provider 自治 paths/parser/loader
protocol UsageProvider: Sendable {
    /// 唯一标识,用于 UI Tab / Bookmark key / 状态字典 key
    var id: ProviderID { get }
    /// UI Tab 标题
    var displayName: String { get }
    /// UserDefaults Bookmark 持久化键
    var bookmarkKey: String { get }
    /// NSOpenPanel 默认定位目录(绝对路径)
    var defaultDirectoryPath: String { get }
    /// NSOpenPanel 顶部说明文案
    var openPanelMessage: String { get }
    /// 该 provider 是否产出 cache write tokens(决定 UI 是否展示该行)
    /// Claude=true,Codex=false
    var hasCacheWriteDimension: Bool { get }

    /// 扫描+解析,产出统一条目
    /// - Parameter rootURL: 已通过 Security-Scoped Bookmark 取得访问权限的根目录
    func loadEntries(from rootURL: URL) throws -> [ParsedUsageEntry]
}
```

- [ ] **Step 3: 修改 ParsedUsageEntry 添加 provider 字段**

修改 `TokenWatch/Models/ParsedUsageEntry.swift`,在结构体内 `let isSubagent: Bool` 之后新增:

```swift
    /// 数据源标识(用于将来跨 provider 合并视图区分来源)
    let provider: ProviderID
```

> **注意:** `dedupKey` / `hash(into:)` / `==` 不变 — Claude 的 `messageId` 全局唯一,Codex 的合成 key `<sessionId>:<timestamp>` 不会与 Claude messageId 撞;两者共用 Set 也安全。

- [ ] **Step 4: 修改 ClaudeJSONLParser 在初始化条目时填入 provider**

修改 `TokenWatch/Providers/Claude/ClaudeJSONLParser.swift` 中构造 `ParsedUsageEntry` 的地方,在末尾追加:

```swift
                isSubagent: fileInfo.isSubagent,
                provider: .claude
```

- [ ] **Step 5: 创建 ClaudeProvider**

写入 `TokenWatch/Providers/Claude/ClaudeProvider.swift`:

```swift
import Foundation

/// Claude Code 数据源
/// 装配现有 ClaudeJSONLScanner + ClaudeJSONLParser,适配 UsageProvider 协议
struct ClaudeProvider: UsageProvider {
    let id: ProviderID = .claude
    let displayName = "Claude Code"
    let bookmarkKey = "ClaudeDirectoryBookmark"  // 与历史版本兼容,勿改
    let defaultDirectoryPath = NSString("~/.claude").expandingTildeInPath
    let openPanelMessage = "请选择 ~/.claude 目录以授权 TokenWatch 读取 Claude Code 用量数据"
    let hasCacheWriteDimension = true

    private let scanner = ClaudeJSONLScanner()
    private let parser = ClaudeJSONLParser()

    func loadEntries(from rootURL: URL) throws -> [ParsedUsageEntry] {
        let files = try scanner.scanAllJSONLFiles(in: rootURL)
        return try parser.parseAllFiles(files, claudeDataRoot: rootURL)
    }
}
```

- [ ] **Step 6: 创建 ProviderRegistry**

写入 `TokenWatch/Providers/ProviderRegistry.swift`:

```swift
import Foundation

/// 全部已注册 provider 的静态注册表
/// 新增 provider 在此追加一行即可,UI / ViewModel 自动感知
enum ProviderRegistry {
    /// 顺序即 UI Tab 顺序
    static let allProviders: [any UsageProvider] = [
        ClaudeProvider(),
        // CodexProvider() — Task 7 加入
    ]

    static func provider(for id: ProviderID) -> (any UsageProvider)? {
        allProviders.first(where: { $0.id == id })
    }
}
```

- [ ] **Step 7: 修复测试中 ParsedUsageEntry 直接构造的地方**

下列文件中所有手工构造 `ParsedUsageEntry(...)` 的位置,在末尾参数加 `, provider: .claude`:

- `TokenWatchTests/Models/TokenUsageDecodingTests.swift` — 8 处(行 226 / 231 / 245 / 250 / 263 / 268 / 279 / 284)
- `TokenWatchTests/Analytics/UsageAggregatorTests.swift` — 1 处(行 174,工厂方法)
- `TokenWatchTests/Providers/Claude/ClaudeJSONLParserTests.swift` — 4 处(原 `TokenWatchTests/Services/JSONLParserTests.swift` 行 120 / 125 / 146 / 151,Task 1 移动后行号不变)

- [ ] **Step 8: 创建 ProviderRegistry 测试**

写入 `TokenWatchTests/Providers/ProviderRegistryTests.swift`:

```swift
import Testing
@testable import TokenWatch

@Suite("ProviderRegistry")
struct ProviderRegistryTests {
    @Test("allProviders 至少含 .claude")
    func containsClaude() {
        let ids = ProviderRegistry.allProviders.map(\.id)
        #expect(ids.contains(.claude))
    }

    @Test("每个 provider 的 bookmarkKey 唯一")
    func bookmarkKeysUnique() {
        let keys = ProviderRegistry.allProviders.map(\.bookmarkKey)
        #expect(Set(keys).count == keys.count)
    }

    @Test("provider(for:) 能按 id 查到对应实例")
    func lookupById() {
        let claude = ProviderRegistry.provider(for: .claude)
        #expect(claude?.id == .claude)
    }
}
```

- [ ] **Step 9: 构建并跑全量测试**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests test
```

Expected: 全绿。

- [ ] **Step 10: 提交**

```bash
git add -A
git commit -m "feat(providers): 引入 UsageProvider 协议与 ProviderRegistry"
```

---

## Task 3: SecurityScopedBookmarkManager 多 key 化

**Files:**
- Modify: `TokenWatch/Services/SecurityScopedBookmarkManager.swift`
- Modify: `TokenWatch/AppDelegate.swift`(`applicationWillTerminate` 改为遍历所有 provider 调 stop)

> **设计原因:** 原实现单 key 写死 `ClaudeDirectoryBookmark`,改为按外部传入的 `key` 区分,内部维护 `[String: AccessSession]`。Claude 旧 key 不变,新 provider 用各自的 key,持久化数据互不干扰。

- [ ] **Step 1: 重写 SecurityScopedBookmarkManager**

将 `TokenWatch/Services/SecurityScopedBookmarkManager.swift` 整体替换为:

```swift
import Foundation
import AppKit

/// 管理多个 Security-Scoped Bookmark 的创建、存储和恢复
/// 每个 provider 使用自己的 bookmarkKey,数据互相独立
///
/// 历史 key `ClaudeDirectoryBookmark` 由 ClaudeProvider 复用,迁移用户无需重新授权
@MainActor
final class SecurityScopedBookmarkManager: Sendable {

    static let shared = SecurityScopedBookmarkManager()

    /// 每个 key 对应的会话状态(已恢复的 URL + 是否处于 startAccessing)
    private struct Session {
        var url: URL
        var isAccessing: Bool
    }
    private var sessions: [String: Session] = [:]

    // MARK: - 查询

    /// 是否已存储该 key 对应的 Bookmark
    func hasBookmark(forKey key: String) -> Bool {
        UserDefaults.standard.data(forKey: key) != nil
    }

    // MARK: - 授权流程

    /// 通过 NSOpenPanel 让用户选择 provider 默认目录
    /// 选择后创建 Security-Scoped Bookmark 并持久化到 UserDefaults
    func promptUserToSelectDirectory(forProvider provider: any UsageProvider) async -> URL? {
        return await withCheckedContinuation { continuation in
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.message = provider.openPanelMessage
            panel.prompt = "授权访问"
            panel.showsHiddenFiles = true
            panel.treatsFilePackagesAsDirectories = true

            // 默认定位到 provider 期望的目录;不存在则回退到 home
            let target = URL(fileURLWithPath: provider.defaultDirectoryPath, isDirectory: true)
            if FileManager.default.fileExists(atPath: target.path) {
                panel.directoryURL = target
            } else {
                panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            }

            let key = provider.bookmarkKey
            panel.begin { [weak self] response in
                guard response == .OK, let url = panel.url else {
                    continuation.resume(returning: nil)
                    return
                }
                self?.createAndSaveBookmark(for: url, key: key)
                continuation.resume(returning: url)
            }
        }
    }

    // MARK: - Bookmark 恢复

    /// 从 UserDefaults 恢复指定 key 的 Bookmark 并 startAccessing
    /// stale 处理:解析得到的 URL 仍可临时使用,startAccessing 后立即用其重建 bookmark
    func restoreBookmarkAndAccess(forKey key: String) -> URL? {
        // 已经在访问中 → 直接返回缓存 URL
        if let session = sessions[key], session.isAccessing {
            return session.url
        }

        guard let bookmarkData = UserDefaults.standard.data(forKey: key) else {
            return nil
        }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            UserDefaults.standard.removeObject(forKey: key)
            return nil
        }

        guard url.startAccessingSecurityScopedResource() else {
            UserDefaults.standard.removeObject(forKey: key)
            return nil
        }

        if isStale {
            if let fresh = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                UserDefaults.standard.set(fresh, forKey: key)
            }
        }

        sessions[key] = Session(url: url, isAccessing: true)
        return url
    }

    /// 停止指定 key 的安全访问
    func stopAccessing(forKey key: String) {
        guard let session = sessions[key], session.isAccessing else { return }
        session.url.stopAccessingSecurityScopedResource()
        sessions[key] = nil
    }

    /// 停止所有 key 的安全访问(applicationWillTerminate 用)
    func stopAccessingAll() {
        for key in Array(sessions.keys) {
            stopAccessing(forKey: key)
        }
    }

    // MARK: - Private

    private func createAndSaveBookmark(for url: URL, key: String) {
        guard let bookmarkData = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            return
        }
        UserDefaults.standard.set(bookmarkData, forKey: key)
    }
}
```

> **API 变更说明:**
> - 旧 `hasBookmark` / `restoreBookmarkAndAccess()` / `stopAccessing()` / `promptUserToSelectClaudeDirectory()` 全部被新签名替代。
> - `TokenStatsViewModel` 在 Task 9 改造时会切换到新 API,这一步的 ViewModel 暂时编译会断;但 Task 9 紧跟此后,中间不需要单独保持兼容老 API。
> - **若希望此步独立可构建**,在 Task 3 内 `TokenStatsViewModel` 也一并按新 API 调:
>   - `bookmarkManager.hasBookmark` → `bookmarkManager.hasBookmark(forKey: "ClaudeDirectoryBookmark")`
>   - `bookmarkManager.restoreBookmarkAndAccess()` → `bookmarkManager.restoreBookmarkAndAccess(forKey: "ClaudeDirectoryBookmark")`
>   - `bookmarkManager.stopAccessing()` → `bookmarkManager.stopAccessing(forKey: "ClaudeDirectoryBookmark")`
>   - `bookmarkManager.promptUserToSelectClaudeDirectory()` → `bookmarkManager.promptUserToSelectDirectory(forProvider: ClaudeProvider())`

- [ ] **Step 2: 更新 TokenStatsViewModel 的临时调用**

修改 `TokenWatch/ViewModels/TokenStatsViewModel.swift` 中所有 bookmarkManager 调用为新 API(用 `"ClaudeDirectoryBookmark"` 字面量,Task 9 会再重构):

```swift
if !bookmarkManager.hasBookmark(forKey: "ClaudeDirectoryBookmark") { ... }
guard let claudeDir = bookmarkManager.restoreBookmarkAndAccess(forKey: "ClaudeDirectoryBookmark") else { ... }
defer { bookmarkManager.stopAccessing(forKey: "ClaudeDirectoryBookmark") }
// requestAuthorization 内:
if let _ = await bookmarkManager.promptUserToSelectDirectory(forProvider: ClaudeProvider()) { ... }
```

- [ ] **Step 3: 更新 AppDelegate**

修改 `TokenWatch/AppDelegate.swift`:

```swift
    func applicationWillTerminate(_ aNotification: Notification) {
        SecurityScopedBookmarkManager.shared.stopAccessingAll()
    }
```

- [ ] **Step 4: 构建并跑全量测试**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests test
```

Expected: 全绿。

- [ ] **Step 5: 提交**

```bash
git add -A
git commit -m "feat(bookmark): SecurityScopedBookmarkManager 多 key 化"
```

---

## Task 4: Codex 数据模型 CodexRecord

**Files:**
- Create: `TokenWatch/Providers/Codex/CodexRecord.swift`
- Create: `TokenWatchTests/Providers/Codex/CodexRecordTests.swift`

> **设计原因:** Codex JSONL 每行一个 event,顶层 `type` 字段决定 `payload` 形态。直接用一个大结构体 + 若干 optional 子字段会耦合各 type;改用顶层 enum `CodexPayload` 在 init 阶段按 `type` 分发,既保解码安全又方便后续扩展。

- [ ] **Step 1: 写失败的测试**

写入 `TokenWatchTests/Providers/Codex/CodexRecordTests.swift`:

```swift
import Testing
import Foundation
@testable import TokenWatch

@Suite("CodexRecord")
struct CodexRecordTests {

    private let decoder = JSONDecoder()

    @Test("解析 session_meta 行")
    func decodeSessionMeta() throws {
        let json = """
        {"timestamp":"2026-05-04T08:35:44.692Z","type":"session_meta","payload":{"id":"abc-123","cwd":"/tmp","originator":"Codex Desktop","cli_version":"0.128","source":"vscode","model_provider":"openai"}}
        """
        let record = try decoder.decode(CodexRecord.self, from: Data(json.utf8))
        #expect(record.type == "session_meta")
        guard case let .sessionMeta(meta) = record.payload else {
            Issue.record("payload 不是 sessionMeta")
            return
        }
        #expect(meta.id == "abc-123")
        #expect(meta.cwd == "/tmp")
        #expect(meta.modelProvider == "openai")
    }

    @Test("解析 turn_context 行")
    func decodeTurnContext() throws {
        let json = """
        {"timestamp":"2026-05-04T08:35:44.717Z","type":"turn_context","payload":{"turn_id":"t1","cwd":"/tmp","model":"gpt-5.5","effort":"xhigh"}}
        """
        let record = try decoder.decode(CodexRecord.self, from: Data(json.utf8))
        guard case let .turnContext(ctx) = record.payload else {
            Issue.record("payload 不是 turnContext")
            return
        }
        #expect(ctx.model == "gpt-5.5")
    }

    @Test("解析 event_msg.token_count 行")
    func decodeTokenCount() throws {
        let json = """
        {"timestamp":"2026-05-04T08:35:59.868Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":38078,"cached_input_tokens":3456,"output_tokens":707,"reasoning_output_tokens":516,"total_tokens":38785},"last_token_usage":{"input_tokens":38078,"cached_input_tokens":3456,"output_tokens":707,"reasoning_output_tokens":516,"total_tokens":38785},"model_context_window":258400}}}
        """
        let record = try decoder.decode(CodexRecord.self, from: Data(json.utf8))
        guard case let .eventMsg(event) = record.payload else {
            Issue.record("payload 不是 eventMsg")
            return
        }
        #expect(event.type == "token_count")
        #expect(event.info?.lastTokenUsage?.inputTokens == 38078)
        #expect(event.info?.lastTokenUsage?.cachedInputTokens == 3456)
        #expect(event.info?.lastTokenUsage?.reasoningOutputTokens == 516)
        #expect(event.info?.totalTokenUsage?.totalTokens == 38785)
    }

    @Test("解析 event_msg.token_count info=null(rate_limits 心跳)")
    func decodeTokenCountInfoNull() throws {
        let json = """
        {"timestamp":"2026-05-04T08:35:45.748Z","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{}}}
        """
        let record = try decoder.decode(CodexRecord.self, from: Data(json.utf8))
        guard case let .eventMsg(event) = record.payload else {
            Issue.record("payload 不是 eventMsg")
            return
        }
        #expect(event.info == nil)
    }

    @Test("无关 type 解析为 unknown 不抛错")
    func decodeUnknownType() throws {
        let json = """
        {"timestamp":"2026-05-04T08:35:44.716Z","type":"response_item","payload":{"type":"message","role":"developer"}}
        """
        let record = try decoder.decode(CodexRecord.self, from: Data(json.utf8))
        if case .unknown = record.payload {
            // OK
        } else {
            Issue.record("response_item 应被识别为 unknown payload")
        }
    }

    @Test("缺失 timestamp 不阻断解码")
    func decodeMissingTimestamp() throws {
        let json = """
        {"type":"session_meta","payload":{"id":"abc","cwd":"/tmp"}}
        """
        let record = try decoder.decode(CodexRecord.self, from: Data(json.utf8))
        #expect(record.timestamp == nil)
    }
}
```

- [ ] **Step 2: 跑测试,确认失败**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/CodexRecordTests test 2>&1 | tail -20
```

Expected: 失败,提示 `CodexRecord` / `CodexPayload` 等未定义。

- [ ] **Step 3: 实现 CodexRecord**

写入 `TokenWatch/Providers/Codex/CodexRecord.swift`:

```swift
import Foundation

/// Codex JSONL(`~/.codex/sessions/.../rollout-*.jsonl`)中每一行的顶层结构
/// 仅解析 token 统计需要的 type:session_meta / turn_context / event_msg
/// 其余 type(response_item / function_call / 等)归为 .unknown 并跳过
struct CodexRecord: Decodable, Sendable {
    let timestamp: Date?
    let type: String
    let payload: CodexPayload

    enum CodingKeys: String, CodingKey {
        case timestamp, type, payload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)

        if let ts = try container.decodeIfPresent(String.self, forKey: .timestamp) {
            timestamp = ISO8601DateFormatterHelper.parse(ts)
        } else {
            timestamp = nil
        }

        // payload 形态由 type 决定 — 解码失败的子结构降级为 .unknown,
        // 保持单行损坏不阻断后续行(参考 Claude JSONL 的容错风格)
        switch type {
        case "session_meta":
            if let meta = try? container.decode(CodexSessionMeta.self, forKey: .payload) {
                payload = .sessionMeta(meta)
            } else {
                payload = .unknown
            }
        case "turn_context":
            if let ctx = try? container.decode(CodexTurnContext.self, forKey: .payload) {
                payload = .turnContext(ctx)
            } else {
                payload = .unknown
            }
        case "event_msg":
            if let evt = try? container.decode(CodexEventMsg.self, forKey: .payload) {
                payload = .eventMsg(evt)
            } else {
                payload = .unknown
            }
        default:
            payload = .unknown
        }
    }
}

/// 按 type 分发后的 payload
enum CodexPayload: Sendable {
    case sessionMeta(CodexSessionMeta)
    case turnContext(CodexTurnContext)
    case eventMsg(CodexEventMsg)
    case unknown
}

/// session_meta.payload — 整个 rollout 文件首行,提供 sessionId / cwd
struct CodexSessionMeta: Decodable, Sendable {
    let id: String
    let cwd: String?
    let modelProvider: String?

    enum CodingKeys: String, CodingKey {
        case id, cwd
        case modelProvider = "model_provider"
    }
}

/// turn_context.payload — 每轮对话开始,标明此后 token_count 归属的 model
struct CodexTurnContext: Decodable, Sendable {
    let model: String?
}

/// event_msg.payload — 包一层 type 才到我们关心的 token_count
struct CodexEventMsg: Decodable, Sendable {
    let type: String                 // 只关心 "token_count"
    let info: CodexTokenCountInfo?

    enum CodingKeys: String, CodingKey {
        case type, info
    }
}

/// token_count.info — 心跳事件该字段为 null
struct CodexTokenCountInfo: Decodable, Sendable {
    let lastTokenUsage: CodexTokenCounts?
    let totalTokenUsage: CodexTokenCounts?

    enum CodingKeys: String, CodingKey {
        case lastTokenUsage = "last_token_usage"
        case totalTokenUsage = "total_token_usage"
    }
}

/// 单次 token 计数四元组(+ total)
struct CodexTokenCounts: Decodable, Sendable, Equatable {
    let inputTokens: Int           // 注意:Codex 的 input 已包含 cached_input,计费时需扣减
    let cachedInputTokens: Int
    let outputTokens: Int          // 注意:已包含 reasoning_output_tokens,reasoning 不另行计费
    let reasoningOutputTokens: Int
    let totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case cachedInputTokens = "cached_input_tokens"
        case outputTokens = "output_tokens"
        case reasoningOutputTokens = "reasoning_output_tokens"
        case totalTokens = "total_tokens"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        inputTokens = try c.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
        cachedInputTokens = try c.decodeIfPresent(Int.self, forKey: .cachedInputTokens) ?? 0
        outputTokens = try c.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
        reasoningOutputTokens = try c.decodeIfPresent(Int.self, forKey: .reasoningOutputTokens) ?? 0
        totalTokens = try c.decodeIfPresent(Int.self, forKey: .totalTokens) ?? 0
    }

    init(inputTokens: Int, cachedInputTokens: Int, outputTokens: Int,
         reasoningOutputTokens: Int, totalTokens: Int) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.totalTokens = totalTokens
    }

    static let zero = CodexTokenCounts(
        inputTokens: 0, cachedInputTokens: 0,
        outputTokens: 0, reasoningOutputTokens: 0, totalTokens: 0
    )

    var isAllZero: Bool {
        inputTokens == 0 && cachedInputTokens == 0
            && outputTokens == 0 && reasoningOutputTokens == 0
    }
}
```

- [ ] **Step 4: 跑测试,确认全部通过**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/CodexRecordTests test 2>&1 | tail -20
```

Expected: 6 个测试全绿。

- [ ] **Step 5: 提交**

```bash
git add -A
git commit -m "feat(codex): 添加 CodexRecord 数据模型"
```

---

## Task 5: CodexRolloutScanner

**Files:**
- Create: `TokenWatch/Providers/Codex/CodexRolloutScanner.swift`
- Create: `TokenWatchTests/Providers/Codex/CodexRolloutScannerTests.swift`

> **设计原因:** Codex 同时存在 `sessions/` 和 `archived_sessions/` 两层目录,同名(相对路径相同)条目以 `sessions/` 为准 — 与 ccusage `adapter/codex/loader.rs` 行为一致。Scanner 仅返回文件 URL + 推断的 sessionID,实际解析在 Parser 完成。

- [ ] **Step 1: 写失败的测试**

写入 `TokenWatchTests/Providers/Codex/CodexRolloutScannerTests.swift`:

```swift
import Testing
import Foundation
@testable import TokenWatch

@Suite("CodexRolloutScanner")
struct CodexRolloutScannerTests {

    /// 在临时目录构造一个简化的 Codex 数据结构
    /// 返回 (rootURL, cleanup)
    private func makeFixture() throws -> (URL, () -> Void) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex-test-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default

        let sessions = root.appendingPathComponent("sessions/2026/05/04", isDirectory: true)
        let archived = root.appendingPathComponent("archived_sessions/2026/05/04", isDirectory: true)
        try fm.createDirectory(at: sessions, withIntermediateDirectories: true)
        try fm.createDirectory(at: archived, withIntermediateDirectories: true)

        // 主目录下 2 个 rollout
        try Data().write(to: sessions.appendingPathComponent("rollout-2026-05-04T16-35-18-019df220-aaaa-bbbb-cccc-ddddeeeeffff.jsonl"))
        try Data().write(to: sessions.appendingPathComponent("rollout-2026-05-04T17-00-00-019df221-1111-2222-3333-444455556666.jsonl"))
        // archived 一个与主目录同名(以相对路径计),应被去重
        try Data().write(to: archived.appendingPathComponent("rollout-2026-05-04T16-35-18-019df220-aaaa-bbbb-cccc-ddddeeeeffff.jsonl"))
        // archived 一个独立的
        try Data().write(to: archived.appendingPathComponent("rollout-2026-05-04T18-00-00-019df222-7777-8888-9999-aaaabbbbcccc.jsonl"))
        // 一个非 jsonl 文件(应忽略)
        try Data().write(to: sessions.appendingPathComponent("not-a-rollout.txt"))

        let cleanup = { try? fm.removeItem(at: root) }
        return (root, cleanup)
    }

    @Test("递归扫 sessions/ + archived_sessions/,去重保留 sessions/ 优先")
    func scansAndDedupes() throws {
        let (root, cleanup) = try makeFixture()
        defer { cleanup() }

        let scanner = CodexRolloutScanner()
        let files = try scanner.scanAll(in: root)

        #expect(files.count == 3)  // 2 sessions + 1 唯一 archived;同名 archived 被剔除

        // 同名(16-35-18 那条)应来自 sessions/,不应来自 archived_sessions/
        let dupName = "rollout-2026-05-04T16-35-18-019df220-aaaa-bbbb-cccc-ddddeeeeffff.jsonl"
        let chosen = files.first(where: { $0.url.lastPathComponent == dupName })
        #expect(chosen != nil)
        #expect(chosen?.url.path.contains("/sessions/") == true)
        #expect(chosen?.url.path.contains("/archived_sessions/") == false)
    }

    @Test("从文件名推断 sessionID")
    func extractsSessionIDFromFilename() throws {
        let (root, cleanup) = try makeFixture()
        defer { cleanup() }

        let scanner = CodexRolloutScanner()
        let files = try scanner.scanAll(in: root)
        let target = files.first(where: {
            $0.url.lastPathComponent.contains("019df220-aaaa")
        })
        #expect(target?.sessionID == "019df220-aaaa-bbbb-cccc-ddddeeeeffff")
    }

    @Test("非 jsonl 文件被忽略")
    func ignoresNonJsonl() throws {
        let (root, cleanup) = try makeFixture()
        defer { cleanup() }

        let scanner = CodexRolloutScanner()
        let files = try scanner.scanAll(in: root)
        #expect(files.allSatisfy { $0.url.pathExtension == "jsonl" })
    }

    @Test("根目录不存在时返回空数组,不抛错")
    func missingRootReturnsEmpty() throws {
        let nonExistent = URL(fileURLWithPath: "/tmp/codex-non-existent-\(UUID().uuidString)")
        let scanner = CodexRolloutScanner()
        let files = try scanner.scanAll(in: nonExistent)
        #expect(files.isEmpty)
    }
}
```

- [ ] **Step 2: 跑测试,确认失败**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/CodexRolloutScannerTests test 2>&1 | tail -20
```

Expected: 失败,提示 `CodexRolloutScanner` / `CodexRolloutFileInfo` 未定义。

- [ ] **Step 3: 实现 CodexRolloutScanner**

写入 `TokenWatch/Providers/Codex/CodexRolloutScanner.swift`:

```swift
import Foundation
import os.log

/// Codex rollout 文件元数据
/// sessionID 优先从文件名 UUID 推断,Parser 解析到 session_meta 后可覆盖
struct CodexRolloutFileInfo: Sendable {
    let url: URL
    let sessionID: String
    /// true 表示来自 archived_sessions/,UI 可据此区分(本期未使用)
    let isArchived: Bool
}

/// 扫描 ${codexRoot}/sessions/ 与 ${codexRoot}/archived_sessions/
/// 同相对路径(YYYY/MM/DD/<filename>)同时存在时,sessions/ 优先
/// 参考 ccusage `rust/crates/ccusage/src/adapter/codex/loader.rs`
final class CodexRolloutScanner: Sendable {

    private let logger = Logger(subsystem: "com.xiaoao.TokenWatch", category: "CodexRolloutScanner")

    /// 扫描 codexRoot 下所有 rollout-*.jsonl 文件
    /// - Parameter codexRoot: 已通过 Bookmark 取得访问权限的 ~/.codex 目录
    func scanAll(in codexRoot: URL) throws -> [CodexRolloutFileInfo] {
        let sessionsDir = codexRoot.appendingPathComponent("sessions")
        let archivedDir = codexRoot.appendingPathComponent("archived_sessions")

        // 先收 sessions/,再收 archived_sessions/ 中相对路径未撞名的部分
        let primary = scanDirectory(sessionsDir, isArchived: false)
        var seenRelative = Set(primary.map(\.relativePath))

        var files = primary.map(\.fileInfo)
        for hit in scanDirectory(archivedDir, isArchived: true) where !seenRelative.contains(hit.relativePath) {
            seenRelative.insert(hit.relativePath)
            files.append(hit.fileInfo)
        }

        logger.info("Codex 扫描完成:共 \(files.count) 个 rollout 文件")
        return files
    }

    // MARK: - Private

    /// 扫描单个根目录下所有 rollout-*.jsonl,同时返回相对路径用于跨目录去重
    private func scanDirectory(_ dir: URL, isArchived: Bool) -> [(fileInfo: CodexRolloutFileInfo, relativePath: String)] {
        guard FileManager.default.fileExists(atPath: dir.path) else {
            return []
        }
        guard let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            logger.warning("无法枚举目录: \(dir.path)")
            return []
        }

        var results: [(CodexRolloutFileInfo, String)] = []
        let dirPath = dir.path
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl" else { continue }
            let name = fileURL.lastPathComponent
            guard name.hasPrefix("rollout-") else { continue }

            let relativePath = String(fileURL.path.dropFirst(dirPath.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let sessionID = extractSessionID(from: name) ?? name
            results.append((CodexRolloutFileInfo(url: fileURL, sessionID: sessionID, isArchived: isArchived), relativePath))
        }
        return results
    }

    /// 从 `rollout-2026-05-04T16-35-18-<UUID>.jsonl` 提取尾部 UUID
    /// UUID 标准 5 段 8-4-4-4-12 = 36 字符,取文件名最后 36 字符
    private func extractSessionID(from filename: String) -> String? {
        let stem = (filename as NSString).deletingPathExtension
        guard stem.count >= 36 else { return nil }
        let uuid = String(stem.suffix(36))
        // 简单校验:含 4 个 '-'
        guard uuid.filter({ $0 == "-" }).count == 4 else { return nil }
        return uuid
    }
}
```

- [ ] **Step 4: 跑测试,确认全部通过**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/CodexRolloutScannerTests test 2>&1 | tail -20
```

Expected: 4 个测试全绿。

- [ ] **Step 5: 提交**

```bash
git add -A
git commit -m "feat(codex): 添加 CodexRolloutScanner"
```

---

## Task 6: CodexRolloutParser 与去重

**Files:**
- Create: `TokenWatch/Providers/Codex/CodexRolloutParser.swift`
- Create: `TokenWatchTests/Providers/Codex/CodexRolloutParserTests.swift`

> **设计原因:** Codex 没有 `message.id`,以 `(sessionId, timestamp.iso8601)` 合成 dedup key。同一会话多文件镜像(归档/重启)的概率较低,合成 key 已能消除复扫重复。`last_token_usage` 优先用,缺失时从 `total - prevTotal` 用 `saturating_sub` 推导;`input` 中扣除 `cached_input` 防止双计;`output` 已含 reasoning,reasoning 不另行计费(参考 ccusage `parser.rs` + TokenTracker `pickDelta`/`normalizeUsage`)。

- [ ] **Step 1: 写失败的测试**

写入 `TokenWatchTests/Providers/Codex/CodexRolloutParserTests.swift`:

```swift
import Testing
import Foundation
@testable import TokenWatch

@Suite("CodexRolloutParser")
struct CodexRolloutParserTests {

    /// 写一个临时 jsonl 文件,返回 fileInfo + cleanup
    private func makeJsonlFile(_ lines: [String], sessionID: String = "019df220-aaaa-bbbb-cccc-ddddeeeeffff") throws -> (CodexRolloutFileInfo, () -> Void) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex-parser-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("rollout-2026-05-04T16-35-18-\(sessionID).jsonl")
        let body = lines.joined(separator: "\n") + "\n"
        try body.write(to: url, atomically: true, encoding: .utf8)
        let info = CodexRolloutFileInfo(url: url, sessionID: sessionID, isArchived: false)
        return (info, { try? FileManager.default.removeItem(at: dir) })
    }

    private let sessionMeta = #"{"timestamp":"2026-05-04T08:35:44.692Z","type":"session_meta","payload":{"id":"019df220-aaaa-bbbb-cccc-ddddeeeeffff","cwd":"/tmp/proj","model_provider":"openai"}}"#

    private let turnContextGpt5 = #"{"timestamp":"2026-05-04T08:35:44.717Z","type":"turn_context","payload":{"model":"gpt-5"}}"#

    private let turnContextGpt55 = #"{"timestamp":"2026-05-04T08:36:00.000Z","type":"turn_context","payload":{"model":"gpt-5.5"}}"#

    /// 4 维全 0 的 token_count(replay marker / info=null 心跳)
    private let replayMarker = #"{"timestamp":"2026-05-04T08:35:45.748Z","type":"event_msg","payload":{"type":"token_count","info":null}}"#

    /// 真实增量 — last_token_usage 直接取
    private let normalEvent = #"{"timestamp":"2026-05-04T08:35:59.868Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":300,"output_tokens":200,"reasoning_output_tokens":50,"total_tokens":1200},"last_token_usage":{"input_tokens":1000,"cached_input_tokens":300,"output_tokens":200,"reasoning_output_tokens":50,"total_tokens":1200},"model_context_window":258400}}}"#

    @Test("last_token_usage 优先 + cached 从 input 中扣减")
    func lastTokenUsagePreferred() throws {
        let (file, cleanup) = try makeJsonlFile([sessionMeta, turnContextGpt5, normalEvent])
        defer { cleanup() }

        let parser = CodexRolloutParser()
        let entries = try parser.parseFile(file)

        #expect(entries.count == 1)
        let e = entries[0]
        #expect(e.provider == .codex)
        #expect(e.model == "gpt-5")
        #expect(e.cwd == "/tmp/proj")
        #expect(e.sessionID == "019df220-aaaa-bbbb-cccc-ddddeeeeffff")
        // input 已扣 cached:1000 - 300 = 700
        #expect(e.usage.inputTokens == 700)
        #expect(e.usage.cacheReadInputTokens == 300)
        // output 不减 reasoning(reasoning 已含在 output 中,但我们记完整 output 由 PricingEngine 计费)
        #expect(e.usage.outputTokens == 200)
        // Codex 无 cache write
        #expect(e.usage.totalCacheCreationTokens == 0)
    }

    @Test("4 维全 0 的 token_count 被跳过")
    func skipsAllZeroEvent() throws {
        let allZero = #"{"timestamp":"2026-05-04T08:35:46.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":0,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":0},"last_token_usage":{"input_tokens":0,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":0}}}}"#

        let (file, cleanup) = try makeJsonlFile([sessionMeta, turnContextGpt5, allZero, normalEvent])
        defer { cleanup() }

        let entries = try CodexRolloutParser().parseFile(file)
        #expect(entries.count == 1)
    }

    @Test("info=null 心跳被跳过")
    func skipsHeartbeat() throws {
        let (file, cleanup) = try makeJsonlFile([sessionMeta, turnContextGpt5, replayMarker, normalEvent])
        defer { cleanup() }

        let entries = try CodexRolloutParser().parseFile(file)
        #expect(entries.count == 1)
    }

    @Test("last_token_usage 缺失时从 total 增量推导")
    func deltaFromTotals() throws {
        // 第一条 last 缺失 — 应取整个 total 作为 delta(prevTotal=0)
        let firstNoLast = #"{"timestamp":"2026-05-04T08:35:59.868Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":300,"output_tokens":200,"reasoning_output_tokens":50,"total_tokens":1200}}}}"#
        // 第二条 last 仍缺失 — delta = (2000-1000, 600-300, 350-200, 80-50)
        let secondNoLast = #"{"timestamp":"2026-05-04T08:36:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":2000,"cached_input_tokens":600,"output_tokens":350,"reasoning_output_tokens":80,"total_tokens":2350}}}}"#

        let (file, cleanup) = try makeJsonlFile([sessionMeta, turnContextGpt5, firstNoLast, secondNoLast])
        defer { cleanup() }

        let entries = try CodexRolloutParser().parseFile(file).sorted(by: { ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast) })
        #expect(entries.count == 2)
        // 第一条:input=1000-300=700, cacheRead=300, output=200
        #expect(entries[0].usage.inputTokens == 700)
        #expect(entries[0].usage.cacheReadInputTokens == 300)
        #expect(entries[0].usage.outputTokens == 200)
        // 第二条 delta:input_delta=1000, cached_delta=300 → pure_input=700
        #expect(entries[1].usage.inputTokens == 700)
        #expect(entries[1].usage.cacheReadInputTokens == 300)
        #expect(entries[1].usage.outputTokens == 150)
    }

    @Test("total 倒退时 saturating_sub 退化为 0")
    func saturatingSubOnRollover() throws {
        let firstHigh = #"{"timestamp":"2026-05-04T08:35:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":5000,"cached_input_tokens":1000,"output_tokens":500,"reasoning_output_tokens":100,"total_tokens":5500}}}}"#
        // 第二条 total 倒退到比第一条还小
        let secondLow = #"{"timestamp":"2026-05-04T08:36:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":200,"output_tokens":100,"reasoning_output_tokens":20,"total_tokens":1100}}}}"#

        let (file, cleanup) = try makeJsonlFile([sessionMeta, turnContextGpt5, firstHigh, secondLow])
        defer { cleanup() }

        let entries = try CodexRolloutParser().parseFile(file).sorted(by: { ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast) })
        #expect(entries.count >= 1)
        // 第二条的 delta 应全为 0(saturating_sub),因此不被 emit;只剩第一条
        #expect(entries.count == 1)
        #expect(entries[0].usage.inputTokens == 4000)  // 5000 - 1000
    }

    @Test("turn_context 切模型后,后续 token_count 用新 model")
    func modelSwitchTakesEffect() throws {
        let event2 = #"{"timestamp":"2026-05-04T08:36:30.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":2000,"cached_input_tokens":500,"output_tokens":300,"reasoning_output_tokens":100,"total_tokens":2300}}}}"#

        let (file, cleanup) = try makeJsonlFile([sessionMeta, turnContextGpt5, normalEvent, turnContextGpt55, event2])
        defer { cleanup() }

        let entries = try CodexRolloutParser().parseFile(file).sorted(by: { ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast) })
        #expect(entries.count == 2)
        #expect(entries[0].model == "gpt-5")
        #expect(entries[1].model == "gpt-5.5")
    }

    @Test("currentModel 缺失时跳过 token_count")
    func skipsWhenNoModel() throws {
        // 没有 turn_context,直接来 token_count
        let (file, cleanup) = try makeJsonlFile([sessionMeta, normalEvent])
        defer { cleanup() }

        let entries = try CodexRolloutParser().parseFile(file)
        #expect(entries.isEmpty)
    }

    @Test("session_meta 缺失时 cwd 为 nil 不崩")
    func missingSessionMeta() throws {
        let (file, cleanup) = try makeJsonlFile([turnContextGpt5, normalEvent])
        defer { cleanup() }

        let entries = try CodexRolloutParser().parseFile(file)
        #expect(entries.count == 1)
        #expect(entries[0].cwd == nil)
        // sessionID 仍可从 fileInfo 拿到
        #expect(entries[0].sessionID == "019df220-aaaa-bbbb-cccc-ddddeeeeffff")
    }

    @Test("dedupKey 由 sessionId+timestamp 合成 — parseAllFiles 重复扫不重复计数")
    func dedupAcrossRescans() throws {
        let (file, cleanup) = try makeJsonlFile([sessionMeta, turnContextGpt5, normalEvent])
        defer { cleanup() }

        let parser = CodexRolloutParser()
        // 模拟同一文件出现两次(理论上 Scanner 已去重,这里测 parser 内 dedup 兜底)
        let merged = try parser.parseAllFiles([file, file])
        #expect(merged.count == 1)
    }
}
```

- [ ] **Step 2: 跑测试,确认失败**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/CodexRolloutParserTests test 2>&1 | tail -20
```

Expected: 失败,提示 `CodexRolloutParser` 未定义。

- [ ] **Step 3: 实现 CodexRolloutParser**

写入 `TokenWatch/Providers/Codex/CodexRolloutParser.swift`:

```swift
import Foundation
import os.log

/// 解析 Codex rollout JSONL,提取 token_count 事件 → 统一 ParsedUsageEntry
///
/// 关键策略(参考 ccusage `adapter/codex/parser.rs` + TokenTracker `codex-rollout-parser.js`):
/// - `last_token_usage` 优先;缺失则 `delta = saturatingSub(total, prevTotal)`
/// - `previousTotals` 始终更新(包括跳过本条的情形),确保后续 delta 推导正确
/// - 4 维全 0 的事件视为 replay marker / 心跳,跳过(prevTotals 仍要更新)
/// - `pure_input = max(0, input - cached_input)` 防止与 cache_read 双计
/// - `output_tokens` 已含 reasoning,直接进 PricingEngine,reasoning 不另计费
final class CodexRolloutParser: Sendable {

    private let logger = Logger(subsystem: "com.xiaoao.TokenWatch", category: "CodexRolloutParser")

    /// 解析单文件
    func parseFile(_ fileInfo: CodexRolloutFileInfo) throws -> [ParsedUsageEntry] {
        let handle = try FileHandle(forReadingFrom: fileInfo.url)
        defer { try? handle.close() }

        let decoder = JSONDecoder()
        let newline: UInt8 = 0x0A

        var entries: [ParsedUsageEntry] = []
        var currentModel: String? = nil
        var sessionCwd: String? = nil
        var sessionID = fileInfo.sessionID    // 优先文件名,session_meta 出现时覆盖
        var previousTotals = CodexTokenCounts.zero
        var hasSeenAnyTotal = false

        // 流式 64KB 分块,与 Claude 解析保持一致
        var buffer = Data()
        let chunkSize = 64 * 1024

        let processLine: (Data) -> Void = { lineData in
            guard !lineData.isEmpty else { return }
            guard let record = try? decoder.decode(CodexRecord.self, from: lineData) else { return }

            switch record.payload {
            case .sessionMeta(let meta):
                sessionID = meta.id
                sessionCwd = meta.cwd

            case .turnContext(let ctx):
                if let m = ctx.model { currentModel = m }

            case .eventMsg(let event):
                guard event.type == "token_count" else { return }
                guard let info = event.info else { return }     // info=null 心跳

                // 计算 delta:优先 last_token_usage,否则用 total 增量
                let delta: CodexTokenCounts
                if let last = info.lastTokenUsage {
                    delta = last
                } else if let total = info.totalTokenUsage {
                    delta = CodexTokenCounts(
                        inputTokens: max(0, total.inputTokens - previousTotals.inputTokens),
                        cachedInputTokens: max(0, total.cachedInputTokens - previousTotals.cachedInputTokens),
                        outputTokens: max(0, total.outputTokens - previousTotals.outputTokens),
                        reasoningOutputTokens: max(0, total.reasoningOutputTokens - previousTotals.reasoningOutputTokens),
                        totalTokens: max(0, total.totalTokens - previousTotals.totalTokens)
                    )
                } else {
                    return
                }

                // previousTotals 始终更新(即便后面跳过本条)— 否则 delta 推导会错位
                if let total = info.totalTokenUsage {
                    previousTotals = total
                    hasSeenAnyTotal = true
                }

                // replay marker / 静默事件 → 跳过 emit,但 prevTotal 已更新
                guard !delta.isAllZero else { return }

                // 模型未确定无法计价 → 跳过
                guard let model = currentModel else {
                    return
                }

                // 防双计:input 已含 cached,扣减后才是 pure 新 token
                let pureInput = max(0, delta.inputTokens - delta.cachedInputTokens)

                let usage = TokenUsage(
                    inputTokens: pureInput,
                    cacheCreationInputTokens: 0,
                    cacheReadInputTokens: delta.cachedInputTokens,
                    outputTokens: delta.outputTokens,
                    serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
                    serviceTier: "",
                    cacheCreation: CacheCreation(ephemeral1hInputTokens: 0, ephemeral5mInputTokens: 0),
                    inferenceGeo: "",
                    iterations: [],
                    speed: ""
                )

                // 合成 dedup key:sessionId + timestamp ISO8601(无 message.id)
                let tsKey = record.timestamp.map { Self.iso8601Key($0) } ?? "no-ts-\(UUID().uuidString)"
                let messageId = "\(sessionID):\(tsKey)"

                entries.append(ParsedUsageEntry(
                    recordUUID: messageId,
                    messageId: messageId,
                    requestId: nil,
                    sessionID: sessionID,
                    timestamp: record.timestamp,
                    model: model,
                    cwd: sessionCwd,
                    agentId: nil,
                    usage: usage,
                    isSubagent: false,
                    provider: .codex
                ))

            case .unknown:
                return
            }
        }

        while true {
            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty { break }
            buffer.append(chunk)

            var searchStart = buffer.startIndex
            while let nl = buffer[searchStart..<buffer.endIndex].firstIndex(of: newline) {
                processLine(Data(buffer[searchStart..<nl]))
                searchStart = buffer.index(after: nl)
            }
            if searchStart > buffer.startIndex {
                buffer.removeSubrange(buffer.startIndex..<searchStart)
            }
        }
        if !buffer.isEmpty {
            processLine(buffer)
        }

        _ = hasSeenAnyTotal  // silence unused
        return entries
    }

    /// 批量解析并按 dedupKey 取 magnitude 最大那条(沿用 Claude 的策略)
    func parseAllFiles(_ files: [CodexRolloutFileInfo]) throws -> [ParsedUsageEntry] {
        var all: [ParsedUsageEntry] = []
        for f in files {
            do {
                all.append(contentsOf: try parseFile(f))
            } catch {
                logger.warning("Codex 文件解析失败: \(f.url.lastPathComponent) — \(error.localizedDescription)")
            }
        }

        var bestByKey: [String: ParsedUsageEntry] = [:]
        bestByKey.reserveCapacity(all.count)
        for e in all {
            let key = e.dedupKey
            if let existing = bestByKey[key] {
                if Self.magnitude(e.usage) > Self.magnitude(existing.usage) {
                    bestByKey[key] = e
                }
            } else {
                bestByKey[key] = e
            }
        }
        return Array(bestByKey.values)
    }

    private static func magnitude(_ u: TokenUsage) -> Int {
        u.inputTokens + u.outputTokens + u.cacheReadInputTokens + u.totalCacheCreationTokens
    }

    /// 把 Date 转为稳定的字符串,作为 dedup key 的时间分量
    /// 设计原因:Date 的 hashValue 在不同平台/版本可能差异;ISO8601 字符串可读且稳定
    private static func iso8601Key(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
```

- [ ] **Step 4: 跑测试,确认全部通过**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/CodexRolloutParserTests test 2>&1 | tail -30
```

Expected: 9 个测试全绿。

- [ ] **Step 5: 提交**

```bash
git add -A
git commit -m "feat(codex): 添加 CodexRolloutParser 与去重"
```

---

## Task 7: CodexProvider 装配 Scanner+Parser

**Files:**
- Create: `TokenWatch/Providers/Codex/CodexProvider.swift`
- Modify: `TokenWatch/Providers/ProviderRegistry.swift`(注册 CodexProvider)

> **设计原因:** `CodexProvider` 是 `UsageProvider` 协议在 Codex 上的实现,只做装配 — 让 `Scanner` 给 `Parser` 喂文件、把结果交给上层。`hasCacheWriteDimension=false` 让 UI 在该 Tab 不展示 cache 写入行。

- [ ] **Step 1: 创建 CodexProvider**

写入 `TokenWatch/Providers/Codex/CodexProvider.swift`:

```swift
import Foundation

/// Codex CLI / Codex Desktop 数据源
/// 装配 CodexRolloutScanner + CodexRolloutParser,适配 UsageProvider 协议
struct CodexProvider: UsageProvider {
    let id: ProviderID = .codex
    let displayName = "Codex"
    let bookmarkKey = "CodexDirectoryBookmark"
    let defaultDirectoryPath = NSString("~/.codex").expandingTildeInPath
    let openPanelMessage = "请选择 ~/.codex 目录以授权 TokenWatch 读取 Codex 用量数据"
    /// Codex 不暴露 cache write 概念,UI 该 Tab 不展示该行
    let hasCacheWriteDimension = false

    private let scanner = CodexRolloutScanner()
    private let parser = CodexRolloutParser()

    func loadEntries(from rootURL: URL) throws -> [ParsedUsageEntry] {
        let files = try scanner.scanAll(in: rootURL)
        return try parser.parseAllFiles(files)
    }
}
```

- [ ] **Step 2: 注册到 ProviderRegistry**

修改 `TokenWatch/Providers/ProviderRegistry.swift`:

```swift
    static let allProviders: [any UsageProvider] = [
        ClaudeProvider(),
        CodexProvider(),
    ]
```

- [ ] **Step 3: 构建并跑全量测试**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests test 2>&1 | tail -20
```

Expected: 全绿,且 `ProviderRegistryTests.bookmarkKeysUnique` 仍通过(claude/codex key 不同)。

- [ ] **Step 4: 提交**

```bash
git add -A
git commit -m "feat(codex): 添加 CodexProvider 装配 Scanner+Parser"
```

---

## Task 8: PricingTable 新增 OpenAI GPT-5 系列定价

**Files:**
- Modify: `TokenWatch/Pricing/PricingTable.swift`

> **设计原因:** Codex 主要使用 OpenAI GPT-5 家族(`gpt-5` ~ `gpt-5.5`)。价位以 ccusage `rust/crates/ccusage/src/pricing.rs::put_builtin_pricing` 为准,所有 GPT-5 系列的 `cache_write` 与 `input` 价相同。这些定价主要给 Codex 用,但 PricingTable 是全局共享的,Claude 模型若意外接入 GPT-5 名也能命中。

- [ ] **Step 1: 在 PricingTable.prices 字典末尾追加 OpenAI 段**

修改 `TokenWatch/Pricing/PricingTable.swift`,在 `glm-5.1` 条目之后(字典闭合 `]` 之前)追加:

```swift
        // MARK: - OpenAI GPT-5 系列(供 Codex provider 使用)
        //
        // 价位参考 ccusage `rust/crates/ccusage/src/pricing.rs::put_builtin_pricing`。
        // GPT-5 family 没有 200k tier above 单价,也没有 fast multiplier。
        // cache_write 与 input 同价(ccusage 表中显式写入),Codex 实际不会产生
        // cache write tokens(无 5m/1h ephemeral 概念),但保持字段对齐以防万一。
        //
        // Codex 的 reasoning_output_tokens 已包含在 output_tokens 中,
        // CodexRolloutParser 仅记录 outputTokens,此处定价直接对 outputTokens 计费即可。

        "gpt-5": ModelPricing(
            modelID: "gpt-5",
            displayName: "GPT-5",
            inputPrice: 1.25, outputPrice: 10.0,
            cacheReadPrice: 0.125, cacheWritePrice: 1.25
        ),
        "gpt-5.1": ModelPricing(
            modelID: "gpt-5.1",
            displayName: "GPT-5.1",
            inputPrice: 1.25, outputPrice: 10.0,
            cacheReadPrice: 0.125, cacheWritePrice: 1.25
        ),
        "gpt-5.1-codex": ModelPricing(
            modelID: "gpt-5.1-codex",
            displayName: "GPT-5.1 Codex",
            inputPrice: 1.25, outputPrice: 10.0,
            cacheReadPrice: 0.125, cacheWritePrice: 1.25
        ),
        "gpt-5.2": ModelPricing(
            modelID: "gpt-5.2",
            displayName: "GPT-5.2",
            inputPrice: 1.75, outputPrice: 14.0,
            cacheReadPrice: 0.175, cacheWritePrice: 1.75
        ),
        "gpt-5.2-codex": ModelPricing(
            modelID: "gpt-5.2-codex",
            displayName: "GPT-5.2 Codex",
            inputPrice: 1.75, outputPrice: 14.0,
            cacheReadPrice: 0.175, cacheWritePrice: 1.75
        ),
        "gpt-5.3-codex": ModelPricing(
            modelID: "gpt-5.3-codex",
            displayName: "GPT-5.3 Codex",
            inputPrice: 1.75, outputPrice: 14.0,
            cacheReadPrice: 0.175, cacheWritePrice: 1.75
        ),
        "gpt-5.4": ModelPricing(
            modelID: "gpt-5.4",
            displayName: "GPT-5.4",
            inputPrice: 2.5, outputPrice: 15.0,
            cacheReadPrice: 0.25, cacheWritePrice: 2.5
        ),
        "gpt-5.4-mini": ModelPricing(
            modelID: "gpt-5.4-mini",
            displayName: "GPT-5.4 Mini",
            inputPrice: 0.75, outputPrice: 4.5,
            cacheReadPrice: 0.075, cacheWritePrice: 0.75
        ),
        "gpt-5.4-nano": ModelPricing(
            modelID: "gpt-5.4-nano",
            displayName: "GPT-5.4 Nano",
            inputPrice: 0.20, outputPrice: 1.25,
            cacheReadPrice: 0.020, cacheWritePrice: 0.20
        ),
        "gpt-5.5": ModelPricing(
            modelID: "gpt-5.5",
            displayName: "GPT-5.5",
            inputPrice: 5.0, outputPrice: 30.0,
            cacheReadPrice: 0.5, cacheWritePrice: 5.0
        ),
```

- [ ] **Step 2: 跑现有 Pricing 测试,确认无回归**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/PricingEngineTests test 2>&1 | tail -10
```

Expected: 全绿。

- [ ] **Step 3: 添加 GPT-5 命中测试(可选但推荐)**

修改 `TokenWatchTests/Pricing/PricingEngineTests.swift`,追加一个 case:

```swift
    @Test("GPT-5 系列命中并计费 — Codex Provider 用")
    func gpt5Pricing() {
        #expect(PricingTable.pricing(for: "gpt-5")?.inputPrice == 1.25)
        #expect(PricingTable.pricing(for: "gpt-5.5")?.outputPrice == 30.0)
        #expect(PricingTable.pricing(for: "gpt-5.4-mini")?.cacheReadPrice == 0.075)
        // 前缀匹配:实际 Codex 不会拼日期后缀,但确保行为不破坏
        #expect(PricingTable.pricing(for: "gpt-5") != nil)
    }
```

- [ ] **Step 4: 跑测试**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests test 2>&1 | tail -10
```

Expected: 全绿。

- [ ] **Step 5: 提交**

```bash
git add -A
git commit -m "feat(pricing): PricingTable 新增 OpenAI GPT-5 系列定价"
```

---

## Task 9: TokenStatsViewModel 改为 per-provider 状态

**Files:**
- Modify: `TokenWatch/ViewModels/TokenStatsViewModel.swift`(整体重写)
- Modify: `TokenWatch/AppDelegate.swift`(applicationDidFinishLaunching 触发 loadAllStats)

> **设计原因:** 把单一 stats 改为 `[ProviderID: ProviderState]`,每个 Tab 独立 isLoading/error/needsAuthorization。`onStateChange` 改为带 `ProviderID` 参数,UI 层能精确刷新对应 Tab。

- [ ] **Step 1: 重写 TokenStatsViewModel**

将 `TokenWatch/ViewModels/TokenStatsViewModel.swift` 整体替换为:

```swift
import Foundation
import os.log

/// 多 provider 用量统计 ViewModel
///
/// 每个 provider 维护独立 ProviderState(stats / loading / error / 授权状态),
/// 各 Tab 之间互不影响。重 IO + 解析在后台 actor 上执行,保证 UI 不卡顿。
@MainActor
final class TokenStatsViewModel: Sendable {

    /// 单 provider 的 UI 状态
    struct ProviderState: Sendable {
        var stats: AggregatedStats?
        var isLoading = false
        var errorMessage: String?
        var needsAuthorization = true
    }

    /// 当前所有 provider 的状态(只读)
    private(set) var states: [ProviderID: ProviderState] = [:]

    /// 状态变更回调,UI 层据此刷新指定 Tab
    var onStateChange: (@MainActor (ProviderID) -> Void)?

    private let bookmarkManager = SecurityScopedBookmarkManager.shared
    private let aggregator = UsageAggregator()
    private let logger = Logger(subsystem: "com.xiaoao.TokenWatch", category: "TokenStatsViewModel")

    init() {
        for provider in ProviderRegistry.allProviders {
            states[provider.id] = ProviderState()
        }
    }

    /// 通知 UI 指定 provider 状态已变更
    private func notifyStateChange(_ id: ProviderID) {
        onStateChange?(id)
    }

    /// 启动时并发触发所有 provider 的 loadStats
    func loadAllStats() async {
        await withTaskGroup(of: Void.self) { group in
            for provider in ProviderRegistry.allProviders {
                group.addTask { @MainActor [weak self] in
                    await self?.loadStats(for: provider.id)
                }
            }
        }
    }

    /// 加载指定 provider 的统计
    func loadStats(for id: ProviderID) async {
        guard let provider = ProviderRegistry.provider(for: id) else { return }

        states[id]?.isLoading = true
        states[id]?.errorMessage = nil
        notifyStateChange(id)

        // Step 1: 检查 Bookmark
        if !bookmarkManager.hasBookmark(forKey: provider.bookmarkKey) {
            states[id]?.needsAuthorization = true
            states[id]?.isLoading = false
            logger.info("\(provider.displayName) 未授权,需要用户操作")
            notifyStateChange(id)
            return
        }

        // Step 2: 恢复 Bookmark
        guard let rootURL = bookmarkManager.restoreBookmarkAndAccess(forKey: provider.bookmarkKey) else {
            states[id]?.errorMessage = "无法访问 \(provider.defaultDirectoryPath),请重新授权"
            states[id]?.needsAuthorization = true
            states[id]?.isLoading = false
            logger.error("\(provider.displayName) Bookmark 恢复失败")
            notifyStateChange(id)
            return
        }
        defer { bookmarkManager.stopAccessing(forKey: provider.bookmarkKey) }

        // Step 3-5: 后台扫 + 解析 + 聚合
        let aggregator = self.aggregator
        let logger = self.logger
        let providerCopy = provider

        let result: Result<AggregatedStats, Error> = await Task.detached(priority: .userInitiated) {
            do {
                let entries = try providerCopy.loadEntries(from: rootURL)
                logger.info("\(providerCopy.displayName) 解析得 \(entries.count) 条记录")
                let stats = aggregator.aggregate(entries)
                return .success(stats)
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success(let stats):
            states[id]?.stats = stats
            states[id]?.needsAuthorization = false
            states[id]?.errorMessage = nil
        case .failure(let error):
            states[id]?.errorMessage = "数据加载失败: \(error.localizedDescription)"
            logger.error("\(provider.displayName) 加载失败: \(error.localizedDescription)")
        }

        states[id]?.isLoading = false
        notifyStateChange(id)
    }

    /// 触发指定 provider 的授权流程
    func requestAuthorization(for id: ProviderID) async {
        guard let provider = ProviderRegistry.provider(for: id) else { return }
        if let _ = await bookmarkManager.promptUserToSelectDirectory(forProvider: provider) {
            states[id]?.needsAuthorization = false
            logger.info("\(provider.displayName) 用户授权成功")
            await loadStats(for: id)
        } else {
            logger.info("\(provider.displayName) 用户取消授权")
        }
    }
}
```

- [ ] **Step 2: 更新 AppDelegate**

修改 `TokenWatch/AppDelegate.swift` 中的 `applicationDidFinishLaunching`:

```swift
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        Task {
            await viewModel.loadAllStats()
        }
    }
```

- [ ] **Step 3: ViewController 临时适配**

`TokenWatch/ViewController.swift` 此时还在用旧的 `vm.stats` / `vm.isLoading` 等字段,会编译失败 — Task 10 整体重写 UI 时会替换它。临时为了让 Task 9 单步可构建,把 `ViewController.swift` 的 `render()` 内对 vm 旧字段的访问改为读 `.claude` 状态:

```swift
    @MainActor
    private func render() {
        guard let vm = viewModel,
              let state = vm.states[.claude] else {
            statusLabel.stringValue = "ViewModel 未就绪"
            actionButton.isHidden = true
            return
        }

        if state.isLoading {
            statusLabel.stringValue = "正在加载用量数据…"
            actionButton.isHidden = true
            return
        }
        if state.needsAuthorization {
            statusLabel.stringValue = "TokenWatch 需要读取 ~/.claude 目录\n以统计 Token 用量"
            actionButton.title = "授权访问 ~/.claude"
            actionButton.isHidden = false
            return
        }
        if let error = state.errorMessage {
            statusLabel.stringValue = error
            actionButton.title = "重试"
            actionButton.isHidden = false
            return
        }
        if let stats = state.stats {
            statusLabel.stringValue = formatStatsText(stats)
            actionButton.title = "刷新"
            actionButton.isHidden = false
            return
        }
        statusLabel.stringValue = "暂无数据"
        actionButton.title = "刷新"
        actionButton.isHidden = false
    }
```

`bindViewModel()` 内闭包参数加 `_ in`(忽略 ProviderID):

```swift
        viewModel?.onStateChange = { [weak self] _ in
            self?.render()
        }
```

`actionButtonClicked` 内调用改为 `.claude`:

```swift
    @objc private func actionButtonClicked() {
        guard let vm = viewModel, let state = vm.states[.claude] else { return }
        Task { @MainActor in
            if state.needsAuthorization {
                await vm.requestAuthorization(for: .claude)
            } else {
                await vm.loadStats(for: .claude)
            }
        }
    }
```

- [ ] **Step 4: 构建并跑全量测试**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests test 2>&1 | tail -10
```

Expected: 全绿。

- [ ] **Step 5: 提交**

```bash
git add -A
git commit -m "feat(viewmodel): TokenStatsViewModel 改为 per-provider 状态"
```

---

## Task 10: 主视图改 NSTabViewController + ProviderStatsViewController

**Files:**
- Create: `TokenWatch/ViewControllers/ProviderStatsViewController.swift`
- Modify: `TokenWatch/ViewController.swift`(改为 NSTabViewController 容器)
- Modify: `TokenWatch/Base.lproj/Main.storyboard`(若 Storyboard 内有 ViewController class 定义,保持兼容)

> **设计原因:** 单一 ViewController 已无法承载多 provider — 改为 `NSTabViewController` 容器,每个 Tab 一个 `ProviderStatsViewController` 实例,各自渲染自己 provider 的状态。`ProviderStatsViewController` 由原 `ViewController` 重构而来,通过 `provider.hasCacheWriteDimension` 决定是否展示 `Cache(write):` 行。

- [ ] **Step 1: 创建 ProviderStatsViewController**

写入 `TokenWatch/ViewControllers/ProviderStatsViewController.swift`:

```swift
import Cocoa

/// 单个 provider 的用量展示 ViewController
/// 由 ViewController(NSTabViewController)装入每个 Tab,通过初始化参数区分 provider
final class ProviderStatsViewController: NSViewController {

    private let provider: any UsageProvider
    private let statusLabel = NSTextField(labelWithString: "")
    private let actionButton = NSButton(title: "", target: nil, action: nil)

    private var viewModel: TokenStatsViewModel? {
        (NSApp.delegate as? AppDelegate)?.viewModel
    }

    /// 通过 provider 显式注入,避免依赖外部状态
    init(provider: any UsageProvider) {
        self.provider = provider
        super.init(nibName: nil, bundle: nil)
        self.title = provider.displayName
    }

    required init?(coder: NSCoder) {
        fatalError("ProviderStatsViewController 必须用 init(provider:) 构造")
    }

    /// NSTabViewController 装载子 VC 时若没显式 view,会触发 loadView,我们手动建一个
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 280))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupSubviews()
        bindViewModel()
        render()
    }

    // MARK: - 视图

    private func setupSubviews() {
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.alignment = .left
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 0
        statusLabel.font = .systemFont(ofSize: 13)

        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.bezelStyle = .rounded
        actionButton.target = self
        actionButton.action = #selector(actionButtonClicked)

        view.addSubview(statusLabel)
        view.addSubview(actionButton)

        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -16),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),

            actionButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            actionButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 16),
        ])
    }

    // MARK: - 绑定

    private func bindViewModel() {
        // 顶层 ViewController 已绑过 onStateChange,这里订阅同一个回调
        // 设计:让 ViewController 把回调多路复用到所有 Tab,各 Tab 只关心自己 provider id
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(stateDidChange(_:)),
            name: .providerStateDidChange,
            object: nil
        )
    }

    @objc private func stateDidChange(_ note: Notification) {
        guard let id = note.userInfo?["providerID"] as? ProviderID, id == provider.id else { return }
        render()
    }

    // MARK: - 渲染

    @MainActor
    private func render() {
        guard let state = viewModel?.states[provider.id] else {
            statusLabel.stringValue = "ViewModel 未就绪"
            actionButton.isHidden = true
            return
        }

        if state.isLoading {
            statusLabel.stringValue = "正在加载 \(provider.displayName) 用量数据…"
            actionButton.isHidden = true
            return
        }
        if state.needsAuthorization {
            statusLabel.stringValue = "TokenWatch 需要读取 \(provider.defaultDirectoryPath) 目录\n以统计 \(provider.displayName) Token 用量"
            actionButton.title = "授权访问 \(provider.defaultDirectoryPath)"
            actionButton.isHidden = false
            return
        }
        if let error = state.errorMessage {
            statusLabel.stringValue = error
            actionButton.title = "重试"
            actionButton.isHidden = false
            return
        }
        if let stats = state.stats {
            statusLabel.stringValue = formatStatsText(stats)
            actionButton.title = "刷新"
            actionButton.isHidden = false
            return
        }
        statusLabel.stringValue = "暂无 \(provider.displayName) 数据"
        actionButton.title = "刷新"
        actionButton.isHidden = false
    }

    // MARK: - 交互

    @objc private func actionButtonClicked() {
        guard let vm = viewModel, let state = vm.states[provider.id] else { return }
        let id = provider.id
        Task { @MainActor in
            if state.needsAuthorization {
                await vm.requestAuthorization(for: id)
            } else {
                await vm.loadStats(for: id)
            }
        }
    }

    // MARK: - 文案构造

    /// 拼装「本日 + 累计」概览。Codex provider 的 cache 行替换为 Cached Input
    private func formatStatsText(_ stats: AggregatedStats) -> String {
        let todayKey = Self.todayKey()
        let today = stats.byDay[todayKey] ?? .zero
        let overall = stats.overall

        let cacheLineToday: String
        if provider.hasCacheWriteDimension {
            cacheLineToday = "  └ Cache:  \(Self.formatInt(today.cacheReadTokens + today.cacheCreationTokens))"
        } else {
            // Codex:只有 cache_read,没有 5m/1h write
            cacheLineToday = "  └ Cached: \(Self.formatInt(today.cacheReadTokens))"
        }

        return """
        ── 本日 (\(todayKey)) ──
        总 Token: \(Self.formatInt(today.totalTokens))
          ├ Input:  \(Self.formatInt(today.inputTokens))
          ├ Output: \(Self.formatInt(today.outputTokens))
        \(cacheLineToday)
        成本: $\(String(format: "%.4f", today.cost))
        记录: \(today.entryCount)

        ── 累计 ──
        总 Token: \(Self.formatInt(overall.totalTokens))
        成本: $\(String(format: "%.4f", overall.cost))
        记录: \(overall.entryCount)  会话: \(stats.bySession.count)
        """
    }

    private static func todayKey() -> String {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month, .day], from: Date())
        guard let y = comps.year, let m = comps.month, let d = comps.day else {
            return "unknown"
        }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    private static func formatInt(_ value: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }
}

extension Notification.Name {
    /// provider 状态变更通知,userInfo["providerID"] = ProviderID
    static let providerStateDidChange = Notification.Name("com.xiaoao.TokenWatch.providerStateDidChange")
}
```

- [ ] **Step 2: 改写 ViewController 为 NSTabViewController 容器**

将 `TokenWatch/ViewController.swift` 整体替换为:

```swift
//
//  ViewController.swift
//  TokenWatch
//
//  Created by OrrHsiao on 2026/6/13.
//

import Cocoa

/// 主视图控制器 — NSTabViewController 容器
/// 每个 provider 一个 Tab,内容由 ProviderStatsViewController 提供
///
/// 设计:Storyboard 仍指向本类,但运行时用 NSTabView 替换默认视图,
/// 把 ProviderRegistry 注册的 provider 一一装载为 TabViewItem。
class ViewController: NSTabViewController {

    private var viewModel: TokenStatsViewModel? {
        (NSApp.delegate as? AppDelegate)?.viewModel
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tabStyle = .toolbar
        installTabs()
        bindViewModel()
    }

    /// 把 ProviderRegistry 注册的 provider 顺序装入 Tab
    private func installTabs() {
        for provider in ProviderRegistry.allProviders {
            let vc = ProviderStatsViewController(provider: provider)
            let item = NSTabViewItem(viewController: vc)
            item.label = provider.displayName
            addTabViewItem(item)
        }
    }

    /// 把 ViewModel 的 onStateChange 回调多路复用到 Notification,
    /// 各 Tab 的 ProviderStatsViewController 自行订阅自己 provider id 的事件
    private func bindViewModel() {
        viewModel?.onStateChange = { providerID in
            NotificationCenter.default.post(
                name: .providerStateDidChange,
                object: nil,
                userInfo: ["providerID": providerID]
            )
        }
    }
}
```

> **注意:** `Main.storyboard` 中 ViewController 仍以 `class = "ViewController"` 标识 — `NSTabViewController` 是 `NSViewController` 子类,storyboard 加载该类后 `viewDidLoad` 中替换内容生效;**无需改 storyboard XML**。如 storyboard 中有顶层 `view` 子视图(如 `Hello, World!` Label)会被 `NSTabViewController` 用 `NSTabView` 替换显示,无副作用。

- [ ] **Step 3: 删除原 ProviderStatsViewController 内的废弃代码引用(可选)**

如果原 `ViewController.swift` 的 `formatStatsText` / `formatInt` / `todayKey` 已被新版引用搬到 `ProviderStatsViewController`,Task 10 第 2 步整体替换后这些函数已经不存在,无需手动删。

- [ ] **Step 4: 构建并跑全量测试**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests test 2>&1 | tail -10
```

Expected: 全绿。

- [ ] **Step 5: 手动 smoke-test**

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Debug build
open ./build/Debug/TokenWatch.app  # 路径以 BUILT_PRODUCTS_DIR 为准
```

或直接用 Xcode MCP 的 `Run` 功能 build & run。

Expected:
- 启动后看到两个 Tab:「Claude Code」与「Codex」
- Claude Tab 自动加载已授权数据(若历史授权过);否则展示授权按钮
- Codex Tab 展示「授权访问 ~/.codex」按钮
- 点击 Codex 授权按钮 → NSOpenPanel 默认定位到 ~/.codex → 选择目录 → 数据加载并展示
- 两个 Tab 互不干扰(刷新一个不会触发另一个)

- [ ] **Step 6: 提交**

```bash
git add -A
git commit -m "feat(ui): 主视图改 NSTabViewController + ProviderStatsViewController"
```

---

## Task 11: README 更新多 provider 说明

**Files:**
- Modify: `README.md`

> **设计原因:** 文档与新架构对齐,读者一眼看到现在支持哪些 provider、未来如何加新 provider。

- [ ] **Step 1: 修改 README.md**

打开 `README.md`,做下列修改:

1. **顶部一句话说明改为多 provider:**
   ```markdown
   macOS 原生应用,统计 Coding Agent (Claude Code / Codex 等) 的 Token 用量与费用。
   ```

2. **「目录结构」章节**用新版 `Providers/` 结构替换。

3. **「数据流」章节**改为多 provider 流图:
   ```
   ┌──────────────┐  ┌──────────────┐
   │ ClaudeProvider │  │ CodexProvider │  ... 未来 GeminiProvider
   └──────┬───────┘  └──────┬───────┘
          ▼                 ▼
   [扫描 + 解析] → ParsedUsageEntry
                       │
                       ▼
                PricingEngine + UsageAggregator (共享)
                       │
                       ▼
                TokenStatsViewModel.states[providerID]
                       │
                       ▼
                NSTabViewController (一个 Tab/provider)
   ```

4. **新增「支持的数据源」章节,列两条:**
   - Claude Code(`~/.claude/projects/`,按 `message.id` 去重)
   - Codex(`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`,按 `(sessionId, timestamp)` 合成 key 去重,用 `last_token_usage` 优先 / `total` 增量推导兜底)

5. **「定价表」章节追加 OpenAI GPT-5 系列:**
   ```markdown
   | gpt-5 | $1.25 | $10.00 | $0.125 | $1.25 | — | — |
   | gpt-5.5 | $5.00 | $30.00 | $0.50 | $5.00 | — | — |
   ...(列出 10 个 gpt-5 系列条目)
   ```

6. **「开发计划」勾选 Phase 8 部分项:**
   ```markdown
   - [x] Phase 8: 支持更多数据源(已支持 Codex,后续 Gemini CLI)
   ```

7. **「Sandbox 适配」章节**改为说明每个 provider 各自管理 Bookmark(key 不同,互不影响)。

- [ ] **Step 2: 提交**

```bash
git add README.md
git commit -m "docs(readme): 更新多 provider 架构说明"
```

---

## 完成验证

- [ ] 全部 11 个任务的 commit 已落地,分支 `feat/codex-provider` 一气呵成。
- [ ] `xcodebuild test` 全绿(原 47 + 新增 ~17 ≈ 64 个 case)。
- [ ] 手动启动 app,Claude Tab 与 Codex Tab 各自展示用量。
- [ ] Codex Tab 用量数与外部 `ccusage codex daily`(若用户安装)对比,误差 < 1%。

---

## 已知限制 / 后续 issue

- `CODEX_HOME` 环境变量未读取 — 默认 `~/.codex`。
- ccusage 的「thread_spawn 同秒 replay 检测」未实现 — 我们的合成 dedup key 已能消除复扫重复,sub-agent 跨文件镜像概率较低,出问题再加。
- Codex `byProject` 维度由 `session_meta.cwd` 提供,单 session = 单 project,不像 Claude 可跨 cwd。
- 后续若要做「Claude + Codex 合并视图」,可在 `TokenStatsViewModel` 加 `combinedStats` 派生属性,复用现有 `UsageAggregator`。
