# Incremental JSONL Parsing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 Claude 与 Codex JSONL 在文件追加时只读取 committed offset 之后的字节，并在尾行、截断、替换和暂时读取失败时保持与全量解析完全一致的结果。

**Architecture:** 数据正确性计划先提供 `JSONLFileReading`、文件 identity/size/mtime 元数据、last-good 回退、Claude 全局去重器和 Codex 可选累计状态。本计划在其上增加通用状态迁移模型；每个 parser 保存 stable raw candidates、未提交尾段和 committed checkpoint，只有完整换行才推进 offset。所有缓存更新先在局部构建成功，再一次性替换。

**Tech Stack:** Swift 6、Foundation `FileHandle`、Swift Testing、Xcode 26.5、macOS 15+

## Global Constraints

- 先完成 `2026-07-10-ccusage-pricing-parity.md` 和 `2026-07-10-provider-data-correctness-and-authorization.md`。
- 保留 Claude 的 billing raw prefilter、严格 DTO、`costUSD`、`isSidechain`、`hasSourceMessageID` 与 daily 单遍去重语义；缓存必须保存去重前 raw candidates。
- 保留 Codex 的 `CodexUsageCandidate`、loader dedup key、replay classifier、resolved model/source、service tier、session metadata 与 `previousTotals`。
- identity/size/mtime 全同才允许零读取复用；identity 不可验证时必须全量重建。
- 所有 metadata 必须来自与 stream 相同的 opened descriptor snapshot；append 前校验有界 continuity anchor，以识别同 inode truncate 后重写为更大文件。
- EOF 无换行的完整 JSON 只作为 provisional candidate 返回，不能推进 offset 或 checkpoint。
- 测试比较必须使用 deep snapshot，不能使用只比较 `dedupKey` 的 `ParsedUsageEntry.==`。
- 不引入第三方流式解析、数据库或运行时网络依赖。
- 每个生产改动前必须先看到对应回归测试按预期失败。
- 测试使用 `.build/DerivedData`；app-hosted test 在沙盒中需要提升权限。
- test/build-for-testing 命令统一使用 `CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=-` 的临时 ad-hoc 签名；纯 build/analyze 使用 `CODE_SIGNING_ALLOWED=NO`。
- Commit 使用中文并遵循 `<type>(<scope>): <summary>`。

## File Structure

- Create: `TokenWatch/Providers/IncrementalJSONLFileState.swift` — 通用缓存状态和 metadata 迁移决策。
- Create: `TokenWatch/Providers/Codex/CodexRolloutParsingState.swift` — 可保存/恢复的 Codex 行级 checkpoint reducer。
- Modify: `TokenWatch/Providers/Claude/ClaudeJSONLParser.swift` — Claude 后缀读取、provisional tail 与原子缓存替换。
- Modify: `TokenWatch/Providers/Codex/CodexRolloutParser.swift` — Codex 后缀读取与 checkpoint 恢复。
- Create: `TokenWatchTests/Providers/IncrementalJSONLFileStateTests.swift` — 迁移矩阵测试。
- Modify: `TokenWatchTests/Providers/Claude/ClaudeJSONLParserTests.swift` — Claude append/tail/truncate/replace/I/O 测试。
- Create: `TokenWatchTests/Providers/Codex/CodexRolloutParsingStateTests.swift` — reducer checkpoint 测试。
- Modify: `TokenWatchTests/Providers/Codex/CodexRolloutParserTests.swift` — Codex append/tail/truncate/replace/I/O 测试。
- Reuse: `TokenWatchTests/TestSupport/ParsedUsageEntryDeepSnapshot.swift` — 数据正确性计划提供的完整业务快照。
- Reuse: `TokenWatchTests/TestSupport/RecordingJSONLFileReader.swift` — 数据正确性计划提供的 seek/read 记录器与故障注入。

---

### Task 1: 固定通用状态与迁移矩阵

**Files:**
- Create: `TokenWatch/Providers/IncrementalJSONLFileState.swift`
- Create: `TokenWatchTests/Providers/IncrementalJSONLFileStateTests.swift`

**Interfaces:**
- Consumes: `JSONLFileMetadata` from `TokenWatch/Providers/JSONLFileReader.swift`。
- Produces: `IncrementalJSONLFileState<Candidate, Checkpoint>`、`JSONLContinuityAnchor`、`IncrementalJSONLTransition.decide(previous:newMetadata:)`。`.append` 只表示 metadata 候选，parser 校验 anchor 成功后才能执行后缀解析。

- [ ] **Step 1: 写迁移矩阵失败测试**

```swift
import Foundation
import Testing
@testable import TokenWatch

@Suite("IncrementalJSONLFileState")
struct IncrementalJSONLFileStateTests {
    private let identity = JSONLFileIdentity(deviceID: 7, fileID: 11)

    @Test func transitionMatrixIsDeterministic() {
        let old = JSONLFileMetadata(
            identity: identity,
            size: 100,
            modificationDate: Date(timeIntervalSince1970: 10)
        )
        let state = IncrementalJSONLFileState<Int, String>(
            metadata: old,
            committedOffset: 80,
            stableCandidates: [1],
            provisionalTail: Data([0x7B]),
            provisionalCandidates: [],
            continuityAnchor: JSONLContinuityAnchor(
                offset: 76,
                bytes: Data("tail".utf8)
            ),
            checkpointAtCommittedOffset: "checkpoint"
        )

        #expect(IncrementalJSONLTransition.decide(previous: state, newMetadata: old) == .reuse)
        #expect(IncrementalJSONLTransition.decide(
            previous: state,
            newMetadata: JSONLFileMetadata(identity: identity, size: 120, modificationDate: .init(timeIntervalSince1970: 11))
        ) == .append(fromOffset: 80))
        #expect(IncrementalJSONLTransition.decide(
            previous: state,
            newMetadata: JSONLFileMetadata(identity: identity, size: 90, modificationDate: .init(timeIntervalSince1970: 12))
        ) == .rebuild)
        #expect(IncrementalJSONLTransition.decide(
            previous: state,
            newMetadata: JSONLFileMetadata(identity: identity, size: 100, modificationDate: .init(timeIntervalSince1970: 12))
        ) == .rebuild)
        #expect(IncrementalJSONLTransition.decide(
            previous: state,
            newMetadata: JSONLFileMetadata(identity: .init(deviceID: 7, fileID: 12), size: 120, modificationDate: .init(timeIntervalSince1970: 11))
        ) == .rebuild)
        #expect(IncrementalJSONLTransition.decide(
            previous: state,
            newMetadata: JSONLFileMetadata(identity: nil, size: 120, modificationDate: .init(timeIntervalSince1970: 11))
        ) == .rebuild)
    }
}
```

- [ ] **Step 2: 运行测试并确认类型尚不存在**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/IncrementalJSONLFileStateTests -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: FAIL，编译器报告找不到 `IncrementalJSONLFileState` 或 `IncrementalJSONLTransition`。

- [ ] **Step 3: 实现状态容器和唯一迁移函数**

