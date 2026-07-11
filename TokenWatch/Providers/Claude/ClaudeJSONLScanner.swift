import Foundation
import os.log

/// JSONL 文件信息
struct ClaudeJSONLFileInfo: Sendable {
    let url: URL
    let sessionID: String         // 从文件名提取的 session UUID
    let projectPath: String       // 解码后的项目绝对路径
    let isSubagent: Bool          // 是否来自 subagents/ 子目录
    let agentId: String?          // subagent 的 agent ID
}

/// 扫描 ~/.claude/projects/ 目录，找到所有 JSONL 文件
/// 区分主会话文件和 subagent 文件，解析项目路径
final class ClaudeJSONLScanner: Sendable {

    private let logger = Logger(subsystem: "com.xiaoao.TokenWatch", category: "ClaudeJSONLScanner")
    private let directoryLister: any JSONLDirectoryListing

    init(directoryLister: any JSONLDirectoryListing = SystemJSONLDirectoryLister()) {
        self.directoryLister = directoryLister
    }

    /// 扫描 claudeDataRoot 目录下的所有 JSONL 文件
    /// - Parameter claudeDataRoot: Security-Scoped 访问下的 ~/.claude 目录 URL
    /// - Returns: 所有 JSONL 文件信息列表
    func scanAllJSONLFiles(in claudeDataRoot: URL) throws -> [ClaudeJSONLFileInfo] {
        let projectsDir = claudeDataRoot.appendingPathComponent("projects")
        var results: [ClaudeJSONLFileInfo] = []

        let fileURLs: [URL]
        do {
            fileURLs = try directoryLister.recursiveFileURLs(in: projectsDir)
        } catch {
            logger.error("projects 枚举失败: \(error.localizedDescription)")
            throw error
        }

        for fileURL in fileURLs {
            guard fileURL.pathExtension == "jsonl" else { continue }

            let isSubagent = fileURL.pathComponents.contains("subagents")
            let sessionID = extractSessionID(from: fileURL)
            let projectPath = extractProjectPath(from: fileURL, projectsDir: projectsDir)
            let agentId = isSubagent ? extractAgentId(from: fileURL) : nil

            results.append(ClaudeJSONLFileInfo(
                url: fileURL,
                sessionID: sessionID,
                projectPath: projectPath,
                isSubagent: isSubagent,
                agentId: agentId
            ))
        }

        logger.info("扫描完成：共找到 \(results.count) 个 JSONL 文件")
        // daily 单遍 replacement 的结果依赖输入顺序，因此不能沿用文件系统枚举顺序。
        return results.sorted {
            $0.url.standardizedFileURL.path < $1.url.standardizedFileURL.path
        }
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
    /// "-Users-name-my--cool--app"               -> "/Users/name/my-cool-app"
    ///
    /// 设计说明：
    /// Claude Code 把项目绝对路径编码为 `~/.claude/projects/<encoded>/` 的目录名时，
    /// 会把路径分隔符 `/` 替换为 `-`。但项目目录名本身可能含有 `-`（例如 `my-cool-app`），
    /// 若简单地把所有 `-` 还原为 `/`，会错误展开成 `/my/cool/app`。
    ///
    /// 截至实现时，未找到 Claude Code 官方关于该编码的公开文档；
    /// 这里**采用经验性假设**：原始路径中的字面 `-` 被编码为 `--`（双连字符转义），
    /// 即解码时 `--` 还原为字面 `-`，单 `-` 还原为 `/`。
    /// 若日后官方公布了不同规则（例如使用其他转义字符或不转义），需要回过头来调整这里。
    func decodeProjectPath(_ encoded: String) -> String {
        guard encoded.hasPrefix("-") else { return encoded }

        // 跳过开头的 `-`(对应原始路径起始的 `/`),逐字符扫描剩余部分
        var result = "/"
        let body = encoded.dropFirst()
        var index = body.startIndex
        while index < body.endIndex {
            let ch = body[index]
            if ch == "-" {
                let next = body.index(after: index)
                if next < body.endIndex, body[next] == "-" {
                    // `--` 是字面 `-` 的转义,消耗两个字符
                    result.append("-")
                    index = body.index(after: next)
                } else {
                    // 单 `-` 是路径分隔符
                    result.append("/")
                    index = next
                }
            } else {
                result.append(ch)
                index = body.index(after: index)
            }
        }
        return result
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
