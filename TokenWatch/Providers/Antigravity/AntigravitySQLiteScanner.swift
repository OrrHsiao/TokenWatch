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
final class AntigravitySQLiteScanner: Sendable {

    private let logger = Logger(subsystem: "com.xiaoao.TokenWatch", category: "AntigravitySQLiteScanner")
    private let busyTimeoutMs: Int32

    init(busyTimeoutMs: Int32 = 2000) {
        self.busyTimeoutMs = busyTimeoutMs
    }

    /// 在指定数据根目录下发现所有 conversations 数据库文件
    /// - Parameter rootURL: 用户授权的数据根目录（如 `~/.gemini/antigravity` 或 `~/.gemini`）
    /// - Returns: 匹配的 `.db` 文件 URL 列表
    func locateDatabaseFiles(in rootURL: URL) -> [URL] {
        var candidateDirs: [URL] = []

        // 1. 直接是 conversations 目录
        if rootURL.lastPathComponent == "conversations" {
            candidateDirs.append(rootURL)
        }

        // 2. rootURL 下包含 conversations 目录（如 ~/.gemini/antigravity）
        let directConversations = rootURL.appendingPathComponent("conversations", isDirectory: true)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: directConversations.path, isDirectory: &isDir), isDir.boolValue {
            candidateDirs.append(directConversations)
        }

        // 3. rootURL 为 ~/.gemini，可能包含 antigravity/conversations 与 antigravity-cli/conversations
        for sub in ["antigravity", "antigravity-cli"] {
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

    /// 打开单个数据库连接：
    /// 1. 优先以 mode=ro 打开（支持读取活跃 WAL 中的最新写入）。
    /// 2. 执行 SELECT 1 探针测试；若因缺少 -shm 或只读沙盒环境导致 CANTOPEN，安全回退到 immutable=1。
    /// 3. 若 immutable=1 亦无法打开，记录告警并跳过。
    private func openDatabase(at dbURL: URL) -> OpaquePointer? {
        var db: OpaquePointer?

        let uriRo = "file:\(dbURL.path)?mode=ro"
        if sqlite3_open_v2(uriRo, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK, let database = db {
            sqlite3_busy_timeout(database, busyTimeoutMs)
            var testStmt: OpaquePointer?
            let prep = sqlite3_prepare_v2(database, "SELECT 1;", -1, &testStmt, nil)
            sqlite3_finalize(testStmt)
            if prep == SQLITE_OK {
                return database
            }
            sqlite3_close(database)
            db = nil
        } else if let database = db {
            sqlite3_close(database)
            db = nil
        }

        let uriImm = "file:\(dbURL.path)?immutable=1"
        if sqlite3_open_v2(uriImm, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK, let database = db {
            sqlite3_busy_timeout(database, busyTimeoutMs)
            var testStmt: OpaquePointer?
            let prep = sqlite3_prepare_v2(database, "SELECT 1;", -1, &testStmt, nil)
            sqlite3_finalize(testStmt)
            if prep == SQLITE_OK {
                return database
            }
            sqlite3_close(database)
        } else if let database = db {
            sqlite3_close(database)
        }

        logger.warning("无法以只读或不可变模式打开会话数据库: \(dbURL.lastPathComponent)")
        return nil
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
