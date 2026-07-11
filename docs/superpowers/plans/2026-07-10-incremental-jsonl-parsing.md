# Incremental JSONL Parsing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 Claude 与 Codex JSONL 在可证明仍为原内容追加时只读取 committed offset 之后的字节，并在尾行、截断、替换和暂时读取失败时保持与全量解析完全一致的结果。

**Architecture:** 数据正确性计划先提供 `JSONLFileReading`、文件 identity/size/mtime 元数据、共享 `JSONLLastGoodCacheCoordinator`、Claude 全局去重器和 Codex 可选累计状态。本计划把该 coordinator 的泛型 payload 从候选数组演进为 provider-specific `State`，由同一个 `loadListedFiles` 循环继续唯一负责 snapshot、cache hit、scope-sensitive last-good、成功后的原子替换与 prune；Claude/Codex 只提供 previous-state transition/build 和 candidate projection closure。每个 state 保存 stable raw candidates、未提交尾段和 committed checkpoint，只有完整换行才推进 offset。

**Tech Stack:** Swift 6、Foundation `FileHandle`、Swift Testing、Xcode 26.5、macOS 15+

## Global Constraints

- 先完成 `2026-07-10-ccusage-pricing-parity.md` 和 `2026-07-10-provider-data-correctness-and-authorization.md`。
- 保留 Claude 的 billing raw prefilter、严格 DTO、`costUSD`、`isSidechain`、`hasSourceMessageID` 与 daily 单遍去重语义；缓存必须保存去重前 raw candidates。
- 保留 Codex 的 `CodexUsageCandidate`、loader dedup key、replay classifier、resolved model/source、service tier、session metadata 与 `previousTotals`；config 的 fast/priority 只写 `TokenUsage.serviceTier`，Codex 的 `TokenUsage.speed` 始终为空。
- `JSONLLastGoodCacheCoordinator<State, Scope>.loadListedFiles(...)` 必须继续是 Claude/Codex 唯一的 listed-file、open snapshot、unchanged hit、scope-sensitive last-good、原子替换和 prune 协调循环；parser 不得重新声明 `cachedFiles`、cache lock/hit counter、per-file catch 或 prune。
- identity/size/mtime 全同才允许零读取复用；identity 不可验证时必须全量重建。
- 所有 metadata 必须来自与 stream 相同的 opened descriptor snapshot；append 前校验 continuity anchor。只有 anchor 从 offset 0 覆盖整个 committed prefix 时，匹配结果才足以证明可安全复用；超过 256 bytes 的 committed prefix 一律从 0 重建。
- EOF 无换行的完整 JSON 只作为 provisional candidate 返回，不能推进 offset 或 checkpoint。
- 测试比较必须使用 deep snapshot，不能使用只比较 `dedupKey` 的 `ParsedUsageEntry.==`。
- 不引入第三方流式解析、数据库或运行时网络依赖。
- 每个生产改动前必须先看到对应回归测试按预期失败。
- 测试使用 `.build/DerivedData`；app-hosted test 在沙盒中需要提升权限。
- test/build-for-testing 命令统一使用 `CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=-` 的临时 ad-hoc 签名；纯 build/analyze 使用 `CODE_SIGNING_ALLOWED=NO`。
- Commit 使用中文并遵循 `<type>(<scope>): <summary>`。

## 2026-07-11 Correctness Amendment

Task 2 的真实 RED/GREEN 运行证明：单一 256-byte suffix anchor 无法可靠区分合法 append 与“同 inode truncate 后重写成更大文件”。测试 fixture 的旧/新行均为 580 bytes，所有差异位于 offsets 28...270，而旧 suffix anchor 为 324..<580；因此 metadata、anchor 和 committed-offset 后缀读取在两种历史下完全同构。任何只依赖该有界样本的实现都可能复用已经不存在的旧 candidate。

本计划因此采用 correctness-first 规则，并覆盖下文较早的示例：

- `.append` 只有在 `anchor.offset == 0` 且 `anchor.bytes.count == committedOffset` 时才允许复用 stable candidates/checkpoint；随后还必须逐字节匹配完整 committed prefix。
- committed prefix 超过 256 bytes 时，即使 suffix anchor 匹配也必须 seek 0 重建。不可修改 fixture 或删除 deep-snapshot/seek-0 断言来掩盖碰撞。
- unchanged metadata 仍为 0-byte/0-seek cache hit；完整 committed prefix 不超过 256 bytes 的小文件仍走 anchor + suffix 增量路径。
- Claude/Codex 的 append 性能测试必须使用小于等于 256 bytes 的有效 compact fixture；大文件测试只断言正确重建与 fresh full scan 一致。

该修正牺牲大文件 append 的增量收益，但避免计价和用量残留被重写的历史记录。若以后要恢复大文件 suffix-only 性能，必须引入能够证明整个 committed prefix 连续性的独立文件世代信号或完整内容验证，不能重新依赖单个有界样本。

## 2026-07-11 Replay Classification Amendment

Task 4 审查证明 `.notReplay` 本身不一定能跨 append 复用：短文件的 provisional tail 可能只含 `forked_from_id` / `thread_spawn` 的前半段，首次扫描因 marker 尚未完整而得到 `.notReplay`，下一次 append 补全 marker 与同秒 usage 后 fresh scan 会变为 `.replay`。若直接复用旧分类，会保留本应撤销的历史 candidate 并重复计量。

因此 Codex state 还必须保存 replay decision 是否在 append 下稳定：

- 找到 marker 且已观察到前两条有效 usage 后，`.replay` 或“异秒 `.notReplay`”均稳定。
- marker probe 未找到 marker 时，只有已完整覆盖 pinned 16 KiB probe window 才稳定；短文件的 `.notReplay` 不稳定。
- `.pending` 永远不稳定。
- append 只有在 content continuity 与 replay decision stability 同时成立时才复用分类；否则重新分类。若 `replaySecond` 改变，必须从 0 重建。
- 回归测试必须包含“partial marker -> append 补全 marker -> 同秒 replay”，并使用 committed prefix <= 256 bytes 的 fixture 真正经过 reuse-eligible 路径。
- provisional checkpoint 和 `.pending -> .replay` 测试同样必须使用 committed prefix <= 256 bytes；不能靠 correctness gate 的无条件全量重建让断言偶然通过。

## File Structure

