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
        #expect(e.usage.cacheCreation == nil)
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

    @Test("tokens.total-only 把全部缺口并入可计费 output")
    func totalOnlyFallsBackToBillableOutput() throws {
        let row = makeRow(
            id: "total-only",
            sessionID: "s",
            timeMs: 0,
            json: #"{"role":"assistant","modelID":"claude-sonnet-4-5","providerID":"anthropic","tokens":{"total":123}}"#,
            directory: "/d"
        )

        let entry = try #require(parser.parseAll([row]).first)
        #expect(entry.usage.inputTokens == 0)
        #expect(entry.usage.cacheReadInputTokens == 0)
        #expect(entry.usage.totalCacheCreationTokens == 0)
        #expect(entry.usage.outputTokens == 123)
        #expect(entry.usage.reasoningTokens == 0)
    }

    @Test("tokens.total 只补 known token 之外的余量，不重复计费")
    func partialTotalAddsOnlyMissingRemainder() throws {
        let row = makeRow(
            id: "partial-total",
            sessionID: "s",
            timeMs: 0,
            json: #"{"role":"assistant","modelID":"claude-sonnet-4-5","providerID":"anthropic","tokens":{"total":200,"input":100,"output":10,"cache":{"read":50,"write":25}}}"#,
            directory: "/d"
        )

        let entry = try #require(parser.parseAll([row]).first)
        #expect(entry.usage.inputTokens == 100)
        #expect(entry.usage.cacheReadInputTokens == 50)
        #expect(entry.usage.totalCacheCreationTokens == 25)
        #expect(entry.usage.outputTokens == 25) // 10 + max(200 - 185, 0)
        #expect(entry.usage.reasoningTokens == 0)
    }

    @Test("复合 UInt64 极值饱和到 Int.max 且 total 不重复补量")
    func saturatesCompositeMaximumTokensWithoutOverflow() throws {
        let row = makeRow(
            id: "maximum-tokens",
            sessionID: "s",
            timeMs: 0,
            json: #"{"role":"assistant","modelID":"claude-sonnet-4-5","providerID":"anthropic","tokens":{"input":18446744073709551615,"output":18446744073709551615,"total":18446744073709551615,"cache":{"read":18446744073709551615,"write":18446744073709551615}}}"#,
            directory: "/d"
        )

        let entry = try #require(parser.parseAll([row]).first)
        #expect(entry.usage.inputTokens == Int.max)
        #expect(entry.usage.outputTokens == Int.max)
        #expect(entry.usage.cacheReadInputTokens == Int.max)
        #expect(entry.usage.totalCacheCreationTokens == Int.max)
    }

    @Test("OpenCode token null 与负数归零且保留其余可用字段")
    func nullAndNegativeTokenFieldsBecomeZero() throws {
        let row = makeRow(
            id: "null-negative",
            sessionID: "s",
            timeMs: 0,
            json: #"{"role":"assistant","modelID":"claude-sonnet-4-5","providerID":"anthropic","cost":0.25,"path":{"cwd":"/valid"},"tokens":{"input":null,"output":10,"reasoning":-1,"total":null,"cache":{"read":-1,"write":null}}}"#,
            directory: "/fallback"
        )

        let entry = try #require(parser.parseAll([row]).first)
        #expect(entry.usage.inputTokens == 0)
        #expect(entry.usage.outputTokens == 10)
        #expect(entry.usage.reasoningTokens == 0)
        #expect(entry.usage.cacheReadInputTokens == 0)
        #expect(entry.usage.totalCacheCreationTokens == 0)
        #expect(entry.upstreamCost == 0.25)
        #expect(entry.cwd == "/valid")
    }

    @Test("OpenCode token 坏类型归零而不丢整行，reasoning-only 不计入")
    func lenientTokenFieldsMatchPinnedAdapter() throws {
        let usable = makeRow(
            id: "usable",
            sessionID: "s",
            timeMs: 0,
            json: #"{"role":"assistant","modelID":" claude-sonnet-4-5 ","providerID":"anthropic","cost":"bad","path":5,"tokens":{"input":"100","output":10,"cache":"bad"}}"#,
            directory: "/d"
        )
        let reasoningOnly = makeRow(
            id: "reasoning-only",
            sessionID: "s",
            timeMs: 1,
            json: #"{"role":"assistant","modelID":"claude-sonnet-4-5","providerID":"anthropic","tokens":{"reasoning":20}}"#,
            directory: "/d"
        )

        let entries = parser.parseAll([usable, reasoningOnly])

        #expect(entries.count == 1)
        #expect(entries.first?.recordUUID == "usable")
        #expect(entries.first?.usage.inputTokens == 0)
        #expect(entries.first?.usage.outputTokens == 10)
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