```swift
import Foundation

struct IncrementalJSONLFileState<Candidate: Sendable, Checkpoint: Sendable>: Sendable {
    let metadata: JSONLFileMetadata
    let committedOffset: UInt64
    let stableCandidates: [Candidate]
    let provisionalTail: Data
    let provisionalCandidates: [Candidate]
    let continuityAnchor: JSONLContinuityAnchor
    let checkpointAtCommittedOffset: Checkpoint

    var returnedCandidates: [Candidate] {
        stableCandidates + provisionalCandidates
    }
}

struct JSONLContinuityAnchor: Sendable, Equatable {
    static let maximumByteCount = 256

    let offset: UInt64
    let bytes: Data

    static let empty = JSONLContinuityAnchor(offset: 0, bytes: Data())

    static func make(
        previous: JSONLContinuityAnchor,
        newlyCommittedBytes: Data,
        committedOffset: UInt64
    ) -> JSONLContinuityAnchor {
        let combined = previous.bytes + newlyCommittedBytes
        let bytes = Data(combined.suffix(maximumByteCount))
        return JSONLContinuityAnchor(
            offset: committedOffset - UInt64(bytes.count),
            bytes: bytes
        )
    }

    func matches(in stream: any JSONLByteStream) throws -> Bool {
        guard !bytes.isEmpty else { return true }
        try stream.seek(toOffset: offset)
        var actual = Data()
        while actual.count < bytes.count {
            let chunk = try stream.read(upToCount: bytes.count - actual.count)
            guard !chunk.isEmpty else { return false }
            actual.append(chunk)
        }
        return actual == bytes
    }
}

struct StatelessJSONLCheckpoint: Sendable, Equatable {}

enum IncrementalJSONLReadError: Error, Equatable {
    case unexpectedEOF
}

enum IncrementalJSONLTransition: Sendable, Equatable {
    case reuse
    case append(fromOffset: UInt64)
    case rebuild

    static func decide<Candidate, Checkpoint>(
        previous: IncrementalJSONLFileState<Candidate, Checkpoint>,
        newMetadata: JSONLFileMetadata
    ) -> IncrementalJSONLTransition where Candidate: Sendable, Checkpoint: Sendable {
        guard let oldIdentity = previous.metadata.identity,
              let newIdentity = newMetadata.identity,
              oldIdentity == newIdentity
        else {
            return .rebuild
        }
        if newMetadata.size == previous.metadata.size,
           newMetadata.modificationDate == previous.metadata.modificationDate {
            return .reuse
        }
        if newMetadata.size > previous.metadata.size {
            return .append(fromOffset: previous.committedOffset)
        }
        return .rebuild
    }
}
```

- [ ] **Step 4: 运行定向测试确认通过**

Run: 与 Step 2 相同。

Expected: PASS，6 个迁移断言全部通过。

同 suite 再断言 `JSONLContinuityAnchor.make` 在连续多段 committed bytes 后只保留最后 256 bytes，offset 始终等于 `committedOffset - bytes.count`。真实文件匹配/不匹配由 Task 3/6 的 parser I/O 测试覆盖。

- [ ] **Step 5: 提交通用状态**

```bash
git add TokenWatch/Providers/IncrementalJSONLFileState.swift TokenWatchTests/Providers/IncrementalJSONLFileStateTests.swift
git commit -m "feat(parser): 新增 JSONL 增量状态迁移"
```

### Task 2: Claude 追加只读取后缀

**Files:**
- Modify: `TokenWatch/Providers/Claude/ClaudeJSONLParser.swift`
- Modify: `TokenWatchTests/Providers/Claude/ClaudeJSONLParserTests.swift`

**Interfaces:**
- Consumes: `JSONLFileReading`、`RecordingJSONLFileReader`、`IncrementalJSONLFileState<ParsedUsageEntry, StatelessJSONLCheckpoint>`。
- Produces: `ClaudeJSONLParser.init(fileReader:)`；既有 `parseJSONLFile` 和 `parseAllFiles` 签名保持可用。

- [ ] **Step 1: 写 unchanged 与 append I/O 失败测试**

```swift
@Test("Claude 未变化文件零读取，追加从 committed offset 开始")
func appendReadsOnlySuffix() throws {
    let fixture = try makeClaudeFixture()
    defer { fixture.cleanup() }
    let reader = RecordingJSONLFileReader()
    let parser = ClaudeJSONLParser(fileReader: reader)
    let firstLine = Self.assistantLine(messageId: "m1", inputTokens: 10)
    try (firstLine + "\n").write(to: fixture.file.url, atomically: false, encoding: .utf8)

    let first = try parser.parseAllFiles([fixture.file], claudeDataRoot: fixture.root)
    let committedOffset = UInt64((firstLine + "\n").utf8.count)
    #expect(first.count == 1)

    reader.resetMetrics()
    _ = try parser.parseAllFiles([fixture.file], claudeDataRoot: fixture.root)
    #expect(reader.openCount == 1)
    #expect(reader.totalBytesRead == 0)
    #expect(reader.seekOffsets.isEmpty)

    let secondLine = Self.assistantLine(messageId: "m2", inputTokens: 20)
    let anchor = try #require(parser.debugContinuityAnchor(for: fixture.file.url))
    try appendUTF8(secondLine + "\n", to: fixture.file.url)
    reader.resetMetrics()
    let appended = try parser.parseAllFiles([fixture.file], claudeDataRoot: fixture.root)

    #expect(appended.map(\.messageId).sorted() == ["m1", "m2"])
    #expect(reader.seekOffsets == [anchor.offset, committedOffset])
    #expect(reader.totalBytesRead == anchor.bytes.count + (secondLine + "\n").utf8.count)
}
```

测试文件同时加入不做 atomic replace 的 helper：

```swift
private func appendUTF8(_ text: String, to url: URL) throws {
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(text.utf8))
}

private struct ClaudeFixture {
    let root: URL
    let file: ClaudeJSONLFileInfo
    let cleanup: () -> Void
}

private func makeClaudeFixture() throws -> ClaudeFixture {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ClaudeIncremental-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let url = root.appendingPathComponent("session.jsonl")
    try Data().write(to: url)
    return ClaudeFixture(
        root: root,
        file: ClaudeJSONLFileInfo(
            url: url,
            sessionID: "session",
            projectPath: "/project",
            isSubagent: false,
            agentId: nil
        ),
        cleanup: { try? FileManager.default.removeItem(at: root) }
    )
}
```

把既有 `Self.assistantLine` helper 扩展为 `messageId`、`requestId: String? = nil`、`inputTokens`、`isSidechain: Bool = false` 四个业务参数，生成 compact `"usage":{` 形状并使用固定 3 位毫秒 timestamp；本文后续所有 Claude fixture 复用该唯一 helper。

- [ ] **Step 2: 运行测试并确认当前实现从 0 重读**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/ClaudeJSONLParserTests/appendReadsOnlySuffix -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: FAIL；当前 parser 没有 reader 注入接口，或 metrics 显示 seek offset 为 0、读取整个文件。

- [ ] **Step 3: 将 Claude 文件缓存改为增量 raw candidate 状态**

在 parser 中固定以下结构和装配：

```swift
private typealias ClaudeFileState = IncrementalJSONLFileState<ParsedUsageEntry, StatelessJSONLCheckpoint>

private let fileReader: any JSONLFileReading
private var cachedFiles: [String: ClaudeFileState] = [:]

init(fileReader: any JSONLFileReading = SystemJSONLFileReader()) {
    self.fileReader = fileReader
}
```

读取范围必须受 metadata.size 限制，避免 stat 后并发追加被混进当前快照：

