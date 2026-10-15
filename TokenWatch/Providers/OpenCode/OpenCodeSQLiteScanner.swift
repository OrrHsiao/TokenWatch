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
    let role: String               // 角色:2.0 为 session_message.type,旧版为 data.role
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
/// 同时兼容两种表结构,同库并存时以 2.0 数据为准:
/// - opencode 2.0:`session_message`(消息,`type` 列为角色) + `session_v2`(会话目录与 fork 信息)
/// - 旧版(v1):`message`(消息,角色在 `data.role`) + `session`(会话目录)
/// 旧表中已存在于 `session_message` 的消息直接排除,避免同一条消息被计两次。
///
/// 设计原因:
/// - 用 `file:<path>?mode=ro` URI 模式只读打开。**不能用 `immutable=1`**:
///   immutable 会让 SQLite 完全忽略 `-wal`/`-shm`,只读主 db 的旧 checkpoint;
///   但 opencode 是常驻进程,新写入的 message 全在 WAL 里(WAL 通常远大于主 db),
///   导致 TokenWatch 只能看到 opencode 启动那一刻的 stale 快照,统计永远落后。
/// - `mode=ro` 同样不写主 db;opencode 在跑时 `-shm` 一定已存在,SQLite 以只读
///   mmap 方式接入即可,与 App Sandbox(目录级 readonly user-selected files)兼容。
/// - fork 子会话会把父会话历史复制进 `session_message`:行 id 是新的,但保留了父会话的 `seq`。
///   这些复制行不是子会话自己的用量,按 `session_v2.fork_boundary` 的分叉点截止值跳过。
/// - 仅查 message+session 必要字段,JSON blob 留给 Parser 解码,职责清晰
final class OpenCodeSQLiteScanner: Sendable {

    private let logger = Logger(subsystem: "com.xiaoao.TokenWatch", category: "OpenCodeSQLiteScanner")

    /// 锁冲突等待窗口(毫秒)。opencode 常驻写库时,checkpoint、独占锁等
    /// 少数窗口会瞬时返回 SQLITE_BUSY;等待超过该窗口才失败,避免整轮
    /// 扫描因瞬时锁冲突直接抛错。测试可注入更短窗口验证有界失败。
    private let busyTimeoutMs: Int32

    init(busyTimeoutMs: Int32 = 2000) {
        self.busyTimeoutMs = busyTimeoutMs
    }

    /// 2.0 assistant 消息查询,列序为 id, session_id, time_created, data, directory, type, seq。
    /// 角色取 `session_message.type`,目录取 `session_v2`;旧 schema 缺少 `seq` 时以 NULL 代替,此时不做 fork 去重。
    static func sessionMessageQuery(hasSeq: Bool) -> String {
        """
        SELECT sm.id,
               sm.session_id,
               sm.time_created,
               sm.data,
               s.directory,
               sm.type,
               \(hasSeq ? "sm.seq" : "NULL")
        FROM session_message AS sm
        JOIN session_v2 AS s ON sm.session_id = s.id
        WHERE sm.type = 'assistant'
        ORDER BY sm.time_created;
        """
    }

    /// 旧版 assistant 消息查询,列序与 `sessionMessageQuery` 一致,seq 恒为 NULL。
    /// `excludingSessionMessages` 为 true 时跳过 `session_message` 中已存在的消息 id。
    static func legacyMessageQuery(excludingSessionMessages: Bool) -> String {
        let exclusion = excludingSessionMessages
            ? "AND NOT EXISTS (SELECT 1 FROM session_message AS sm WHERE sm.id = m.id)"
            : ""
        return """
        SELECT m.id,
               m.session_id,
               m.time_created,
               m.data,
               s.directory,
               json_extract(m.data, '$.role'),
               NULL
        FROM message AS m
        JOIN session AS s ON m.session_id = s.id
        WHERE CASE
                WHEN json_valid(m.data)
                THEN json_extract(m.data, '$.role') = 'assistant'
                ELSE 0
              END
          \(exclusion)
        ORDER BY m.time_created;
        """
    }

