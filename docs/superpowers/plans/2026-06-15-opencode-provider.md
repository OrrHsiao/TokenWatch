# opencode Provider 接入实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 TokenWatch 接入 opencode 第三个 provider —— 直读 SQLite,新增 reasoning token 维度
和上游 cost fallback 能力,沿用现有 `UsageProvider` + Scanner + Parser 二件套架构。

**Architecture:** 数据模型层 (`TokenUsage`/`UsageSummary`/`ParsedUsageEntry`) 加 reasoning + 上
游元数据三个字段,所有改动向后兼容(默认值 0/nil);`UsageProvider` 协议加 `hasReasoningDimension`;
新建 `TokenWatch/Providers/OpenCode/` 四件套(Provider / SQLiteScanner / MessageParser /
MessageData);`UsageAggregator` 引入 `upstreamCost` fallback;`PricingEngine` 不动。Xcode 16 file
system synchronized groups 使新增 .swift 文件自动入工程,无需改 pbxproj。

**Tech Stack:** Swift 6.0,Swift Testing(`import Testing`),`import SQLite3`(系统 C API,
非第三方依赖),App Sandbox readonly user-selected file。

---

## File Structure

| 文件 | 职责 | 类型 |
|---|---|---|
| `TokenWatch/Models/TokenUsage.swift` | 加 `reasoningTokens` 字段 + decode 兼容 + 便捷 init 默认值 | 修改 |
| `TokenWatch/Models/ParsedUsageEntry.swift` | 加 `upstreamProviderID` / `upstreamCost` 两个可选字段 | 修改 |
| `TokenWatch/Models/UsageAggregation.swift` | `UsageSummary` 加 `reasoningTokens` 字段(参与 totalTokens) | 修改 |
| `TokenWatch/Providers/UsageProvider.swift` | 协议加 `hasReasoningDimension` | 修改 |
| `TokenWatch/Providers/ProviderID.swift` | enum 加 `case opencode` | 修改 |
| `TokenWatch/Providers/Claude/ClaudeProvider.swift` | 显式 `hasReasoningDimension = false` | 修改 |
| `TokenWatch/Providers/Claude/ClaudeJSONLParser.swift` | 构造 `ParsedUsageEntry` 时显式填 `upstreamProviderID/upstreamCost = nil` | 修改 |
| `TokenWatch/Providers/Codex/CodexProvider.swift` | 显式 `hasReasoningDimension = false` | 修改 |
| `TokenWatch/Providers/Codex/CodexRolloutParser.swift` | 构造 `ParsedUsageEntry` 时显式填 `upstreamProviderID/upstreamCost = nil` | 修改 |
| `TokenWatch/Providers/OpenCode/OpenCodeMessageData.swift` | `message.data` JSON 模型 | 新增 |
| `TokenWatch/Providers/OpenCode/OpenCodeSQLiteScanner.swift` | 直读 SQLite,产出 `OpenCodeMessageRow` | 新增 |
| `TokenWatch/Providers/OpenCode/OpenCodeMessageParser.swift` | row → `ParsedUsageEntry` 字段映射 | 新增 |
| `TokenWatch/Providers/OpenCode/OpenCodeProvider.swift` | 装配 + 实现 `UsageProvider` | 新增 |
| `TokenWatch/Providers/ProviderRegistry.swift` | 注册 `OpenCodeProvider()` | 修改 |
| `TokenWatch/Analytics/UsageAggregator.swift` | aggregateEntries 加 reasoning 求和 + cost fallback | 修改 |
| `TokenWatchTests/Models/TokenUsageDecodingTests.swift` | 加 reasoning_tokens 兼容性测试,调整 helper 签名 | 修改 |
| `TokenWatchTests/Analytics/UsageAggregatorTests.swift` | 加 reasoning 聚合 + upstreamCost fallback 测试,调整 helper | 修改 |
| `TokenWatchTests/Providers/ProviderRegistryTests.swift` | 加 opencode 注册 + 路径校验 | 修改 |
| `TokenWatchTests/Providers/OpenCode/OpenCodeMessageParserTests.swift` | 新建 | 新增 |
| `TokenWatchTests/Providers/OpenCode/OpenCodeSQLiteScannerTests.swift` | 新建,临时目录构造 mini db | 新增 |

---

## Task 顺序

1. 模型层扩展(reasoning + upstream 元数据)
2. 协议扩展(hasReasoningDimension)
3. Claude / Codex parser 适配新字段
4. opencode 四件套(数据模型 → Scanner → Parser → Provider)
5. registry 注册
6. UsageAggregator cost fallback + reasoning 求和
7. 全量构建 + 测试
8. 统一提交(单 commit)

每个 task 完成后**不单独 commit**,Task 8 统一提交。中间态会有编译错误(模型变化),这是正常的。

---

## Task 1:扩展数据模型(`TokenUsage` / `ParsedUsageEntry` / `UsageSummary`)

**Files:**
- Modify: `TokenWatch/Models/TokenUsage.swift`
- Modify: `TokenWatch/Models/ParsedUsageEntry.swift`
- Modify: `TokenWatch/Models/UsageAggregation.swift`

- [ ] **Step 1: 给 `TokenUsage` 加 `reasoningTokens` 字段**

修改 `TokenWatch/Models/TokenUsage.swift`:

(a) 在 `outputTokens` 字段后追加:

```swift
    let reasoningTokens: Int
```

(b) 在 `CodingKeys` 枚举中,`outputTokens = "output_tokens"` 之后追加:

```swift
        case reasoningTokens = "reasoning_tokens"
```

(c) 在 `init(from decoder:)` 内,`outputTokens = try container.decode(...)` 后追加:

```swift
        reasoningTokens = try container.decodeIfPresent(Int.self, forKey: .reasoningTokens) ?? 0
```

(d) 便捷初始化器(以 `init(inputTokens: Int,` 开头那个)的参数列表里,在 `outputTokens: Int,`
   之后追加:

```swift
        reasoningTokens: Int = 0,
```

把对应 init body 的 `self.outputTokens = outputTokens` 之后补一行:

```swift
        self.reasoningTokens = reasoningTokens
```

> **重点**:`reasoningTokens` 在便捷 init 中**必须**有默认值 `= 0`,否则所有现有测试构造
> `TokenUsage(...)` 都会编译失败。这是设计稿里"Claude/Codex 默认 0,行为与现状一致"的实现保证。

- [ ] **Step 2: 给 `ParsedUsageEntry` 加 upstream 元数据**

修改 `TokenWatch/Models/ParsedUsageEntry.swift`,在 `provider: ProviderID` 字段(struct 最后
一个属性)之后追加两行:

```swift
    /// opencode 的上游 provider 标识(如 "anthropic" / "huoshan-zijie");Claude/Codex 填 nil
    let upstreamProviderID: String?
    /// 数据源自带的单条 cost(USD);PricingEngine 查不到模型时作为 fallback;Claude/Codex 填 nil
    let upstreamCost: Double?
```

