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
}