    /// 每个 fork 子会话的继承截止 seq,返回 (子会话 id, 截止 seq);截止值为 NULL 表示无法解析。
    /// `fork_boundary` 为 JSON `{"type":"through"|"before","messageID":...}`(opencode 的 Session.ForkBoundary):
    /// - through:截止值为父会话中分叉点消息的 seq(包含分叉点)
    /// - before:截止值为父会话中位于分叉点之前的最大 seq(不含分叉点)。
    ///   不能直接用分叉点 seq - 1:父会话 seq 可能有空洞,子会话自己的第一条行会接在复制行之后。
    static let forkCopyCutoffQuery = """
    SELECT f.id,
           CASE WHEN json_valid(f.fork_boundary) THEN
             CASE json_extract(f.fork_boundary, '$.type')
               WHEN 'through' THEN (
                 SELECT p.seq FROM session_message AS p
                 WHERE p.session_id = f.fork_session_id
                   AND p.id = json_extract(f.fork_boundary, '$.messageID'))
               WHEN 'before' THEN (
                 SELECT MAX(q.seq) FROM session_message AS q
                 WHERE q.session_id = f.fork_session_id
                   AND q.seq < (
                     SELECT p.seq FROM session_message AS p
                     WHERE p.session_id = f.fork_session_id
                       AND p.id = json_extract(f.fork_boundary, '$.messageID')))
             END
           END
    FROM session_v2 AS f
    WHERE f.fork_session_id IS NOT NULL
      AND f.fork_boundary IS NOT NULL;
    """

    /// 扫描指定根目录下的 opencode.db
    /// - Parameter rootURL: ~/.local/share/opencode 目录(已通过 SecurityScopedBookmark 授权)
    /// - Returns: assistant 消息行列表(已去除 fork 复制的历史行),按时间排序
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
        sqlite3_busy_timeout(database, busyTimeoutMs)

        // 先探测表与列:表不存在时列集合为空;结构不符的数据源直接跳过,不让整个数据源报错
        let sessionMessageColumns = try Self.columnNames(of: "session_message", in: database)
        let sessionV2Columns = try Self.columnNames(of: "session_v2", in: database)
        let legacyMessageColumns = try Self.columnNames(of: "message", in: database)
        let legacySessionColumns = try Self.columnNames(of: "session", in: database)
        let hasSessionMessages = sessionMessageColumns.isSuperset(of: ["id", "session_id", "type", "time_created", "data"])
            && sessionV2Columns.isSuperset(of: ["id", "directory"])
        let hasLegacyMessages = legacyMessageColumns.isSuperset(of: ["id", "session_id", "time_created", "data"])
            && legacySessionColumns.isSuperset(of: ["id", "directory"])
        guard hasSessionMessages || hasLegacyMessages else {
            throw OpenCodeScannerError.queryFailed(
                code: SQLITE_ERROR,
                message: "no usable opencode message table"
            )
        }

        var rows: [OpenCodeMessageRow] = []
        var v2Count = 0
        var legacyCount = 0
        var forkSkipped = 0

        if hasSessionMessages {
            let hasSeq = sessionMessageColumns.contains("seq")
            let hasForkColumns = sessionV2Columns.contains("fork_session_id")
                && sessionV2Columns.contains("fork_boundary")
            var cutoffs: [String: Int64] = [:]
            if hasSeq && hasForkColumns {
                cutoffs = try forkCopyCutoffs(in: database)
            }
            try Self.forEachRow(Self.sessionMessageQuery(hasSeq: hasSeq), in: database) { statement in
                guard let scanned = Self.readRow(statement) else { return }
                if let seq = scanned.seq, let cutoff = cutoffs[scanned.row.sessionID], seq <= cutoff {
                    forkSkipped += 1
                    return
                }
                rows.append(scanned.row)
                v2Count += 1
            }
        }

        if hasLegacyMessages {
            // v2 库里已有的消息由 session_message 提供,旧表只补充缺失的部分
            let query = Self.legacyMessageQuery(excludingSessionMessages: hasSessionMessages)
            try Self.forEachRow(query, in: database) { statement in
                guard let scanned = Self.readRow(statement) else { return }
                rows.append(scanned.row)
                legacyCount += 1
            }
        }

