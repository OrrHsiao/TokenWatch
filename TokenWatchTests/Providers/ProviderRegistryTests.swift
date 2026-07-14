import Foundation
import SQLite3
import Testing
@testable import TokenWatch

private let SQLITE_TRANSIENT_DESTRUCTOR = unsafeBitCast(
    OpaquePointer(bitPattern: -1),
    to: sqlite3_destructor_type.self
)

@Suite("ProviderRegistry")
struct ProviderRegistryTests {
    @Test("allProviders 至少含 .claude")
    func containsClaude() {
        let ids = ProviderRegistry.allProviders.map(\.id)
        #expect(ids.contains(.claude))
    }

    @Test("所有 provider 共享用户目录 bookmarkKey")
    func bookmarkKeysUseHomeDirectory() {
        let keys = ProviderRegistry.allProviders.map(\.bookmarkKey)
        #expect(Set(keys) == ["HomeDirectoryBookmark"])
    }

    @Test("所有 provider 授权弹窗提示为用户目录")
    func openPanelMessagesUseHomeDirectory() {
        #expect(ProviderRegistry.allProviders.allSatisfy {
            $0.openPanelMessage == "TokenWatch 想访问用户目录"
        })
    }

    @Test("provider(for:) 能按 id 查到对应实例")
    func lookupById() {
        let claude = ProviderRegistry.provider(for: .claude)
        #expect(claude?.id == .claude)
    }

    @Test("allProviders 含 .opencode")
    func containsOpenCode() {
        let ids = ProviderRegistry.allProviders.map(\.id)
        #expect(ids.contains(.opencode))
    }

    @Test("hasReasoningDimension:仅 opencode=true,Claude/Codex=false")
    func reasoningDimensionFlags() {
        #expect(ProviderRegistry.provider(for: .claude)?.hasReasoningDimension == false)
        #expect(ProviderRegistry.provider(for: .codex)?.hasReasoningDimension == false)
        #expect(ProviderRegistry.provider(for: .opencode)?.hasReasoningDimension == true)
    }

    @Test("Claude provider 从用户目录下 .claude 读取")
    func claudeLoadsFromHomeSubdirectory() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let projects = home.appendingPathComponent(".claude/projects/-tmp-project", isDirectory: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        let file = projects.appendingPathComponent("session.jsonl")
        try claudeUsageLine.write(to: file, atomically: true, encoding: .utf8)

        let entries = try ClaudeProvider().loadEntries(from: home)

        #expect(entries.count == 1)
        #expect(entries.first?.messageId == "claude-msg")
    }

    @Test("Codex provider 从用户目录下 .codex 读取")
    func codexLoadsFromHomeSubdirectory() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let sessions = home.appendingPathComponent(".codex/sessions/2026/05/04", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let file = sessions.appendingPathComponent("rollout-2026-05-04T16-35-18-019df220-aaaa-bbbb-cccc-ddddeeeeffff.jsonl")
        try [codexSessionMeta, codexTurnContext, codexTokenEvent]
            .joined(separator: "\n")
            .write(to: file, atomically: true, encoding: .utf8)

        let entries = try CodexProvider().loadEntries(from: home)

        #expect(entries.count == 1)
        #expect(entries.first?.messageId == "019df220-aaaa-bbbb-cccc-ddddeeeeffff:2026-05-04T08:35:59.868Z")
    }

    @Test("opencode provider 从用户目录下 .local/share/opencode 读取")
    func openCodeLoadsFromHomeSubdirectory() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let opencode = home.appendingPathComponent(".local/share/opencode", isDirectory: true)
        try FileManager.default.createDirectory(at: opencode, withIntermediateDirectories: true)
        try buildMiniOpenCodeDB(at: opencode.appendingPathComponent("opencode.db"))

        let entries = try OpenCodeProvider().loadEntries(from: home)

        #expect(entries.count == 1)
        #expect(entries.first?.messageId == "opencode-msg")
    }

    private var claudeUsageLine: String {
        """
        {"type":"assistant","uuid":"u1","sessionId":"s1","timestamp":"2026-06-13T11:55:26.715Z","message":{"id":"claude-msg","role":"assistant","model":"deepseek-v4-pro","content":[{"type":"text","text":"hi"}],"stop_reason":"end_turn","usage":{"input_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":50,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"}}}
        """
    }

    private var codexSessionMeta: String {
        #"{"timestamp":"2026-05-04T08:35:44.692Z","type":"session_meta","payload":{"id":"019df220-aaaa-bbbb-cccc-ddddeeeeffff","cwd":"/tmp/proj","model_provider":"openai"}}"#
    }

    private var codexTurnContext: String {
        #"{"timestamp":"2026-05-04T08:35:44.717Z","type":"turn_context","payload":{"model":"gpt-5"}}"#
    }

    private var codexTokenEvent: String {
        #"{"timestamp":"2026-05-04T08:35:59.868Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":300,"output_tokens":200,"reasoning_output_tokens":50,"total_tokens":1200}}}}"#
    }

    private func makeTempHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("provider-home-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func buildMiniOpenCodeDB(at url: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK,
              let database = db else {
            throw NSError(domain: "test.sqlite", code: 1)
        }
        defer { sqlite3_close(database) }

        let schema = """
        CREATE TABLE session (id TEXT PRIMARY KEY, directory TEXT NOT NULL);
        CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT NOT NULL,
                              time_created INTEGER NOT NULL, data TEXT NOT NULL);
        INSERT INTO session (id, directory) VALUES ('opencode-session', '/tmp/proj');
        """
        guard sqlite3_exec(database, schema, nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "test.sqlite", code: 2)
        }

        let sql = "INSERT INTO message (id, session_id, time_created, data) VALUES (?, ?, ?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw NSError(domain: "test.sqlite", code: 3)
        }
        defer { sqlite3_finalize(stmt) }

        let json = #"{"role":"assistant","modelID":"m","providerID":"p","tokens":{"input":1,"output":1,"reasoning":0,"cache":{"read":0,"write":0}}}"#
        sqlite3_bind_text(stmt, 1, "opencode-msg", -1, SQLITE_TRANSIENT_DESTRUCTOR)
        sqlite3_bind_text(stmt, 2, "opencode-session", -1, SQLITE_TRANSIENT_DESTRUCTOR)
        sqlite3_bind_int64(stmt, 3, 1_781_316_000_000)
        sqlite3_bind_text(stmt, 4, json, -1, SQLITE_TRANSIENT_DESTRUCTOR)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw NSError(domain: "test.sqlite", code: 4)
        }
    }
}