`dedupKey` / `hash(into:)` / `==` 不修改 —— 新字段不参与去重。

- [ ] **Step 3: 给 `UsageSummary` 加 `reasoningTokens`**

修改 `TokenWatch/Models/UsageAggregation.swift`:

(a) `UsageSummary` struct 的字段顺序改为:

```swift
struct UsageSummary: Sendable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheCreationTokens: Int
    let reasoningTokens: Int
    let totalTokens: Int
    let cost: Double
    let entryCount: Int
    let modelBreakdown: [String: UsageSummary]

    /// 创建空的聚合结果
    static var zero: UsageSummary {
        UsageSummary(
            inputTokens: 0, outputTokens: 0,
            cacheReadTokens: 0, cacheCreationTokens: 0,
            reasoningTokens: 0,
            totalTokens: 0, cost: 0, entryCount: 0,
            modelBreakdown: [:]
        )
    }
}
```

`AggregatedStats` 不需要改 —— 它只引用 `UsageSummary`。

- [ ] **Step 4: 不构建,继续 Task 2**

模型变化会导致 `UsageAggregator.swift` 中所有 `UsageSummary(...)` 的初始化报缺 `reasoningTokens`
参数。这正常,Task 6 会修复。先继续。

---

## Task 2:扩展 `UsageProvider` 协议

**Files:**
- Modify: `TokenWatch/Providers/UsageProvider.swift`
- Modify: `TokenWatch/Providers/ProviderID.swift`

- [ ] **Step 1: 协议加 `hasReasoningDimension`**

修改 `TokenWatch/Providers/UsageProvider.swift`,在 `var hasCacheWriteDimension: Bool { get }`
之后追加:

```swift
    /// 该 provider 是否暴露 reasoning token 维度(决定 UI 是否展示该行)
    /// Claude=false(无该字段)、Codex=false(reasoning 已并入 output)、opencode=true
    var hasReasoningDimension: Bool { get }
```

- [ ] **Step 2: `ProviderID` 加 `case opencode`**

修改 `TokenWatch/Providers/ProviderID.swift`,enum 改为:

```swift
enum ProviderID: String, Sendable, CaseIterable, Hashable, Codable {
    case claude
    case codex
    case opencode
}
```

---

## Task 3:Claude / Codex Provider & Parser 适配

**Files:**
- Modify: `TokenWatch/Providers/Claude/ClaudeProvider.swift`
- Modify: `TokenWatch/Providers/Claude/ClaudeJSONLParser.swift`(`processLine` 闭包内构造
  `ParsedUsageEntry` 处)
- Modify: `TokenWatch/Providers/Codex/CodexProvider.swift`
- Modify: `TokenWatch/Providers/Codex/CodexRolloutParser.swift`(`processLine` 闭包内构造
  `ParsedUsageEntry` 处)

- [ ] **Step 1: ClaudeProvider 加 `hasReasoningDimension`**

修改 `TokenWatch/Providers/Claude/ClaudeProvider.swift`,在 `let hasCacheWriteDimension = true`
之后追加:

```swift
    let hasReasoningDimension = false
```

- [ ] **Step 2: ClaudeJSONLParser 显式填 upstream 字段**

修改 `TokenWatch/Providers/Claude/ClaudeJSONLParser.swift`,找到 `processLine` 闭包内的
`entries.append(ParsedUsageEntry(...))` 调用(约文件第 60~73 行),在 `provider: .claude` 之后
新增两个尾部参数:

```swift
            entries.append(ParsedUsageEntry(
                recordUUID: record.uuid,
                messageId: messageId,
                requestId: record.requestId,
                sessionID: record.sessionId,
                timestamp: record.timestamp,
                model: model,
                cwd: record.cwd,
                agentId: fileInfo.agentId,
                usage: usage,
                isSubagent: fileInfo.isSubagent,
                provider: .claude,
                upstreamProviderID: nil,
                upstreamCost: nil
            ))
```

- [ ] **Step 3: CodexProvider 加 `hasReasoningDimension`**

修改 `TokenWatch/Providers/Codex/CodexProvider.swift`,在 `let hasCacheWriteDimension = false`
之后追加:

```swift
    /// Codex 的 reasoning 已并入 output_tokens,不单列维度
    let hasReasoningDimension = false
```

- [ ] **Step 4: CodexRolloutParser 显式填 upstream 字段**

修改 `TokenWatch/Providers/Codex/CodexRolloutParser.swift`,找到
`entries.append(ParsedUsageEntry(...))`(`processLine` 闭包内,约文件第 100~113 行),在
`provider: .codex` 之后新增两个尾部参数:

```swift
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
                    provider: .codex,
                    upstreamProviderID: nil,
                    upstreamCost: nil
                ))
```

---

## Task 4:opencode 四件套

**Files:**
- Create: `TokenWatch/Providers/OpenCode/OpenCodeMessageData.swift`
- Create: `TokenWatch/Providers/OpenCode/OpenCodeSQLiteScanner.swift`
- Create: `TokenWatch/Providers/OpenCode/OpenCodeMessageParser.swift`
- Create: `TokenWatch/Providers/OpenCode/OpenCodeProvider.swift`

> Xcode 16 的 file system synchronized groups 会自动把 `TokenWatch/Providers/OpenCode/` 下的
> .swift 文件纳入 TokenWatch target,不需要手改 pbxproj。

- [ ] **Step 1: 创建 `OpenCodeMessageData.swift`**

写入 `TokenWatch/Providers/OpenCode/OpenCodeMessageData.swift`:

```swift
import Foundation

/// opencode SQLite 中 `message.data` JSON blob 的 Decodable 模型
/// 仅解码 token 统计需要的子树,其余字段忽略
///
/// 字段来源:opencode v1.17.5 schema(`message` 表 `data` 列,role=assistant)
struct OpenCodeMessageData: Decodable {
    let role: String
    let modelID: String?
    let providerID: String?
    let cost: Double?
    let tokens: OpenCodeTokens?
    let path: OpenCodePath?

    enum CodingKeys: String, CodingKey {
        case role, modelID, providerID, cost, tokens, path
    }
}

/// `data.tokens` 子结构 — 含 5 类 token
struct OpenCodeTokens: Decodable {
    let input: Int
    let output: Int
    let reasoning: Int
    let cache: OpenCodeCache

    enum CodingKeys: String, CodingKey {
        case input, output, reasoning, cache
    }

    /// 5 维全 0 视为 placeholder,Parser 跳过
    var isAllZero: Bool {
        input == 0 && output == 0 && reasoning == 0
            && cache.read == 0 && cache.write == 0
    }
}

/// `data.tokens.cache` 子结构
struct OpenCodeCache: Decodable {
    let read: Int
    let write: Int
}

/// `data.path` 子结构 — 仅取 cwd
struct OpenCodePath: Decodable {
    let cwd: String?
}
```

