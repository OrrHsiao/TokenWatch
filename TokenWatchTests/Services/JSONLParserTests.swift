import Foundation
import Testing
@testable import TokenWatch

/// JSONL 解析器测试
/// 验证 JSONL 解析和去重逻辑
struct JSONLParserTests {

    let parser = JSONLParser()

    // MARK: - 解析

    @Test("解析包含 usage 的 assistant 记录")
    func parseAssistantWithUsage() throws {
        let jsonl = """
        {"type":"assistant","uuid":"u1","sessionId":"s1","timestamp":"2026-06-13T11:55:26.715Z","message":{"id":"m1","role":"assistant","model":"deepseek-v4-pro","content":[{"type":"text","text":"Hello"}],"stop_reason":"end_turn","usage":{"input_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":200,"output_tokens":50,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"}}}
        """

        let tmpDir = FileManager.default.temporaryDirectory
        let fileURL = tmpDir.appendingPathComponent("test.jsonl")
        try jsonl.write(to: fileURL, atomically: true, encoding: .utf8)

        let fileInfo = JSONLFileInfo(
            url: fileURL,
            sessionID: "s1",
            projectPath: "/test",
            isSubagent: false,
            agentId: nil
        )

        let entries = try parser.parseJSONLFile(fileInfo, claudeDataRoot: tmpDir)

        #expect(entries.count == 1)
        #expect(entries[0].model == "deepseek-v4-pro")
        #expect(entries[0].usage.inputTokens == 100)
        #expect(entries[0].usage.outputTokens == 50)
        #expect(entries[0].sessionID == "s1")

        try? FileManager.default.removeItem(at: fileURL)
    }

    @Test("跳过不含 usage 的记录")
    func skipNonUsageRecords() throws {
        let jsonl = """
        {"type":"user","uuid":"u2","sessionId":"s1","timestamp":"2026-06-13T12:00:00Z","message":{"id":"m2","role":"user","content":[{"type":"text","text":"Hi"}]}}
        {"type":"system","uuid":"u3","sessionId":"s1","subtype":"hook"}
        {"type":"assistant","uuid":"u4","sessionId":"s1","timestamp":"2026-06-13T12:01:00Z","message":{"id":"m3","role":"assistant","model":"deepseek-v4-pro","content":[{"type":"text","text":"Hello"}],"stop_reason":"end_turn","usage":{"input_tokens":50,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":25,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"}}}
        """

        let tmpDir = FileManager.default.temporaryDirectory
        let fileURL = tmpDir.appendingPathComponent("test2.jsonl")
        try jsonl.write(to: fileURL, atomically: true, encoding: .utf8)

        let fileInfo = JSONLFileInfo(
            url: fileURL,
            sessionID: "s1",
            projectPath: "/test",
            isSubagent: false,
            agentId: nil
        )

        let entries = try parser.parseJSONLFile(fileInfo, claudeDataRoot: tmpDir)

        // 只有 assistant 记录被解析
        #expect(entries.count == 1)
        #expect(entries[0].usage.inputTokens == 50)

        try? FileManager.default.removeItem(at: fileURL)
    }

    @Test("跳过无 model 的 assistant 记录")
    func skipAssistantWithoutModel() throws {
        let jsonl = """
        {"type":"assistant","uuid":"u5","sessionId":"s1","timestamp":"2026-06-13T12:00:00Z","message":{"id":"m4","role":"assistant","content":[{"type":"text","text":"No model"}],"usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":5,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"}}}
        """

        let tmpDir = FileManager.default.temporaryDirectory
        let fileURL = tmpDir.appendingPathComponent("test3.jsonl")
        try jsonl.write(to: fileURL, atomically: true, encoding: .utf8)

        let fileInfo = JSONLFileInfo(
            url: fileURL,
            sessionID: "s1",
            projectPath: "/test",
            isSubagent: false,
            agentId: nil
        )

        let entries = try parser.parseJSONLFile(fileInfo, claudeDataRoot: tmpDir)

        // 无 model 的 assistant 记录应被跳过
        #expect(entries.isEmpty)

        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - 去重

    @Test("Set 去重 - 重复记录只保留一条")
    func dedupWithSet() {
        let usage = TokenUsage(
            inputTokens: 100,
            cacheCreationInputTokens: 0,
            cacheReadInputTokens: 0,
            outputTokens: 50,
            serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
            serviceTier: "standard",
            cacheCreation: CacheCreation(ephemeral1hInputTokens: 0, ephemeral5mInputTokens: 0),
            inferenceGeo: "",
            iterations: [],
            speed: "standard"
        )

        let date = Date()
        let entry1 = ParsedUsageEntry(
            recordUUID: "uuid-1", sessionID: "s1",
            timestamp: date, model: "deepseek-v4-pro",
            cwd: "/test", agentId: nil,
            usage: usage, isSubagent: false
        )
        let entry2 = ParsedUsageEntry(
            recordUUID: "uuid-2", sessionID: "s1",
            timestamp: date, model: "deepseek-v4-pro",
            cwd: "/test", agentId: nil,
            usage: usage, isSubagent: false
        )

        let unique = Array(Set([entry1, entry2]))
        #expect(unique.count == 1)
    }

    @Test("Set 不去重不同模型")
    func noDedupDifferentModels() {
        let usage1 = TokenUsage(
            inputTokens: 100, cacheCreationInputTokens: 0, cacheReadInputTokens: 0,
            outputTokens: 50,
            serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
            serviceTier: "standard",
            cacheCreation: CacheCreation(ephemeral1hInputTokens: 0, ephemeral5mInputTokens: 0),
            inferenceGeo: "", iterations: [], speed: "standard"
        )
        let usage2 = usage1

        let date = Date()
        let entry1 = ParsedUsageEntry(
            recordUUID: "u1", sessionID: "s1",
            timestamp: date, model: "deepseek-v4-pro",
            cwd: "/test", agentId: nil,
            usage: usage1, isSubagent: false
        )
        let entry2 = ParsedUsageEntry(
            recordUUID: "u2", sessionID: "s1",
            timestamp: date, model: "deepseek-v4-flash",  // 不同模型
            cwd: "/test", agentId: nil,
            usage: usage2, isSubagent: false
        )

        let unique = Array(Set([entry1, entry2]))
        #expect(unique.count == 2)
    }
}
