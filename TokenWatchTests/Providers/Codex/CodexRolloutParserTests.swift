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
        let cleanup: () -> Void = { try? FileManager.default.removeItem(at: dir) }
        return (info, cleanup)
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
        #expect(e.usage.cacheCreation == nil)
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

    @Test("parseAllFiles 复用未变化 rollout 缓存,文件变化后失效")
    func parseAllFilesCachesUnchangedRollouts() throws {
        let (file, cleanup) = try makeJsonlFile([sessionMeta, turnContextGpt5, normalEvent])
        defer { cleanup() }

        let parser = CodexRolloutParser()
        let firstEntries = try parser.parseAllFiles([file])
        #expect(firstEntries.count == 1)
        #expect(parser.debugCachedFileCount == 1)

        let hitCountBeforeSecondParse = parser.debugCacheHitCount
        let secondEntries = try parser.parseAllFiles([file])
        #expect(secondEntries.count == 1)
        #expect(parser.debugCacheHitCount == hitCountBeforeSecondParse + 1)

        let secondEvent = #"{"timestamp":"2026-05-04T08:36:30.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":2000,"cached_input_tokens":500,"output_tokens":300,"reasoning_output_tokens":100,"total_tokens":2300}}}}"#
        let changedBody = [sessionMeta, turnContextGpt5, normalEvent, secondEvent].joined(separator: "\n") + "\n"
        try changedBody.write(to: file.url, atomically: true, encoding: .utf8)

        let hitCountBeforeChangedParse = parser.debugCacheHitCount
        let changedEntries = try parser.parseAllFiles([file])
        #expect(changedEntries.count == 2)
        #expect(parser.debugCacheHitCount == hitCountBeforeChangedParse)
    }
}