- [ ] **Step 2: 创建 `OpenCodeSQLiteScanner.swift`**

写入 `TokenWatch/Providers/OpenCode/OpenCodeSQLiteScanner.swift`:

```swift
import Foundation
import SQLite3
import os.log

/// SQLite 扫描产出的单行原始数据(JSON blob 未解码)
struct OpenCodeMessageRow: Sendable {
    let id: String                 // message.id (PK,作 dedup messageId)
    let sessionID: String
    let timeCreatedMs: Int64       // ms epoch
    let dataJSON: String           // message.data 原始 JSON 字符串
    let directory: String          // session.directory(cwd 兜底)
}

enum OpenCodeScannerError: Error, CustomStringConvertible {
    case databaseNotFound(URL)
    case openFailed(code: Int32, message: String)
    case queryFailed(code: Int32, message: String)

    var description: String {
        switch self {
        case .databaseNotFound(let url):
            return "opencode.db 不存在: \(url.path)"
        case .openFailed(let code, let msg):
            return "无法打开 opencode.db (SQLite code=\(code)): \(msg)"
        case .queryFailed(let code, let msg):
            return "查询 opencode.db 失败 (SQLite code=\(code)): \(msg)"
        }
    }
}

/// 直读 ~/.local/share/opencode/opencode.db
///
/// 设计原因:
/// - 用 `file:<path>?immutable=1` URI 模式只读打开 → 不会创建/修改 WAL/SHM 文件,
///   与 App Sandbox readonly 完全兼容,且避开锁竞争(opencode 进程在跑也能读)
/// - 仅查 message+session 必要字段,JSON blob 留给 Parser 解码,职责清晰
final class OpenCodeSQLiteScanner: Sendable {

    private let logger = Logger(subsystem: "com.xiaoao.TokenWatch", category: "OpenCodeSQLiteScanner")

    /// SQL 文本作为静态常量便于 Scanner 测试断言可见
    static let assistantMessageQuery = """
    SELECT m.id,
           m.session_id,
           m.time_created,
           m.data,
           s.directory
    FROM message AS m
    JOIN session AS s ON m.session_id = s.id
    WHERE json_extract(m.data, '$.role') = 'assistant'
    ORDER BY m.time_created;
    """

    /// 扫描指定根目录下的 opencode.db
    /// - Parameter rootURL: ~/.local/share/opencode 目录(已通过 SecurityScopedBookmark 授权)
    /// - Returns: assistant 消息行列表
    func scanAll(in rootURL: URL) throws -> [OpenCodeMessageRow] {
        let dbURL = rootURL.appendingPathComponent("opencode.db")
        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            throw OpenCodeScannerError.databaseNotFound(dbURL)
        }

        var db: OpaquePointer?
        let uri = "file:\(dbURL.path)?immutable=1"
        let openFlags: Int32 = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI

        let openCode = sqlite3_open_v2(uri, &db, openFlags, nil)
        guard openCode == SQLITE_OK, let database = db else {
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(db)
            throw OpenCodeScannerError.openFailed(code: openCode, message: msg)
        }
        defer { sqlite3_close(database) }

        var stmt: OpaquePointer?
        let prepCode = sqlite3_prepare_v2(database, Self.assistantMessageQuery, -1, &stmt, nil)
        guard prepCode == SQLITE_OK, let statement = stmt else {
            let msg = String(cString: sqlite3_errmsg(database))
            sqlite3_finalize(stmt)
            throw OpenCodeScannerError.queryFailed(code: prepCode, message: msg)
        }
        defer { sqlite3_finalize(statement) }

        var rows: [OpenCodeMessageRow] = []
        while true {
            let stepCode = sqlite3_step(statement)
            if stepCode == SQLITE_DONE { break }
            guard stepCode == SQLITE_ROW else {
                let msg = String(cString: sqlite3_errmsg(database))
                throw OpenCodeScannerError.queryFailed(code: stepCode, message: msg)
            }
            // column index 与 SELECT 列顺序一致
            guard let idC = sqlite3_column_text(statement, 0),
                  let sidC = sqlite3_column_text(statement, 1),
                  let dataC = sqlite3_column_text(statement, 3),
                  let dirC = sqlite3_column_text(statement, 4)
            else {
                continue   // 必填列缺失 → 跳过该行
            }
            let id = String(cString: idC)
            let sessionID = String(cString: sidC)
            let timeMs = sqlite3_column_int64(statement, 2)
            let dataJSON = String(cString: dataC)
            let directory = String(cString: dirC)

            rows.append(OpenCodeMessageRow(
                id: id,
                sessionID: sessionID,
                timeCreatedMs: timeMs,
                dataJSON: dataJSON,
                directory: directory
            ))
        }

        logger.info("opencode SQLite 读出 assistant 行数: \(rows.count)")
        return rows
    }
}
```

- [ ] **Step 3: 创建 `OpenCodeMessageParser.swift`**

写入 `TokenWatch/Providers/OpenCode/OpenCodeMessageParser.swift`:

