import Foundation
import SQLite3
import Testing
@testable import TokenWatch

/// SQLite C API 中 SQLITE_TRANSIENT 常量在 Swift 不能直接 import,
/// 社区惯用法:用 `bitPattern: -1` 构造 OpaquePointer 后 unsafeBitCast 到 destructor_type
private let SQLITE_TRANSIENT_DESTRUCTOR = unsafeBitCast(
    OpaquePointer(bitPattern: -1),
    to: sqlite3_destructor_type.self
)

/// OpenCodeSQLiteScanner 单元测试
/// 在临时目录用 sqlite3 C API 构造 mini opencode.db,验证 Scanner 读取行为
@Suite("OpenCodeSQLiteScanner", .serialized)
struct OpenCodeSQLiteScannerTests {

    let scanner = OpenCodeSQLiteScanner()

    // MARK: - 正常路径

    @Test("从临时目录读取 mini opencode.db 应得到 assistant 行")
    func readsAssistantRows() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try buildMiniDB(at: dir.appendingPathComponent("opencode.db"),
                        sessions: [("ses_a", "/proj/A"), ("ses_b", "/proj/B")],
                        messages: [
                            ("msg_1", "ses_a", 100, #"{"role":"assistant","modelID":"m","providerID":"p","tokens":{"input":1,"output":1,"reasoning":0,"cache":{"read":0,"write":0}}}"#),
                            ("msg_2", "ses_a", 200, #"{"role":"user","content":"hi"}"#),  // 应被 query 过滤
                            ("msg_3", "ses_b", 300, #"{"role":"assistant","modelID":"m","providerID":"p","tokens":{"input":2,"output":2,"reasoning":0,"cache":{"read":0,"write":0}}}"#),
                        ])

        let rows = try scanner.scanAll(in: dir)
        // 用 #require 守护下标访问:#expect 失败不会终止执行,直接 rows[0] 会触发数组越界 trap 把测试进程打挂
        try #require(rows.count == 2, "应过滤出 2 条 assistant 行,实际: \(rows.count) → \(rows.map(\.id))")
        // ORDER BY time_created
        #expect(rows[0].id == "msg_1")
        #expect(rows[0].sessionID == "ses_a")
        #expect(rows[0].timeCreatedMs == 100)
        #expect(rows[0].directory == "/proj/A")
        #expect(rows[1].id == "msg_3")
        #expect(rows[1].directory == "/proj/B")
    }

    @Test("损坏 JSON 被跳过且其他 assistant 行继续返回")
    func malformedJSONDoesNotAbortAssistantQuery() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try buildMiniDB(
            at: dir.appendingPathComponent("opencode.db"),
            sessions: [("ses", "/project")],
            messages: [
                (
                    "valid-before",
                    "ses",
                    100,
                    #"{"role":"assistant","tokens":{"input":1,"output":1,"reasoning":0,"cache":{"read":0,"write":0}}}"#
                ),
                ("broken", "ses", 200, "{not-json"),
                (
                    "valid-after",
                    "ses",
                    300,
                    #"{"role":"assistant","tokens":{"input":2,"output":2,"reasoning":0,"cache":{"read":0,"write":0}}}"#
                ),
                ("user", "ses", 400, #"{"role":"user"}"#),
            ]
        )

        let rows = try scanner.scanAll(in: dir)

        #expect(rows.map(\.id) == ["valid-before", "valid-after"])
    }

    // MARK: - 错误路径

    @Test("opencode.db 不存在时返回空数组,不抛错")
    func missingDBReturnsEmptyRows() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let rows = try scanner.scanAll(in: dir)

        #expect(rows.isEmpty)
    }

    @Test("非合法 SQLite 文件 → openFailed")
    func corruptedDB() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let dbURL = dir.appendingPathComponent("opencode.db")
        try Data("not a sqlite db".utf8).write(to: dbURL)

        do {
            _ = try scanner.scanAll(in: dir)
            Issue.record("应抛错")
        } catch let err as OpenCodeScannerError {
            // SQLite 在打开非法文件时,可能在 open_v2 阶段(openFailed)或 prepare/step 阶段(queryFailed)报错;两者均接受
            switch err {
            case .openFailed, .queryFailed: return
            default: Issue.record("错类型不对: \(err)")
            }
        }
    }

