import Foundation
import SQLite3
import os.log

/// SQLite 扫描产出的单行原始数据(JSON blob 未解码)
struct OpenCodeMessageRow: Sendable {
    let id: String                 // message.id (PK,作 dedup messageId)
    let sessionID: String
    let timeCreatedMs: Int64       // ms epoch
    let dataJSON: String           // message.data 原始 JSON 字符串
    let directory: String          // session.directory(cwd 兜底)
}

enum OpenCodeScannerError: Error, CustomStringConvertible {
    case databaseNotFound(URL)
    case openFailed(code: Int32, message: String)
    case queryFailed(code: Int32, message: String)

    var description: String {
        switch self {
        case .databaseNotFound(let url):
            return "opencode.db 不存在: \(url.path)"
        case .openFailed(let code, let msg):
            return "无法打开 opencode.db (SQLite code=\(code)): \(msg)"
        case .queryFailed(let code, let msg):
            return "查询 opencode.db 失败 (SQLite code=\(code)): \(msg)"
        }
    }
}

/// 直读 ~/.local/share/opencode/opencode.db
///
/// 设计原因:
/// - 用 `file:<path>?immutable=1` URI 模式只读打开 → 不会创建/修改 WAL/SHM 文件,
///   与 App Sandbox readonly 完全兼容,且避开锁竞争(opencode 进程在跑也能读)
/// - 仅查 message+session 必要字段,JSON blob 留给 Parser 解码,职责清晰
final class OpenCodeSQLiteScanner: Sendable {

    private let logger = Logger(subsystem: "com.xiaoao.TokenWatch", category: "OpenCodeSQLiteScanner")

    /// SQL 文本作为静态常量便于 Scanner 测试断言可见
    static let assistantMessageQuery = """
    SELECT m.id,
           m.session_id,
           m.time_created,
           m.data,
           s.directory
    FROM message AS m
    JOIN session AS s ON m.session_id = s.id
    WHERE json_extract(m.data, '$.role') = 'assistant'
    ORDER BY m.time_created;
    """

    /// 扫描指定根目录下的 opencode.db
    /// - Parameter rootURL: ~/.local/share/opencode 目录(已通过 SecurityScopedBookmark 授权)
    /// - Returns: assistant 消息行列表
    func scanAll(in rootURL: URL) throws -> [OpenCodeMessageRow] {
        let dbURL = rootURL.appendingPathComponent("opencode.db")
        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            throw OpenCodeScannerError.databaseNotFound(dbURL)
        }

        var db: OpaquePointer?
        let uri = "file:\(dbURL.path)?immutable=1"
        let openFlags: Int32 = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI

        let openCode = sqlite3_open_v2(uri, &db, openFlags, nil)
        guard openCode == SQLITE_OK, let database = db else {
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(db)
            throw OpenCodeScannerError.openFailed(code: openCode, message: msg)
        }
        defer { sqlite3_close(database) }

        var stmt: OpaquePointer?
        let prepCode = sqlite3_prepare_v2(database, Self.assistantMessageQuery, -1, &stmt, nil)
        guard prepCode == SQLITE_OK, let statement = stmt else {
            let msg = String(cString: sqlite3_errmsg(database))
            sqlite3_finalize(stmt)
            throw OpenCodeScannerError.queryFailed(code: prepCode, message: msg)
        }
        defer { sqlite3_finalize(statement) }

        var rows: [OpenCodeMessageRow] = []
        while true {
            let stepCode = sqlite3_step(statement)
            if stepCode == SQLITE_DONE { break }
            guard stepCode == SQLITE_ROW else {
                let msg = String(cString: sqlite3_errmsg(database))
                throw OpenCodeScannerError.queryFailed(code: stepCode, message: msg)
            }
            // column index 与 SELECT 列顺序一致
            guard let idC = sqlite3_column_text(statement, 0),
                  let sidC = sqlite3_column_text(statement, 1),
                  let dataC = sqlite3_column_text(statement, 3),
                  let dirC = sqlite3_column_text(statement, 4)
            else {
                continue   // 必填列缺失 → 跳过该行
            }
            let id = String(cString: idC)
            let sessionID = String(cString: sidC)
            let timeMs = sqlite3_column_int64(statement, 2)
            let dataJSON = String(cString: dataC)
            let directory = String(cString: dirC)

            rows.append(OpenCodeMessageRow(
                id: id,
                sessionID: sessionID,
                timeCreatedMs: timeMs,
                dataJSON: dataJSON,
                directory: directory
            ))
        }

        logger.info("opencode SQLite 读出 assistant 行数: \(rows.count)")
        return rows
    }
}
