import Foundation
import os.log

/// Codex rollout 文件元数据
/// sessionID 优先从文件名 UUID 推断,Parser 解析到 session_meta 后可覆盖
struct CodexRolloutFileInfo: Sendable {
    let url: URL
    let sessionID: String
    /// true 表示来自 archived_sessions/,UI 可据此区分(本期未使用)
    let isArchived: Bool
}

/// 扫描 ${codexRoot}/sessions/ 与 ${codexRoot}/archived_sessions/
/// 同相对路径(YYYY/MM/DD/<filename>)同时存在时,sessions/ 优先
/// 参考 ccusage `rust/crates/ccusage/src/adapter/codex/loader.rs`
final class CodexRolloutScanner: Sendable {

    private let logger = Logger(subsystem: "com.xiaoao.TokenWatch", category: "CodexRolloutScanner")
    private let directoryLister: any JSONLDirectoryListing

    init(directoryLister: any JSONLDirectoryListing = SystemJSONLDirectoryLister()) {
        self.directoryLister = directoryLister
    }

    /// 扫描 codexRoot 下所有 rollout-*.jsonl 文件
    /// - Parameter codexRoot: 已通过 Bookmark 取得访问权限的 ~/.codex 目录
    func scanAll(in codexRoot: URL) throws -> [CodexRolloutFileInfo] {
        let sessionsDir = codexRoot.appendingPathComponent("sessions")
        let archivedDir = codexRoot.appendingPathComponent("archived_sessions")

        // 先收 sessions/,再收 archived_sessions/ 中相对路径未撞名的部分
        let primary = try scanDirectory(sessionsDir, isArchived: false)
        var seenRelative = Set(primary.map(\.relativePath))

        var files = primary.map(\.fileInfo)
        for hit in try scanDirectory(archivedDir, isArchived: true)
        where !seenRelative.contains(hit.relativePath) {
            seenRelative.insert(hit.relativePath)
            files.append(hit.fileInfo)
        }

        logger.info("Codex 扫描完成:共 \(files.count) 个 rollout 文件")
        return files
    }

    // MARK: - Private

    /// 扫描单个根目录下所有 rollout-*.jsonl,同时返回相对路径用于跨目录去重
    private func scanDirectory(
        _ dir: URL,
        isArchived: Bool
    ) throws -> [(fileInfo: CodexRolloutFileInfo, relativePath: String)] {
        let fileURLs: [URL]
        do {
            fileURLs = try directoryLister.recursiveFileURLs(in: dir)
        } catch {
            logger.error("目录枚举失败: \(dir.path), \(error.localizedDescription)")
            throw error
        }

        var results: [(fileInfo: CodexRolloutFileInfo, relativePath: String)] = []
        let dirPath = dir.path
        for fileURL in fileURLs {
            guard fileURL.pathExtension == "jsonl" else { continue }
            let name = fileURL.lastPathComponent
            guard name.hasPrefix("rollout-") else { continue }

            let relativePath = String(fileURL.path.dropFirst(dirPath.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let sessionID = extractSessionID(from: name) ?? name
            results.append((
                CodexRolloutFileInfo(url: fileURL, sessionID: sessionID, isArchived: isArchived),
                relativePath
            ))
        }
        return results.sorted {
            if $0.relativePath != $1.relativePath {
                return $0.relativePath < $1.relativePath
            }
            return $0.fileInfo.url.standardizedFileURL.path < $1.fileInfo.url.standardizedFileURL.path
        }
    }

    /// 从 `rollout-2026-05-04T16-35-18-<UUID>.jsonl` 提取尾部 UUID
    /// UUID 标准 5 段 8-4-4-4-12 = 36 字符,取文件名最后 36 字符
    private func extractSessionID(from filename: String) -> String? {
        let stem = (filename as NSString).deletingPathExtension
        guard stem.count >= 36 else { return nil }
        let uuid = String(stem.suffix(36))
        // 简单校验:含 4 个 '-'
        guard uuid.filter({ $0 == "-" }).count == 4 else { return nil }
        return uuid
    }
}
