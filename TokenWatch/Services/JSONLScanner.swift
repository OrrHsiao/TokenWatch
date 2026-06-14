import Foundation
import os.log

/// JSONL 文件信息
struct JSONLFileInfo: Sendable {
    let url: URL
    let sessionID: String         // 从文件名提取的 session UUID
    let projectPath: String       // 解码后的项目绝对路径
    let isSubagent: Bool          // 是否来自 subagents/ 子目录
    let agentId: String?          // subagent 的 agent ID
}

/// 扫描 ~/.claude/projects/ 目录，找到所有 JSONL 文件
/// 区分主会话文件和 subagent 文件，解析项目路径
final class JSONLScanner: Sendable {

    private let logger = Logger(subsystem: "com.xiaoao.TokenWatch", category: "JSONLScanner")

    /// 扫描 claudeDataRoot 目录下的所有 JSONL 文件
    /// - Parameter claudeDataRoot: Security-Scoped 访问下的 ~/.claude 目录 URL
    /// - Returns: 所有 JSONL 文件信息列表
    nonisolated func scanAllJSONLFiles(in claudeDataRoot: URL) throws -> [JSONLFileInfo] {
        let projectsDir = claudeDataRoot.appendingPathComponent("projects")
        var results: [JSONLFileInfo] = []

        // 检查 projects 目录是否存在
        guard FileManager.default.fileExists(atPath: projectsDir.path) else {
            logger.warning("projects 目录不存在: \(projectsDir.path)")
            return results
        }

        guard let projectEnumerator = FileManager.default.enumerator(
            at: projectsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            logger.warning("无法枚举 projects 目录")
            return results
        }

        for case let fileURL as URL in projectEnumerator {
            guard fileURL.pathExtension == "jsonl" else { continue }

            let isSubagent = fileURL.pathComponents.contains("subagents")
            let sessionID = extractSessionID(from: fileURL)
            let projectPath = extractProjectPath(from: fileURL, projectsDir: projectsDir)
            let agentId = isSubagent ? extractAgentId(from: fileURL) : nil

            results.append(JSONLFileInfo(
                url: fileURL,
                sessionID: sessionID,
                projectPath: projectPath,
                isSubagent: isSubagent,
                agentId: agentId
            ))
        }

        logger.info("扫描完成：共找到 \(results.count) 个 JSONL 文件")
        return results
    }

    // MARK: - Private

    /// 从文件名提取 session ID
    /// 文件名格式：<uuid>.jsonl
    private func extractSessionID(from url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    /// 从路径提取并解码项目路径
    /// 路径格式：projects/-Users-orrhsiao-Desktop-Code-TokenWatch/<session>.jsonl
    /// 解码后：/Users/orrhsiao/Desktop/Code/TokenWatch
    private func extractProjectPath(from url: URL, projectsDir: URL) -> String {
        guard let range = url.path.range(of: projectsDir.path) else {
            return ""
        }
        let relativePath = String(url.path[range.upperBound...])
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let components = relativePath.split(separator: "/")
        guard let projectDir = components.first else {
            return ""
        }
        return decodeProjectPath(String(projectDir))
    }

    /// 将编码后的项目路径还原
    /// "-Users-orrhsiao-Desktop-Code-TokenWatch" -> "/Users/orrhsiao/Desktop/Code/TokenWatch"
    private func decodeProjectPath(_ encoded: String) -> String {
        guard encoded.hasPrefix("-") else { return encoded }
        return "/" + String(encoded.dropFirst()).replacingOccurrences(of: "-", with: "/")
    }

    /// 从 subagent 文件路径提取 agent ID
    /// 文件名格式：agent-<id>.jsonl
    private func extractAgentId(from url: URL) -> String {
        let filename = url.deletingPathExtension().lastPathComponent
        if filename.hasPrefix("agent-") {
            return String(filename.dropFirst(6))
        }
        return filename
    }
}
