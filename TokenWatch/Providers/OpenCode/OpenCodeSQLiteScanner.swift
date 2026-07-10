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

enum OpenCodeScannerError: AppLocalizedError, CustomStringConvertible {
    case databaseNotFound(URL)
    case openFailed(code: Int32, message: String)
    case queryFailed(code: Int32, message: String)

    var description: String {
        localizedDescription(language: .zhHans)
    }

    func localizedDescription(language: AppLanguage) -> String {
        switch self {
        case .databaseNotFound(let url):
            return String(
                format: AppStrings.text(.errorOpenCodeDatabaseNotFoundFormat, language: language),
                url.path
            )
        case .openFailed(let code, let msg):
            return String(
                format: AppStrings.text(.errorOpenCodeDatabaseOpenFailedFormat, language: language),
                Int(code),
                msg
            )
        case .queryFailed(let code, let msg):
            return String(
                format: AppStrings.text(.errorOpenCodeDatabaseQueryFailedFormat, language: language),
                Int(code),
                msg
            )
        }
    }
}

/// 直读 ~/.local/share/opencode/opencode.db
///
/// 设计原因:
/// - 用 `file:<path>?mode=ro` URI 模式只读打开。**不能用 `immutable=1`**:
///   immutable 会让 SQLite 完全忽略 `-wal`/`-shm`,只读主 db 的旧 checkpoint;
///   但 opencode 是常驻进程,新写入的 message 全在 WAL 里(WAL 通常远大于主 db),
///   导致 TokenWatch 只能看到 opencode 启动那一刻的 stale 快照,统计永远落后。
/// - `mode=ro` 同样不写主 db;opencode 在跑时 `-shm` 一定已存在,SQLite 以只读
///   mmap 方式接入即可,与 App Sandbox(目录级 readonly user-selected files)兼容。
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
    WHERE CASE
            WHEN json_valid(m.data)
            THEN json_extract(m.data, '$.role') = 'assistant'
            ELSE 0
          END
    ORDER BY m.time_created;
    """

    /// 扫描指定根目录下的 opencode.db
    /// - Parameter rootURL: ~/.local/share/opencode 目录(已通过 SecurityScopedBookmark 授权)
    /// - Returns: assistant 消息行列表
    func scanAll(in rootURL: URL) throws -> [OpenCodeMessageRow] {
        let dbURL = rootURL.appendingPathComponent("opencode.db")
        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            logger.info("opencode.db 不存在,跳过 opencode 数据源: \(dbURL.path)")
            return []
        }

        var db: OpaquePointer?
        // mode=ro 而非 immutable=1:见类型注释,后者会跳过 WAL 导致漏读 opencode 在跑时的新数据
        let uri = "file:\(dbURL.path)?mode=ro"
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
