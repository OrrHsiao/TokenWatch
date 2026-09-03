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

    @Test("若本地存在真实的 Antigravity 目录，能成功无损扫描且无报错")
    func scansRealLocalAntigravityIfPresent() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let localAntigravity = home.appendingPathComponent(".gemini/antigravity")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: localAntigravity.path, isDirectory: &isDir), isDir.boolValue else {
            return
        }

        let provider = AntigravityProvider()
        #expect(provider.validateDataRoot(localAntigravity) == .valid)

        let entries = try provider.loadEntries(from: localAntigravity)
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
        steps: [(idx: Int64, metadata: Data)]
    ) throws {
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
