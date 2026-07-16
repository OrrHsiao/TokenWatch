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

    @Test("每个 provider 使用固定且互不相同的 bookmark key")
    func bookmarkKeysAreIndependent() {
        let expected: [ProviderID: String] = [
            .claude: "ClaudeDataDirectoryBookmark",
            .codex: "CodexDataDirectoryBookmark",
            .opencode: "OpenCodeDataDirectoryBookmark",
        ]

        #expect(Dictionary(uniqueKeysWithValues: ProviderRegistry.allProviders.map {
            ($0.id, $0.bookmarkKey)
        }) == expected)
    }

    @Test("provider 面板文案互相独立且没有 Home 语义")
    func openPanelMessagesAreProviderSpecificAndAvoidHomeSemantics() {
        let messages = ProviderRegistry.allProviders.map {
            AppStrings.text($0.openPanelMessageKey, language: .en)
        }

        #expect(Set(messages) == [
            "Choose the Claude Code data folder",
            "Choose the Codex data folder",
            "Choose the opencode data folder",
        ])
        #expect(messages.allSatisfy {
            !$0.localizedCaseInsensitiveContains("home")
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

    @Test("Claude provider 从用户选择的数据根读取 projects")
    func claudeLoadsFromSelectedDataRoot() throws {
        let root = try makeTempDataRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let projects = root.appendingPathComponent("projects/-tmp-project", isDirectory: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        try claudeUsageLine.write(
            to: projects.appendingPathComponent("session.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let entries = try ClaudeProvider().loadEntries(from: root)

        #expect(entries.count == 1)
        #expect(entries.first?.messageId == "claude-msg")
    }

    @Test("Codex provider 从用户选择的数据根读取 sessions 与根部配置")
    func codexLoadsFromSelectedDataRoot() throws {
        let root = try makeTempDataRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appendingPathComponent("sessions/2026/05/04", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let file = sessions.appendingPathComponent(
            "rollout-2026-05-04T16-35-18-019df220-aaaa-bbbb-cccc-ddddeeeeffff.jsonl"
        )
        try [codexSessionMeta, codexTurnContext, codexTokenEvent]
            .joined(separator: "\n")
            .write(to: file, atomically: true, encoding: .utf8)
        try "service_tier = \"fast\"\n".write(
            to: root.appendingPathComponent("config.toml"),
            atomically: true,
            encoding: .utf8
        )

        let entries = try CodexProvider().loadEntries(from: root)

        #expect(entries.count == 1)
        #expect(entries.first?.messageId == "019df220-aaaa-bbbb-cccc-ddddeeeeffff:2026-05-04T08:35:59.868Z")
        #expect(entries.first?.usage.serviceTier == "fast")
    }

    @Test("opencode provider 从用户选择的数据根读取数据库")
    func openCodeLoadsFromSelectedDataRoot() throws {
        let root = try makeTempDataRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try buildMiniOpenCodeDB(at: root.appendingPathComponent("opencode.db"))

        let entries = try OpenCodeProvider().loadEntries(from: root)

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

    private func makeTempDataRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("provider-data-root-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
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