- Create: `TokenWatch/Providers/IncrementalJSONLFileState.swift` — 通用缓存状态和 metadata 迁移决策。
- Modify: `TokenWatch/Providers/JSONLLastGoodCacheCoordinator.swift` — 将泛型 payload 演进为 provider-specific state，并把 previous-state build/projection 纳入同一协调循环。
- Create: `TokenWatch/Providers/Codex/CodexRolloutParsingState.swift` — 可保存/恢复的 Codex 行级 checkpoint reducer。
- Modify: `TokenWatch/Providers/Claude/ClaudeJSONLParser.swift` — Claude provider-specific state build/projection、后缀读取与 provisional tail。
- Modify: `TokenWatch/Providers/Codex/CodexRolloutParser.swift` — Codex provider-specific state build/projection、后缀读取与 checkpoint 恢复。
- Create: `TokenWatchTests/Providers/IncrementalJSONLFileStateTests.swift` — 迁移矩阵测试。
- Modify: `TokenWatchTests/Providers/JSONLLastGoodCacheCoordinatorTests.swift` — previous-state build、projection、scope、last-good、hit 与 prune 的唯一协调器契约。
- Modify: `TokenWatchTests/Providers/Claude/ClaudeJSONLParserTests.swift` — Claude append/tail/truncate/replace/I/O 测试。
- Create: `TokenWatchTests/Providers/Codex/CodexRolloutParsingStateTests.swift` — reducer checkpoint 测试。
- Modify: `TokenWatchTests/Providers/Codex/CodexRolloutParserTests.swift` — Codex append/tail/truncate/replace/I/O 测试。
- Reuse: `TokenWatchTests/TestSupport/ParsedUsageEntryDeepSnapshot.swift` — 数据正确性计划提供的完整业务快照。
- Reuse: `TokenWatchTests/TestSupport/RecordingJSONLFileReader.swift` — 数据正确性计划提供的 seek/read 记录器与故障注入。

---

### Task 1: 固定通用状态并演进唯一 cache coordinator

**Files:**
- Create: `TokenWatch/Providers/IncrementalJSONLFileState.swift`
- Modify: `TokenWatch/Providers/JSONLLastGoodCacheCoordinator.swift`
- Modify: `TokenWatch/Providers/Claude/ClaudeJSONLParser.swift`
- Modify: `TokenWatch/Providers/Codex/CodexRolloutParser.swift`
- Create: `TokenWatchTests/Providers/IncrementalJSONLFileStateTests.swift`
- Modify: `TokenWatchTests/Providers/JSONLLastGoodCacheCoordinatorTests.swift`

**Interfaces:**
- Consumes: Provider Task 6 的 `JSONLFileMetadata`、`JSONLFileReading` 与唯一 `JSONLLastGoodCacheCoordinator<Candidate, Scope>`。
- Produces: `IncrementalJSONLFileState<Candidate, Checkpoint>`、`JSONLContinuityAnchor`、`IncrementalJSONLTransition.decide(previous:newMetadata:)`；以及演进后的 `JSONLLastGoodCacheCoordinator<State, Scope>.loadListedFiles(...build:project:onFailure:)` 和只读 `cachedState(for:scope:)`。`.append` 只表示 metadata 候选，provider build closure 校验 anchor 成功后才能执行后缀解析。

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

    @Test func continuityAnchorKeepsOnlyTheCommittedSuffix() {
        let first = Data(repeating: 0x41, count: 200)
        let second = Data(repeating: 0x42, count: 200)
        let firstAnchor = JSONLContinuityAnchor.make(
            previous: .empty,
            newlyCommittedBytes: first,
            committedOffset: 200
        )
        let secondAnchor = JSONLContinuityAnchor.make(
            previous: firstAnchor,
            newlyCommittedBytes: second,
            committedOffset: 400
        )

        #expect(secondAnchor.bytes == Data((first + second).suffix(256)))
        #expect(secondAnchor.offset == 144)
    }

    @Test func continuityAnchorMatchesAndRejectsOpenedStreamBytes() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ContinuityAnchor-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("0123456789abcdef".utf8).write(to: url)
        let snapshot = try SystemJSONLFileReader().openSnapshot(for: url)
        defer { snapshot.stream.close() }

        let matching = JSONLContinuityAnchor(
            offset: 4,
            bytes: Data("4567".utf8)
        )
        let mismatching = JSONLContinuityAnchor(
            offset: 4,
            bytes: Data("4568".utf8)
        )

        #expect(try matching.matches(in: snapshot.stream))
        #expect(try mismatching.matches(in: snapshot.stream) == false)
    }
}
```

在 `JSONLLastGoodCacheCoordinatorTests` 中把既有 coordinator payload 从单个 candidate 改成候选数组 state，并将原 `parse:` closure 精确替换为 `build/project`；原 unchanged、scope-sensitive last-good、成功替换与 prune 断言保持不变：

```swift
let coordinator = JSONLLastGoodCacheCoordinator<[String], Scope>(
    fileReader: reader
)

func load(_ files: [ListedFile], scope: Scope) -> [String] {
    coordinator.loadListedFiles(
        files,
        scope: scope,
        cacheKey: { $0.url.standardizedFileURL.path },
        urlForFile: \.url,
        build: { _, snapshot, _ in
            try readLines(from: snapshot.stream)
        },
        project: { $0 },
        onFailure: { _, _, reusedLastGood in
            fallbackFlags.append(reusedLastGood)
        }
    )
}
```

同一 suite 增加 previous-state、projection 与只读 state forwarding 的失败测试：

```swift
private struct IncrementalCoordinatorState: Sendable, Equatable {
    let revision: Int
    let lines: [String]
}