```swift
private func readCandidates(
    from fileInfo: ClaudeJSONLFileInfo,
    snapshot: JSONLFileSnapshot,
    startOffset: UInt64,
    stablePrefix: [ParsedUsageEntry],
    previousAnchor: JSONLContinuityAnchor
) throws -> ClaudeFileState {
    try snapshot.stream.seek(toOffset: startOffset)

    var stable = stablePrefix
    var committedOffset = startOffset
    var nextReadOffset = startOffset
    var bufferStartOffset = startOffset
    var buffer = Data()
    var newlyCommittedBytes = Data()

    while nextReadOffset < snapshot.metadata.size {
        let count = Int(min(UInt64(64 * 1024), snapshot.metadata.size - nextReadOffset))
        let chunk = try snapshot.stream.read(upToCount: count)
        guard !chunk.isEmpty else { throw IncrementalJSONLReadError.unexpectedEOF }
        nextReadOffset += UInt64(chunk.count)
        buffer.append(chunk)

        var consumed = 0
        while let newline = buffer[consumed...].firstIndex(of: 0x0A) {
            let sourceOffset = bufferStartOffset + UInt64(consumed)
            let line = Data(buffer[consumed..<newline])
            if let candidate = parseCandidate(
                line,
                fileInfo: fileInfo,
                sourceOffset: sourceOffset
            ) {
                stable.append(candidate)
            }
            consumed = buffer.index(after: newline)
        }
        if consumed > 0 {
            newlyCommittedBytes.append(buffer[..<consumed])
            buffer.removeSubrange(0..<consumed)
            committedOffset += UInt64(consumed)
            bufferStartOffset = committedOffset
        }
    }

    let provisional = parseCandidate(
        buffer,
        fileInfo: fileInfo,
        sourceOffset: committedOffset
    ).map { [$0] } ?? []
    return ClaudeFileState(
        metadata: snapshot.metadata,
        committedOffset: committedOffset,
        stableCandidates: stable,
        provisionalTail: buffer,
        provisionalCandidates: provisional,
        continuityAnchor: .make(
            previous: previousAnchor,
            newlyCommittedBytes: newlyCommittedBytes,
            committedOffset: committedOffset
        ),
        checkpointAtCommittedOffset: StatelessJSONLCheckpoint()
    )
}
```

`parseCachedJSONLFile` 每轮只调用一次 `openSnapshot`，使用其 descriptor metadata 计算唯一迁移：`.reuse` 关闭 stream 并返回旧状态；`.append` 先调用共享 `previous.continuityAnchor.matches(in: snapshot.stream)`，匹配才保留 stable candidates 并从 committed offset 读，不匹配转 `.rebuild`；`.rebuild` 从 0、空数组和 `.empty` anchor 开始。只有 `readCandidates` 成功返回后才在 lock 内替换 cache。

为 I/O 契约测试增加只读 debug accessor：

```swift
func debugCommittedOffset(for url: URL) -> UInt64? {
    let key = Self.cacheKey(for: url)
    return withCacheLock { cachedFiles[key]?.committedOffset }
}

func debugContinuityAnchor(for url: URL) -> JSONLContinuityAnchor? {
    let key = Self.cacheKey(for: url)
    return withCacheLock { cachedFiles[key]?.continuityAnchor }
}
```

- [ ] **Step 4: 运行 Claude parser suite**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/ClaudeJSONLParserTests -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: PASS；既有缓存测试和新增 I/O 测试同时通过。

- [ ] **Step 5: 提交 Claude 后缀读取**

```bash
git add TokenWatch/Providers/Claude/ClaudeJSONLParser.swift TokenWatchTests/Providers/Claude/ClaudeJSONLParserTests.swift
git commit -m "perf(claude): 增量读取追加 JSONL"
```

### Task 3: Claude provisional tail、重建与全局替换

**Files:**
- Modify: `TokenWatch/Providers/Claude/ClaudeJSONLParser.swift`
- Modify: `TokenWatchTests/Providers/Claude/ClaudeJSONLParserTests.swift`

**Interfaces:**
- Consumes: `ClaudeUsageDeduplicator.deduplicate(_:)` 与 `ParsedUsageEntryDeepSnapshot`。
- Produces: append、full rebuild 对外返回完全相同的 deep snapshots。

- [ ] **Step 1: 写尾段和重建失败测试**

```swift
@Test("Claude provisional 尾行重读后不重复")
func provisionalTailIsReplacedWhenNewlineArrives() throws {
    let fixture = try makeClaudeFixture()
    defer { fixture.cleanup() }
    let reader = RecordingJSONLFileReader()
    let parser = ClaudeJSONLParser(fileReader: reader)
    let line = Self.assistantLine(messageId: "tail", inputTokens: 42)
    try line.write(to: fixture.file.url, atomically: false, encoding: .utf8)

    let provisional = try parser.parseAllFiles([fixture.file], claudeDataRoot: fixture.root)
    #expect(provisional.count == 1)
    #expect(parser.debugCommittedOffset(for: fixture.file.url) == 0)

    reader.resetMetrics()
    try appendUTF8("\n", to: fixture.file.url)
    let committed = try parser.parseAllFiles([fixture.file], claudeDataRoot: fixture.root)
    #expect(committed.count == 1)
    #expect(committed.first?.messageId == "tail")
    #expect(parser.debugCommittedOffset(for: fixture.file.url) == UInt64((line + "\n").utf8.count))
    #expect(reader.seekOffsets == [0])
    #expect(reader.totalBytesRead == (line + "\n").utf8.count)
}

@Test("Claude 追加 parent 可替换 stable sidechain")
func appendedParentReplacesStableSidechain() throws {
    let fixture = try makeClaudeFixture()
    defer { fixture.cleanup() }
    let parser = ClaudeJSONLParser()
    let sidechain = Self.assistantLine(messageId: "shared", requestId: "side", inputTokens: 500, isSidechain: true)
    let parent = Self.assistantLine(messageId: "shared", requestId: "parent", inputTokens: 5, isSidechain: false)
    try (sidechain + "\n").write(to: fixture.file.url, atomically: false, encoding: .utf8)
    _ = try parser.parseAllFiles([fixture.file], claudeDataRoot: fixture.root)
    try appendUTF8(parent + "\n", to: fixture.file.url)

    let result = try parser.parseAllFiles([fixture.file], claudeDataRoot: fixture.root)
    #expect(result.count == 1)
    #expect(result.first?.requestId == "parent")
    #expect(result.first?.usage.inputTokens == 5)
}

@Test("Claude 缺 source message ID 的绝对 offset 在 provisional/commit/append 中稳定")
func missingMessageIDUsesStableAbsoluteOffset() throws {
    let fixture = try makeClaudeFixture()
    defer { fixture.cleanup() }
    let parser = ClaudeJSONLParser()
    let first = #"{"timestamp":"2026-06-13T12:00:00.000Z","message":{"model":"claude-sonnet-4-5","usage":{"input_tokens":1,"output_tokens":1}}}"#
    let second = #"{"timestamp":"2026-06-13T12:00:01.000Z","message":{"model":"claude-sonnet-4-5","usage":{"input_tokens":2,"output_tokens":1}}}"#
    try first.write(to: fixture.file.url, atomically: false, encoding: .utf8)
    let provisional = try parser.parseAllFiles([fixture.file], claudeDataRoot: fixture.root)
    try appendUTF8("\n" + second + "\n", to: fixture.file.url)
    let incremental = try parser.parseAllFiles([fixture.file], claudeDataRoot: fixture.root)
    let fresh = try ClaudeJSONLParser().parseAllFiles([fixture.file], claudeDataRoot: fixture.root)

    #expect(provisional.first?.messageId == incremental.first?.messageId)
    #expect(Set(incremental.map(\.messageId)).count == 2)
    #expect(incremental.allSatisfy { !$0.hasSourceMessageID })
    #expect(ParsedUsageEntryDeepSnapshot.sorted(incremental) ==
        ParsedUsageEntryDeepSnapshot.sorted(fresh))
}
```

加入半行续写与 rebuild 矩阵；测试 helper 中的 `rewrite` 必须按指定方式保留或替换 identity：

