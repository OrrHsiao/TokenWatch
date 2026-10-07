import Foundation
import SQLite3
import os.log

enum AntigravityScannerError: AppLocalizedError, CustomStringConvertible {
    case databaseNotFound(URL)
    case openFailed(code: Int32, message: String)
    case queryFailed(code: Int32, message: String)

    var description: String {
        localizedDescription(language: .zhHans)
    }

    func localizedDescription(language: AppLanguage) -> String {
        switch self {
        case .databaseNotFound(let url):
            return "Antigravity database not found: \(url.path)"
        case .openFailed(let code, let msg):
            return "Failed to open Antigravity database (\(code)): \(msg)"
        case .queryFailed(let code, let msg):
            return "Failed to query Antigravity database (\(code)): \(msg)"
        }
    }
}

/// 扫描 Antigravity 会话目录下的所有 SQLite 数据库
///
/// 设计原因：
/// 1. Antigravity 每个会话独立一个 `<uuid>.db`，存储在 `conversations/` 下。
/// 2. 使用 `file:<path>?mode=ro` 只读打开。若遇到没有 `-shm` 的已归档数据库，自动回退到 `immutable=1` 避免 `CANTOPEN`。
/// 3. 设置 `sqlite3_busy_timeout`，避免与运行中的 Antigravity 写入发生排他锁冲突。
/// 4. 对「WAL 模式且已 checkpoint（无 `-wal`/`-shm`）」的归档库直接走 `immutable=1`：
///    这类库的只读连接无法建立 WAL 索引，`mode=ro` 首次查询必然失败，
///    先试一次只会让每轮扫描白白多出一倍的打开次数。
final class AntigravitySQLiteScanner: Sendable {

    private let logger = Logger(subsystem: "com.xiaoao.TokenWatch", category: "AntigravitySQLiteScanner")
    private let busyTimeoutMs: Int32

    init(busyTimeoutMs: Int32 = 2000) {
        self.busyTimeoutMs = busyTimeoutMs
    }

    /// 在指定数据根目录下发现所有 conversations 数据库文件
    /// - Parameter rootURL: 用户授权的数据根目录（推荐 `~/.gemini`，亦支持 `~/.gemini/antigravity` 或 `~/.gemini/antigravity-cli`）
    /// - Returns: 匹配的 `.db` 文件 URL 列表
    func locateDatabaseFiles(in rootURL: URL) -> [URL] {
        var candidateDirs: [URL] = []

        // 1. 直接是 conversations 目录
        if rootURL.lastPathComponent == "conversations" {
            candidateDirs.append(rootURL)
        }

        // 2. rootURL 下包含 conversations 目录（如 ~/.gemini/antigravity 或 ~/.gemini/antigravity-cli）
        let directConversations = rootURL.appendingPathComponent("conversations", isDirectory: true)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: directConversations.path, isDirectory: &isDir), isDir.boolValue {
            candidateDirs.append(directConversations)
        }

