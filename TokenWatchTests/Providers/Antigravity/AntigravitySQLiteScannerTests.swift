import Foundation
import SQLite3
import Testing
@testable import TokenWatch

private let SQLITE_TRANSIENT_DESTRUCTOR = unsafeBitCast(
    OpaquePointer(bitPattern: -1),
    to: sqlite3_destructor_type.self
)

@Suite("AntigravitySQLiteScanner")
struct AntigravitySQLiteScannerTests {

    let scanner = AntigravitySQLiteScanner()

    @Test("正确发现 conversations 目录下的所有 .db 文件并忽略 -shm 和 -wal")
    func locatesDatabaseFilesCorrectly() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let convDir = root.appendingPathComponent("conversations", isDirectory: true)
        try FileManager.default.createDirectory(at: convDir, withIntermediateDirectories: true)

        try Data().write(to: convDir.appendingPathComponent("conv-1.db"))
        try Data().write(to: convDir.appendingPathComponent("conv-1.db-shm"))
        try Data().write(to: convDir.appendingPathComponent("conv-1.db-wal"))
        try Data().write(to: convDir.appendingPathComponent("conv-2.db"))

        let found = scanner.locateDatabaseFiles(in: root)
        #expect(found.map(\.lastPathComponent) == ["conv-1.db", "conv-2.db"])
    }

    @Test("扫描 mini Antigravity SQLite 数据库能提取 generations 与 steps 时间戳")
    func scansMiniDatabaseSuccessfully() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let convDir = root.appendingPathComponent("conversations", isDirectory: true)
        try FileManager.default.createDirectory(at: convDir, withIntermediateDirectories: true)

        let dbURL = convDir.appendingPathComponent("test-conv.db")

        // 构造 step 时间戳 proto (Tag 1 -> Tag 1 seconds = 1785300000)
        let stepMeta = makeSubmessage(tag: 1, content: makeVarintField(tag: 1, value: 1785300000))
        let genData = Data([0x0A, 0x04, 0x08, 0x01, 0x10, 0x02])

        try buildMiniAntigravityDB(
            at: dbURL,
            trajectoryId: "traj-uuid-1",
            generations: [(idx: 0, data: genData)],
            steps: [(idx: 5, metadata: stepMeta)]
        )

        let results = try scanner.scanAll(in: root)
        try! #require(results.count == 1)

        let res = results[0]
        #expect(res.conversationID == "traj-uuid-1")
        #expect(res.generations.count == 1)
        #expect(res.generations[0].genIdx == 0)
        #expect(res.generations[0].dataBlob == genData)
        #expect(res.stepTimestamps[5]?.timeIntervalSince1970 == 1785300000)
    }

    @Test("WAL 模式且已 checkpoint（无 -wal/-shm）的归档库仍能被完整扫描")
    func scansArchivedWALDatabaseWithoutShm() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let convDir = root.appendingPathComponent("conversations", isDirectory: true)
        try FileManager.default.createDirectory(at: convDir, withIntermediateDirectories: true)

        // 文件名不能含 "-wal"/"-shm"，否则会被 locateDatabaseFiles 当作附属文件过滤掉。
        let dbURL = convDir.appendingPathComponent("archived-conv.db")
        let genData = Data([0x0A, 0x04, 0x08, 0x01, 0x10, 0x02])

        try buildMiniAntigravityDB(
            at: dbURL,
            trajectoryId: "traj-archived-1",
            generations: [(idx: 0, data: genData)],
            steps: [],
            journalMode: "WAL"
        )
        try archiveWALDatabase(at: dbURL)

        // 夹具自校验：必须是 WAL 头且 -wal/-shm 都已移除，
        // 否则用例会退化成普通 rollback 库，覆盖不到 prefersImmutableOpen。
        let header = try Data(contentsOf: dbURL, options: .mappedIfSafe).prefix(20)
        #expect(header.count == 20)
        #expect(header[18] == 2 && header[19] == 2)
        #expect(!FileManager.default.fileExists(atPath: dbURL.path + "-wal"))
        #expect(!FileManager.default.fileExists(atPath: dbURL.path + "-shm"))

        let results = try scanner.scanAll(in: root)
        try #require(results.count == 1)
        #expect(results[0].conversationID == "traj-archived-1")
        #expect(results[0].generations.count == 1)
        #expect(results[0].generations[0].dataBlob == genData)
    }

    @Test("存在活跃 -wal 时仍能读到尚未 checkpoint 的最新写入")
    func readsLiveWALDatabase() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let convDir = root.appendingPathComponent("conversations", isDirectory: true)
        try FileManager.default.createDirectory(at: convDir, withIntermediateDirectories: true)

        let dbURL = convDir.appendingPathComponent("live-conv.db")
        let checkpointed = Data([0x0A, 0x04, 0x08, 0x01, 0x10, 0x02])
        let freshInWAL = Data([0x0A, 0x04, 0x08, 0x03, 0x10, 0x04])

        try buildMiniAntigravityDB(
            at: dbURL,
            trajectoryId: "traj-live-1",
            generations: [(idx: 0, data: checkpointed)],
            steps: [],
            journalMode: "delete"
        )

        // 模拟 Antigravity 正在写入：切到 WAL 后追加一行并保持连接不关闭，
        // 使 -wal/-shm 存在且该行只存在于 WAL 中。
        var writer: OpaquePointer?
        try #require(sqlite3_open_v2(
            dbURL.path,
            &writer,
            SQLITE_OPEN_READWRITE,
            nil
        ) == SQLITE_OK)
        let database = try #require(writer)
        defer { sqlite3_close(database) }

        try #require(sqlite3_exec(database, "PRAGMA journal_mode=WAL;", nil, nil, nil) == SQLITE_OK)
        var insert: OpaquePointer?
        try #require(sqlite3_prepare_v2(
            database,
            "INSERT INTO gen_metadata (idx, data, size) VALUES (1, ?, ?);",
            -1,
            &insert,
            nil
        ) == SQLITE_OK)
        let statement = try #require(insert)
        freshInWAL.withUnsafeBytes { ptr in
            sqlite3_bind_blob(statement, 1, ptr.baseAddress, Int32(freshInWAL.count), SQLITE_TRANSIENT_DESTRUCTOR)
        }
        sqlite3_bind_int(statement, 2, Int32(freshInWAL.count))
        try #require(sqlite3_step(statement) == SQLITE_DONE)
        sqlite3_finalize(statement)

        #expect(FileManager.default.fileExists(atPath: dbURL.path + "-wal"))

        // 保持写连接打开的前提下扫描，必须同时看到已 checkpoint 与仅存在于 WAL 的两条记录。
        let results = try scanner.scanAll(in: root)
        try #require(results.count == 1)
        #expect(results[0].generations.count == 2)
        #expect(results[0].generations.map(\.dataBlob) == [checkpointed, freshInWAL])
    }

    @Test("空目录或不存在的目录返回空数组而不抛错")
    func emptyOrMissingDirectoryReturnsEmpty() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let results = try scanner.scanAll(in: root)
        #expect(results.isEmpty)

        let nonExistent = root.appendingPathComponent("not-here")
        let resultsNonExistent = try scanner.scanAll(in: nonExistent)
        #expect(resultsNonExistent.isEmpty)
    }

    /// 注意：本用例在沙盒化的测试宿主中会**静默空跑**。
    ///
    /// `~/.gemini` 不在 App Sandbox 允许访问的范围内（只有用户通过 NSOpenPanel 授权并
    /// 存为书签的目录才可读），因此 `fileExists` 判定为 false 后直接返回。
    /// 这里显式打印一条跳过提示，避免日志里看不到任何输出时把它误读成
    /// 「已经用真实数据验证过 Antigravity 解析」——真实数据的回归覆盖请以
    /// `scansArchivedWALDatabaseWithoutShm` / `readsLiveWALDatabase` 等夹具用例为准。
    @Test("若本地存在真实的 Antigravity 目录，能成功无损扫描且无报错")
    func scansRealLocalAntigravityIfPresent() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let localGemini = home.appendingPathComponent(".gemini")
        let localAntigravity = home.appendingPathComponent(".gemini/antigravity")
        var isDir: ObjCBool = false
        let targetURL: URL
        if FileManager.default.fileExists(atPath: localGemini.path, isDirectory: &isDir), isDir.boolValue {
            targetURL = localGemini
        } else if FileManager.default.fileExists(atPath: localAntigravity.path, isDirectory: &isDir), isDir.boolValue {
            targetURL = localAntigravity
        } else {
            print("DEBUG_ANTIGRAVITY: SKIPPED — ~/.gemini 在沙盒测试宿主中不可访问，本用例未验证任何真实数据")
            return
        }

        let provider = AntigravityProvider()
        #expect(provider.validateDataRoot(targetURL) == .valid)

        let entries = try provider.loadEntries(from: targetURL)
        print("DEBUG_ANTIGRAVITY: total entries count = \(entries.count)")
        let withTimestamp = entries.filter { $0.timestamp != nil }
        print("DEBUG_ANTIGRAVITY: entries with timestamp = \(withTimestamp.count), without = \(entries.count - withTimestamp.count)")
        let dates = withTimestamp.compactMap(\.timestamp)
        if let minDate = dates.min(), let maxDate = dates.max() {
            print("DEBUG_ANTIGRAVITY: minDate = \(minDate), maxDate = \(maxDate)")
        }
        let cal = Calendar.current
        let todayEntries = entries.filter { entry in
            guard let t = entry.timestamp else { return false }
            return cal.isDateInToday(t)
        }
        print("DEBUG_ANTIGRAVITY: todayEntries count = \(todayEntries.count)")
        for (i, e) in todayEntries.prefix(5).enumerated() {
            print("DEBUG_ANTIGRAVITY: sample today entry [\(i)]: model=\(e.model), in=\(e.usage.inputTokens), out=\(e.usage.outputTokens), time=\(String(describing: e.timestamp))")
        }
        #expect(!entries.isEmpty)
        #expect(entries.allSatisfy { $0.provider == .antigravity })
        #expect(entries.allSatisfy { $0.usage.inputTokens > 0 || $0.usage.outputTokens > 0 })
    }

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("antigravity-scanner-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func buildMiniAntigravityDB(
        at url: URL,
        trajectoryId: String,
        generations: [(idx: Int64, data: Data)],
        steps: [(idx: Int64, metadata: Data)],
        journalMode: String = "delete"
    ) throws {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK,
              let database = db else {
            throw NSError(domain: "test.sqlite", code: 1)
        }
        defer { sqlite3_close(database) }

        // WAL 需要显式开启。注意：连接干净关闭并不会移除 -wal/-shm（实测），
        // 需要归档形态时另调用 archiveWALDatabase(at:)。
        guard sqlite3_exec(database, "PRAGMA journal_mode=\(journalMode);", nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "test.sqlite", code: 3)
        }

        let schema = """
        CREATE TABLE trajectory_meta (trajectory_id TEXT PRIMARY KEY);
        CREATE TABLE steps (idx INTEGER PRIMARY KEY, metadata BLOB);
        CREATE TABLE gen_metadata (idx INTEGER PRIMARY KEY, data BLOB, size INTEGER NOT NULL DEFAULT 0);
        INSERT INTO trajectory_meta (trajectory_id) VALUES ('\(trajectoryId)');
        """
        guard sqlite3_exec(database, schema, nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "test.sqlite", code: 2)
        }

        for s in steps {
            let sql = "INSERT INTO steps (idx, metadata) VALUES (?, ?);"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else { continue }
            sqlite3_bind_int64(stmt, 1, s.idx)
            s.metadata.withUnsafeBytes { ptr in
                sqlite3_bind_blob(stmt, 2, ptr.baseAddress, Int32(s.metadata.count), SQLITE_TRANSIENT_DESTRUCTOR)
            }
            _ = sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }

        for g in generations {
            let sql = "INSERT INTO gen_metadata (idx, data, size) VALUES (?, ?, ?);"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else { continue }
            sqlite3_bind_int64(stmt, 1, g.idx)
            g.data.withUnsafeBytes { ptr in
                sqlite3_bind_blob(stmt, 2, ptr.baseAddress, Int32(g.data.count), SQLITE_TRANSIENT_DESTRUCTOR)
            }
            sqlite3_bind_int(stmt, 3, Int32(g.data.count))
            _ = sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    /// 把 WAL 库整理成 Antigravity 归档后的形态。
    ///
    /// 先 `wal_checkpoint(TRUNCATE)` 把 WAL 内容并入主库，再移除已空的 `-wal`/`-shm`。
    /// 主库文件头仍保留 WAL 标记（字节 18/19 = 2），因此能复现
    /// 「头声明 WAL 但缺少 `-shm`」这一让只读连接必然 CANTOPEN 的形态。
    /// - Parameter dbURL: 目标会话数据库。
    private func archiveWALDatabase(at dbURL: URL) throws {
        var db: OpaquePointer?
        try #require(sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK)
        let database = try #require(db)
        try #require(sqlite3_exec(database, "PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, nil) == SQLITE_OK)
        sqlite3_close(database)

        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: dbURL.path + suffix)
            if FileManager.default.fileExists(atPath: sidecar.path) {
                try FileManager.default.removeItem(at: sidecar)
            }
        }
    }

    private func makeVarint(_ value: UInt64) -> Data {
        var data = Data()
        var v = value
        while v >= 0x80 {
            data.append(UInt8((v & 0x7F) | 0x80))
            v >>= 7
        }
        data.append(UInt8(v & 0x7F))
        return data
    }

    private func makeVarintField(tag: Int, value: UInt64) -> Data {
        let key = UInt64(tag << 3 | 0)
        return makeVarint(key) + makeVarint(value)
    }

    private func makeSubmessage(tag: Int, content: Data) -> Data {
        let key = UInt64(tag << 3 | 2)
        return makeVarint(key) + makeVarint(UInt64(content.count)) + content
    }
}