```swift
@Test("Claude 半行续写只在完整后返回")
func incompleteTailWaitsForCompletion() throws {
    let fixture = try makeClaudeFixture()
    defer { fixture.cleanup() }
    let parser = ClaudeJSONLParser()
    let line = Self.assistantLine(messageId: "partial", inputTokens: 9)
    let split = line.utf8.index(line.utf8.startIndex, offsetBy: line.utf8.count / 2)
    let firstHalf = String(decoding: line.utf8[..<split], as: UTF8.self)
    let secondHalf = String(decoding: line.utf8[split...], as: UTF8.self)
    try firstHalf.write(to: fixture.file.url, atomically: false, encoding: .utf8)
    #expect(try parser.parseAllFiles([fixture.file], claudeDataRoot: fixture.root).isEmpty)
    try appendUTF8(secondHalf + "\n", to: fixture.file.url)
    #expect(try parser.parseAllFiles([fixture.file], claudeDataRoot: fixture.root).map(\.messageId) == ["partial"])
}

@Test(arguments: ["truncate", "truncate-grow", "replace", "touch"])
func rebuildTransitionsReadFromZero(kind: String) throws {
    let fixture = try makeClaudeFixture()
    defer { fixture.cleanup() }
    let reader = RecordingJSONLFileReader()
    let parser = ClaudeJSONLParser(fileReader: reader)
    let original = Self.assistantLine(messageId: "old", inputTokens: 10) + "\n"
    try original.write(to: fixture.file.url, atomically: false, encoding: .utf8)
    _ = try parser.parseAllFiles([fixture.file], claudeDataRoot: fixture.root)

    let replacement = Self.assistantLine(messageId: "new", inputTokens: 20) + "\n"
    switch kind {
    case "truncate":
        let handle = try FileHandle(forWritingTo: fixture.file.url)
        try handle.truncate(atOffset: 0)
        try handle.close()
    case "truncate-grow":
        let handle = try FileHandle(forWritingTo: fixture.file.url)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data((replacement + replacement).utf8))
        try handle.close()
    case "replace":
        try replacement.write(to: fixture.file.url, atomically: true, encoding: .utf8)
    case "touch":
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(5)],
            ofItemAtPath: fixture.file.url.path
        )
    default:
        Issue.record("unexpected transition kind")
    }

    reader.resetMetrics()
    let incremental = try parser.parseAllFiles([fixture.file], claudeDataRoot: fixture.root)
    let fresh = try ClaudeJSONLParser().parseAllFiles([fixture.file], claudeDataRoot: fixture.root)
    #expect(reader.seekOffsets.contains(0))
    #expect(ParsedUsageEntryDeepSnapshot.sorted(incremental) == ParsedUsageEntryDeepSnapshot.sorted(fresh))
}
```

- [ ] **Step 2: 运行新增测试确认至少一个语义失败**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/ClaudeJSONLParserTests/provisionalTailIsReplacedWhenNewlineArrives -only-testing:TokenWatchTests/ClaudeJSONLParserTests/appendedParentReplacesStableSidechain -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: FAIL；若 parser 只 append 最终去重结果，parent replacement 断言失败；若错误提交 EOF，committed offset 断言失败。

- [ ] **Step 3: 每次返回前统一对 raw candidates 去重**

```swift
private func deduplicatedEntries(from states: [ClaudeFileState]) -> [ParsedUsageEntry] {
    let candidates = states.flatMap(\.returnedCandidates)
    return ClaudeUsageDeduplicator.deduplicate(candidates)
}
```

保持 provisional candidate 只存在于 `provisionalCandidates`；下一次 `.append(fromOffset:)` 丢弃旧 provisional 数组，从 committed offset 重新解析 tail + suffix。`.rebuild` 必须从空 stable candidates 开始。parse 失败沿用数据正确性阶段的 last-good state，不覆盖 cache。

- [ ] **Step 4: 运行 Claude、去重器和状态测试**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/ClaudeJSONLParserTests -only-testing:TokenWatchTests/ClaudeUsageDeduplicatorTests -only-testing:TokenWatchTests/IncrementalJSONLFileStateTests -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: PASS；deep snapshot、I/O 与 sidechain replacement 全部通过。

- [ ] **Step 5: 提交 Claude 边界语义**

```bash
git add TokenWatch/Providers/Claude/ClaudeJSONLParser.swift TokenWatchTests/Providers/Claude/ClaudeJSONLParserTests.swift
git commit -m "fix(claude): 保持增量尾行与全量结果一致"
```

### Task 4: 抽出可保存的 Codex 行级 checkpoint

**Files:**
- Create: `TokenWatch/Providers/Codex/CodexRolloutParsingState.swift`
- Create: `TokenWatchTests/Providers/Codex/CodexRolloutParsingStateTests.swift`
- Modify: `TokenWatch/Providers/Codex/CodexRolloutParser.swift`

**Interfaces:**
- Consumes: 数据计划的 `CodexUsageCandidate`、`CodexEventDedupKey`、normalized timestamp/model/token helper，以及 `CodexModelState`、`CodexPricingSpeed`、`CodexTokenCounts?`。
- Produces: `CodexParserCheckpoint.consume(_:sourceOffset:speed:) -> CodexUsageCandidate?`；session token_count 无合法 timestamp 时返回 nil，byte offset 只用于有 timestamp candidate 的本地 record UUID。

- [ ] **Step 1: 写 checkpoint 跨批恢复失败测试**

```swift
import Foundation
import Testing
@testable import TokenWatch

@Suite("CodexRolloutParsingState")
struct CodexRolloutParsingStateTests {
    @Test func checkpointRestoresModelSessionAndPreviousTotals() throws {
        let decoder = JSONDecoder()
        var checkpoint = CodexParserCheckpoint.initial(
            sessionID: "file-session",
            replaySecond: nil
        )
        let speed = CodexPricingSpeed.standard
        let lines = [
            #"{"timestamp":"2026-05-04T08:35:44Z","type":"session_meta","payload":{"id":"meta-session","cwd":"/tmp/project","model_provider":"openai"}}"#,
            #"{"timestamp":"2026-05-04T08:35:45Z","type":"turn_context","payload":{"model":"gpt-5.4"}}"#,
            #"{"timestamp":"2026-05-04T08:35:46Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":300,"output_tokens":200,"reasoning_output_tokens":0,"total_tokens":1200}}}}"#
        ]
        let firstCandidates = try lines.enumerated().compactMap { index, line -> CodexUsageCandidate? in
            let record = try decoder.decode(CodexRecord.self, from: Data(line.utf8))
            return checkpoint.consume(record, sourceOffset: UInt64(index), speed: speed)
        }
        #expect(firstCandidates.count == 1)

        var restored = checkpoint
        let next = #"{"timestamp":"2026-05-04T08:36:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1600,"cached_input_tokens":500,"output_tokens":260,"reasoning_output_tokens":0,"total_tokens":1860}}}}"#
        let record = try decoder.decode(CodexRecord.self, from: Data(next.utf8))
        let entry = try #require(
            restored.consume(record, sourceOffset: 3, speed: speed)?.entry
        )

        #expect(entry.sessionID == "meta-session")
        #expect(entry.cwd == "/tmp/project")
        #expect(entry.model == "gpt-5.4")
        #expect(entry.usage.inputTokens == 400)
        #expect(entry.usage.cacheReadInputTokens == 200)
        #expect(entry.usage.outputTokens == 60)
    }

    @Test("checkpoint 保留 last-first、cached clamp 与 zero-model 顺序")
    func reducerMatchesPinnedOrdering() throws {
        let decoder = JSONDecoder()
        var checkpoint = CodexParserCheckpoint.initial(
            sessionID: "session",
            replaySecond: nil
        )
        let turn = #"{"timestamp":"2026-05-04T08:35:44.000Z","type":"turn_context","payload":{"model":"gpt-5"}}"#
        let zero = #"{"timestamp":"2026-05-04T08:35:45.000Z","type":"event_msg","payload":{"type":"token_count","model":"gpt-5.5","info":{"last_token_usage":{"input_tokens":0,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":0}}}}"#
        let first = #"{"timestamp":"2026-05-04T08:35:46.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":150,"output_tokens":1,"reasoning_output_tokens":0,"total_tokens":101},"last_token_usage":{"input_tokens":100,"cached_input_tokens":150,"output_tokens":1,"reasoning_output_tokens":0,"total_tokens":101}}}}"#
        let repeated = first.replacingOccurrences(
            of: "08:35:46.000Z",
            with: "08:35:47.000Z"
        )
        for (offset, line) in [turn, zero].enumerated() {
            let record = try decoder.decode(CodexRecord.self, from: Data(line.utf8))
            let candidate = checkpoint.consume(
                record,
                sourceOffset: UInt64(offset),
                speed: .standard
            )
            #expect(candidate?.entry == nil)
        }
        let firstRecord = try decoder.decode(CodexRecord.self, from: Data(first.utf8))
        let repeatedRecord = try decoder.decode(CodexRecord.self, from: Data(repeated.utf8))
        let emitted = [
            checkpoint.consume(firstRecord, sourceOffset: 2, speed: .standard),
            checkpoint.consume(repeatedRecord, sourceOffset: 3, speed: .standard),
        ].compactMap { $0?.entry }

        #expect(emitted.count == 2)
        #expect(emitted.allSatisfy { $0.model == "gpt-5" })
        #expect(emitted.allSatisfy { $0.usage.inputTokens == 0 })
        #expect(emitted.allSatisfy { $0.usage.cacheReadInputTokens == 100 })
    }

    @Test("session token_count 缺 timestamp 不使用 offset 计费")
    func missingTimestampIsSkipped() throws {
        let decoder = JSONDecoder()
        var checkpoint = CodexParserCheckpoint.initial(
            sessionID: "session",
            replaySecond: nil
        )
        let line = #"{"type":"event_msg","payload":{"type":"token_count","model":"gpt-5","info":{"last_token_usage":{"input_tokens":10,"output_tokens":1}}}}"#
        let record = try decoder.decode(CodexRecord.self, from: Data(line.utf8))

        #expect(checkpoint.consume(
            record,
            sourceOffset: 99,
            speed: .standard
        )?.entry == nil)
    }
}
```