@Test("协调器把同 scope previous state 交给 build，并继续唯一处理 hit fallback prune")
func coordinatorBuildsAndProjectsProviderStateAtomically() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("JSONLIncrementalCoordinator-\(UUID().uuidString).jsonl")
    try Data("first\n".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let listed = ListedFile(url: url)
    let key = url.standardizedFileURL.path
    let reader = RecordingJSONLFileReader()
    let coordinator = JSONLLastGoodCacheCoordinator<
        IncrementalCoordinatorState,
        Scope
    >(fileReader: reader)
    var receivedPreviousRevisions: [Int?] = []

    func load(_ files: [ListedFile], scope: Scope) -> [String] {
        coordinator.loadListedFiles(
            files,
            scope: scope,
            cacheKey: { $0.url.standardizedFileURL.path },
            urlForFile: \.url,
            build: { _, snapshot, previous in
                receivedPreviousRevisions.append(previous?.revision)
                return IncrementalCoordinatorState(
                    revision: (previous?.revision ?? 0) + 1,
                    lines: try readLines(from: snapshot.stream)
                )
            },
            project: \.lines,
            onFailure: { _, _, _ in }
        )
    }

    #expect(load([listed], scope: .standard) == ["first"])
    #expect(receivedPreviousRevisions == [nil])

    reader.resetMetrics()
    #expect(load([listed], scope: .standard) == ["first"])
    #expect(reader.totalBytesRead == 0)
    #expect(receivedPreviousRevisions == [nil])

    let handle = try FileHandle(forWritingTo: url)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data("second\n".utf8))
    try handle.close()
    #expect(load([listed], scope: .standard) == ["first", "second"])
    #expect(receivedPreviousRevisions == [nil, 1])
    #expect(coordinator.cachedState(for: key, scope: .standard)?.revision == 2)

    let failingHandle = try FileHandle(forWritingTo: url)
    try failingHandle.seekToEnd()
    try failingHandle.write(contentsOf: Data("third\n".utf8))
    try failingHandle.close()
    reader.failure = .read
    #expect(load([listed], scope: .standard) == ["first", "second"])
    #expect(load([listed], scope: .fast).isEmpty)

    reader.failure = .none
    #expect(load([], scope: .standard).isEmpty)
    #expect(coordinator.debugCachedFileCount == 0)
}
```

- [ ] **Step 2: 运行状态与唯一协调器测试并确认 RED**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/IncrementalJSONLFileStateTests -only-testing:TokenWatchTests/JSONLLastGoodCacheCoordinatorTests -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: FAIL；除 `IncrementalJSONLFileState`/anchor 类型尚不存在外，Provider Task 6 的 coordinator 仍以单个 `Candidate` 为 payload，只接受 `parse:`，没有 `build(previous:)`、`project(state:)` 或 `cachedState(for:scope:)`。

- [ ] **Step 3: 实现状态容器并演进唯一 coordinator**

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

把 Provider Task 6 的 coordinator 原地演进为以下唯一实现；不新增第二个 cache helper：

```swift
import Foundation

struct JSONLUnscopedCacheScope: Sendable, Equatable {
    static let shared = JSONLUnscopedCacheScope()

    private init() {}
}

/// 统一协调 scanner 已列出文件的 snapshot、state cache、last-good 与 prune。
/// Provider 只通过 build/project closure 定义状态迁移和候选投影。
final class JSONLLastGoodCacheCoordinator<
    State: Sendable,
    Scope: Sendable & Equatable