```swift
import Foundation
import os.log

/// 把 OpenCodeMessageRow 转成统一的 ParsedUsageEntry
///
/// 字段映射策略(见设计稿"opencode 字段映射"表):
/// - model = "{providerID}/{modelID}"(Q4=b,严格区分上游)
/// - tokens.cache.write → cacheCreationInputTokens 扁平字段(ephemeral_5m/1h 留 0,
///   派生属性 totalCacheCreationTokens 自动 fall through 到扁平字段)
/// - data.cost → upstreamCost(USD,作 PricingEngine miss 的 fallback)
/// - 跳过条件:role != assistant / tokens 缺失 / 5 维全 0 placeholder
final class OpenCodeMessageParser: Sendable {

    private let logger = Logger(subsystem: "com.xiaoao.TokenWatch", category: "OpenCodeMessageParser")

    /// 批量解析行 → 统一条目(messageId 由 SQLite PK 保证全局唯一,无需再去重)
    func parseAll(_ rows: [OpenCodeMessageRow]) -> [ParsedUsageEntry] {
        let decoder = JSONDecoder()
        var entries: [ParsedUsageEntry] = []
        var skippedNotAssistant = 0
        var skippedMissingTokens = 0
        var skippedAllZero = 0
        var skippedDecodeFailed = 0

        for row in rows {
            guard let dataBytes = row.dataJSON.data(using: .utf8) else {
                skippedDecodeFailed += 1
                continue
            }
            let parsed: OpenCodeMessageData
            do {
                parsed = try decoder.decode(OpenCodeMessageData.self, from: dataBytes)
            } catch {
                skippedDecodeFailed += 1
                continue
            }

            // 双保险:query 已过滤 role=assistant
            guard parsed.role == "assistant" else {
                skippedNotAssistant += 1
                continue
            }
            guard let tokens = parsed.tokens else {
                skippedMissingTokens += 1
                continue
            }
            guard !tokens.isAllZero else {
                skippedAllZero += 1
                continue
            }

            let usage = TokenUsage(
                inputTokens: tokens.input,
                cacheCreationInputTokens: tokens.cache.write,
                cacheReadInputTokens: tokens.cache.read,
                outputTokens: tokens.output,
                reasoningTokens: tokens.reasoning,
                serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
                serviceTier: "",
                cacheCreation: CacheCreation(ephemeral1hInputTokens: 0, ephemeral5mInputTokens: 0),
                inferenceGeo: "",
                iterations: [],
                speed: ""
            )

            // model = "{providerID}/{modelID}",任一缺失则降级展示
            let modelKey: String
            switch (parsed.providerID, parsed.modelID) {
            case let (p?, m?): modelKey = "\(p)/\(m)"
            case (_, let m?):  modelKey = m
            case (let p?, _):  modelKey = p
            default:           modelKey = "unknown"
            }

            // cwd:优先 data.path.cwd,否则 session.directory
            let cwd = parsed.path?.cwd ?? row.directory

            // upstreamCost:0 视为缺省(opencode 算不出会写 0)
            let upstreamCost: Double? = (parsed.cost.map { $0 > 0 ? $0 : nil }) ?? nil

            entries.append(ParsedUsageEntry(
                recordUUID: row.id,
                messageId: row.id,
                requestId: nil,
                sessionID: row.sessionID,
                timestamp: Date(timeIntervalSince1970: TimeInterval(row.timeCreatedMs) / 1000.0),
                model: modelKey,
                cwd: cwd,
                agentId: nil,
                usage: usage,
                isSubagent: false,
                provider: .opencode,
                upstreamProviderID: parsed.providerID,
                upstreamCost: upstreamCost
            ))
        }

        if skippedNotAssistant + skippedMissingTokens + skippedAllZero + skippedDecodeFailed > 0 {
            logger.info("opencode 解析跳过 — notAssistant:\(skippedNotAssistant) missingTokens:\(skippedMissingTokens) allZero:\(skippedAllZero) decodeFailed:\(skippedDecodeFailed)")
        }
        return entries
    }
}
```

- [ ] **Step 4: 创建 `OpenCodeProvider.swift`**

写入 `TokenWatch/Providers/OpenCode/OpenCodeProvider.swift`:

```swift
import Foundation

/// opencode (https://opencode.ai) 数据源
/// 装配 OpenCodeSQLiteScanner + OpenCodeMessageParser,适配 UsageProvider 协议
struct OpenCodeProvider: UsageProvider {
    let id: ProviderID = .opencode
    let displayName = "opencode"
    let bookmarkKey = "OpenCodeDirectoryBookmark"
    let defaultDirectoryPath = NSString("~/.local/share/opencode").expandingTildeInPath
    let openPanelMessage = "请选择 ~/.local/share/opencode 目录以授权 TokenWatch 读取 opencode 用量数据"
    /// opencode 的 cache.write 含义与 Anthropic cache_creation 不完全等价,数据层映射保留但 UI 暂不展示
    let hasCacheWriteDimension = false
    /// opencode 显式暴露 reasoning_tokens(GPT-5/o3 系列)
    let hasReasoningDimension = true

    private let scanner = OpenCodeSQLiteScanner()
    private let parser = OpenCodeMessageParser()

    /// 扫描 opencode.db 并解析为统一条目
    /// - Parameter rootURL: 已授权的 ~/.local/share/opencode 目录
    /// - Returns: ParsedUsageEntry 列表(messageId 由 SQLite PK 保证全局唯一,无需去重)
    func loadEntries(from rootURL: URL) throws -> [ParsedUsageEntry] {
        let rows = try scanner.scanAll(in: rootURL)
        return parser.parseAll(rows)
    }
}
```

---

## Task 5:Registry 注册

**Files:**
- Modify: `TokenWatch/Providers/ProviderRegistry.swift`

- [ ] **Step 1: 注册 `OpenCodeProvider()`**

修改 `TokenWatch/Providers/ProviderRegistry.swift`,`allProviders` 数组改为:

```swift
    /// 顺序即 UI Tab 顺序
    static let allProviders: [any UsageProvider] = [
        ClaudeProvider(),
        CodexProvider(),
        OpenCodeProvider()
    ]
```

---

## Task 6:UsageAggregator —— reasoning 求和 + cost fallback

**Files:**
- Modify: `TokenWatch/Analytics/UsageAggregator.swift`(`aggregateEntries(_:)` 内部)

- [ ] **Step 1: 改 `aggregateEntries` —— 加 reasoning 累加 + cost fallback + UsageSummary 加字段**

把 `TokenWatch/Analytics/UsageAggregator.swift::aggregateEntries(_:)` 整个函数体替换为:

```swift
    /// 聚合一组条目为 UsageSummary，内含按模型细分
    private func aggregateEntries(_ entries: [ParsedUsageEntry]) -> UsageSummary {
        var totalInput = 0, totalOutput = 0, totalCacheRead = 0, totalCacheCreation = 0
        var totalReasoning = 0
        var totalCost = 0.0
        var modelBreakdown: [String: UsageSummary] = [:]

        let byModel = Dictionary(grouping: entries, by: { $0.model })

        for (model, modelEntries) in byModel {
            var mInput = 0, mOutput = 0, mCacheRead = 0, mCacheCreation = 0
            var mReasoning = 0
            var mCost = 0.0

            for entry in modelEntries {
                mInput += entry.usage.inputTokens
                mOutput += entry.usage.outputTokens
                mCacheRead += entry.usage.cacheReadInputTokens
                // cache_creation_input_tokens 与 ephemeral_5m/1h 是总分关系
                // 由 TokenUsage.totalCacheCreationTokens 统一处理，避免 double-count
                mCacheCreation += entry.usage.totalCacheCreationTokens
                mReasoning += entry.usage.reasoningTokens

                // Cost fallback:PricingEngine 查不到模型(常见于 opencode 上游小众模型)
                // 时退回到数据源自带 cost(opencode 的 message.data.cost)
                let (engineCost, pricing) = pricingEngine.calculateCost(
                    usage: entry.usage,
                    model: entry.model
                )
                if pricing == nil, let upstream = entry.upstreamCost, upstream > 0 {
                    mCost += upstream
                } else {
                    mCost += engineCost
                }
            }

            totalInput += mInput
            totalOutput += mOutput
            totalCacheRead += mCacheRead
            totalCacheCreation += mCacheCreation
            totalReasoning += mReasoning
            totalCost += mCost

            modelBreakdown[model] = UsageSummary(
                inputTokens: mInput,
                outputTokens: mOutput,
                cacheReadTokens: mCacheRead,
                cacheCreationTokens: mCacheCreation,
                reasoningTokens: mReasoning,
                totalTokens: mInput + mOutput + mCacheRead + mCacheCreation + mReasoning,
                cost: mCost,
                entryCount: modelEntries.count,
                modelBreakdown: [:]
            )
        }

        return UsageSummary(
            inputTokens: totalInput,
            outputTokens: totalOutput,
            cacheReadTokens: totalCacheRead,
            cacheCreationTokens: totalCacheCreation,
            reasoningTokens: totalReasoning,
            totalTokens: totalInput + totalOutput + totalCacheRead + totalCacheCreation + totalReasoning,
            cost: totalCost,
            entryCount: entries.count,
            modelBreakdown: modelBreakdown
        )
    }
```