- [ ] **Step 2: 运行测试并确认 checkpoint 尚不存在**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/CodexRolloutParsingStateTests -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: FAIL，找不到 `CodexParserCheckpoint`。

- [ ] **Step 3: 把现有行处理逻辑移动到值类型 reducer**

```swift
struct CodexParserCheckpoint: Sendable {
    var currentModel: CodexModelState?
    var sessionID: String
    var cwd: String?
    var previousTotals: CodexTokenCounts?
    var replaySecond: String?
    var isSkippingReplay: Bool

    static func initial(
        sessionID: String,
        replaySecond: String?
    ) -> CodexParserCheckpoint {
        CodexParserCheckpoint(
            currentModel: nil,
            sessionID: sessionID,
            cwd: nil,
            previousTotals: nil,
            replaySecond: replaySecond,
            isSkippingReplay: replaySecond != nil
        )
    }

    mutating func consume(
        _ record: CodexRecord,
        sourceOffset: UInt64,
        speed: CodexPricingSpeed
    ) -> CodexUsageCandidate? {
        switch record.payload {
        case .sessionMeta(let meta):
            sessionID = meta.id
            cwd = meta.cwd
            return nil
        case .turnContext(let context):
            _ = CodexModelResolver.resolve(
                parsedModel: context.preferredModel,
                eventDate: record.normalizedTimestamp?.date,
                current: &currentModel
            )
            return nil
        case .eventMsg(let event):
            guard event.type == "token_count", let info = event.info else { return nil }
            guard let timestamp = record.normalizedTimestamp else { return nil }

            if isSkippingReplay, let replaySecond {
                if timestamp.key.prefix(19) == replaySecond {
                    if let total = info.totalTokenUsage { previousTotals = total }
                    return nil
                }
                isSkippingReplay = false
            }

            let delta = info.lastTokenUsage
                ?? info.totalTokenUsage.map { $0.subtracting(previousTotals ?? .zero) }
            if let total = info.totalTokenUsage { previousTotals = total }
            guard let delta, !delta.isAllZero else { return nil }

            let model = CodexModelResolver.resolve(
                parsedModel: event.preferredModel ?? info.preferredModel,
                eventDate: timestamp.date,
                current: &currentModel
            )
            return CodexUsageCandidate.make(
                sessionID: sessionID,
                timestamp: timestamp,
                sourceOffset: sourceOffset,
                model: model,
                cwd: cwd,
                counts: delta,
                speed: speed
            )
        case .unknown:
            return nil
        }
    }
}
```

同文件加入完整 helper；Codex input 继续减 cached，cache creation 明确为 nil：

```swift
extension CodexTokenCounts {
    func subtracting(_ previous: CodexTokenCounts) -> CodexTokenCounts {
        CodexTokenCounts(
            inputTokens: max(0, inputTokens - previous.inputTokens),
            cachedInputTokens: max(0, cachedInputTokens - previous.cachedInputTokens),
            outputTokens: max(0, outputTokens - previous.outputTokens),
            reasoningOutputTokens: max(0, reasoningOutputTokens - previous.reasoningOutputTokens),
            totalTokens: max(0, totalTokens - previous.totalTokens)
        )
    }
}

extension CodexPricingSpeed {
    var usageSpeed: String {
        self == .fast ? "fast" : ""
    }
}

extension CodexUsageCandidate {
    static func make(
        sessionID: String,
        timestamp: CodexNormalizedTimestamp,
        sourceOffset: UInt64,
        model: String,
        cwd: String?,
        counts: CodexTokenCounts,
        speed: CodexPricingSpeed
    ) -> CodexUsageCandidate {
        let normalized = counts.normalizedForBilling
        let messageID = "\(sessionID):\(timestamp.key):\(sourceOffset)"
        let usage = TokenUsage(
            inputTokens: normalized.pureInput,
            cacheCreationInputTokens: 0,
            cacheReadInputTokens: normalized.cachedInput,
            outputTokens: normalized.output,
            reasoningTokens: normalized.reasoning,
            serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
            serviceTier: speed == .fast ? "fast" : "",
            cacheCreation: nil,
            inferenceGeo: "",
            iterations: [],
            speed: speed.usageSpeed
        )
        let entry = ParsedUsageEntry(
            recordUUID: messageID,
            messageId: messageID,
            requestId: nil,
            sessionID: sessionID,
            timestamp: timestamp.date,
            model: model,
            cwd: cwd,
            agentId: nil,
            usage: usage,
            isSubagent: false,
            isSidechain: false,
            provider: .codex,
            upstreamProviderID: nil,
            upstreamCost: nil
        )
        return CodexUsageCandidate(
            entry: entry,
            dedupKey: CodexEventDedupKey(
                timestampKey: timestamp.key,
                model: model,
                rawInput: normalized.rawInput,
                cachedInput: normalized.cachedInput,
                output: normalized.output,
                reasoning: normalized.reasoning,
                total: normalized.total
            )
        )
    }
}
```

`CodexTokenCounts.normalizedForBilling` 是数据计划 Task 4 建立的唯一归一化 helper：先非负化 raw input，再将 cached clamp 到 raw input，输出 pure/raw/cached/output/reasoning/total。计价阶段的全量 parser 与本 reducer 都必须调它，不保留两份 `max(input-cached, 0)` 逻辑。

`CodexRolloutParser.parseFile` 改为创建 checkpoint，并把每条 line 的绝对起始 byte offset 传给 `consume`，不保留第二套状态机。

- [ ] **Step 4: 运行 reducer 与既有 Codex parser suites**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/CodexRolloutParsingStateTests -only-testing:TokenWatchTests/CodexRolloutParserTests -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: PASS，现有模型切换、fallback 和 delta 测试无回归；repeated total + nonzero last 仍 emit，四维全零不污染 model，cached clamp、timestamp 和 replay baseline 保持数据计划契约。

- [ ] **Step 5: 提交 Codex reducer**

```bash
git add TokenWatch/Providers/Codex/CodexRolloutParsingState.swift TokenWatch/Providers/Codex/CodexRolloutParser.swift TokenWatchTests/Providers/Codex/CodexRolloutParsingStateTests.swift
git commit -m "refactor(codex): 抽出可恢复的 rollout 状态"
```

### Task 5: Codex 追加从 checkpoint 恢复