>: @unchecked Sendable {
    private struct CachedFile {
        let metadata: JSONLFileMetadata
        let scope: Scope
        let state: State
    }

    private let fileReader: any JSONLFileReading
    private let lock = NSLock()
    private var cachedFiles: [String: CachedFile] = [:]
    private var cacheHitCount = 0

    init(fileReader: any JSONLFileReading) {
        self.fileReader = fileReader
    }

    var debugCachedFileCount: Int {
        withLock { cachedFiles.count }
    }

    var debugCacheHitCount: Int {
        withLock { cacheHitCount }
    }

    /// 返回同 scope 的只读 state 副本，供 parser 的定向 debug accessor 转发。
    func cachedState(for key: String, scope: Scope) -> State? {
        withLock {
            guard let cached = cachedFiles[key], cached.scope == scope else {
                return nil
            }
            return cached.state
        }
    }

    /// 这是唯一 listed-file 协调循环。只有 build 完整成功才原子替换 state；
    /// 失败时只投影同 scope last-good，scanner 未列出的 key 在本轮末尾 prune。
    func loadListedFiles<FileInfo, Candidate: Sendable>(
        _ files: [FileInfo],
        scope: Scope,
        cacheKey: (FileInfo) -> String,
        urlForFile: (FileInfo) -> URL,
        build: (FileInfo, JSONLFileSnapshot, State?) throws -> State,
        project: (State) -> [Candidate],
        onFailure: (FileInfo, Error, Bool) -> Void
    ) -> [Candidate] {
        var allCandidates: [Candidate] = []
        var listedKeys: Set<String> = []

        for fileInfo in files {
            let key = cacheKey(fileInfo)
            listedKeys.insert(key)

            do {
                let snapshot = try fileReader.openSnapshot(
                    for: urlForFile(fileInfo)
                )
                defer { snapshot.stream.close() }

                if let unchanged = unchangedState(
                    for: key,
                    matching: snapshot.metadata,
                    scope: scope
                ) {
                    allCandidates.append(contentsOf: project(unchanged))
                    continue
                }

                let previous = cachedState(for: key, scope: scope)
                let next = try build(fileInfo, snapshot, previous)
                store(
                    next,
                    metadata: snapshot.metadata,
                    scope: scope,
                    for: key
                )
                allCandidates.append(contentsOf: project(next))
            } catch {
                let lastGood = cachedState(for: key, scope: scope)
                if let lastGood {
                    allCandidates.append(contentsOf: project(lastGood))
                }
                onFailure(fileInfo, error, lastGood != nil)
            }
        }

        prune(keeping: listedKeys)
        return allCandidates
    }

    private func unchangedState(
        for key: String,
        matching metadata: JSONLFileMetadata,
        scope: Scope
    ) -> State? {
        withLock {
            guard metadata.identity != nil,
                  let cached = cachedFiles[key],
                  cached.metadata == metadata,
                  cached.scope == scope else {
                return nil
            }
            cacheHitCount += 1
            return cached.state
        }
    }

    private func store(
        _ state: State,
        metadata: JSONLFileMetadata,
        scope: Scope,
        for key: String
    ) {
        withLock {
            cachedFiles[key] = CachedFile(
                metadata: metadata,
                scope: scope,
                state: state
            )
        }
    }

    private func prune(keeping listedKeys: Set<String>) {
        withLock {
            cachedFiles = cachedFiles.filter { listedKeys.contains($0.key) }
        }
    }

    @discardableResult
    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
```

为保证 Task 1 自身可编译提交，先把 Provider Task 6 的两个 parser 机械迁移到“候选数组作为 state”的新 API；Task 2/4 再分别把 state 换成真正的增量 state。Claude 完整装配为：

```swift
private let fileReader: any JSONLFileReading
private let cacheCoordinator: JSONLLastGoodCacheCoordinator<
    [ParsedUsageEntry],
    JSONLUnscopedCacheScope
>

init(fileReader: any JSONLFileReading = SystemJSONLFileReader()) {
    self.fileReader = fileReader
    self.cacheCoordinator = JSONLLastGoodCacheCoordinator<
        [ParsedUsageEntry],
        JSONLUnscopedCacheScope
    >(fileReader: fileReader)
}

func parseAllFiles(
    _ files: [ClaudeJSONLFileInfo],
    claudeDataRoot: URL
) throws -> [ParsedUsageEntry] {
    let allCandidates: [ParsedUsageEntry] = cacheCoordinator.loadListedFiles(
        files,
        scope: .shared,
        cacheKey: { Self.cacheKey(for: $0.url) },
        urlForFile: { $0.url },
        build: { [self] fileInfo, snapshot, _ in
            try parseJSONLStream(
                snapshot.stream,
                fileInfo: fileInfo,
                claudeDataRoot: claudeDataRoot
            )
        },
        project: { $0 },
        onFailure: { [self] fileInfo, error, reusedLastGood in
            if reusedLastGood {
                logger.warning(
                    "文件暂时不可读，复用上次成功结果: \(fileInfo.url.lastPathComponent) — \(error.localizedDescription)"
                )
            } else {
                logger.warning(
                    "文件首次读取失败，跳过: \(fileInfo.url.lastPathComponent) — \(error.localizedDescription)"
                )
            }
        }
    )
    return ClaudeUsageDeduplicator.deduplicate(allCandidates)
}
```

Codex 同步机械迁移，`CodexPricingSpeed` 仍是 coordinator scope：

```swift
private let fileReader: any JSONLFileReading
private let cacheCoordinator: JSONLLastGoodCacheCoordinator<
    [CodexUsageCandidate],
    CodexPricingSpeed
>

init(fileReader: any JSONLFileReading = SystemJSONLFileReader()) {
    self.fileReader = fileReader
    self.cacheCoordinator = JSONLLastGoodCacheCoordinator<
        [CodexUsageCandidate],
        CodexPricingSpeed
    >(fileReader: fileReader)
}

func parseAllFiles(
    _ files: [CodexRolloutFileInfo],
    pricingSpeed: CodexPricingSpeed = .standard
) throws -> [ParsedUsageEntry] {
    let allCandidates: [CodexUsageCandidate] = cacheCoordinator.loadListedFiles(
        files,
        scope: pricingSpeed,
        cacheKey: { Self.cacheKey(for: $0.url) },
        urlForFile: { $0.url },
        build: { [self] fileInfo, snapshot, _ in
            try parseCandidates(
                snapshot.stream,
                metadata: snapshot.metadata,
                fileInfo: fileInfo,
                pricingSpeed: pricingSpeed
            )
        },
        project: { $0 },
        onFailure: { [self] fileInfo, error, reusedLastGood in
            if reusedLastGood {
                logger.warning(
                    "文件暂时不可读，复用上次成功结果: \(fileInfo.url.lastPathComponent) — \(error.localizedDescription)"
                )
            } else {
                logger.warning(
                    "文件首次读取失败，跳过: \(fileInfo.url.lastPathComponent) — \(error.localizedDescription)"
                )
            }
        }
    )

    var seen: Set<CodexEventDedupKey> = []
    return allCandidates.compactMap { candidate in
        guard seen.insert(candidate.dedupKey).inserted else { return nil }
        return candidate.entry
    }
}
```

- [ ] **Step 4: 运行状态、coordinator 与两个 parser suites**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/IncrementalJSONLFileStateTests -only-testing:TokenWatchTests/JSONLLastGoodCacheCoordinatorTests -only-testing:TokenWatchTests/ClaudeJSONLParserTests -only-testing:TokenWatchTests/CodexRolloutParserTests -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: PASS；迁移/anchor 断言通过，coordinator 的 previous-state build、projection、unchanged hit、scope-sensitive last-good、原子替换与 prune 仍由一个 suite 锁定，两个 parser 在候选数组 state 的过渡形态下无回归。

- [ ] **Step 5: 提交通用状态与 coordinator 演进**

```bash
git add TokenWatch/Providers/IncrementalJSONLFileState.swift \
  TokenWatch/Providers/JSONLLastGoodCacheCoordinator.swift \
  TokenWatch/Providers/Claude/ClaudeJSONLParser.swift \
  TokenWatch/Providers/Codex/CodexRolloutParser.swift \
  TokenWatchTests/Providers/IncrementalJSONLFileStateTests.swift \
  TokenWatchTests/Providers/JSONLLastGoodCacheCoordinatorTests.swift
git commit -m "refactor(parser): 让共享缓存协调器承载增量状态"
```

### Task 2: Claude 追加、provisional tail 与重建

**Files:**
- Modify: `TokenWatch/Providers/Claude/ClaudeJSONLParser.swift`
- Modify: `TokenWatchTests/Providers/Claude/ClaudeJSONLParserTests.swift`

**Interfaces:**
- Consumes: Task 1 的 `JSONLLastGoodCacheCoordinator<State, Scope>.loadListedFiles(...build:project:onFailure:)`、`cachedState(for:scope:)`、`RecordingJSONLFileReader` 与 `IncrementalJSONLFileState<ParsedUsageEntry, StatelessJSONLCheckpoint>`。
- Produces: coordinator payload `ClaudeFileState`；既有 `parseJSONLFile` 和 `parseAllFiles` 签名保持可用；append、provisional commit、truncate/replace/touch rebuild 与 fresh full scan 的 deep snapshot 完全一致。Claude parser 不拥有 cache dictionary、lock、per-file catch 或 prune。

- [ ] **Step 1: 写 unchanged、append、provisional、replacement 与 rebuild 失败测试**

```swift
@Test("Claude 未变化文件零读取，追加从 committed offset 开始")
func appendReadsOnlySuffix() throws {
    let fixture = try makeClaudeFixture()
    defer { fixture.cleanup() }
    let reader = RecordingJSONLFileReader()
    let parser = ClaudeJSONLParser(fileReader: reader)
    // 该性能用例必须使用完整 committed prefix <= 256 bytes 的有效 compact 行。
    let firstLine = Self.minimalAssistantLine(messageId: "m1", inputTokens: 10)
    try (firstLine + "\n").write(to: fixture.file.url, atomically: false, encoding: .utf8)

    let first = try parser.parseAllFiles([fixture.file], claudeDataRoot: fixture.root)
    let committedOffset = UInt64((firstLine + "\n").utf8.count)
    #expect(first.count == 1)

    reader.resetMetrics()
    _ = try parser.parseAllFiles([fixture.file], claudeDataRoot: fixture.root)
    #expect(reader.openCount == 1)
    #expect(reader.totalBytesRead == 0)
    #expect(reader.seekOffsets.isEmpty)

    let secondLine = Self.minimalAssistantLine(messageId: "m2", inputTokens: 20)
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

同一步先加入所有将由增量 state 实现的边界测试，不能等生产读取循环已经处理 provisional/rebuild 后再补测试：

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

- [ ] **Step 2: 运行完整 Claude parser suite 并确认真实 RED**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/ClaudeJSONLParserTests -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: FAIL；当前 parser 的 append metrics 仍显示从 0 读取，且尚无 committed offset/continuity anchor state，provisional checkpoint 与 truncate/replace rebuild 断言不能全部通过。这一 RED 必须在 Step 3 的读取循环和 cache state 改动前观察到。

- [ ] **Step 3: 将 Claude 文件缓存改为增量 raw candidate 状态**

将 Task 1 的候选数组过渡 state 换成真正的 Claude state；parser 仍把同一个 reader 交给唯一 coordinator：

```swift
private typealias ClaudeFileState = IncrementalJSONLFileState<ParsedUsageEntry, StatelessJSONLCheckpoint>

private let fileReader: any JSONLFileReading
private let cacheCoordinator: JSONLLastGoodCacheCoordinator<
    ClaudeFileState,
    JSONLUnscopedCacheScope
>

init(fileReader: any JSONLFileReading = SystemJSONLFileReader()) {
    self.fileReader = fileReader
    self.cacheCoordinator = JSONLLastGoodCacheCoordinator<
        ClaudeFileState,
        JSONLUnscopedCacheScope
    >(fileReader: fileReader)
}

var debugCachedFileCount: Int {
    cacheCoordinator.debugCachedFileCount
}

var debugCacheHitCount: Int {
    cacheCoordinator.debugCacheHitCount
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

provider-specific build closure 使用 coordinator 传入的同 scope previous state 计算 transition；它不读取或写入任何 cache 容器：

```swift
private func buildClaudeState(
    fileInfo: ClaudeJSONLFileInfo,
    snapshot: JSONLFileSnapshot,
    previous: ClaudeFileState?
) throws -> ClaudeFileState {
    func rebuild() throws -> ClaudeFileState {
        try readCandidates(
            from: fileInfo,
            snapshot: snapshot,
            startOffset: 0,
            stablePrefix: [],
            previousAnchor: .empty
        )
    }

    guard let previous else { return try rebuild() }
    switch IncrementalJSONLTransition.decide(
        previous: previous,
        newMetadata: snapshot.metadata
    ) {
    case .reuse:
        return previous
    case .append(let startOffset):
        let anchorCoversCommittedPrefix = previous.continuityAnchor.offset == 0
            && UInt64(previous.continuityAnchor.bytes.count) == previous.committedOffset
        guard anchorCoversCommittedPrefix,
              try previous.continuityAnchor.matches(in: snapshot.stream) else {
            return try rebuild()
        }
        return try readCandidates(
            from: fileInfo,
            snapshot: snapshot,
            startOffset: startOffset,
            stablePrefix: previous.stableCandidates,
            previousAnchor: previous.continuityAnchor
        )
    case .rebuild:
        return try rebuild()
    }
}
```

`parseAllFiles` 只提供 cache key、scope、state build、candidate projection、日志与最终 Claude 去重；open/hit/store/catch/prune 全部留在 coordinator：

```swift
func parseAllFiles(
    _ files: [ClaudeJSONLFileInfo],
    claudeDataRoot: URL
) throws -> [ParsedUsageEntry] {
    let allCandidates: [ParsedUsageEntry] = cacheCoordinator.loadListedFiles(
        files,
        scope: .shared,
        cacheKey: { Self.cacheKey(for: $0.url) },
        urlForFile: { $0.url },
        build: { [self] fileInfo, snapshot, previous in
            try buildClaudeState(
                fileInfo: fileInfo,
                snapshot: snapshot,
                previous: previous
            )
        },
        project: \.returnedCandidates,
        onFailure: { [self] fileInfo, error, reusedLastGood in
            if reusedLastGood {
                logger.warning(
                    "文件暂时不可读，复用上次成功结果: \(fileInfo.url.lastPathComponent) — \(error.localizedDescription)"
                )
            } else {
                logger.warning(
                    "文件首次读取失败，跳过: \(fileInfo.url.lastPathComponent) — \(error.localizedDescription)"
                )
            }
        }
    )
    return ClaudeUsageDeduplicator.deduplicate(allCandidates)
}
```

I/O debug accessor 只读转发 coordinator state：

```swift
func debugCommittedOffset(for url: URL) -> UInt64? {
    let key = Self.cacheKey(for: url)
    return cacheCoordinator.cachedState(
        for: key,
        scope: .shared
    )?.committedOffset
}

func debugContinuityAnchor(for url: URL) -> JSONLContinuityAnchor? {
    let key = Self.cacheKey(for: url)
    return cacheCoordinator.cachedState(
        for: key,
        scope: .shared
    )?.continuityAnchor
}
```

下一次 `.append(fromOffset:)` 由 build closure 丢弃旧 provisional 数组，从 committed offset 重新解析 tail + suffix；`.rebuild` 从空 stable candidates 开始。build 抛错时 coordinator 保留并投影 last-good state，成功返回后才原子替换；scanner 未列出的 key 仍由同一 coordinator prune。

- [ ] **Step 4: 运行 Claude、去重器和通用状态 suites**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/JSONLLastGoodCacheCoordinatorTests -only-testing:TokenWatchTests/ClaudeJSONLParserTests -only-testing:TokenWatchTests/ClaudeUsageDeduplicatorTests -only-testing:TokenWatchTests/IncrementalJSONLFileStateTests -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: PASS；deep snapshot、offset/read byte count、provisional commit、rebuild、scope-compatible last-good、prune 与 sidechain replacement 全部通过，coordinator suite 继续证明 cache lifecycle 只有一个实现。

- [ ] **Step 5: 提交 Claude 增量边界**

```bash
git add TokenWatch/Providers/Claude/ClaudeJSONLParser.swift TokenWatchTests/Providers/Claude/ClaudeJSONLParserTests.swift
git commit -m "perf(claude): 增量解析 JSONL 边界"
```

### Task 3: 抽出可保存的 Codex 行级 checkpoint

**Files:**
- Create: `TokenWatch/Providers/Codex/CodexRolloutParsingState.swift`
- Create: `TokenWatchTests/Providers/Codex/CodexRolloutParsingStateTests.swift`
- Modify: `TokenWatch/Providers/Codex/CodexRolloutParser.swift`

**Interfaces:**
- Consumes: 数据计划的 `CodexUsageCandidate`、`CodexEventDedupKey`、normalized timestamp/model/token helper，以及 `CodexModelState`、`CodexPricingSpeed`、`CodexTokenCounts?`。
- Produces: `CodexParserCheckpoint.consume(_:sourceOffset:pricingSpeed:) -> CodexUsageCandidate?`；`CodexPricingSpeed` 只映射到 `TokenUsage.serviceTier`，`TokenUsage.speed` 对 Codex 始终为空；session token_count 无合法 timestamp 时返回 nil，byte offset 只用于有 timestamp candidate 的本地 record UUID。

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
        let pricingSpeed = CodexPricingSpeed.standard
        let lines = [
            #"{"timestamp":"2026-05-04T08:35:44Z","type":"session_meta","payload":{"id":"meta-session","cwd":"/tmp/project","model_provider":"openai"}}"#,
            #"{"timestamp":"2026-05-04T08:35:45Z","type":"turn_context","payload":{"model":"gpt-5.4"}}"#,
            #"{"timestamp":"2026-05-04T08:35:46Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":300,"output_tokens":200,"reasoning_output_tokens":0,"total_tokens":1200}}}}"#
        ]
        let firstCandidates = try lines.enumerated().compactMap { index, line -> CodexUsageCandidate? in
            let record = try decoder.decode(CodexRecord.self, from: Data(line.utf8))
            return checkpoint.consume(
                record,
                sourceOffset: UInt64(index),
                pricingSpeed: pricingSpeed
            )
        }
        #expect(firstCandidates.count == 1)

        var restored = checkpoint
        let next = #"{"timestamp":"2026-05-04T08:36:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1600,"cached_input_tokens":500,"output_tokens":260,"reasoning_output_tokens":0,"total_tokens":1860}}}}"#
        let record = try decoder.decode(CodexRecord.self, from: Data(next.utf8))
        let entry = try #require(
            restored.consume(
                record,
                sourceOffset: 3,
                pricingSpeed: pricingSpeed
            )?.entry
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
                pricingSpeed: .standard
            )
            #expect(candidate?.entry == nil)
        }
        let firstRecord = try decoder.decode(CodexRecord.self, from: Data(first.utf8))
        let repeatedRecord = try decoder.decode(CodexRecord.self, from: Data(repeated.utf8))
        let emitted = [
            checkpoint.consume(firstRecord, sourceOffset: 2, pricingSpeed: .standard),
            checkpoint.consume(repeatedRecord, sourceOffset: 3, pricingSpeed: .standard),
        ].compactMap { $0?.entry }

        #expect(emitted.count == 2)
        #expect(emitted.allSatisfy { $0.model == "gpt-5" })
        #expect(emitted.allSatisfy { $0.usage.inputTokens == 0 })
        #expect(emitted.allSatisfy { $0.usage.cacheReadInputTokens == 100 })
    }

    @Test("Codex fast 只写 serviceTier，不污染 Claude usage.speed")
    func pricingSpeedMapsOnlyToServiceTier() throws {
        let decoder = JSONDecoder()
        var checkpoint = CodexParserCheckpoint.initial(
            sessionID: "session",
            replaySecond: nil
        )
        let turn = #"{"timestamp":"2026-05-04T08:35:44.000Z","type":"turn_context","payload":{"model":"gpt-5.4"}}"#
        let event = #"{"timestamp":"2026-05-04T08:35:46.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":20,"output_tokens":1,"reasoning_output_tokens":0,"total_tokens":101}}}}"#
        let turnRecord = try decoder.decode(CodexRecord.self, from: Data(turn.utf8))
        let eventRecord = try decoder.decode(CodexRecord.self, from: Data(event.utf8))
        _ = checkpoint.consume(
            turnRecord,
            sourceOffset: 0,
            pricingSpeed: .fast
        )
        let entry = try #require(checkpoint.consume(
            eventRecord,
            sourceOffset: 1,
            pricingSpeed: .fast
        )?.entry)

        #expect(entry.usage.serviceTier == "fast")
        #expect(entry.usage.speed.isEmpty)
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
            pricingSpeed: .standard
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
        pricingSpeed: CodexPricingSpeed
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
                pricingSpeed: pricingSpeed
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

extension CodexUsageCandidate {
    static func make(
        sessionID: String,
        timestamp: CodexNormalizedTimestamp,
        sourceOffset: UInt64,
        model: String,
        cwd: String?,
        counts: CodexTokenCounts,
        pricingSpeed: CodexPricingSpeed
    ) -> CodexUsageCandidate {
        let normalized = counts.normalizedForBilling
        let messageID = "\(sessionID):\(timestamp.key)"
        let recordUUID = "\(messageID):\(sourceOffset)"
        let usage = TokenUsage(
            inputTokens: normalized.pureInput,
            cacheCreationInputTokens: 0,
            cacheReadInputTokens: normalized.cachedInput,
            outputTokens: normalized.output,
            reasoningTokens: normalized.reasoning,
            serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
            serviceTier: pricingSpeed == .fast ? "fast" : "",
            cacheCreation: nil,
            inferenceGeo: "",
            iterations: [],
            speed: ""
        )
        let entry = ParsedUsageEntry(
            recordUUID: recordUUID,
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

`CodexRolloutParser.parseFile` 改为创建 checkpoint，并把每条 line 的绝对起始 byte offset 与 `pricingSpeed` 传给 `consume`，不保留第二套状态机。Codex fast/priority 的唯一持久化表达是 `usage.serviceTier`；不得把配置值复制到 Claude 专用的 `usage.speed`。

- [ ] **Step 4: 运行 reducer 与既有 Codex parser suites**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/CodexRolloutParsingStateTests -only-testing:TokenWatchTests/CodexRolloutParserTests -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: PASS，现有模型切换、fallback 和 delta 测试无回归；repeated total + nonzero last 仍 emit，四维全零不污染 model，cached clamp、timestamp 和 replay baseline 保持数据计划契约；fast entry 的 `serviceTier == "fast"` 且 `speed.isEmpty`。

- [ ] **Step 5: 提交 Codex reducer**

```bash
git add TokenWatch/Providers/Codex/CodexRolloutParsingState.swift TokenWatch/Providers/Codex/CodexRolloutParser.swift TokenWatchTests/Providers/Codex/CodexRolloutParsingStateTests.swift
git commit -m "refactor(codex): 抽出可恢复的 rollout 状态"
```

### Task 4: Codex 追加、provisional、replay 与重建

**Files:**
- Modify: `TokenWatch/Providers/Codex/CodexRolloutParser.swift`
- Modify: `TokenWatchTests/Providers/Codex/CodexRolloutParserTests.swift`

**Interfaces:**
- Consumes: Task 1 的 `JSONLLastGoodCacheCoordinator<State, CodexPricingSpeed>`、`IncrementalJSONLFileState<CodexUsageCandidate, CodexParserCheckpoint>`、data plan 的 replay/last-good 语义与 deep snapshot helper。
- Produces: coordinator payload `CodexIncrementalState`（replay classification + file state）；保留 `pricingSpeed:` 标签的 `parseAllFiles`，由 coordinator scope 负责 tier-sensitive hit/last-good/失效，entry 只更新 `serviceTier` 且 `speed` 为空。Codex parser 不拥有 cache dictionary、lock、per-file catch 或 prune。

- [ ] **Step 1: 写 append checkpoint、provisional、replay 与 rebuild 失败测试**

```swift
@Test("Codex append 从 committed checkpoint 恢复")
func appendReadsOnlySuffixAndRestoresCheckpoint() throws {
    // 保持首轮 committed prefix <= 256 bytes，才能被完整 anchor 证明连续。
    let compactInitialEvent = #"{"timestamp":"2026-05-04T08:35:46Z","type":"event_msg","payload":{"type":"token_count","model":"gpt-5","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":300,"output_tokens":200}}}}"#
    let fixture = try makeRolloutFixture(lines: [compactInitialEvent])
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

同一步先加入所有将由增量 cache 实现的边界测试；metadata/read failure、prune 和 unchanged 零读取继续复用数据计划已经落地的测试：

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
        incremental.debugContinuityAnchor(
            for: fixture.file.url,
            pricingSpeed: .fast
        )
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

@Test(arguments: ["truncate", "truncate-grow", "replace", "touch", "service-tier"])
func codexRebuildTransitionsMatchFreshScan(kind: String) throws {
    let fixture = try makeRolloutFixture(lines: [sessionMeta, turnContextGpt5, normalEvent])
    defer { fixture.cleanup() }
    let reader = RecordingJSONLFileReader()
    let parser = CodexRolloutParser(fileReader: reader)
    _ = try parser.parseAllFiles([fixture.file], pricingSpeed: .standard)

    let truncated = [sessionMeta, turnContextGpt55, normalEvent].joined(separator: "\n") + "\n"
    let replacement = [sessionMeta, turnContextGpt55, normalEvent].joined(separator: "\n") + "\n"
    var pricingSpeed = CodexPricingSpeed.standard
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
    case "service-tier":
        pricingSpeed = .fast
    default:
        Issue.record("unexpected transition kind")
    }

    reader.resetMetrics()
    let incremental = try parser.parseAllFiles([fixture.file], pricingSpeed: pricingSpeed)
    let fresh = try CodexRolloutParser().parseAllFiles([fixture.file], pricingSpeed: pricingSpeed)
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

- [ ] **Step 2: 运行完整 Codex parser suite 并确认真实 RED**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/CodexRolloutParserTests -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: FAIL；append metrics 仍显示从 0 读取，且尚无 committed checkpoint/provisional isolation、pending→replay rebuild 与 service-tier cache invalidation。该 suite 必须在 Step 3 修改 cache/read loop 前观察到至少一个上述语义或 I/O 断言失败。

- [ ] **Step 3: 将 Codex coordinator payload 改为带 checkpoint 的增量状态**

```swift
private typealias CodexFileState = IncrementalJSONLFileState<CodexUsageCandidate, CodexParserCheckpoint>

private struct CodexReplayDecision: Sendable {
    let classification: CodexReplayClassification
    let isStableUnderAppend: Bool
}

private struct CodexIncrementalState: Sendable {
    let replayClassification: CodexReplayClassification
    let replayClassificationIsStableUnderAppend: Bool
    let fileState: CodexFileState

    var returnedCandidates: [CodexUsageCandidate] {
        fileState.returnedCandidates
    }
}

private let fileReader: any JSONLFileReading
private let cacheCoordinator: JSONLLastGoodCacheCoordinator<
    CodexIncrementalState,
    CodexPricingSpeed
>

init(fileReader: any JSONLFileReading = SystemJSONLFileReader()) {
    self.fileReader = fileReader
    self.cacheCoordinator = JSONLLastGoodCacheCoordinator<
        CodexIncrementalState,
        CodexPricingSpeed
    >(fileReader: fileReader)
}

var debugCachedFileCount: Int {
    cacheCoordinator.debugCachedFileCount
}

var debugCacheHitCount: Int {
    cacheCoordinator.debugCacheHitCount
}
```

读取完整行时对可变 checkpoint 调 `consume(record, sourceOffset: lineStartOffset, pricingSpeed: pricingSpeed)`，每消费一个以换行结束的 line 后更新 `checkpointAtCommittedOffset`。处理 EOF tail 时必须复制 checkpoint：

```swift
var provisionalCheckpoint = committedCheckpoint
let provisionalCandidates = parseRecord(buffer).flatMap {
    provisionalCheckpoint.consume(
        $0,
        sourceOffset: committedOffset,
        pricingSpeed: pricingSpeed
    )
}.map { [$0] } ?? []
```

返回 file state 时保存 `committedCheckpoint`，不能保存 `provisionalCheckpoint`。coordinator 的 build closure 获得同 `pricingSpeed` scope 的 previous `CodexIncrementalState`；provider 只负责 content transition、anchor 与 replay classification：

```swift
private func buildCodexState(
    fileInfo: CodexRolloutFileInfo,
    snapshot: JSONLFileSnapshot,
    previous: CodexIncrementalState?,
    pricingSpeed: CodexPricingSpeed
) throws -> CodexIncrementalState {
    let previousFileState = previous?.fileState
    let contentTransition = previousFileState.map {
        IncrementalJSONLTransition.decide(
            previous: $0,
            newMetadata: snapshot.metadata
        )
    } ?? .rebuild

    let anchorMatches: Bool
    if case .append = contentTransition, let previousFileState {
        let anchor = previousFileState.continuityAnchor
        let anchorCoversCommittedPrefix = anchor.offset == 0
            && UInt64(anchor.bytes.count) == previousFileState.committedOffset
        anchorMatches = anchorCoversCommittedPrefix
            && (try anchor.matches(in: snapshot.stream))
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

    let replayDecision: CodexReplayDecision
    if let previous,
       contentCanReuseClassification,
       previous.replayClassificationIsStableUnderAppend {
        replayDecision = CodexReplayDecision(
            classification: previous.replayClassification,
            isStableUnderAppend: true
        )
    } else {
        replayDecision = try CodexReplayDetector.classify(snapshot: snapshot)
    }
    let replayClassification = replayDecision.classification
    let replaySecond = replayClassification.replaySecond
    let reusableFileState: CodexFileState? = {
        guard let previousFileState,
              contentCanReuseClassification,
              previousFileState.checkpointAtCommittedOffset.replaySecond == replaySecond else {
            return nil
        }
        return previousFileState
    }()
    let effectiveTransition = reusableFileState == nil ? .rebuild : contentTransition
    let nextFileState = try buildCodexFileState(
        fileInfo: fileInfo,
        snapshot: snapshot,
        previous: reusableFileState,
        transition: effectiveTransition,
        replaySecond: replaySecond,
        pricingSpeed: pricingSpeed
    )
    return CodexIncrementalState(
        replayClassification: replayClassification,
        replayClassificationIsStableUnderAppend: replayDecision.isStableUnderAppend,
        fileState: nextFileState
    )
}
```

config 从 standard 切到 fast 时 coordinator 以 scope 不匹配向 build 传 `previous == nil`，因此从 0 重建并更新所有 entry 的 `usage.serviceTier`，同时 `usage.speed` 继续为空；parser 不再自行比较或存储 pricing scope。

`CodexReplayDetector.classify` 返回 `CodexReplayDecision` 并复用数据计划的 pinned 规则。对带 marker 但尚不足两条 usage 的文件返回不稳定 `.pending`；第二条同秒 usage 追加后分类从 pending 变为稳定 replay，replaySecond 不匹配会令 `reusableFileState == nil` 并从 0 重建，撤销上一轮 provisional/stable 的第一条历史 candidate。没有 marker 且 probe window 尚短于 16 KiB 的 `.notReplay` 也必须标记为不稳定。

`buildCodexFileState` 与底层读取循环只构建 provider state，确保每个完整行之后的 checkpoint 与 committed offset 同步推进：

```swift
private func buildCodexFileState(
    fileInfo: CodexRolloutFileInfo,
    snapshot: JSONLFileSnapshot,
    previous: CodexFileState?,
    transition: IncrementalJSONLTransition,
    replaySecond: String?,
    pricingSpeed: CodexPricingSpeed
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
            pricingSpeed: pricingSpeed
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
            pricingSpeed: pricingSpeed
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
    pricingSpeed: CodexPricingSpeed
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
                    pricingSpeed: pricingSpeed
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
            pricingSpeed: pricingSpeed
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

`parseRecord(_:)` 只负责 `JSONDecoder` 解码非空单行并返回 optional `CodexRecord`；无效行仍算已提交字节，但不能改变 checkpoint。snapshot metadata、replay 分类、anchor/seek/read 与完整 state build 任一步抛错时，coordinator 不 store，并按 `CodexPricingSpeed` scope 投影 last-good。

`parseAllFiles` 只提供 state build/projection、日志和最终 first-wins 去重：

```swift
func parseAllFiles(
    _ files: [CodexRolloutFileInfo],
    pricingSpeed: CodexPricingSpeed = .standard
) throws -> [ParsedUsageEntry] {
    let allCandidates: [CodexUsageCandidate] = cacheCoordinator.loadListedFiles(
        files,
        scope: pricingSpeed,
        cacheKey: { Self.cacheKey(for: $0.url) },
        urlForFile: { $0.url },
        build: { [self] fileInfo, snapshot, previous in
            try buildCodexState(
                fileInfo: fileInfo,
                snapshot: snapshot,
                previous: previous,
                pricingSpeed: pricingSpeed
            )
        },
        project: \.returnedCandidates,
        onFailure: { [self] fileInfo, error, reusedLastGood in
            if reusedLastGood {
                logger.warning(
                    "文件暂时不可读，复用上次成功结果: \(fileInfo.url.lastPathComponent) — \(error.localizedDescription)"
                )
            } else {
                logger.warning(
                    "文件首次读取失败，跳过: \(fileInfo.url.lastPathComponent) — \(error.localizedDescription)"
                )
            }
        }
    )

    var seen: Set<CodexEventDedupKey> = []
    return allCandidates.compactMap { candidate in
        guard seen.insert(candidate.dedupKey).inserted else { return nil }
        return candidate.entry
    }
}

func debugContinuityAnchor(
    for url: URL,
    pricingSpeed: CodexPricingSpeed = .standard
) -> JSONLContinuityAnchor? {
    cacheCoordinator.cachedState(
        for: Self.cacheKey(for: url),
        scope: pricingSpeed
    )?.fileState.continuityAnchor
}
```

不能把 per-file 最终 entries 直接 append 到旧去重结果，也不能丢掉 candidate 中的 source total/reasoning/timestamp key。parser 只读转发 coordinator state，不访问 coordinator 内部 dictionary 或 lock。

- [ ] **Step 4: 运行两个 parser 的完整定向回归**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/IncrementalJSONLFileStateTests -only-testing:TokenWatchTests/JSONLFileReaderTests -only-testing:TokenWatchTests/JSONLLastGoodCacheCoordinatorTests -only-testing:TokenWatchTests/ClaudeJSONLParserTests -only-testing:TokenWatchTests/ClaudeUsageDeduplicatorTests -only-testing:TokenWatchTests/CodexRolloutParsingStateTests -only-testing:TokenWatchTests/CodexRolloutParserTests -skip-testing:TokenWatchUITests -derivedDataPath .build/DerivedData CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- test
```

Expected: PASS；所有 deep snapshot、offset/read byte count、tail、pending→replay rebuild、scope-sensitive last-good/prune、service-tier cache invalidation 与 `usage.speed.isEmpty` 断言通过；coordinator suite 证明 state 生命周期仍只有一个实现。

- [ ] **Step 5: 提交 Codex 增量边界**

```bash
git add TokenWatch/Providers/Codex/CodexRolloutParser.swift TokenWatchTests/Providers/Codex/CodexRolloutParserTests.swift
git commit -m "perf(codex): 增量解析 rollout 边界"
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
- committed prefix <= 256 bytes 的普通追加：先 seek/read 覆盖整个 prefix 的 continuity anchor，再 seek committed offset 并只读 provisional tail + suffix；解析新 candidate 的起点仍是 committed offset。
- committed prefix > 256 bytes 的普通追加：有界 anchor 不能证明整个历史未被同 inode 重写，因此 correctness-first seek 0 全量重建。
- Codex replay `.pending` 文件：允许为重新分类额外读取 pinned replay probe；只有完整 committed prefix 可由 anchor 证明连续时，分类稳定后的追加才走后缀路径。
- 截断、替换、同 size 改写，以及同 inode truncate 后重写成更大文件：最终 seek 0 全量重建；不得因 suffix anchor 碰撞复用旧 candidate/checkpoint。
- Claude/Codex 的 incremental 与 fresh full scan deep snapshots 完全一致。
- `git status --short` 只包含本计划预期文件，且每个任务已有独立中文 commit。