- [ ] **Step 2: 跑全工程构建,确认通过**

Run: `xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Debug build`
Expected: BUILD SUCCEEDED。如果有 `UsageSummary` 缺参数错误,说明哪里漏改了 `reasoningTokens:`。

---

## Task 7:测试 —— 既有扩展 + opencode 新增

**Files:**
- Modify: `TokenWatchTests/Models/TokenUsageDecodingTests.swift`
- Modify: `TokenWatchTests/Analytics/UsageAggregatorTests.swift`
- Modify: `TokenWatchTests/Providers/ProviderRegistryTests.swift`
- Create: `TokenWatchTests/Providers/OpenCode/OpenCodeMessageParserTests.swift`
- Create: `TokenWatchTests/Providers/OpenCode/OpenCodeSQLiteScannerTests.swift`

- [ ] **Step 1: TokenUsageDecodingTests 加 reasoning 兼容性测试**

修改 `TokenWatchTests/Models/TokenUsageDecodingTests.swift`,在 `decodeWithoutOptionalFields()`
之后追加:

```swift
    @Test("解析含 reasoning_tokens 字段(opencode/GPT-5 系列)")
    func decodeWithReasoningTokens() throws {
        let json = """
        {
            "input_tokens": 100,
            "output_tokens": 50,
            "reasoning_tokens": 250
        }
        """
        let usage = try JSONDecoder().decode(TokenUsage.self, from: json.data(using: .utf8)!)
        #expect(usage.inputTokens == 100)
        #expect(usage.outputTokens == 50)
        #expect(usage.reasoningTokens == 250)
    }

    @Test("缺失 reasoning_tokens 默认 0(向后兼容 Claude/Codex)")
    func reasoningTokensDefaultsToZero() throws {
        let json = """
        {
            "input_tokens": 10,
            "output_tokens": 5
        }
        """
        let usage = try JSONDecoder().decode(TokenUsage.self, from: json.data(using: .utf8)!)
        #expect(usage.reasoningTokens == 0)
    }
```

> **既有断言不需要改**:`createUsage` helper 通过便捷 init 构造 `TokenUsage`,`reasoningTokens`
> 默认 0,所有现存测试无需修改。

- [ ] **Step 2: UsageAggregatorTests 加 reasoning 聚合 + cost fallback 测试**

修改 `TokenWatchTests/Analytics/UsageAggregatorTests.swift`:

(a) 修改 `makeEntry` helper —— 加两个可选参数(默认值保证既有调用零改动)。把 helper 整个改为:

```swift
    private func makeEntry(
        sessionID: String,
        date: Date,
        model: String,
        input: Int,
        output: Int,
        cacheRead: Int = 0,
        cacheCreation: Int = 0,
        reasoning: Int = 0,
        cwd: String = "/test",
        upstreamProviderID: String? = nil,
        upstreamCost: Double? = nil
    ) -> ParsedUsageEntry {
        let id = UUID().uuidString
        return ParsedUsageEntry(
            recordUUID: id,
            messageId: id,
            requestId: nil,
            sessionID: sessionID,
            timestamp: date,
            model: model,
            cwd: cwd,
            agentId: nil,
            usage: TokenUsage(
                inputTokens: input,
                cacheCreationInputTokens: cacheCreation,
                cacheReadInputTokens: cacheRead,
                outputTokens: output,
                reasoningTokens: reasoning,
                serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
                serviceTier: "standard",
                cacheCreation: CacheCreation(ephemeral1hInputTokens: 0, ephemeral5mInputTokens: 0),
                inferenceGeo: "",
                iterations: [],
                speed: "standard"
            ),
            isSubagent: false,
            provider: .claude,
            upstreamProviderID: upstreamProviderID,
            upstreamCost: upstreamCost
        )
    }
```

> 关键:**保留 `provider: .claude`** 默认 —— 现有所有断言都基于这个,不要改成 `.opencode`。
> 新加的 cost fallback 测试可以传不同 model 来触发 PricingEngine miss,不需要切 provider。

(b) 在 `MARK: - 模型细分` 之后追加新区域(`// MARK: - Helpers` 之前):

```swift
    // MARK: - Reasoning 聚合

    @Test("reasoningTokens 参与 byModel/byDay/overall 求和与 totalTokens")
    func reasoningAggregation() {
        let entries = [
            makeEntry(sessionID: "s1", date: date(2026, 6, 13), model: "gpt-5",
                      input: 100, output: 50, reasoning: 200),
            makeEntry(sessionID: "s1", date: date(2026, 6, 13), model: "gpt-5",
                      input: 200, output: 100, reasoning: 400),
            makeEntry(sessionID: "s2", date: date(2026, 6, 14), model: "gpt-5-mini",
                      input: 50, output: 20, reasoning: 30),
        ]

        let stats = aggregator.aggregate(entries)

        #expect(stats.overall.reasoningTokens == 630)
        // totalTokens 包含 reasoning:300+150+30 input/output + 0 cache + 630 reasoning = 1110
        #expect(stats.overall.totalTokens
                == stats.overall.inputTokens + stats.overall.outputTokens
                 + stats.overall.cacheReadTokens + stats.overall.cacheCreationTokens
                 + stats.overall.reasoningTokens)

        #expect(stats.byModel["gpt-5"]?.reasoningTokens == 600)
        #expect(stats.byModel["gpt-5-mini"]?.reasoningTokens == 30)
        #expect(stats.byDay["2026-06-13"]?.reasoningTokens == 600)
        #expect(stats.byDay["2026-06-14"]?.reasoningTokens == 30)
    }

    @Test("reasoning=0 时不影响既有维度求和(向后兼容)")
    func reasoningZeroIsNoOp() {
        let entries = [
            makeEntry(sessionID: "s1", date: date(2026, 6, 13), model: "claude-sonnet-4-5",
                      input: 100, output: 50, reasoning: 0),
        ]
        let stats = aggregator.aggregate(entries)
        #expect(stats.overall.reasoningTokens == 0)
        #expect(stats.overall.totalTokens == 150)  // 100 + 50,不被 reasoning 污染
    }

    // MARK: - Cost Fallback

    @Test("PricingEngine miss 且 upstreamCost > 0 → 走 fallback")
    func upstreamCostFallback() {
        // "private-unknown-model" 必定不在 PricingTable 中
        let entries = [
            makeEntry(sessionID: "s1", date: date(2026, 6, 13),
                      model: "private-unknown-model", input: 1000, output: 500,
                      upstreamCost: 0.123),
        ]
        let stats = aggregator.aggregate(entries)
        #expect(stats.overall.cost == 0.123)
    }

    @Test("PricingEngine miss 且 upstreamCost 缺失 → cost 为 0")
    func upstreamCostFallbackMissing() {
        let entries = [
            makeEntry(sessionID: "s1", date: date(2026, 6, 13),
                      model: "private-unknown-model", input: 1000, output: 500),
        ]
        let stats = aggregator.aggregate(entries)
        #expect(stats.overall.cost == 0.0)
    }

    @Test("upstreamCost 不污染 PricingEngine 命中的模型 cost")
    func upstreamCostDoesNotPolluteEngineCost() {
        // claude-sonnet-4-5 必在 PricingTable 中,即便传了 upstreamCost 也应忽略
        let claudeEntries = [
            makeEntry(sessionID: "s1", date: date(2026, 6, 13),
                      model: "claude-sonnet-4-5", input: 1000, output: 500,
                      upstreamCost: 999.99),
        ]
        let claudeStats = aggregator.aggregate(claudeEntries)
        #expect(claudeStats.overall.cost > 0.0)
        #expect(claudeStats.overall.cost < 100.0,
                "命中 PricingEngine 应使用引擎计算的小额 cost,而非 upstream 999.99")
    }
```