**Files:**
- Modify: `TokenWatch/Providers/Codex/CodexRolloutParser.swift`
- Modify: `TokenWatchTests/Providers/Codex/CodexRolloutParserTests.swift`

**Interfaces:**
- Consumes: `IncrementalJSONLFileState<CodexUsageCandidate, CodexParserCheckpoint>`、descriptor-based `JSONLFileReading`。
- Produces: `CodexRolloutParser.init(fileReader:)` 和保留计价计划 `pricingSpeed:` 标签的仅后缀读取 `parseAllFiles`。

- [ ] **Step 1: 写模型/session/total 跨 append 的 I/O 失败测试**

```swift
@Test("Codex append 从 committed checkpoint 恢复")
func appendReadsOnlySuffixAndRestoresCheckpoint() throws {
    let fixture = try makeRolloutFixture(lines: [sessionMeta, turnContextGpt5, normalEvent])
    defer { fixture.cleanup() }
    let reader = RecordingJSONLFileReader()
    let parser = CodexRolloutParser(fileReader: reader)
    let first = try parser.parseAllFiles([fixture.file], pricingSpeed: .standard)
    #expect(first.count == 1)
    let committedOffset = try #require(reader.latestMetadata?.size)
    let anchor = try #require(parser.debugContinuityAnchor(for: fixture.file.url))

    let next = #"{"timestamp":"2026-05-04T08:36:30Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1600,"cached_input_tokens":500,"output_tokens":260,"reasoning_output_tokens":0,"total_tokens":1860}}}}"#
    try appendUTF8(next + "\n", to: fixture.file.url)
    reader.resetMetrics()
    let entries = try parser.parseAllFiles([fixture.file], pricingSpeed: .standard)
        .sorted { ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast) }

    #expect(reader.seekOffsets == [anchor.offset, committedOffset])
    #expect(reader.totalBytesRead == anchor.bytes.count + (next + "\n").utf8.count)
    #expect(entries.count == 2)
    #expect(entries[1].model == "gpt-5")
    #expect(entries[1].sessionID == "019df220-aaaa-bbbb-cccc-ddddeeeeffff")
    #expect(entries[1].usage.inputTokens == 400)
    #expect(entries[1].usage.cacheReadInputTokens == 200)
    #expect(entries[1].usage.outputTokens == 60)
}

private struct RolloutFixture {
    let file: CodexRolloutFileInfo
    let cleanup: () -> Void
}

private func makeRolloutFixture(lines: [String]) throws -> RolloutFixture {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("CodexIncremental-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let sessionID = "019df220-aaaa-bbbb-cccc-ddddeeeeffff"
    let url = dir.appendingPathComponent(
        "rollout-2026-05-04T16-35-18-\(sessionID).jsonl"
    )
    try (lines.joined(separator: "\n") + "\n")
        .write(to: url, atomically: false, encoding: .utf8)
    return RolloutFixture(
        file: CodexRolloutFileInfo(
            url: url,
            sessionID: sessionID,
            isArchived: false
        ),
        cleanup: { try? FileManager.default.removeItem(at: dir) }
    )
}

private func appendUTF8(_ text: String, to url: URL) throws {
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(text.utf8))
}
```

上述 helper 定义在 `CodexRolloutParserTests.swift` 自身；不引用 Claude test file 的 file-private `appendUTF8`。

- [ ] **Step 2: 运行测试并确认当前 Codex cache 全量失效**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/CodexRolloutParserTests/appendReadsOnlySuffixAndRestoresCheckpoint -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: FAIL；metrics 显示从 0 读取，或增量 delta 没有 previous totals。

- [ ] **Step 3: 将 Codex cache 改为带 checkpoint 的增量状态**

```swift
private typealias CodexFileState = IncrementalJSONLFileState<CodexUsageCandidate, CodexParserCheckpoint>

private struct CachedCodexFile: Sendable {
    let speed: CodexPricingSpeed
    let replayClassification: CodexReplayClassification
    let state: CodexFileState
}

private let fileReader: any JSONLFileReading
private var cachedFiles: [String: CachedCodexFile] = [:]

init(fileReader: any JSONLFileReading = SystemJSONLFileReader()) {
    self.fileReader = fileReader
}
```

读取完整行时对可变 checkpoint 调 `consume(record, sourceOffset: lineStartOffset, speed: speed)`，每消费一个以换行结束的 line 后更新 `checkpointAtCommittedOffset`。处理 EOF tail 时必须复制 checkpoint：

```swift
var provisionalCheckpoint = committedCheckpoint
let provisionalCandidates = parseRecord(buffer).flatMap {
    provisionalCheckpoint.consume($0, sourceOffset: committedOffset, speed: speed)
}.map { [$0] } ?? []
```

返回 state 时保存 `committedCheckpoint`，不能保存 `provisionalCheckpoint`。`parseCachedFile` 每轮打开一个 descriptor snapshot；metadata + speed 完全相同时可直接 reuse，其他情况先重新分类 replay，然后只计算一次 transition：

```swift
let snapshot = try fileReader.openSnapshot(for: fileInfo.url)
defer { snapshot.stream.close() }
let cached = withCacheLock { cachedFiles[cacheKey] }

if let cached,
   cached.speed == speed,
   cached.state.metadata == snapshot.metadata,
   snapshot.metadata.identity != nil {
    withCacheLock { cacheHitCount += 1 }
    return cached.state.returnedCandidates
}

let contentTransition = cached.map {
    IncrementalJSONLTransition.decide(
        previous: $0.state,
        newMetadata: snapshot.metadata
    )
} ?? .rebuild
let anchorMatches: Bool
if case .append = contentTransition, let cached {
    anchorMatches = try cached.state.continuityAnchor.matches(
        in: snapshot.stream
    )
} else {
    anchorMatches = false
}
let contentCanReuseClassification: Bool = {
    switch contentTransition {
    case .reuse:
        return true
    case .append:
        return anchorMatches
    case .rebuild:
        return false
    }
}()
let replayClassification: CodexReplayClassification
if let cached,
   contentCanReuseClassification,
   cached.replayClassification != .pending {
    replayClassification = cached.replayClassification
} else {
    replayClassification = try CodexReplayDetector.classify(snapshot: snapshot)
}
let replaySecond = replayClassification.replaySecond
let previous: CodexFileState? = {
    guard let cached,
          cached.speed == speed,
          contentCanReuseClassification,
          cached.state.checkpointAtCommittedOffset.replaySecond == replaySecond
    else { return nil }
    return cached.state
}()
let transition = previous == nil ? .rebuild : contentTransition

let nextState = try buildState(
    fileInfo: fileInfo,
    snapshot: snapshot,
    previous: previous,
    transition: transition,
    replaySecond: replaySecond,
    speed: speed
)
```

只在 `buildState` 完整成功后写入 `CachedCodexFile(speed: speed, replayClassification: replayClassification, state: nextState)`；config 从 standard 切到 fast 时 `previous == nil`，必须从 0 重建，使所有 entry 的 `usage.speed` 更新。不得在 `buildState` 内再根据 metadata 重算 transition，否则 speed mismatch 会错误 reuse 旧 state。

`CodexReplayDetector.classify` 复用数据计划的 pinned 规则。对带 marker 但尚不足两条 usage 的文件返回 `.pending`；第二条同秒 usage 追加后分类从 pending 变为 replay，上述 replaySecond 比较会强制从 0 重建，因而能撤销上一轮 provisional/stable 的第一条历史 candidate。

`buildState` 与底层读取循环按以下唯一算法实现，确保每个完整行之后的 checkpoint 与 committed offset 同步推进：

