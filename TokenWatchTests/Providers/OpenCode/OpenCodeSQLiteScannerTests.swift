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
@Suite("OpenCodeSQLiteScanner")
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

    // MARK: - 错误路径

    @Test("opencode.db 不存在 → databaseNotFound")
    func missingDB() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        do {
            _ = try scanner.scanAll(in: dir)
            Issue.record("应抛错")
        } catch let err as OpenCodeScannerError {
            if case .databaseNotFound = err { return }
            Issue.record("错类型不对: \(err)")
        }
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

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("opencode-scanner-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