- [ ] **Step 3: ProviderRegistryTests 加 opencode 校验**

修改 `TokenWatchTests/Providers/ProviderRegistryTests.swift`,在 `lookupById()` 之后追加:

```swift
    @Test("allProviders 含 .opencode")
    func containsOpenCode() {
        let ids = ProviderRegistry.allProviders.map(\.id)
        #expect(ids.contains(.opencode))
    }

    @Test("opencode provider 默认目录指向 ~/.local/share/opencode")
    func openCodeDefaultDirectory() {
        let provider = ProviderRegistry.provider(for: .opencode)
        let expected = NSString("~/.local/share/opencode").expandingTildeInPath
        #expect(provider?.defaultDirectoryPath == expected)
    }

    @Test("hasReasoningDimension:仅 opencode=true,Claude/Codex=false")
    func reasoningDimensionFlags() {
        #expect(ProviderRegistry.provider(for: .claude)?.hasReasoningDimension == false)
        #expect(ProviderRegistry.provider(for: .codex)?.hasReasoningDimension == false)
        #expect(ProviderRegistry.provider(for: .opencode)?.hasReasoningDimension == true)
    }
```

- [ ] **Step 4: 创建 `OpenCodeMessageParserTests.swift`**

写入 `TokenWatchTests/Providers/OpenCode/OpenCodeMessageParserTests.swift`:

```swift
import Foundation
import Testing
@testable import TokenWatch

/// OpenCodeMessageParser 单元测试
/// 验证 row → ParsedUsageEntry 的字段映射、跳过条件、upstream 元数据
@Suite("OpenCodeMessageParser")
struct OpenCodeMessageParserTests {

    let parser = OpenCodeMessageParser()

    // MARK: - 字段映射

    @Test("完整 assistant 行映射为 ParsedUsageEntry")
    func fullMapping() {
        let row = makeRow(
            id: "msg_001",
            sessionID: "ses_abc",
            timeMs: 1781509598103,
            json: """
            {"role":"assistant","modelID":"GLM-5.1","providerID":"huoshan-zijie",
             "cost":0.0123,
             "tokens":{"input":446,"output":30,"reasoning":0,"cache":{"read":0,"write":0}},
             "path":{"cwd":"/Users/me/proj","root":"/"}}
            """,
            directory: "/Users/me/proj-fallback"
        )

        let entries = parser.parseAll([row])
        #expect(entries.count == 1)
        let e = entries[0]
        #expect(e.messageId == "msg_001")
        #expect(e.recordUUID == "msg_001")
        #expect(e.sessionID == "ses_abc")
        #expect(e.model == "huoshan-zijie/GLM-5.1")
        #expect(e.upstreamProviderID == "huoshan-zijie")
        #expect(e.upstreamCost == 0.0123)
        #expect(e.cwd == "/Users/me/proj")
        #expect(e.usage.inputTokens == 446)
        #expect(e.usage.outputTokens == 30)
        #expect(e.usage.reasoningTokens == 0)
        #expect(e.provider == .opencode)
        #expect(e.requestId == nil)
        #expect(e.agentId == nil)
        #expect(e.isSubagent == false)
    }

    @Test("path.cwd 缺失时降级到 session.directory")
    func cwdFallsBackToSessionDirectory() {
        let row = makeRow(
            id: "msg_002",
            sessionID: "s",
            timeMs: 1_700_000_000_000,
            json: """
            {"role":"assistant","modelID":"m","providerID":"p",
             "tokens":{"input":1,"output":1,"reasoning":0,"cache":{"read":0,"write":0}}}
            """,
            directory: "/fallback/dir"
        )
        let entries = parser.parseAll([row])
        #expect(entries.first?.cwd == "/fallback/dir")
    }

    @Test("reasoning 与 cache.write 落到对应字段")
    func reasoningAndCacheWriteMapping() {
        let row = makeRow(
            id: "msg_003",
            sessionID: "s",
            timeMs: 1_700_000_000_000,
            json: """
            {"role":"assistant","modelID":"m","providerID":"p",
             "tokens":{"input":100,"output":50,"reasoning":200,"cache":{"read":10,"write":20}}}
            """,
            directory: "/d"
        )
        let e = parser.parseAll([row])[0]
        #expect(e.usage.reasoningTokens == 200)
        #expect(e.usage.cacheReadInputTokens == 10)
        // cache.write → cacheCreationInputTokens 扁平字段;派生属性走 fallback 拿 5m
        #expect(e.usage.cacheCreationInputTokens == 20)
        #expect(e.usage.totalCacheCreationTokens == 20)
    }

    @Test("model fallback:仅 modelID 时只用 modelID;仅 providerID 时只用 providerID")
    func modelKeyFallback() {
        let onlyModel = makeRow(
            id: "x", sessionID: "s", timeMs: 0,
            json: """
            {"role":"assistant","modelID":"m-only",
             "tokens":{"input":1,"output":1,"reasoning":0,"cache":{"read":0,"write":0}}}
            """,
            directory: "/d"
        )
        let onlyProvider = makeRow(
            id: "y", sessionID: "s", timeMs: 0,
            json: """
            {"role":"assistant","providerID":"p-only",
             "tokens":{"input":1,"output":1,"reasoning":0,"cache":{"read":0,"write":0}}}
            """,
            directory: "/d"
        )
        #expect(parser.parseAll([onlyModel])[0].model == "m-only")
        #expect(parser.parseAll([onlyProvider])[0].model == "p-only")
    }

    @Test("cost == 0 视为缺省 → upstreamCost = nil")
    func zeroCostBecomesNil() {
        let row = makeRow(
            id: "z", sessionID: "s", timeMs: 0,
            json: """
            {"role":"assistant","modelID":"m","providerID":"p","cost":0,
             "tokens":{"input":1,"output":1,"reasoning":0,"cache":{"read":0,"write":0}}}
            """,
            directory: "/d"
        )
        #expect(parser.parseAll([row])[0].upstreamCost == nil)
    }

    @Test("timestamp 由 timeCreatedMs(epoch ms)还原")
    func timestampFromEpochMillis() {
        let row = makeRow(
            id: "t", sessionID: "s", timeMs: 1_700_000_000_000,  // 2023-11-14T22:13:20Z
            json: """
            {"role":"assistant","modelID":"m","providerID":"p",
             "tokens":{"input":1,"output":1,"reasoning":0,"cache":{"read":0,"write":0}}}
            """,
            directory: "/d"
        )
        let e = parser.parseAll([row])[0]
        let expected = Date(timeIntervalSince1970: 1_700_000_000.0)
        #expect(abs(e.timestamp!.timeIntervalSince(expected)) < 0.001)
    }

    // MARK: - 跳过条件

    @Test("role != assistant 被跳过")
    func skipsNonAssistant() {
        let row = makeRow(
            id: "u", sessionID: "s", timeMs: 0,
            json: """
            {"role":"user","modelID":"m","providerID":"p",
             "tokens":{"input":1,"output":1,"reasoning":0,"cache":{"read":0,"write":0}}}
            """,
            directory: "/d"
        )
        #expect(parser.parseAll([row]).isEmpty)
    }

    @Test("缺 tokens 字段被跳过")
    func skipsMissingTokens() {
        let row = makeRow(
            id: "u", sessionID: "s", timeMs: 0,
            json: #"{"role":"assistant","modelID":"m","providerID":"p"}"#,
            directory: "/d"
        )
        #expect(parser.parseAll([row]).isEmpty)
    }

    @Test("5 维全 0 被跳过(placeholder/失败请求)")
    func skipsAllZero() {
        let row = makeRow(
            id: "u", sessionID: "s", timeMs: 0,
            json: """
            {"role":"assistant","modelID":"m","providerID":"p",
             "tokens":{"input":0,"output":0,"reasoning":0,"cache":{"read":0,"write":0}}}
            """,
            directory: "/d"
        )
        #expect(parser.parseAll([row]).isEmpty)
    }

    @Test("非法 JSON 被跳过,不抛错")
    func skipsInvalidJSON() {
        let row = makeRow(
            id: "u", sessionID: "s", timeMs: 0,
            json: "not a json {{{",
            directory: "/d"
        )
        #expect(parser.parseAll([row]).isEmpty)
    }

    // MARK: - Helper

    private func makeRow(id: String, sessionID: String, timeMs: Int64,
                         json: String, directory: String) -> OpenCodeMessageRow {
        OpenCodeMessageRow(
            id: id, sessionID: sessionID, timeCreatedMs: timeMs,
            dataJSON: json, directory: directory
        )
    }
}
```