```swift
private func buildState(
    fileInfo: CodexRolloutFileInfo,
    snapshot: JSONLFileSnapshot,
    previous: CodexFileState?,
    transition: IncrementalJSONLTransition,
    replaySecond: String?,
    speed: CodexPricingSpeed
) throws -> CodexFileState {
    switch transition {
    case .reuse:
        return previous!
    case .append(let startOffset):
        return try readState(
            fileInfo: fileInfo,
            snapshot: snapshot,
            startOffset: startOffset,
            stablePrefix: previous!.stableCandidates,
            checkpoint: previous!.checkpointAtCommittedOffset,
            previousAnchor: previous!.continuityAnchor,
            speed: speed
        )
    case .rebuild:
        return try readState(
            fileInfo: fileInfo,
            snapshot: snapshot,
            startOffset: 0,
            stablePrefix: [],
            checkpoint: .initial(
                sessionID: fileInfo.sessionID,
                replaySecond: replaySecond
            ),
            previousAnchor: .empty,
            speed: speed
        )
    }
}

private func readState(
    fileInfo: CodexRolloutFileInfo,
    snapshot: JSONLFileSnapshot,
    startOffset: UInt64,
    stablePrefix: [CodexUsageCandidate],
    checkpoint: CodexParserCheckpoint,
    previousAnchor: JSONLContinuityAnchor,
    speed: CodexPricingSpeed
) throws -> CodexFileState {
    try snapshot.stream.seek(toOffset: startOffset)

    var stable = stablePrefix
    var committedCheckpoint = checkpoint
    var buffer = Data()
    var bufferStartOffset = startOffset
    var nextReadOffset = startOffset
    var newlyCommittedBytes = Data()

    while nextReadOffset < snapshot.metadata.size {
        let count = Int(min(UInt64(64 * 1024), snapshot.metadata.size - nextReadOffset))
        let chunk = try snapshot.stream.read(upToCount: count)
        guard !chunk.isEmpty else { throw IncrementalJSONLReadError.unexpectedEOF }
        nextReadOffset += UInt64(chunk.count)
        buffer.append(chunk)

        var consumed = buffer.startIndex
        while let newline = buffer[consumed...].firstIndex(of: 0x0A) {
            let lineStartOffset = bufferStartOffset + UInt64(consumed)
            let line = Data(buffer[consumed..<newline])
            if let record = parseRecord(line),
               let candidate = committedCheckpoint.consume(
                    record,
                    sourceOffset: lineStartOffset,
                    speed: speed
               ) {
                stable.append(candidate)
            }
            consumed = buffer.index(after: newline)
        }
        if consumed > buffer.startIndex {
            newlyCommittedBytes.append(buffer[..<consumed])
            buffer.removeSubrange(buffer.startIndex..<consumed)
            bufferStartOffset += UInt64(consumed)
        }
    }

    let committedOffset = bufferStartOffset
    var provisionalCheckpoint = committedCheckpoint
    let provisionalCandidates = parseRecord(buffer).flatMap {
        provisionalCheckpoint.consume(
            $0,
            sourceOffset: committedOffset,
            speed: speed
        )
    }.map { [$0] } ?? []

    return CodexFileState(
        metadata: snapshot.metadata,
        committedOffset: committedOffset,
        stableCandidates: stable,
        provisionalTail: buffer,
        provisionalCandidates: provisionalCandidates,
        continuityAnchor: .make(
            previous: previousAnchor,
            newlyCommittedBytes: newlyCommittedBytes,
            committedOffset: committedOffset
        ),
        checkpointAtCommittedOffset: committedCheckpoint
    )
}
```

`parseRecord(_:)` 只负责 `JSONDecoder` 解码非空单行并返回 optional `CodexRecord`；无效行仍算已提交字节，但不能改变 checkpoint。`parseCachedFile` 只有在上述方法完整返回后才替换 cache。

- [ ] **Step 4: 运行 Codex parser、reducer 与 reader suites**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/CodexRolloutParserTests -only-testing:TokenWatchTests/CodexRolloutParsingStateTests -only-testing:TokenWatchTests/JSONLFileReaderTests -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: PASS；append I/O、模型、session、delta、speed 全部正确。

- [ ] **Step 5: 提交 Codex 增量读取**

```bash
git add TokenWatch/Providers/Codex/CodexRolloutParser.swift TokenWatchTests/Providers/Codex/CodexRolloutParserTests.swift
git commit -m "perf(codex): 从 checkpoint 增量读取 rollout"
```

### Task 6: Codex provisional、重建、last-good 与深比较

**Files:**
- Modify: `TokenWatch/Providers/Codex/CodexRolloutParser.swift`
- Modify: `TokenWatchTests/Providers/Codex/CodexRolloutParserTests.swift`

**Interfaces:**
- Consumes: data plan 的 last-good cache 语义与 deep snapshot helper。
- Produces: 所有文件状态迁移下增量结果等于 fresh full scan。

- [ ] **Step 1: 写边界状态表驱动失败测试**

新增测试覆盖以下真实写入序列，并在每一行使用 `ParsedUsageEntryDeepSnapshot.sorted(_:)` 排序比较：

```swift
@Test("Codex 增量与 fresh 全量结果深度一致")
func incrementalMatchesFreshFullScanAcrossTransitions() throws {
    let fixture = try makeRolloutFixture(lines: [sessionMeta, turnContextGpt5, normalEvent])
    defer { fixture.cleanup() }
    let reader = RecordingJSONLFileReader()
    let incremental = CodexRolloutParser(fileReader: reader)
    _ = try incremental.parseAllFiles([fixture.file], pricingSpeed: .fast)

    let modelSwitch = #"{"timestamp":"2026-05-04T08:36:10Z","type":"turn_context","payload":{"model":"gpt-5.5"}}"#
    let event = #"{"timestamp":"2026-05-04T08:36:30Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":800,"cached_input_tokens":200,"output_tokens":100,"reasoning_output_tokens":0,"total_tokens":900},"total_token_usage":{"input_tokens":1800,"cached_input_tokens":500,"output_tokens":300,"reasoning_output_tokens":0,"total_tokens":2100}}}}"#
    try appendUTF8(modelSwitch + "\n" + event, to: fixture.file.url)
    let provisional = try incremental.parseAllFiles([fixture.file], pricingSpeed: .fast)
    let provisionalSize = try #require(
        (try FileManager.default.attributesOfItem(atPath: fixture.file.url.path)[.size] as? NSNumber)?.uint64Value
    )
    let eventStartOffset = provisionalSize - UInt64(event.utf8.count)
    let anchor = try #require(
        incremental.debugContinuityAnchor(for: fixture.file.url)
    )
    reader.resetMetrics()
    try appendUTF8("\n", to: fixture.file.url)
    let committed = try incremental.parseAllFiles([fixture.file], pricingSpeed: .fast)
    let fresh = try CodexRolloutParser().parseAllFiles([fixture.file], pricingSpeed: .fast)

    #expect(reader.seekOffsets == [anchor.offset, eventStartOffset])
    #expect(reader.totalBytesRead == anchor.bytes.count + (event + "\n").utf8.count)
    #expect(ParsedUsageEntryDeepSnapshot.sorted(provisional) == ParsedUsageEntryDeepSnapshot.sorted(committed))
    #expect(ParsedUsageEntryDeepSnapshot.sorted(committed) == ParsedUsageEntryDeepSnapshot.sorted(fresh))
}
```

同一 suite 加入以下两个精确测试；metadata/read failure、prune 和 unchanged 零读取继续运行数据计划已经落地的测试：

