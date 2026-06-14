import Foundation
import Testing
@testable import TokenWatch

/// TokenUsage 解码测试
/// 验证 JSONL 中 usage 对象的正确解析
struct TokenUsageDecodingTests {

    // MARK: - TokenUsage 解码

    @Test("解析完整 usage JSON")
    func decodeFullUsage() throws {
        let json = """
        {
            "input_tokens": 5790,
            "cache_creation_input_tokens": 100,
            "cache_read_input_tokens": 10240,
            "output_tokens": 601,
            "server_tool_use": {
                "web_search_requests": 2,
                "web_fetch_requests": 1
            },
            "service_tier": "standard",
            "cache_creation": {
                "ephemeral_1h_input_tokens": 0,
                "ephemeral_5m_input_tokens": 0
            },
            "inference_geo": "",
            "iterations": [],
            "speed": "standard"
        }
        """

        let data = json.data(using: .utf8)!
        let usage = try JSONDecoder().decode(TokenUsage.self, from: data)

        #expect(usage.inputTokens == 5790)
        #expect(usage.cacheCreationInputTokens == 100)
        #expect(usage.cacheReadInputTokens == 10240)
        #expect(usage.outputTokens == 601)
        #expect(usage.serverToolUse.webSearchRequests == 2)
        #expect(usage.serverToolUse.webFetchRequests == 1)
        #expect(usage.serviceTier == "standard")
        #expect(usage.cacheCreation.ephemeral1hInputTokens == 0)
        #expect(usage.cacheCreation.ephemeral5mInputTokens == 0)
        #expect(usage.speed == "standard")
    }

    @Test("解析最小 usage JSON")
    func decodeMinimalUsage() throws {
        let json = """
        {
            "input_tokens": 100,
            "cache_creation_input_tokens": 0,
            "cache_read_input_tokens": 0,
            "output_tokens": 50,
            "server_tool_use": {
                "web_search_requests": 0,
                "web_fetch_requests": 0
            },
            "service_tier": "standard",
            "cache_creation": {
                "ephemeral_1h_input_tokens": 0,
                "ephemeral_5m_input_tokens": 0
            },
            "inference_geo": "",
            "iterations": [],
            "speed": "standard"
        }
        """

        let data = json.data(using: .utf8)!
        let usage = try JSONDecoder().decode(TokenUsage.self, from: data)

        #expect(usage.inputTokens == 100)
        #expect(usage.outputTokens == 50)
        #expect(usage.inputTokens + usage.outputTokens == 150)
    }

    // MARK: - ClaudeRecord 解码

    @Test("解析 assistant 记录含 usage")
    func decodeAssistantRecordWithUsage() throws {
        let json = """
        {
            "type": "assistant",
            "uuid": "test-uuid-123",
            "sessionId": "session-abc",
            "timestamp": "2026-06-13T11:55:26.715Z",
            "message": {
                "id": "msg-1",
                "role": "assistant",
                "model": "deepseek-v4-pro",
                "content": [{"type": "text", "text": "Hello"}],
                "stop_reason": "end_turn",
                "stop_sequence": null,
                "usage": {
                    "input_tokens": 100,
                    "cache_creation_input_tokens": 0,
                    "cache_read_input_tokens": 200,
                    "output_tokens": 50,
                    "server_tool_use": {"web_search_requests": 0, "web_fetch_requests": 0},
                    "service_tier": "standard",
                    "cache_creation": {"ephemeral_1h_input_tokens": 0, "ephemeral_5m_input_tokens": 0},
                    "inference_geo": "",
                    "iterations": [],
                    "speed": "standard"
                }
            }
        }
        """

        let data = json.data(using: .utf8)!
        let record = try JSONDecoder().decode(ClaudeRecord.self, from: data)

        #expect(record.type == "assistant")
        #expect(record.hasUsageData == true)
        #expect(record.message?.model == "deepseek-v4-pro")
        #expect(record.message?.usage?.inputTokens == 100)
        #expect(record.timestamp != nil)
    }

    @Test("解析 user 记录不含 usage")
    func decodeUserRecordWithoutUsage() throws {
        let json = """
        {
            "type": "user",
            "uuid": "test-uuid-456",
            "sessionId": "session-def",
            "timestamp": "2026-06-13T12:00:00Z",
            "message": {
                "id": "msg-2",
                "role": "user",
                "content": [{"type": "text", "text": "Hi"}]
            }
        }
        """

        let data = json.data(using: .utf8)!
        let record = try JSONDecoder().decode(ClaudeRecord.self, from: data)

        #expect(record.type == "user")
        #expect(record.hasUsageData == false)
        #expect(record.message?.usage == nil)
    }

    @Test("ISO 8601 时间戳解析 - 带毫秒")
    func iso8601WithFractionalSeconds() throws {
        let result = ISO8601DateFormatterHelper.parse("2026-06-13T11:55:26.715Z")
        #expect(result != nil)

        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.year, .month, .day], from: result!)
        #expect(components.year == 2026)
        #expect(components.month == 6)
        #expect(components.day == 13)
    }

    @Test("ISO 8601 时间戳解析 - 不带毫秒")
    func iso8601WithoutFractionalSeconds() throws {
        let result = ISO8601DateFormatterHelper.parse("2026-06-13T12:00:00Z")
        #expect(result != nil)
    }

    // MARK: - ParsedUsageEntry 去重

    @Test("ParsedUsageEntry 去重 - 相同复合键应相等")
    func dedupSameKey() throws {
        let usage1 = createUsage(input: 100, output: 50)
        let usage2 = createUsage(input: 100, output: 50)

        let date = Date()
        let entry1 = ParsedUsageEntry(
            recordUUID: "uuid-1", sessionID: "session-1",
            timestamp: date, model: "deepseek-v4-pro",
            cwd: "/test", agentId: nil,
            usage: usage1, isSubagent: false
        )
        let entry2 = ParsedUsageEntry(
            recordUUID: "uuid-2", sessionID: "session-1",
            timestamp: date, model: "deepseek-v4-pro",
            cwd: "/test", agentId: nil,
            usage: usage2, isSubagent: false
        )

        // 不同 recordUUID 但相同复合键，应被视为相等（用于去重）
        #expect(entry1 == entry2)
        #expect(entry1.hashValue == entry2.hashValue)
    }

    @Test("ParsedUsageEntry 去重 - 不同 input tokens 应不相等")
    func dedupDifferentTokens() throws {
        let usage1 = createUsage(input: 100, output: 50)
        let usage2 = createUsage(input: 200, output: 50)

        let date = Date()
        let entry1 = ParsedUsageEntry(
            recordUUID: "uuid-1", sessionID: "session-1",
            timestamp: date, model: "deepseek-v4-pro",
            cwd: "/test", agentId: nil,
            usage: usage1, isSubagent: false
        )
        let entry2 = ParsedUsageEntry(
            recordUUID: "uuid-2", sessionID: "session-1",
            timestamp: date, model: "deepseek-v4-pro",
            cwd: "/test", agentId: nil,
            usage: usage2, isSubagent: false
        )

        #expect(entry1 != entry2)
    }

    // MARK: - Helper

    private func createUsage(input: Int, output: Int) -> TokenUsage {
        TokenUsage(
            inputTokens: input,
            cacheCreationInputTokens: 0,
            cacheReadInputTokens: 0,
            outputTokens: output,
            serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
            serviceTier: "standard",
            cacheCreation: CacheCreation(ephemeral1hInputTokens: 0, ephemeral5mInputTokens: 0),
            inferenceGeo: "",
            iterations: [],
            speed: "standard"
        )
    }
}