        rows.sort { ($0.timeCreatedMs, $0.id) < ($1.timeCreatedMs, $1.id) }
        logger.info("opencode SQLite 读出 assistant 行数: \(rows.count)(v2: \(v2Count), legacy: \(legacyCount), fork 继承跳过: \(forkSkipped))")
        return rows
    }

    /// 解析各 fork 子会话的继承截止 seq。无法解析的分叉(父行或分叉点缺失、JSON 非法)不进入结果,
    /// 其全部行保留:宁可多算也不按猜测丢数据。
    private func forkCopyCutoffs(in database: OpaquePointer) throws -> [String: Int64] {
        var cutoffs: [String: Int64] = [:]
        var unresolved = 0
        try Self.forEachRow(Self.forkCopyCutoffQuery, in: database) { statement in
            guard let forkID = Self.columnText(statement, 0) else { return }
            guard sqlite3_column_type(statement, 1) != SQLITE_NULL else {
                unresolved += 1
                return
            }
            cutoffs[forkID] = sqlite3_column_int64(statement, 1)
        }
        if unresolved > 0 {
            logger.info("opencode fork 分叉点无法解析,保留其全部行: \(unresolved)")
        }
        return cutoffs
    }

    /// 读取当前行(列序见 `sessionMessageQuery`)。必填列缺失时返回 nil,跳过该行。
    /// `seq` 仅 2.0 的 session_message 有值,旧版查询中为 NULL。
    private static func readRow(_ statement: OpaquePointer) -> (row: OpenCodeMessageRow, seq: Int64?)? {
        guard let id = columnText(statement, 0),
              let sessionID = columnText(statement, 1),
              let dataJSON = columnText(statement, 3),
              let directory = columnText(statement, 4),
              let role = columnText(statement, 5)
        else {
            return nil
        }
        let seq: Int64? = sqlite3_column_type(statement, 6) == SQLITE_NULL
            ? nil
            : sqlite3_column_int64(statement, 6)
        let row = OpenCodeMessageRow(
            id: id,
            sessionID: sessionID,
            timeCreatedMs: sqlite3_column_int64(statement, 2),
            dataJSON: dataJSON,
            directory: directory,
            role: role
        )
        return (row, seq)
    }

    /// 预编译并逐行执行查询。prepare/step 失败统一抛出 queryFailed,保留 SQLite 错误码(如 SQLITE_BUSY)。
    private static func forEachRow(
        _ sql: String,
        in database: OpaquePointer,
        _ body: (OpaquePointer) -> Void
    ) throws {
        var stmt: OpaquePointer?
        let prepCode = sqlite3_prepare_v2(database, sql, -1, &stmt, nil)
        guard prepCode == SQLITE_OK, let statement = stmt else {
            let msg = String(cString: sqlite3_errmsg(database))
            sqlite3_finalize(stmt)
            throw OpenCodeScannerError.queryFailed(code: prepCode, message: msg)
        }
        defer { sqlite3_finalize(statement) }

        while true {
            let stepCode = sqlite3_step(statement)
            if stepCode == SQLITE_DONE { break }
            guard stepCode == SQLITE_ROW else {
                let msg = String(cString: sqlite3_errmsg(database))
                throw OpenCodeScannerError.queryFailed(code: stepCode, message: msg)
            }
            body(statement)
        }
    }

    /// 读取表的列名集合;表不存在时为空集合(PRAGMA 对缺失的表只返回 0 行,不报错)。
    /// 表名只来自本文件的常量,因此直接拼入 SQL。
    private static func columnNames(of table: String, in database: OpaquePointer) throws -> Set<String> {
        var names: Set<String> = []
        try forEachRow("SELECT name FROM pragma_table_info('\(table)')", in: database) { statement in
            if let name = columnText(statement, 0) {
                names.insert(name)
            }
        }
        return names
    }

    private static func columnText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        sqlite3_column_text(statement, index).map { String(cString: $0) }
    }
}