```swift
@Test("Codex 半行不会提前提交 checkpoint")
func incompleteTailDoesNotCommitCheckpoint() throws {
    let fixture = try makeRolloutFixture(lines: [sessionMeta, turnContextGpt5])
    defer { fixture.cleanup() }
    let parser = CodexRolloutParser()
    let event = #"{"timestamp":"2026-05-04T08:36:30Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":300,"output_tokens":200,"reasoning_output_tokens":0,"total_tokens":1200}}}}"#
    let split = event.utf8.index(event.utf8.startIndex, offsetBy: event.utf8.count / 2)
    try appendUTF8(String(decoding: event.utf8[..<split], as: UTF8.self), to: fixture.file.url)
    #expect(try parser.parseAllFiles([fixture.file], pricingSpeed: .standard).isEmpty)
    try appendUTF8(String(decoding: event.utf8[split...], as: UTF8.self) + "\n", to: fixture.file.url)
    let result = try parser.parseAllFiles([fixture.file], pricingSpeed: .standard)
    #expect(result.count == 1)
    #expect(result.first?.usage.inputTokens == 700)
    #expect(result.first?.usage.cacheReadInputTokens == 300)
}

@Test(arguments: ["truncate", "truncate-grow", "replace", "touch", "speed"])
func codexRebuildTransitionsMatchFreshScan(kind: String) throws {
    let fixture = try makeRolloutFixture(lines: [sessionMeta, turnContextGpt5, normalEvent])
    defer { fixture.cleanup() }
    let reader = RecordingJSONLFileReader()
    let parser = CodexRolloutParser(fileReader: reader)
    _ = try parser.parseAllFiles([fixture.file], pricingSpeed: .standard)

    let truncated = [sessionMeta, turnContextGpt55, normalEvent].joined(separator: "\n") + "\n"
    let replacement = [sessionMeta, turnContextGpt55, normalEvent].joined(separator: "\n") + "\n"
    var speed = CodexPricingSpeed.standard
    switch kind {
    case "truncate":
        let handle = try FileHandle(forWritingTo: fixture.file.url)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data(truncated.utf8))
        try handle.close()
    case "truncate-grow":
        let handle = try FileHandle(forWritingTo: fixture.file.url)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data((truncated + truncated).utf8))
        try handle.close()
    case "replace":
        try replacement.write(to: fixture.file.url, atomically: true, encoding: .utf8)
    case "touch":
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(5)],
            ofItemAtPath: fixture.file.url.path
        )
    case "speed":
        speed = .fast
    default:
        Issue.record("unexpected transition kind")
    }

    reader.resetMetrics()
    let incremental = try parser.parseAllFiles([fixture.file], pricingSpeed: speed)
    let fresh = try CodexRolloutParser().parseAllFiles([fixture.file], pricingSpeed: speed)
    #expect(reader.seekOffsets.contains(0))
    #expect(ParsedUsageEntryDeepSnapshot.sorted(incremental) == ParsedUsageEntryDeepSnapshot.sorted(fresh))
}

@Test("Codex replay 分类从 pending 变为同秒时撤销已稳定历史")
func replayClassificationChangeForcesRebuild() throws {
    let replayMeta = #"{"timestamp":"2026-05-04T08:35:40.000Z","type":"session_meta","payload":{"id":"child","cwd":"/tmp/child","forked_from_id":"root"}}"#
    let first = #"{"timestamp":"2026-05-04T08:35:59.100Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":10,"output_tokens":10,"reasoning_output_tokens":0,"total_tokens":110},"last_token_usage":{"input_tokens":100,"cached_input_tokens":10,"output_tokens":10,"reasoning_output_tokens":0,"total_tokens":110}}}}"#
    let second = #"{"timestamp":"2026-05-04T08:35:59.900Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":200,"cached_input_tokens":20,"output_tokens":20,"reasoning_output_tokens":0,"total_tokens":220},"last_token_usage":{"input_tokens":100,"cached_input_tokens":10,"output_tokens":10,"reasoning_output_tokens":0,"total_tokens":110}}}}"#
    let next = #"{"timestamp":"2026-05-04T08:36:00.100Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":250,"cached_input_tokens":25,"output_tokens":25,"reasoning_output_tokens":0,"total_tokens":275}}}}"#
    let fixture = try makeRolloutFixture(lines: [
        replayMeta, turnContextGpt5, first,
    ])
    defer { fixture.cleanup() }
    let reader = RecordingJSONLFileReader()
    let parser = CodexRolloutParser(fileReader: reader)
    #expect(try parser.parseAllFiles([fixture.file], pricingSpeed: .standard).count == 1)

    try appendUTF8(second + "\n" + next + "\n", to: fixture.file.url)
    reader.resetMetrics()
    let incremental = try parser.parseAllFiles([fixture.file], pricingSpeed: .standard)
    let fresh = try CodexRolloutParser().parseAllFiles(
        [fixture.file],
        pricingSpeed: .standard
    )

    #expect(reader.seekOffsets.contains(0))
    #expect(incremental.count == 1)
    #expect(ParsedUsageEntryDeepSnapshot.sorted(incremental) ==
        ParsedUsageEntryDeepSnapshot.sorted(fresh))
}
```

- [ ] **Step 2: 运行边界测试确认 provisional checkpoint 或回退失败**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/CodexRolloutParserTests/incrementalMatchesFreshFullScanAcrossTransitions -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: FAIL，任何提前提交 provisional model/total、错误覆盖 last-good 或浅层比较都会暴露。

- [ ] **Step 3: 统一 Codex 原子更新和全局去重**

`parseCachedFile` 只能在 snapshot metadata、replay 分类、anchor/seek/read 和完整状态构建全部成功后替换 cache。Task 5 计算出的 `nextState` 原子写入：

```swift
withCacheLock {
    cachedFiles[cacheKey] = CachedCodexFile(
        speed: speed,
        replayClassification: replayClassification,
        state: nextState
    )
}
return nextState.returnedCandidates
```

任何失败由 `parseAllFiles` 捕获；只有旧 `CachedCodexFile.speed == 本轮 speed` 时才返回其 `returnedCandidates`，首次失败或跨 speed 失败继续跳过。最终 dedup 始终对所有文件 state 的 stable + provisional `CodexUsageCandidate` 执行：

```swift
var seen: Set<CodexEventDedupKey> = []
let entries = allCandidates.compactMap { candidate -> ParsedUsageEntry? in
    guard seen.insert(candidate.dedupKey).inserted else { return nil }
    return candidate.entry
}
```

不能把 per-file 最终 entries 直接 append 到旧去重结果，也不能丢掉 candidate 中的 source total/reasoning/timestamp key。

- [ ] **Step 4: 运行两个 parser 的完整定向回归**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/IncrementalJSONLFileStateTests -only-testing:TokenWatchTests/JSONLFileReaderTests -only-testing:TokenWatchTests/ClaudeJSONLParserTests -only-testing:TokenWatchTests/ClaudeUsageDeduplicatorTests -only-testing:TokenWatchTests/CodexRolloutParsingStateTests -only-testing:TokenWatchTests/CodexRolloutParserTests -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: PASS；所有 deep snapshot、offset、read byte count、tail 和回退测试通过。

- [ ] **Step 5: 提交 Codex 边界语义**

```bash
git add TokenWatch/Providers/Codex/CodexRolloutParser.swift TokenWatchTests/Providers/Codex/CodexRolloutParserTests.swift
git commit -m "fix(codex): 保持增量状态与全量解析一致"
```

## Plan-Wide Verification

先运行单元测试；完整 test 需要沙盒外权限：

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

然后验证编译和静态分析：

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- build-for-testing
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Debug -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Debug -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO analyze
```

最后确认增量性能契约：

- 未变化文件：打开 1 个 descriptor snapshot 以取无 TOCTOU metadata，0 byte read、0 次 seek。
- 普通追加文件：先 seek/read 不超过 256 bytes 的 continuity anchor，再 seek committed offset 并只读 provisional tail + suffix；解析新 candidate 的起点仍是 committed offset。
- Codex replay `.pending` 文件：允许为重新分类额外读取 pinned replay probe；分类一旦稳定，后续追加回到上一条有界 I/O 契约。
- 截断、替换、同 size 改写，以及同 inode truncate 后重写成更大文件：最终 seek 0 全量重建；最后一种允许先读 anchor 发现不匹配。
- Claude/Codex 的 incremental 与 fresh full scan deep snapshots 完全一致。
- `git status --short` 只包含本计划预期文件，且每个任务已有独立中文 commit。
