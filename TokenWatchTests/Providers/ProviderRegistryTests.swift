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
            .antigravity: "AntigravityDataDirectoryBookmark",
        ]

        #expect(Dictionary(uniqueKeysWithValues: ProviderRegistry.allProviders.map {
            ($0.id, $0.bookmarkKey)
        }) == expected)
    }

    @Test("provider 面板文案互相独立且不含绝对用户路径")
    func openPanelMessagesAreProviderSpecificAndAvoidAbsoluteUserPaths() {
        let messages = ProviderRegistry.allProviders.map {
            AppStrings.text($0.openPanelMessageKey, language: .en)
        }

        #expect(Set(messages) == [
            "Choose the Claude Code data folder; it is usually ~/.claude.\nRun echo \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\" to find it.",
            "Choose the Codex data folder; it is usually ~/.codex.\nRun echo \"${CODEX_HOME:-$HOME/.codex}\" to find it.",
            "Choose the opencode data folder; it is usually ~/.local/share/opencode.\nRun echo \"${XDG_DATA_HOME:-$HOME/.local/share}/opencode\" to find it.",
            "Choose the Antigravity data folder; it is usually ~/.gemini/antigravity.\nRun echo \"$HOME/.gemini/antigravity\" to find it.",
        ])
        #expect(messages.allSatisfy {
            !$0.localizedCaseInsensitiveContains("home folder")
                && !$0.contains("/Users/")
        })
    }

    @Test("provider(for:) 能按 id 查到对应实例")
    func lookupById() {
        let claude = ProviderRegistry.provider(for: .claude)
        #expect(claude?.id == .claude)
        let antigravity = ProviderRegistry.provider(for: .antigravity)
        #expect(antigravity?.id == .antigravity)
    }

    @Test("allProviders 含 .opencode 与 .antigravity")
    func containsOpenCodeAndAntigravity() {
        let ids = ProviderRegistry.allProviders.map(\.id)
        #expect(ids.contains(.opencode))
        #expect(ids.contains(.antigravity))
    }

    @Test("hasReasoningDimension:opencode与antigravity=true,Claude/Codex=false")
    func reasoningDimensionFlags() {
        #expect(ProviderRegistry.provider(for: .claude)?.hasReasoningDimension == false)
        #expect(ProviderRegistry.provider(for: .codex)?.hasReasoningDimension == false)
        #expect(ProviderRegistry.provider(for: .opencode)?.hasReasoningDimension == true)
        #expect(ProviderRegistry.provider(for: .antigravity)?.hasReasoningDimension == true)
    }

    @Test("JSONL provider 使用各自声明的磁盘缓存兼容策略")
    func diskCacheCompatibilityIsProviderSpecific() {
        #expect(CodexProvider.currentDiskCacheVersion == 4)
        #expect(CodexProvider.compatibleDiskCacheVersions == [2, 3])
        #expect(ClaudeProvider.currentDiskCacheVersion == 3)
        #expect(ClaudeProvider.compatibleDiskCacheVersions.isEmpty)
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

    @Test("Antigravity provider 从用户选择的数据根读取数据库")
    func antigravityLoadsFromSelectedDataRoot() throws {
        let root = try makeTempDataRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let convDir = root.appendingPathComponent("conversations", isDirectory: true)
        try FileManager.default.createDirectory(at: convDir, withIntermediateDirectories: true)
        try buildMiniAntigravityRegistryDB(at: convDir.appendingPathComponent("session-1.db"))

        let entries = try AntigravityProvider().loadEntries(from: root)

        #expect(entries.count == 1)
        #expect(entries.first?.messageId == "antigravity-msg-1")
        #expect(entries.first?.provider == .antigravity)
        #expect(entries.first?.usage.inputTokens == 150)
        #expect(entries.first?.usage.outputTokens == 50)
        #expect(entries.first?.usage.reasoningTokens == 20)
    }

    @Test("provider 能识别明显选错的数据目录")
    func providersValidateExpectedDataRootStructure() throws {
        let root = try makeTempDataRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let claudeRoot = root.appendingPathComponent("claude", isDirectory: true)
        try FileManager.default.createDirectory(
            at: claudeRoot,
            withIntermediateDirectories: true
        )
        #expect(
            ClaudeProvider().validateDataRoot(claudeRoot)
                == .missingExpectedStructure
        )
        try FileManager.default.createDirectory(
            at: claudeRoot.appendingPathComponent("projects", isDirectory: true),
            withIntermediateDirectories: true
        )
        #expect(ClaudeProvider().validateDataRoot(claudeRoot) == .valid)

        let codexRoot = root.appendingPathComponent("codex", isDirectory: true)
        try FileManager.default.createDirectory(
            at: codexRoot,
            withIntermediateDirectories: true
        )
        #expect(
            CodexProvider().validateDataRoot(codexRoot)
                == .missingExpectedStructure
        )
        try FileManager.default.createDirectory(
            at: codexRoot.appendingPathComponent(
                "archived_sessions",
                isDirectory: true
            ),
            withIntermediateDirectories: true
        )
        #expect(CodexProvider().validateDataRoot(codexRoot) == .valid)

        let openCodeRoot = root.appendingPathComponent(
            "opencode",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: openCodeRoot,
            withIntermediateDirectories: true
        )
        #expect(
            OpenCodeProvider().validateDataRoot(openCodeRoot)
                == .missingExpectedStructure
        )
        try Data().write(
            to: openCodeRoot.appendingPathComponent("opencode.db")
        )
        #expect(OpenCodeProvider().validateDataRoot(openCodeRoot) == .valid)

        let antigravityRoot = root.appendingPathComponent(
            "antigravity",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: antigravityRoot,
            withIntermediateDirectories: true
        )
        #expect(
            AntigravityProvider().validateDataRoot(antigravityRoot)
                == .missingExpectedStructure
        )
        try FileManager.default.createDirectory(
            at: antigravityRoot.appendingPathComponent("conversations", isDirectory: true),
            withIntermediateDirectories: true
        )
        #expect(AntigravityProvider().validateDataRoot(antigravityRoot) == .valid)
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

    private func buildMiniAntigravityRegistryDB(at url: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK,
              let database = db else {
            throw NSError(domain: "test.sqlite", code: 1)
        }
        defer { sqlite3_close(database) }

        let schema = """
        CREATE TABLE trajectory_meta (trajectory_id TEXT PRIMARY KEY);
        CREATE TABLE steps (idx INTEGER PRIMARY KEY, metadata BLOB);
        CREATE TABLE gen_metadata (idx INTEGER PRIMARY KEY, data BLOB, size INTEGER NOT NULL DEFAULT 0);
        INSERT INTO trajectory_meta (trajectory_id) VALUES ('antigravity-session');
        """
        guard sqlite3_exec(database, schema, nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "test.sqlite", code: 2)
        }

        func makeVarint(_ value: UInt64) -> Data {
            var data = Data()
            var v = value
            while v >= 0x80 {
                data.append(UInt8((v & 0x7F) | 0x80))
                v >>= 7
            }
            data.append(UInt8(v & 0x7F))
            return data
        }
        func makeVarintField(tag: Int, value: UInt64) -> Data {
            makeVarint(UInt64(tag << 3 | 0)) + makeVarint(value)
        }
        func makeStringField(tag: Int, value: String) -> Data {
            let content = Data(value.utf8)
            return makeVarint(UInt64(tag << 3 | 2)) + makeVarint(UInt64(content.count)) + content
        }
        func makeSubmessage(tag: Int, content: Data) -> Data {
            makeVarint(UInt64(tag << 3 | 2)) + makeVarint(UInt64(content.count)) + content
        }

        // Usage: prompt=150, total=50, thoughts=20, candidates=30, botId="antigravity-msg-1"
        var usageData = Data()
        usageData.append(makeVarintField(tag: 2, value: 150))
        usageData.append(makeVarintField(tag: 3, value: 50))
        usageData.append(makeVarintField(tag: 9, value: 20))
        usageData.append(makeVarintField(tag: 10, value: 30))
        usageData.append(makeStringField(tag: 7, value: "antigravity-msg-1"))

        var sub1 = Data()
        sub1.append(makeStringField(tag: 19, value: "gemini-3.8-flash"))
        sub1.append(makeSubmessage(tag: 4, content: usageData))

        let genBlob = makeSubmessage(tag: 1, content: sub1)

        let insertSQL = "INSERT INTO gen_metadata (idx, data, size) VALUES (0, ?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, insertSQL, -1, &stmt, nil) == SQLITE_OK else {
            throw NSError(domain: "test.sqlite", code: 3)
        }
        defer { sqlite3_finalize(stmt) }

        genBlob.withUnsafeBytes { ptr in
            sqlite3_bind_blob(stmt, 1, ptr.baseAddress, Int32(genBlob.count), SQLITE_TRANSIENT_DESTRUCTOR)
        }
        sqlite3_bind_int(stmt, 2, Int32(genBlob.count))
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw NSError(domain: "test.sqlite", code: 4)
        }
    }
}