- [ ] **Step 5: 创建 `OpenCodeSQLiteScannerTests.swift`**

写入 `TokenWatchTests/Providers/OpenCode/OpenCodeSQLiteScannerTests.swift`:

```swift
import Foundation
import SQLite3
import Testing
@testable import TokenWatch

/// OpenCodeSQLiteScanner 单元测试
/// 在临时目录用 sqlite3 C API 构造 mini opencode.db,验证 Scanner 读取行为
@Suite("OpenCodeSQLiteScanner")
struct OpenCodeSQLiteScannerTests {

    let scanner = OpenCodeSQLiteScanner()

    // MARK: - 正常路径

    @Test("从临时目录读取 mini opencode.db 应得到 assistant 行")
    func readsAssistantRows() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try buildMiniDB(at: dir.appendingPathComponent("opencode.db"),
                        sessions: [("ses_a", "/proj/A"), ("ses_b", "/proj/B")],
                        messages: [
                            ("msg_1", "ses_a", 100, #"{"role":"assistant","modelID":"m","providerID":"p","tokens":{"input":1,"output":1,"reasoning":0,"cache":{"read":0,"write":0}}}"#),
                            ("msg_2", "ses_a", 200, #"{"role":"user","content":"hi"}"#),  // 应被 query 过滤
                            ("msg_3", "ses_b", 300, #"{"role":"assistant","modelID":"m","providerID":"p","tokens":{"input":2,"output":2,"reasoning":0,"cache":{"read":0,"write":0}}}"#),
                        ])

        let rows = try scanner.scanAll(in: dir)
        #expect(rows.count == 2)
        // ORDER BY time_created
        #expect(rows[0].id == "msg_1")
        #expect(rows[0].sessionID == "ses_a")
        #expect(rows[0].timeCreatedMs == 100)
        #expect(rows[0].directory == "/proj/A")
        #expect(rows[1].id == "msg_3")
        #expect(rows[1].directory == "/proj/B")
    }

    // MARK: - 错误路径

    @Test("opencode.db 不存在 → databaseNotFound")
    func missingDB() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        do {
            _ = try scanner.scanAll(in: dir)
            Issue.record("应抛错")
        } catch let err as OpenCodeScannerError {
            if case .databaseNotFound = err { return }
            Issue.record("错类型不对: \(err)")
        }
    }

    @Test("非合法 SQLite 文件 → openFailed")
    func corruptedDB() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let dbURL = dir.appendingPathComponent("opencode.db")
        try Data("not a sqlite db".utf8).write(to: dbURL)

        do {
            _ = try scanner.scanAll(in: dir)
            Issue.record("应抛错")
        } catch let err as OpenCodeScannerError {
            // SQLite 在打开非法文件时,可能在 open_v2 阶段(openFailed)或 prepare/step 阶段(queryFailed)报错;两者均接受
            switch err {
            case .openFailed, .queryFailed: return
            default: Issue.record("错类型不对: \(err)")
            }
        }
    }

    // MARK: - Helpers

    /// 在临时目录用 sqlite3 C API 构造 opencode mini schema(只含本测试用到的列约束)
    private func buildMiniDB(at url: URL,
                              sessions: [(id: String, directory: String)],
                              messages: [(id: String, sessionID: String, timeMs: Int64, dataJSON: String)]) throws {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db,
                              SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK,
              let database = db else {
            throw NSError(domain: "test.sqlite", code: 1)
        }
        defer { sqlite3_close(database) }

        // 极简 schema:仅满足 Scanner 的 SELECT m.id, m.session_id, m.time_created, m.data, s.directory
        let schema = """
        CREATE TABLE session (id TEXT PRIMARY KEY, directory TEXT NOT NULL);
        CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT NOT NULL,
                              time_created INTEGER NOT NULL, data TEXT NOT NULL);
        """
        var errMsg: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, schema, nil, nil, &errMsg) == SQLITE_OK else {
            sqlite3_free(errMsg)
            throw NSError(domain: "test.sqlite", code: 2)
        }

        for s in sessions {
            let sql = "INSERT INTO session (id, directory) VALUES (?, ?);"
            try execInsert(database: database, sql: sql, binds: [s.id, s.directory])
        }
        for m in messages {
            let sql = "INSERT INTO message (id, session_id, time_created, data) VALUES (?, ?, ?, ?);"
            try execInsertMixed(database: database, sql: sql,
                                texts: [m.id, m.sessionID, m.dataJSON],
                                ints: [(2, m.timeMs)])
        }
    }

    private func execInsert(database: OpaquePointer, sql: String, binds: [String]) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw NSError(domain: "test.sqlite", code: 3)
        }
        defer { sqlite3_finalize(stmt) }
        for (i, s) in binds.enumerated() {
            sqlite3_bind_text(stmt, Int32(i + 1), s, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw NSError(domain: "test.sqlite", code: 4)
        }
    }

    /// 混合绑定:texts 按 [1,2,4] 顺序填(跳过 ints 占位的列号)
    private func execInsertMixed(database: OpaquePointer, sql: String,
                                  texts: [String], ints: [(col: Int32, value: Int64)]) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw NSError(domain: "test.sqlite", code: 3)
        }
        defer { sqlite3_finalize(stmt) }

        let intCols = Set(ints.map(\.col))
        var ti = 0
        for col: Int32 in 1...4 {
            if intCols.contains(col) {
                let v = ints.first(where: { $0.col == col })!.value
                sqlite3_bind_int64(stmt, col, v)
            } else {
                sqlite3_bind_text(stmt, col, texts[ti], -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                ti += 1
            }
        }
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw NSError(domain: "test.sqlite", code: 4)
        }
    }

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("opencode-scanner-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
```

