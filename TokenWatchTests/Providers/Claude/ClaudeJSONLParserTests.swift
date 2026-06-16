import Foundation
import Testing
@testable import TokenWatch

/// JSONL 解析器测试
/// 验证 JSONL 解析和 messageId[:requestId] 去重逻辑
struct ClaudeJSONLParserTests {

    let parser = ClaudeJSONLParser()

    // MARK: - 解析

    @Test("解析包含 usage 的 assistant 记录")
    func parseAssistantWithUsage() throws {
        let jsonl = """
        {"type":"assistant","uuid":"u1","sessionId":"s1","timestamp":"2026-06-13T11:55:26.715Z","requestId":"req-1","message":{"id":"m1","role":"assistant","model":"deepseek-v4-pro","content":[{"type":"text","text":"Hello"}],"stop_reason":"end_turn","usage":{"input_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":200,"output_tokens":50,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"}}}
        """

        let tmpDir = FileManager.default.temporaryDirectory
        let fileURL = tmpDir.appendingPathComponent("test.jsonl")
        try jsonl.write(to: fileURL, atomically: true, encoding: .utf8)

        let fileInfo = ClaudeJSONLFileInfo(
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
        #expect(entries[0].messageId == "m1")
        #expect(entries[0].requestId == "req-1")
        #expect(entries[0].dedupKey == "m1:req-1")

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

        let fileInfo = ClaudeJSONLFileInfo(
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
        #expect(entries[0].messageId == "m3")
        #expect(entries[0].requestId == nil)
        #expect(entries[0].dedupKey == "m3")

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

        let fileInfo = ClaudeJSONLFileInfo(
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

    @Test("Set 去重 - 相同 messageId 只保留一条")
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

        let entry1 = ParsedUsageEntry(
            recordUUID: "uuid-1", messageId: "msg-A", requestId: "req-1",
            sessionID: "s1", timestamp: Date(), model: "deepseek-v4-pro",
            cwd: "/test", agentId: nil, usage: usage, isSubagent: false,
            provider: .claude,
            upstreamProviderID: nil, upstreamCost: nil
        )
        let entry2 = ParsedUsageEntry(
            recordUUID: "uuid-2", messageId: "msg-A", requestId: "req-1",
            sessionID: "s1", timestamp: Date(), model: "deepseek-v4-pro",
            cwd: "/test", agentId: nil, usage: usage, isSubagent: false,
            provider: .claude,
            upstreamProviderID: nil, upstreamCost: nil
        )

        let unique = Array(Set([entry1, entry2]))
        #expect(unique.count == 1)
    }

    @Test("Set 不去重不同 messageId")
    func noDedupDifferentMessageIds() {
        let usage = TokenUsage(
            inputTokens: 100, cacheCreationInputTokens: 0, cacheReadInputTokens: 0,
            outputTokens: 50,
            serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
            serviceTier: "standard",
            cacheCreation: CacheCreation(ephemeral1hInputTokens: 0, ephemeral5mInputTokens: 0),
            inferenceGeo: "", iterations: [], speed: "standard"
        )

        let entry1 = ParsedUsageEntry(
            recordUUID: "u1", messageId: "msg-A", requestId: nil,
            sessionID: "s1", timestamp: Date(), model: "deepseek-v4-pro",
            cwd: "/test", agentId: nil, usage: usage, isSubagent: false,
            provider: .claude,
            upstreamProviderID: nil, upstreamCost: nil
        )
        let entry2 = ParsedUsageEntry(
            recordUUID: "u2", messageId: "msg-B", requestId: nil,
            sessionID: "s1", timestamp: Date(), model: "deepseek-v4-pro",
            cwd: "/test", agentId: nil, usage: usage, isSubagent: false,
            provider: .claude,
            upstreamProviderID: nil, upstreamCost: nil
        )

        let unique = Array(Set([entry1, entry2]))
        #expect(unique.count == 2)
    }

    @Test("跨文件去重 - 同 messageId 在多个 JSONL 中只计一次")
    func dedupAcrossFiles() throws {
        // 模拟同一 message 因 sub-agent / resume 被写入两个 JSONL 的场景
        let line = """
        {"type":"assistant","uuid":"u1","sessionId":"s1","timestamp":"2026-06-13T11:55:26.715Z","message":{"id":"shared-msg","role":"assistant","model":"deepseek-v4-pro","content":[{"type":"text","text":"hi"}],"stop_reason":"end_turn","usage":{"input_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":50,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"}}}
        """
        let tmpDir = FileManager.default.temporaryDirectory
        let f1 = tmpDir.appendingPathComponent("dup-a.jsonl")
        let f2 = tmpDir.appendingPathComponent("dup-b.jsonl")
        try line.write(to: f1, atomically: true, encoding: .utf8)
        try line.write(to: f2, atomically: true, encoding: .utf8)

        let infos = [
            ClaudeJSONLFileInfo(url: f1, sessionID: "s1", projectPath: "/p", isSubagent: false, agentId: nil),
            ClaudeJSONLFileInfo(url: f2, sessionID: "s1", projectPath: "/p", isSubagent: true,  agentId: "agent-1"),
        ]
        let entries = try parser.parseAllFiles(infos, claudeDataRoot: tmpDir)
        #expect(entries.count == 1)
        #expect(entries[0].messageId == "shared-msg")

        try? FileManager.default.removeItem(at: f1)
        try? FileManager.default.removeItem(at: f2)
    }

    @Test("批量解析跳过单个失败文件")
    func parseAllFilesSkipsFailedFile() throws {
        let line = """
        {"type":"assistant","uuid":"u1","sessionId":"s1","timestamp":"2026-06-13T11:55:26.715Z","message":{"id":"ok-msg","role":"assistant","model":"deepseek-v4-pro","content":[{"type":"text","text":"hi"}],"stop_reason":"end_turn","usage":{"input_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":50,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"}}}
        """
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeJSONLParserTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let validFile = tmpDir.appendingPathComponent("valid.jsonl")
        try line.write(to: validFile, atomically: true, encoding: .utf8)

        let missingSubagentFile = tmpDir
            .appendingPathComponent("subagents", isDirectory: true)
            .appendingPathComponent("agent-no-access.jsonl")
        let infos = [
            ClaudeJSONLFileInfo(url: validFile, sessionID: "s1", projectPath: "/p", isSubagent: false, agentId: nil),
            ClaudeJSONLFileInfo(url: missingSubagentFile, sessionID: "agent-no-access", projectPath: "/p", isSubagent: true, agentId: "no-access"),
        ]

        let entries = try parser.parseAllFiles(infos, claudeDataRoot: tmpDir)

        #expect(entries.count == 1)
        #expect(entries.first?.messageId == "ok-msg")
    }

    @Test("跳过缺失 message.id 的记录（无法可靠去重）")
    func skipRecordsWithoutMessageId() throws {
        // assistant 记录有 usage 但 message.id 为空字符串 → 跳过
        let jsonl = """
        {"type":"assistant","uuid":"u9","sessionId":"s1","timestamp":"2026-06-13T12:00:00Z","message":{"id":"","role":"assistant","model":"deepseek-v4-pro","usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"}}}
        """
        let tmpDir = FileManager.default.temporaryDirectory
        let fileURL = tmpDir.appendingPathComponent("no-msg-id.jsonl")
        try jsonl.write(to: fileURL, atomically: true, encoding: .utf8)
        let info = ClaudeJSONLFileInfo(url: fileURL, sessionID: "s1", projectPath: "/p", isSubagent: false, agentId: nil)

        let entries = try parser.parseJSONLFile(info, claudeDataRoot: tmpDir)
        #expect(entries.isEmpty)

        try? FileManager.default.removeItem(at: fileURL)
    }

    @Test("同 messageId 多 chunk 去重 - 应保留携带真实 usage 的那条")
    func dedupKeepsRecordWithRealUsage() throws {
        // Claude Code JSONL 中,同一 message.id 会出现多条记录:
        // streaming 过程中的中间 chunk usage 全为 0;最终一条才携带真实 usage。
        // 之前用 Set.insert 保留首条,会丢掉真实 usage,导致今日 token 偏低。
        // 修复后:同 messageId 应保留 token 总量最大的一条(最完整)。
        let zeroUsageLine = """
        {"type":"assistant","uuid":"u-chunk","sessionId":"s1","timestamp":"2026-06-14T10:00:00Z","message":{"id":"shared-msg","role":"assistant","model":"deepseek-v4-pro","content":[],"stop_reason":null,"usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"}}}
        """
        let realUsageLine = """
        {"type":"assistant","uuid":"u-final","sessionId":"s1","timestamp":"2026-06-14T10:00:01Z","message":{"id":"shared-msg","role":"assistant","model":"deepseek-v4-pro","content":[{"type":"text","text":"hi"}],"stop_reason":"end_turn","usage":{"input_tokens":1234,"cache_creation_input_tokens":0,"cache_read_input_tokens":5678,"output_tokens":234,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"}}}
        """

        let tmpDir = FileManager.default.temporaryDirectory
        let fileURL = tmpDir.appendingPathComponent("multi-chunk-\(UUID().uuidString).jsonl")
        // 故意让 (0,0,0) chunk 排在前面 — 模拟真实日志写入顺序
        try (zeroUsageLine + "\n" + realUsageLine).write(to: fileURL, atomically: true, encoding: .utf8)
        let info = ClaudeJSONLFileInfo(url: fileURL, sessionID: "s1", projectPath: "/p", isSubagent: false, agentId: nil)

        let entries = try parser.parseAllFiles([info], claudeDataRoot: tmpDir)

        #expect(entries.count == 1)
        #expect(entries.first?.messageId == "shared-msg")
        // 关键:必须取到带真实 usage 的那条,而不是 (0,0,0) 的 chunk
        #expect(entries.first?.usage.inputTokens == 1234)
        #expect(entries.first?.usage.outputTokens == 234)
        #expect(entries.first?.usage.cacheReadInputTokens == 5678)

        try? FileManager.default.removeItem(at: fileURL)
    }
}
