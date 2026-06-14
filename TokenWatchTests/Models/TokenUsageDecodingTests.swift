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

    @Test("仅核心字段也能解码（周边元数据缺失时降级）")
    func decodeWithoutOptionalFields() throws {
        // 模拟未来格式变化或非标准 provider：只保留 input/output_tokens
        let json = """
        {
            "input_tokens": 42,
            "output_tokens": 7
        }
        """
        let usage = try JSONDecoder().decode(TokenUsage.self, from: json.data(using: .utf8)!)
        #expect(usage.inputTokens == 42)
        #expect(usage.outputTokens == 7)
        #expect(usage.cacheCreationInputTokens == 0)
        #expect(usage.cacheReadInputTokens == 0)
        #expect(usage.serviceTier == "")
        #expect(usage.cacheCreation.ephemeral1hInputTokens == 0)
    }

    // MARK: - cache_creation 派生属性

    @Test("有 ephemeral 细分时优先使用细分（避免双计扁平字段）")
    func cacheCreationBreakdownTakesPriority() {
        let usage = TokenUsage(
            inputTokens: 0, cacheCreationInputTokens: 999,  // 故意设成不合理值
            cacheReadInputTokens: 0, outputTokens: 0,
            serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
            serviceTier: "standard",
            cacheCreation: CacheCreation(ephemeral1hInputTokens: 20, ephemeral5mInputTokens: 10),
            inferenceGeo: "", iterations: [], speed: "standard"
        )
        #expect(usage.cacheCreate5mTokens == 10)
        #expect(usage.cacheCreate1hTokens == 20)
        #expect(usage.totalCacheCreationTokens == 30)  // 不再把 999 双计进来
    }

    @Test("无 ephemeral 细分时回退到扁平字段（视为 5m）")
    func cacheCreationFallbackToFlat() {
        let usage = TokenUsage(
            inputTokens: 0, cacheCreationInputTokens: 500,
            cacheReadInputTokens: 0, outputTokens: 0,
            serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
            serviceTier: "standard",
            cacheCreation: CacheCreation(ephemeral1hInputTokens: 0, ephemeral5mInputTokens: 0),
            inferenceGeo: "", iterations: [], speed: "standard"
        )
        #expect(usage.cacheCreate5mTokens == 500)
        #expect(usage.cacheCreate1hTokens == 0)
        #expect(usage.totalCacheCreationTokens == 500)
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
            "requestId": "req-xyz",
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
        #expect(record.message?.id == "msg-1")
        #expect(record.requestId == "req-xyz")
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

    // MARK: - ParsedUsageEntry 去重（messageId[:requestId]）

    @Test("相同 messageId 应被视为重复（核心场景）")
    func dedupSameMessageId() throws {
        let usage1 = createUsage(input: 100, output: 50)
        // 故意用不同 token 数：dedup 由 messageId 决定，与 token 数量无关
        let usage2 = createUsage(input: 999, output: 999)

        let entry1 = ParsedUsageEntry(
            recordUUID: "uuid-1", messageId: "msg-A", requestId: nil,
            sessionID: "s1", timestamp: Date(), model: "deepseek-v4-pro",
            cwd: "/test", agentId: nil, usage: usage1, isSubagent: false
        )
        let entry2 = ParsedUsageEntry(
            recordUUID: "uuid-2", messageId: "msg-A", requestId: nil,
            sessionID: "s2", timestamp: Date(), model: "deepseek-v4-flash",
            cwd: "/other", agentId: nil, usage: usage2, isSubagent: false
        )

        #expect(entry1 == entry2)
        #expect(entry1.hashValue == entry2.hashValue)
    }

    @Test("不同 messageId 不应去重")
    func noDedupDifferentMessageId() throws {
        let usage = createUsage(input: 100, output: 50)
        let now = Date()
        let entry1 = ParsedUsageEntry(
            recordUUID: "uuid-1", messageId: "msg-A", requestId: nil,
            sessionID: "s1", timestamp: now, model: "deepseek-v4-pro",
            cwd: "/test", agentId: nil, usage: usage, isSubagent: false
        )
        let entry2 = ParsedUsageEntry(
            recordUUID: "uuid-2", messageId: "msg-B", requestId: nil,
            sessionID: "s1", timestamp: now, model: "deepseek-v4-pro",
            cwd: "/test", agentId: nil, usage: usage, isSubagent: false
        )
        #expect(entry1 != entry2)
    }

    @Test("requestId 缺失不影响 dedup（msgId 单独足够）")
    func dedupWorksWhenRequestIdMissing() throws {
        // 还原 TokenTracker issue #64：DeepSeek/Kimi 等 provider 不返回 request-id
        // 旧实现强制 (msgId, reqId) 双键，缺一不可，导致 dedup 失效；新实现 fallback 到 msgId
        let usage = createUsage(input: 100, output: 50)
        let entry1 = ParsedUsageEntry(
            recordUUID: "u1", messageId: "msg-X", requestId: nil,
            sessionID: "s1", timestamp: Date(), model: "deepseek-v4-pro",
            cwd: "/p", agentId: nil, usage: usage, isSubagent: false
        )
        let entry2 = ParsedUsageEntry(
            recordUUID: "u2", messageId: "msg-X", requestId: nil,
            sessionID: "s1", timestamp: Date(), model: "deepseek-v4-pro",
            cwd: "/p", agentId: nil, usage: usage, isSubagent: false
        )
        #expect(entry1 == entry2)
    }

    @Test("reqId 拼接键与纯 msgId 键共存（不互相碰撞）")
    func msgIdAndCompositeKeysCoexist() throws {
        let usage = createUsage(input: 100, output: 50)
        let withReq = ParsedUsageEntry(
            recordUUID: "u1", messageId: "msg-Y", requestId: "req-1",
            sessionID: "s1", timestamp: Date(), model: "claude-sonnet-4-5",
            cwd: "/p", agentId: nil, usage: usage, isSubagent: false
        )
        let withoutReq = ParsedUsageEntry(
            recordUUID: "u2", messageId: "msg-Y", requestId: nil,
            sessionID: "s1", timestamp: Date(), model: "claude-sonnet-4-5",
            cwd: "/p", agentId: nil, usage: usage, isSubagent: false
        )
        // msg-Y 与 msg-Y:req-1 是不同键 → 不应去重
        #expect(withReq != withoutReq)
        #expect(Set([withReq, withoutReq]).count == 2)
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