        // 3. rootURL 为 ~/.gemini，可能包含 antigravity/conversations、antigravity-cli/conversations 与 antigravity-ide/conversations
        for sub in ["antigravity", "antigravity-cli", "antigravity-ide"] {
            let nested = rootURL.appendingPathComponent(sub, isDirectory: true)
                .appendingPathComponent("conversations", isDirectory: true)
            var nestedIsDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: nested.path, isDirectory: &nestedIsDir), nestedIsDir.boolValue {
                candidateDirs.append(nested)
            }
        }

        // 4. rootURL 本身可能直接包含 *.db 文件
        candidateDirs.append(rootURL)

        var dbFiles: [URL] = []
        var seenPaths = Set<String>()

        for dir in candidateDirs {
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for fileURL in contents {
                let name = fileURL.lastPathComponent
                if fileURL.pathExtension == "db" && !name.contains("-shm") && !name.contains("-wal") {
                    if seenPaths.insert(fileURL.path).inserted {
                        dbFiles.append(fileURL)
                    }
                }
            }
        }

        return dbFiles.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// 扫描数据根下所有 Antigravity 会话并提取原始记录
    /// - Parameter rootURL: 用户授权的数据根目录
    /// - Returns: 所有会话数据库的扫描结果列表
    func scanAll(in rootURL: URL) throws -> [AntigravityConversationScanResult] {
        let dbURLs = locateDatabaseFiles(in: rootURL)
        guard !dbURLs.isEmpty else {
            logger.info("未在目录中找到任何 Antigravity 会话数据库: \(rootURL.path)")
            return []
        }

        var results: [AntigravityConversationScanResult] = []
        for dbURL in dbURLs {
            if let result = try scanSingleDatabase(at: dbURL) {
                results.append(result)
            }
        }

        logger.info("Antigravity 扫描完成: 扫描了 \(dbURLs.count) 个数据库，有效会话 \(results.count) 个")
        return results
    }

    /// 扫描单个会话数据库
    private func scanSingleDatabase(at dbURL: URL) throws -> AntigravityConversationScanResult? {
        guard let database = openDatabase(at: dbURL) else {
            return nil
        }
        defer { sqlite3_close(database) }

        // 1. 读取 trajectory_id（若无则取文件名）
        let conversationID = readTrajectoryID(from: database) ?? dbURL.deletingPathExtension().lastPathComponent

        // 2. 读取 workspace 路径（项目工程目录）
        let workspacePath = readWorkspacePath(from: database)

        // 3. 读取 steps 表的时间戳映射
        let stepTimestamps = readStepTimestamps(from: database)

        // 4. 读取 gen_metadata 表的生成记录
        let generations = try readGenerations(from: database, trajectoryID: conversationID)

        guard !generations.isEmpty else {
            return nil
        }

        return AntigravityConversationScanResult(
            conversationID: conversationID,
            databaseURL: dbURL,
            workspacePath: workspacePath,
            generations: generations,
            stepTimestamps: stepTimestamps
        )
    }

    /// 打开单个数据库连接。
    ///
    /// 先按库的物理状态决定两种打开模式的尝试顺序（见 `prefersImmutableOpen`），
    /// 再逐个用 `SELECT 1;` 探针确认连接真的可用；两种模式都失败时记录告警并跳过该库。
    /// - Parameter dbURL: 会话数据库文件。
    /// - Returns: 可用的只读连接；两种模式均无法打开时返回 `nil`。
    private func openDatabase(at dbURL: URL) -> OpaquePointer? {
        let readOnlyURI = "file:\(dbURL.path)?mode=ro"
        let immutableURI = "file:\(dbURL.path)?immutable=1"
        let candidates = prefersImmutableOpen(at: dbURL)
            ? [immutableURI, readOnlyURI]
            : [readOnlyURI, immutableURI]

        for uri in candidates {
            if let database = openAndProbe(uri: uri) {
                return database
            }
        }

        logger.warning("无法以只读或不可变模式打开会话数据库: \(dbURL.lastPathComponent)")
        return nil
    }

    /// 以指定 URI 打开数据库并执行 `SELECT 1;` 探针。
    ///
    /// 只读沙盒或缺少 `-shm` 时 `sqlite3_open_v2` 可能返回成功、但首次查询才报 `CANTOPEN`，
    /// 因此必须用真实查询而非仅看 open 的返回码判断连接是否可用。
    /// - Parameter uri: 带 `mode=ro` 或 `immutable=1` 的 SQLite URI。
    /// - Returns: 探针通过时的连接；open 或探针失败时返回 `nil`（连接已关闭）。
    private func openAndProbe(uri: String) -> OpaquePointer? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK,
              let database = db else {
            if let database = db {
                sqlite3_close(database)
            }
            return nil
        }

        sqlite3_busy_timeout(database, busyTimeoutMs)

        var testStmt: OpaquePointer?
        let prep = sqlite3_prepare_v2(database, "SELECT 1;", -1, &testStmt, nil)
        sqlite3_finalize(testStmt)
        guard prep == SQLITE_OK else {
            sqlite3_close(database)
            return nil
        }
        return database
    }

    /// 判断是否应优先用 `immutable=1` 打开。
    ///
    /// WAL 模式的库需要 `-shm` 索引才能被只读连接读取；Antigravity 归档后 `-wal` 与 `-shm`
    /// 会随 checkpoint 一起消失，此时 `mode=ro` 的连接虽然在 `sqlite3_open_v2` 阶段返回成功，
    /// 但首次查询必然以 `CANTOPEN` 失败。实测本机 55 个会话库全部处于该状态，
    /// 因此先探测一次注定失败的连接，会让每轮扫描多做一倍的打开。
    /// `immutable=1` 跳过 WAL 机制，对这类已归档文件既正确又更快。
    ///
    /// 只要 `-wal` 或 `-shm` 仍存在，就说明该库可能仍有活跃写入或未合并的 WAL，
    /// 此时保持原顺序（`mode=ro` 优先），以便读到 WAL 中的最新内容。
    /// - Parameter dbURL: 会话数据库文件。
    /// - Returns: 库声明为 WAL 模式且 `-wal`/`-shm` 均不存在时返回 `true`。
    private func prefersImmutableOpen(at dbURL: URL) -> Bool {
        guard Self.declaresWALMode(at: dbURL) else { return false }

        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: dbURL.path + "-wal"),
              !fileManager.fileExists(atPath: dbURL.path + "-shm") else {
            return false
        }
        return true
    }

    /// 读取 SQLite 文件头判断日志模式。
    ///
    /// 头两个版本字节（偏移 18/19）同时为 2 表示 WAL，为 1 表示传统 rollback journal。
    /// 读取失败或文件过短时返回 `false`，让调用方退回原有的两段式尝试。
    /// - Parameter dbURL: 会话数据库文件。
    /// - Returns: 头部声明为 WAL 模式时返回 `true`。
    private static func declaresWALMode(at dbURL: URL) -> Bool {
        let headerMinimumLength = 20
        let journalModeOffset = 18
        let walVersion: UInt8 = 2

        guard let handle = try? FileHandle(forReadingFrom: dbURL) else { return false }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: headerMinimumLength),
              header.count >= headerMinimumLength else {
            return false
        }

        let base = header.startIndex
        return header[base + journalModeOffset] == walVersion
            && header[base + journalModeOffset + 1] == walVersion
    }

    private func readTrajectoryID(from database: OpaquePointer) -> String? {
        let query = "SELECT trajectory_id FROM trajectory_meta LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &stmt, nil) == SQLITE_OK, let statement = stmt else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        if sqlite3_step(statement) == SQLITE_ROW, let cStr = sqlite3_column_text(statement, 0) {
            return String(cString: cStr)
        }
        return nil
    }

    private func readWorkspacePath(from database: OpaquePointer) -> String? {
        let query = "SELECT data FROM trajectory_metadata_blob WHERE id = 'main' LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &stmt, nil) == SQLITE_OK, let statement = stmt else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW,
              let blobPtr = sqlite3_column_blob(statement, 0) else {
            return nil
        }
        let blobBytes = sqlite3_column_bytes(statement, 0)
        guard blobBytes > 0 else { return nil }

        let data = Data(bytes: blobPtr, count: Int(blobBytes))
        return AntigravityProtoReader.decodeWorkspacePath(from: data)
    }

    private func readStepTimestamps(from database: OpaquePointer) -> [Int64: Date] {
        let query = "SELECT idx, metadata FROM steps WHERE metadata IS NOT NULL;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &stmt, nil) == SQLITE_OK, let statement = stmt else {
            return [:]
        }
        defer { sqlite3_finalize(statement) }

        var timestamps: [Int64: Date] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            let idx = sqlite3_column_int64(statement, 0)
            guard let blobPtr = sqlite3_column_blob(statement, 1) else { continue }
            let blobBytes = sqlite3_column_bytes(statement, 1)
            guard blobBytes > 0 else { continue }

            let data = Data(bytes: blobPtr, count: Int(blobBytes))
            if let date = AntigravityProtoReader.decodeStepTimestamp(from: data) {
                timestamps[idx] = date
            }
        }
        return timestamps
    }

    private func readGenerations(from database: OpaquePointer, trajectoryID: String) throws -> [AntigravityRawGenerationRow] {
        let query = "SELECT idx, data FROM gen_metadata WHERE size > 0 ORDER BY idx;"
        var stmt: OpaquePointer?
        let prepCode = sqlite3_prepare_v2(database, query, -1, &stmt, nil)
        guard prepCode == SQLITE_OK, let statement = stmt else {
            // 如果表不存在，忽略并返回空
            return []
        }
        defer { sqlite3_finalize(statement) }

        var rows: [AntigravityRawGenerationRow] = []
        while true {
            let stepCode = sqlite3_step(statement)
            if stepCode == SQLITE_DONE { break }
            guard stepCode == SQLITE_ROW else {
                let msg = String(cString: sqlite3_errmsg(database))
                throw AntigravityScannerError.queryFailed(code: stepCode, message: msg)
            }

            let idx = sqlite3_column_int64(statement, 0)
            guard let blobPtr = sqlite3_column_blob(statement, 1) else { continue }
            let blobBytes = sqlite3_column_bytes(statement, 1)
            guard blobBytes > 0 else { continue }

            let data = Data(bytes: blobPtr, count: Int(blobBytes))
            rows.append(AntigravityRawGenerationRow(
                trajectoryID: trajectoryID,
                genIdx: idx,
                dataBlob: data
            ))
        }

        return rows
    }
}