> **关于 SQLite text bind:** SQLite C API 的 `sqlite3_bind_text` 第 5 个参数是 destructor。
> `SQLITE_TRANSIENT` 在 Swift 里表达为 `unsafeBitCast(-1, to: sqlite3_destructor_type.self)`
> —— 这是社区惯用法,告诉 SQLite "复制字符串内容,我可能马上释放原 buffer"。这个测试 helper
> 仅在临时目录构造 db,不影响生产代码;Scanner 自己只读不绑定。

- [ ] **Step 6: 跑全量单元测试,确保通过**

Run: `xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests test`

Expected: 全部 PASS,关注:
- 既有 Claude/Codex/Pricing/Aggregator 测试无回归
- 新增 OpenCodeMessageParserTests / OpenCodeSQLiteScannerTests 全 PASS
- TokenUsageDecodingTests / UsageAggregatorTests / ProviderRegistryTests 增量 PASS

如有失败,先排查类型对齐问题(reasoningTokens / upstreamProviderID / upstreamCost 是否处处填到了)。

---

## Task 8:统一提交

- [ ] **Step 1: 检查工作区改动**

Run: `git status` && `git diff --stat`

Expected: 修改文件应**仅包含** Tasks 1~7 涉及的文件(13 个修改 + 6 个新增 ≈ 19 个文件)。
不应有任何无关文件。如有,先 `git checkout -- <file>` 还原。

- [ ] **Step 2: 提交(单 commit,Conventional Commits + 简体中文)**

```bash
git add TokenWatch/Models/TokenUsage.swift \
        TokenWatch/Models/ParsedUsageEntry.swift \
        TokenWatch/Models/UsageAggregation.swift \
        TokenWatch/Providers/UsageProvider.swift \
        TokenWatch/Providers/ProviderID.swift \
        TokenWatch/Providers/ProviderRegistry.swift \
        TokenWatch/Providers/Claude/ClaudeProvider.swift \
        TokenWatch/Providers/Claude/ClaudeJSONLParser.swift \
        TokenWatch/Providers/Codex/CodexProvider.swift \
        TokenWatch/Providers/Codex/CodexRolloutParser.swift \
        TokenWatch/Providers/OpenCode/ \
        TokenWatch/Analytics/UsageAggregator.swift \
        TokenWatchTests/Models/TokenUsageDecodingTests.swift \
        TokenWatchTests/Analytics/UsageAggregatorTests.swift \
        TokenWatchTests/Providers/ProviderRegistryTests.swift \
        TokenWatchTests/Providers/OpenCode/

git commit -m "feat(provider): 新增 opencode 数据源支持(SQLite + reasoning + 上游 cost fallback)"
```

- [ ] **Step 3: 验证提交**

Run: `git log -1 --stat`
Expected: HEAD 包含上述全部文件,commit message **逐字等于**:
`feat(provider): 新增 opencode 数据源支持(SQLite + reasoning + 上游 cost fallback)`

---

## 自检对照(写完计划后已执行)

- ✅ **Spec 覆盖**:
  - 模型扩展(TokenUsage / ParsedUsageEntry / UsageSummary)→ Task 1
  - 协议扩展(hasReasoningDimension)→ Task 2
  - Claude/Codex 适配新字段 → Task 3
  - opencode 四件套 → Task 4
  - registry 注册 → Task 5
  - cost fallback 接入 → Task 6
  - 全部测试覆盖(reasoning 解码 / 聚合 / fallback / opencode parser/scanner / registry)→ Task 7
  - 提交 → Task 8
- ✅ **占位符扫描**:无 TBD/TODO/"add error handling"等。
- ✅ **类型一致性**:
  - 字段 `reasoningTokens` / `upstreamProviderID` / `upstreamCost` 在模型、parser、聚合器、
    测试 helper 中拼写一致
  - `OpenCodeMessageRow` / `OpenCodeMessageData` / `OpenCodeTokens` / `OpenCodeCache` /
    `OpenCodePath` 在 Scanner / Parser 中签名一致
  - `OpenCodeScannerError` 三个 case 名(databaseNotFound / openFailed / queryFailed)前后一致
  - `OpenCodeSQLiteScanner.assistantMessageQuery` 暴露为 static 便于测试可见(虽然测试目前没用,
    但设计上对齐)
- ✅ **YAGNI**:`hasCacheWriteDimension=false` 数据层映射保留但 UI 不展示,本次不做 UI 切换;
  `byModel` key 仅 opencode 加 provider 前缀,Claude/Codex 不动;cost fallback 仅在 PricingEngine
  miss 时触发,不全局开关
- ✅ **TDD 顺序**:Task 7 把测试集中放在所有实现之后是因为模型字段一改就连环编译失败,先把
  实现链路打通再补测试更现实(否则每改一处要修十几个测试文件);代码层增量小,测试会快速覆盖
