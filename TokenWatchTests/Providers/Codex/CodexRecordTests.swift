import Testing
import Foundation
@testable import TokenWatch

@Suite("CodexRecord")
struct CodexRecordTests {

    private let decoder = JSONDecoder()

    private func decodeLastUsage(_ usage: String) -> CodexTokenCounts? {
        let json = #"{"timestamp":"2026-05-04T08:35:59.868Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":\#(usage)}}}"#
        guard let record = try? decoder.decode(CodexRecord.self, from: Data(json.utf8)),
              case let .eventMsg(event) = record.payload else {
            return nil
        }
        return event.info?.lastTokenUsage
    }

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

    @Test("event payload 与 info model 均可解码")
    func decodeEventModels() throws {
        let payloadModel = #"{"timestamp":"2026-05-04T08:35:59Z","type":"event_msg","payload":{"type":"token_count","model":"gpt-payload","info":{"model":"gpt-info","last_token_usage":{"input_tokens":1,"output_tokens":1}}}}"#
        let record = try decoder.decode(CodexRecord.self, from: Data(payloadModel.utf8))
        guard case let .eventMsg(event) = record.payload else {
            Issue.record("payload 应为 eventMsg")
            return
        }
        #expect(event.model == "gpt-payload")
        #expect(event.info?.model == "gpt-info")
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

    @Test("RFC3339、Unix 秒与 Unix 毫秒解码为同一时刻")
    func normalizesTimestampRepresentations() throws {
        let expected = try #require(ISO8601DateFormatterHelper.parse("2026-05-04T08:35:59.000Z"))
        let timestamps = [
            #""2026-05-04T08:35:59Z""#,
            "1777883759",
            "1777883759000",
        ]

        for timestamp in timestamps {
            let json = #"{"timestamp":\#(timestamp),"type":"session_meta","payload":{"id":"timestamp-test"}}"#
            guard let record = try? decoder.decode(CodexRecord.self, from: Data(json.utf8)) else {
                Issue.record("timestamp fixture 未解码: \(timestamp)")
                continue
            }
            #expect(record.timestamp == expected)
        }
    }

    @Test("数字 timestamp 严格使用 pinned 分界并饱和极值")
    func normalizesTimestampBoundaryAndExtreme() {
        let fixtures: [(raw: String, expected: String)] = [
            ("10000000000", "2286-11-20T17:46:40.000Z"),
            ("10000000001", "1970-04-26T17:46:40.001Z"),
        ]

        for fixture in fixtures {
            let json = #"{"timestamp":\#(fixture.raw),"type":"session_meta","payload":{"id":"timestamp-boundary"}}"#
            guard let record = try? decoder.decode(CodexRecord.self, from: Data(json.utf8)) else {
                Issue.record("timestamp boundary fixture 未解码: \(fixture.raw)")
                continue
            }
            #expect(record.timestamp == ISO8601DateFormatterHelper.parse(fixture.expected))
        }

        let extremeJSON = #"{"timestamp":18446744073709551615,"type":"session_meta","payload":{"id":"timestamp-extreme"}}"#
        guard let extreme = try? decoder.decode(CodexRecord.self, from: Data(extremeJSON.utf8)) else {
            Issue.record("UInt64.max timestamp 应饱和解码")
            return
        }
        #expect(extreme.timestamp?.timeIntervalSince1970 == Double(Int64.max) / 1_000)
    }

    @Test("usage aliases 按优先级 lossy 解码")
    func decodesUsageAliasesAndLossyNumbers() {
        let fixtures: [(json: String, expected: CodexTokenCounts)] = [
            (
                #"{"input_tokens":1,"prompt_tokens":2,"input":3,"cached_input_tokens":4,"cache_read_input_tokens":5,"cached_tokens":6,"output_tokens":7,"completion_tokens":8,"output":9,"reasoning_output_tokens":10,"reasoning_tokens":11,"total_tokens":12}"#,
                CodexTokenCounts(inputTokens: 1, cachedInputTokens: 4, outputTokens: 7, reasoningOutputTokens: 10, totalTokens: 12)
            ),
            (
                #"{"input_tokens":-1,"prompt_tokens":" 12 ","cached_input_tokens":1.5,"cache_read_input_tokens":" 3 ","output_tokens":true,"completion_tokens":" 4 ","reasoning_output_tokens":"bad","reasoning_tokens":" 5 ","total_tokens":" 24 "}"#,
                CodexTokenCounts(inputTokens: 12, cachedInputTokens: 3, outputTokens: 4, reasoningOutputTokens: 5, totalTokens: 24)
            ),
            (
                #"{"input_tokens":-1,"prompt_tokens":1.5,"input":true,"cached_input_tokens":"bad","cache_read_input_tokens":-2,"cached_tokens":false,"output_tokens":2.5,"completion_tokens":-3,"output":"bad","reasoning_output_tokens":false,"reasoning_tokens":-4}"#,
                .zero
            ),
            (
                #"{"input_tokens":" 20 ","cached_input_tokens":" 4 ","output_tokens":" 5 ","reasoning_output_tokens":" 2 ","total_tokens":" 27 "}"#,
                CodexTokenCounts(inputTokens: 20, cachedInputTokens: 4, outputTokens: 5, reasoningOutputTokens: 2, totalTokens: 27)
            ),
            (
                #"{"input_tokens":18446744073709551615,"cached_input_tokens":"18446744073709551615","output_tokens":1,"reasoning_output_tokens":1,"total_tokens":18446744073709551615}"#,
                CodexTokenCounts(inputTokens: .max, cachedInputTokens: .max, outputTokens: 1, reasoningOutputTokens: 1, totalTokens: .max)
            ),
        ]

        for fixture in fixtures {
            guard let usage = decodeLastUsage(fixture.json) else {
                Issue.record("usage fixture 未解码: \(fixture.json)")
                continue
            }
            #expect(usage == fixture.expected)
        }
    }

    @Test("total 缺失或矛盾的显式零回退为饱和字段和")
    func normalizesTotalTokens() {
        let fixtures: [(json: String, expectedTotal: Int)] = [
            (#"{"input_tokens":10,"output_tokens":5,"reasoning_output_tokens":2}"#, 17),
            (#"{"input_tokens":10,"output_tokens":5,"reasoning_output_tokens":2,"total_tokens":0}"#, 17),
            (#"{"input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":0}"#, 0),
            (#"{"input_tokens":10,"output_tokens":5,"reasoning_output_tokens":2,"total_tokens":1}"#, 1),
            (#"{"input_tokens":18446744073709551615,"output_tokens":1,"reasoning_output_tokens":1}"#, .max),
        ]

        for fixture in fixtures {
            guard let usage = decodeLastUsage(fixture.json) else {
                Issue.record("total fixture 未解码: \(fixture.json)")
                continue
            }
            #expect(usage.totalTokens == fixture.expectedTotal)
        }
    }
}