    // MARK: - 锁竞争（busy timeout）

    @Test("写连接短暂持锁时扫描等待锁释放后成功")
    func busyWaitSucceedsWhenLockReleasedWithinTimeout() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try buildMiniDB(
            at: dir.appendingPathComponent("opencode.db"),
            sessions: [("ses", "/project")],
            messages: [("msg_1", "ses", 100, #"{"role":"assistant","tokens":{"input":1,"output":1,"reasoning":0,"cache":{"read":0,"write":0}}}"#)]
        )

        // 写连接以 EXCLUSIVE 锁短暂占用（journal 模式下会阻塞其他连接的读锁）
        let writer = try openWriterHoldingExclusiveLock(at: dir.appendingPathComponent("opencode.db"))

        // CI 虚拟机在并发执行与 CPU 抢占下，写锁释放调度可能存在轻微延时；
        // 使用充足的 10 秒超时窗口避免偶发超时。
        let patientScanner = OpenCodeSQLiteScanner(busyTimeoutMs: 10_000)
        let scanTask = Task { try patientScanner.scanAll(in: dir) }
        try await Task.sleep(nanoseconds: 100_000_000)
        try commitAndClose(writer)

        let rows = try await scanTask.value
        #expect(rows.map(\.id) == ["msg_1"])
    }

    @Test("锁持有超过 busy_timeout 时有界失败且不无限挂起")
    func busyTimeoutFailsAfterBoundedWait() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try buildMiniDB(
            at: dir.appendingPathComponent("opencode.db"),
            sessions: [("ses", "/project")],
            messages: [("msg_1", "ses", 100, #"{"role":"assistant","tokens":{"input":1,"output":1,"reasoning":0,"cache":{"read":0,"write":0}}}"#)]
        )

        // 写连接持续持有 EXCLUSIVE 锁直到测试结束
        let writer = try openWriterHoldingExclusiveLock(at: dir.appendingPathComponent("opencode.db"))
        defer { try? commitAndClose(writer) }

        let shortTimeoutScanner = OpenCodeSQLiteScanner(busyTimeoutMs: 100)
        let clock = ContinuousClock()
        let start = clock.now
        do {
            _ = try shortTimeoutScanner.scanAll(in: dir)
            Issue.record("锁持续持有时应抛错")
        } catch let err as OpenCodeScannerError {
            guard case .queryFailed(let code, _) = err else {
                Issue.record("错误类型不对: \(err)")
                return
            }
            #expect(code == SQLITE_BUSY)
            let elapsed = start.duration(to: clock.now)
            // 至少等待了注入的 timeout，且远早于无限挂起（上界仅为防回归护栏）
            #expect(elapsed >= .milliseconds(50))
            #expect(elapsed < .seconds(5))
        }
    }

    // MARK: - 2.0 schema(session_message / session_v2)

    @Test("2.0 schema 只读取 assistant 行,目录取自 session_v2")
    func readsSessionMessageAssistantRows() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try buildV2DB(
            at: dir.appendingPathComponent("opencode.db"),
            sessionsV2: [SessionV2Fixture(id: "ses_a", directory: "/proj/A")],
            messages: [
                SessionMessageFixture(id: "msg_user", sessionID: "ses_a", type: "user",
                                      seq: 1, timeMs: 100, dataJSON: #"{"content":"hi"}"#),
                assistantFixture("msg_1", sessionID: "ses_a", seq: 2, timeMs: 200),
            ]
        )

        let rows = try scanner.scanAll(in: dir)
        try #require(rows.count == 1)
        #expect(rows[0].id == "msg_1")
        #expect(rows[0].role == "assistant")
        #expect(rows[0].directory == "/proj/A")
        #expect(rows[0].timeCreatedMs == 200)
    }

    @Test("旧 message 表中已存在于 session_message 的消息不重复读取,仅补充 v2 缺失的消息")
    func legacyRowsCoveredByV2AreNotDuplicated() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try buildV2DB(
            at: dir.appendingPathComponent("opencode.db"),
            sessionsV2: [SessionV2Fixture(id: "ses_a", directory: "/v2/dir")],
            messages: [assistantFixture("msg_shared", sessionID: "ses_a", seq: 1, timeMs: 100)],
            legacySessions: [(id: "ses_a", directory: "/legacy/dir")],
            legacyMessages: [
                (id: "msg_shared", sessionID: "ses_a", timeMs: 100, dataJSON: #"{"role":"assistant"}"#),
                (id: "msg_legacy", sessionID: "ses_a", timeMs: 50, dataJSON: #"{"role":"assistant"}"#),
            ]
        )

        let rows = try scanner.scanAll(in: dir)
        #expect(rows.map(\.id) == ["msg_legacy", "msg_shared"])
        #expect(rows.first(where: { $0.id == "msg_legacy" })?.directory == "/legacy/dir")
        #expect(rows.first(where: { $0.id == "msg_shared" })?.directory == "/v2/dir")
    }

    @Test("through 分叉点及之前的复制行被跳过,子会话自己的用量保留")
    func forkCopiesThroughBoundaryAreSkipped() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try buildV2DB(
            at: dir.appendingPathComponent("opencode.db"),
            sessionsV2: [
                SessionV2Fixture(id: "ses_parent", directory: "/proj"),
                SessionV2Fixture(id: "ses_fork", directory: "/proj",
                                 forkSessionID: "ses_parent",
                                 forkBoundary: #"{"type":"through","messageID":"msg_p3"}"#),
            ],
            messages: [
                assistantFixture("msg_p1", sessionID: "ses_parent", seq: 1, timeMs: 100),
                assistantFixture("msg_p3", sessionID: "ses_parent", seq: 3, timeMs: 300),
                // 复制行:新 id,但保留父会话的 seq
                assistantFixture("msg_c1", sessionID: "ses_fork", seq: 1, timeMs: 100),
                assistantFixture("msg_c3", sessionID: "ses_fork", seq: 3, timeMs: 300),
                // 子会话自己的用量
                assistantFixture("msg_c4", sessionID: "ses_fork", seq: 4, timeMs: 500),
            ]
        )

        let rows = try scanner.scanAll(in: dir)
        #expect(rows.map(\.id) == ["msg_p1", "msg_p3", "msg_c4"])
    }

    @Test("before 分叉点只跳过其之前的复制行,截止值取分叉点之前的最大 seq 而非 seq - 1")
    func forkBeforeBoundarySkipsOnlyEarlierCopies() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try buildV2DB(
            at: dir.appendingPathComponent("opencode.db"),
            sessionsV2: [
                SessionV2Fixture(id: "ses_parent", directory: "/proj"),
                SessionV2Fixture(id: "ses_fork", directory: "/proj",
                                 forkSessionID: "ses_parent",
                                 forkBoundary: #"{"type":"before","messageID":"msg_p4"}"#),
            ],
            messages: [
                assistantFixture("msg_p1", sessionID: "ses_parent", seq: 1, timeMs: 100),
                assistantFixture("msg_p2", sessionID: "ses_parent", seq: 2, timeMs: 200),
                // 父会话 seq 3 缺失;子会话自己的第一条行接在复制行之后取得 seq 3,不应被跳过
                assistantFixture("msg_p4", sessionID: "ses_parent", seq: 4, timeMs: 400),
                assistantFixture("msg_p5", sessionID: "ses_parent", seq: 5, timeMs: 500),
                assistantFixture("msg_c1", sessionID: "ses_fork", seq: 1, timeMs: 100),
                assistantFixture("msg_c2", sessionID: "ses_fork", seq: 2, timeMs: 200),
                assistantFixture("msg_c3", sessionID: "ses_fork", seq: 3, timeMs: 350),
            ]
        )

        let rows = try scanner.scanAll(in: dir)
        #expect(rows.map(\.id) == ["msg_p1", "msg_p2", "msg_c3", "msg_p4", "msg_p5"])
    }

    @Test("分叉点无法解析(父行缺失或 JSON 非法)时保留子会话全部行")
    func unresolvableForkBoundaryKeepsAllRows() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try buildV2DB(
            at: dir.appendingPathComponent("opencode.db"),
            sessionsV2: [
                SessionV2Fixture(id: "ses_parent", directory: "/proj"),
                SessionV2Fixture(id: "ses_missing", directory: "/proj",
                                 forkSessionID: "ses_parent",
                                 forkBoundary: #"{"type":"through","messageID":"msg_gone"}"#),
                SessionV2Fixture(id: "ses_broken", directory: "/proj",
                                 forkSessionID: "ses_parent",
                                 forkBoundary: "not json"),
            ],
            messages: [
                assistantFixture("msg_p1", sessionID: "ses_parent", seq: 1, timeMs: 100),
                assistantFixture("msg_a1", sessionID: "ses_missing", seq: 1, timeMs: 100),
                assistantFixture("msg_a2", sessionID: "ses_missing", seq: 2, timeMs: 200),
                assistantFixture("msg_b1", sessionID: "ses_broken", seq: 1, timeMs: 150),
            ]
        )

        let rows = try scanner.scanAll(in: dir)
        #expect(rows.count == 4)
        #expect(Set(rows.map(\.id)) == ["msg_p1", "msg_a1", "msg_a2", "msg_b1"])
    }

    @Test("缺少 seq 与 fork 字段的旧版 2.0 schema 仍能读取 assistant 行")
    func olderV2SchemaWithoutSeqOrForkColumnsStillLoads() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try buildV2DB(
            at: dir.appendingPathComponent("opencode.db"),
            sessionsV2: [SessionV2Fixture(id: "ses_a", directory: "/proj")],
            messages: [assistantFixture("msg_1", sessionID: "ses_a", seq: 1, timeMs: 100)],
            withSeqAndForkColumns: false
        )

        let rows = try scanner.scanAll(in: dir)
        #expect(rows.map(\.id) == ["msg_1"])
        #expect(rows.first?.directory == "/proj")
    }

    // MARK: - Helpers

    /// 在临时目录用 sqlite3 C API 构造 opencode mini schema(只含本测试用到的列约束)
    private func buildMiniDB(at url: URL,
                              sessions: [(id: String, directory: String)],
                              messages: [(id: String, sessionID: String, timeMs: Int64, dataJSON: String)]) throws {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db,
                              SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK,
              let database = db else {
            throw NSError(domain: "test.sqlite", code: 1)
        }
        defer { sqlite3_close(database) }

        // 极简 schema:仅满足 Scanner 的 SELECT m.id, m.session_id, m.time_created, m.data, s.directory
        let schema = """
        CREATE TABLE session (id TEXT PRIMARY KEY, directory TEXT NOT NULL);
        CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT NOT NULL,
                              time_created INTEGER NOT NULL, data TEXT NOT NULL);
        """
        var errMsg: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, schema, nil, nil, &errMsg) == SQLITE_OK else {
            sqlite3_free(errMsg)
            throw NSError(domain: "test.sqlite", code: 2)
        }

        for s in sessions {
            let sql = "INSERT INTO session (id, directory) VALUES (?, ?);"
            try execInsert(database: database, sql: sql, binds: [s.id, s.directory])
        }
        for m in messages {
            let sql = "INSERT INTO message (id, session_id, time_created, data) VALUES (?, ?, ?, ?);"
            // time_created 在 SQL 第 3 列(1-indexed),其余三列为 TEXT
            try execInsertMixed(database: database, sql: sql,
                                texts: [m.id, m.sessionID, m.dataJSON],
                                ints: [(3, m.timeMs)])
        }
    }

    private func execInsert(database: OpaquePointer, sql: String, binds: [String]) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw NSError(domain: "test.sqlite", code: 3)
        }
        defer { sqlite3_finalize(stmt) }
        for (i, s) in binds.enumerated() {
            sqlite3_bind_text(stmt, Int32(i + 1), s, -1, SQLITE_TRANSIENT_DESTRUCTOR)
        }
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw NSError(domain: "test.sqlite", code: 4)
        }
    }

    /// 混合绑定:texts 按 [1,2,4] 顺序填(跳过 ints 占位的列号)
    private func execInsertMixed(database: OpaquePointer, sql: String,
                                  texts: [String], ints: [(col: Int32, value: Int64)]) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw NSError(domain: "test.sqlite", code: 3)
        }
        defer { sqlite3_finalize(stmt) }

        let intCols = Set(ints.map(\.col))
        var ti = 0
        for col: Int32 in 1...4 {
            if intCols.contains(col) {
                let v = ints.first(where: { $0.col == col })!.value
                sqlite3_bind_int64(stmt, col, v)
            } else {
                sqlite3_bind_text(stmt, col, texts[ti], -1, SQLITE_TRANSIENT_DESTRUCTOR)
                ti += 1
            }
        }
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw NSError(domain: "test.sqlite", code: 4)
        }
    }

    private struct SessionV2Fixture {
        let id: String
        let directory: String
        var forkSessionID: String? = nil
        var forkBoundary: String? = nil
    }

    private struct SessionMessageFixture {
        let id: String
        let sessionID: String
        let type: String
        let seq: Int64
        let timeMs: Int64
        let dataJSON: String
    }

    private enum SQLValue {
        case text(String)
        case int(Int64)
        case null
    }

    private func assistantFixture(_ id: String, sessionID: String, seq: Int64, timeMs: Int64) -> SessionMessageFixture {
        SessionMessageFixture(
            id: id, sessionID: sessionID, type: "assistant", seq: seq, timeMs: timeMs,
            dataJSON: #"{"tokens":{"input":1,"output":1,"reasoning":0,"cache":{"read":0,"write":0}}}"#
        )
    }

    /// 构造 2.0 mini schema(session_v2 / session_message),并附带旧版 session / message 表。
    /// `withSeqAndForkColumns` 为 false 时模拟缺少 seq 与 fork 字段的早期 2.0 schema。
    private func buildV2DB(
        at url: URL,
        sessionsV2: [SessionV2Fixture],
        messages: [SessionMessageFixture],
        legacySessions: [(id: String, directory: String)] = [],
        legacyMessages: [(id: String, sessionID: String, timeMs: Int64, dataJSON: String)] = [],
        withSeqAndForkColumns: Bool = true
    ) throws {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK,
              let database = db else {
            throw NSError(domain: "test.sqlite", code: 1)
        }
        defer { sqlite3_close(database) }

        let sessionV2Schema = withSeqAndForkColumns
            ? "CREATE TABLE session_v2 (id TEXT PRIMARY KEY, directory TEXT NOT NULL, fork_session_id TEXT, fork_boundary TEXT);"
            : "CREATE TABLE session_v2 (id TEXT PRIMARY KEY, directory TEXT NOT NULL);"
        let sessionMessageSchema = withSeqAndForkColumns
            ? "CREATE TABLE session_message (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, type TEXT NOT NULL, seq INTEGER NOT NULL, time_created INTEGER NOT NULL, data TEXT NOT NULL);"
            : "CREATE TABLE session_message (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, type TEXT NOT NULL, time_created INTEGER NOT NULL, data TEXT NOT NULL);"
        let legacySchema = """
        CREATE TABLE session (id TEXT PRIMARY KEY, directory TEXT NOT NULL);
        CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, time_created INTEGER NOT NULL, data TEXT NOT NULL);
        """
        try execSchema(database, sessionV2Schema + sessionMessageSchema + legacySchema)

        for session in sessionsV2 {
            if withSeqAndForkColumns {
                try insertRow(
                    database,
                    "INSERT INTO session_v2 (id, directory, fork_session_id, fork_boundary) VALUES (?1, ?2, ?3, ?4);",
                    [
                        .text(session.id),
                        .text(session.directory),
                        session.forkSessionID.map { SQLValue.text($0) } ?? .null,
                        session.forkBoundary.map { SQLValue.text($0) } ?? .null,
                    ]
                )
            } else {
                try insertRow(
                    database,
                    "INSERT INTO session_v2 (id, directory) VALUES (?1, ?2);",
                    [.text(session.id), .text(session.directory)]
                )
            }
        }
        for message in messages {
            if withSeqAndForkColumns {
                try insertRow(
                    database,
                    "INSERT INTO session_message (id, session_id, type, seq, time_created, data) VALUES (?1, ?2, ?3, ?4, ?5, ?6);",
                    [
                        .text(message.id),
                        .text(message.sessionID),
                        .text(message.type),
                        .int(message.seq),
                        .int(message.timeMs),
                        .text(message.dataJSON),
                    ]
                )
            } else {
                try insertRow(
                    database,
                    "INSERT INTO session_message (id, session_id, type, time_created, data) VALUES (?1, ?2, ?3, ?4, ?5);",
                    [
                        .text(message.id),
                        .text(message.sessionID),
                        .text(message.type),
                        .int(message.timeMs),
                        .text(message.dataJSON),
                    ]
                )
            }
        }
        for session in legacySessions {
            try insertRow(
                database,
                "INSERT INTO session (id, directory) VALUES (?1, ?2);",
                [.text(session.id), .text(session.directory)]
            )
        }
        for message in legacyMessages {
            try insertRow(
                database,
                "INSERT INTO message (id, session_id, time_created, data) VALUES (?1, ?2, ?3, ?4);",
                [.text(message.id), .text(message.sessionID), .int(message.timeMs), .text(message.dataJSON)]
            )
        }
    }

    private func execSchema(_ database: OpaquePointer, _ sql: String) throws {
        var errMsg: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errMsg) == SQLITE_OK else {
            sqlite3_free(errMsg)
            throw NSError(domain: "test.sqlite", code: 2)
        }
    }

    private func insertRow(_ database: OpaquePointer, _ sql: String, _ values: [SQLValue]) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw NSError(domain: "test.sqlite", code: 3)
        }
        defer { sqlite3_finalize(stmt) }
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case .text(let text):
                sqlite3_bind_text(stmt, position, text, -1, SQLITE_TRANSIENT_DESTRUCTOR)
            case .int(let number):
                sqlite3_bind_int64(stmt, position, number)
            case .null:
                sqlite3_bind_null(stmt, position)
            }
        }
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw NSError(domain: "test.sqlite", code: 4)
        }
    }

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("opencode-scanner-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 打开写连接并立即 BEGIN EXCLUSIVE 持有排他锁
    /// （mini db 使用默认 journal 模式，EXCLUSIVE 锁会阻塞其他连接的读锁）
    private func openWriterHoldingExclusiveLock(at dbURL: URL) throws -> OpaquePointer {
        var writer: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &writer, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
              let database = writer else {
            throw NSError(domain: "test.sqlite", code: 5)
        }
        var errMsg: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, "BEGIN EXCLUSIVE", nil, nil, &errMsg) == SQLITE_OK else {
            sqlite3_free(errMsg)
            sqlite3_close(database)
            throw NSError(domain: "test.sqlite", code: 6)
        }
        return database
    }

    private func commitAndClose(_ writer: OpaquePointer) throws {
        var errMsg: UnsafeMutablePointer<CChar>?
        sqlite3_exec(writer, "COMMIT", nil, nil, &errMsg)
        sqlite3_free(errMsg)
        sqlite3_close(writer)
    }
}
