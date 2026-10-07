import Foundation
import os.log

/// 一个会话目录中按世代规则选出的唯一日志文件。
struct DeepSeekHarnessSessionLogFile: Sendable, Equatable {
    /// 日志文件 URL。
    let url: URL
    /// 世代版本号；v0（`session.jsonl`）为 0。
    let generation: Int
    /// 是否 zstd 压缩（`.jsonl.zstd`）。
    let isCompressed: Bool

    /// 会话目录路径，用于日志与去重。
    var sessionDirectoryPath: String {
        url.deletingLastPathComponent().path
    }
}

/// DSH 数据根解析结果。
struct DeepSeekHarnessDataRoots: Sendable, Equatable {
    /// `sessions/` 目录。
    let sessionsRoot: URL
    /// `~/.dsh` 根；无法推断时为 nil（此时读不到 DSH 自带的定价目录）。
    let dshHome: URL?
    /// 是否命中 DSH 的规范布局（`<root>/sessions`，或 `<root>` 本身名为 `sessions`）。
    ///
    /// 未命中时仍把用户选中的目录当作 sessions 根尝试扫描（容错），
    /// 但设置页会提示重选，避免「任意目录都算有效数据源」。
    let isStandardLayout: Bool
}

/// DSH 会话目录扫描器。
///
/// 目录布局：`<root>/sessions/--<normalized-cwd>--/<escaped-session-id>/session[.vN].jsonl[.zstd]`。
/// 关键规则（对应 DSH `resolveGenerationInDirectory`）：**每个会话目录只取版本号最高的
/// 一个世代文件**。历史迁移会把旧世代文件留在原地（实测同一会话同时存在 v0 与 v3），
/// 若按 glob 全部解析会重复计数。
struct DeepSeekHarnessScanner: Sendable {
    static let sessionsDirectoryName = "sessions"
    /// `sessions/<project>/<session>/<file>` 三层；再深已不属于规范布局。
    static let maximumDirectoryDepth = 3

    private static let logger = Logger(
        subsystem: "com.xiaoao.TokenWatch",
        category: "DeepSeekHarnessScanner"
    )

    /// 解析用户选择的数据根。
    ///
    /// 同时接受 `~/.dsh`（推荐）与 `~/.dsh/sessions`，以便用户直接授权 sessions 目录。
    /// - Parameter dataRootURL: 用户授权的目录。
    /// - Returns: sessions 根与可选的 DSH 主目录。
    func resolveDataRoots(_ dataRootURL: URL) -> DeepSeekHarnessDataRoots {
        let nestedSessions = dataRootURL.appendingPathComponent(
            Self.sessionsDirectoryName,
            isDirectory: true
        )
        if Self.isDirectory(nestedSessions) {
            return DeepSeekHarnessDataRoots(
                sessionsRoot: nestedSessions,
                dshHome: dataRootURL,
                isStandardLayout: true
            )
        }
        if dataRootURL.lastPathComponent == Self.sessionsDirectoryName {
            return DeepSeekHarnessDataRoots(
                sessionsRoot: dataRootURL,
                dshHome: dataRootURL.deletingLastPathComponent(),
                isStandardLayout: true
            )
        }
        return DeepSeekHarnessDataRoots(
            sessionsRoot: dataRootURL,
            dshHome: nil,
            isStandardLayout: false
        )
    }

    /// 校验数据根是否包含 `sessions/`（或本身即 sessions 目录）。
    func validateDataRoot(_ dataRootURL: URL) -> ProviderDataRootValidationResult {
        resolveDataRoots(dataRootURL).isStandardLayout ? .valid : .missingExpectedStructure
    }

    /// 枚举所有会话目录并挑选每个会话的最高世代日志。
    /// - Parameter dataRootURL: 用户授权的数据根。
    /// - Returns: 按会话目录路径排序的日志文件列表；sessions 目录不存在时返回空数组。
    func locateSessionLogFiles(in dataRootURL: URL) throws -> [DeepSeekHarnessSessionLogFile] {
        let roots = resolveDataRoots(dataRootURL)
        guard Self.isDirectory(roots.sessionsRoot) else { return [] }

        var candidatesByDirectory: [String: [DeepSeekHarnessSessionLogFile]] = [:]
        var directoryOrder: [String] = []
        try Self.collectLogFiles(
            in: roots.sessionsRoot,
            depth: 0,
            candidatesByDirectory: &candidatesByDirectory,
            directoryOrder: &directoryOrder
        )

        var selected: [DeepSeekHarnessSessionLogFile] = []
        selected.reserveCapacity(directoryOrder.count)
        for directoryPath in directoryOrder {
            guard let candidates = candidatesByDirectory[directoryPath], !candidates.isEmpty else {
                continue
            }
            guard let best = Self.preferredLogFile(from: candidates) else { continue }
            if candidates.count > 1 {
                Self.logger.debug(
                    "会话目录存在多个世代文件，已选择 v\(best.generation)\(best.isCompressed ? " (zstd)" : "")：\(directoryPath, privacy: .public)"
                )
            }
            selected.append(best)
        }
        return selected
    }

    /// 从同一会话目录的候选文件中选出唯一日志。
    ///
    /// 先比世代号；同世代同时存在压缩与未压缩文件属于非规范布局（一个 root 只属于一种编码），
    /// 这里固定优先压缩文件，保证结果确定且不依赖枚举顺序。
    static func preferredLogFile(
        from candidates: [DeepSeekHarnessSessionLogFile]
    ) -> DeepSeekHarnessSessionLogFile? {
        candidates.max { lhs, rhs in
            if lhs.generation != rhs.generation {
                return lhs.generation < rhs.generation
            }
            if lhs.isCompressed != rhs.isCompressed {
                return !lhs.isCompressed
            }
            return lhs.url.path > rhs.url.path
        }
    }

    /// 解析规范日志文件名。
    ///
    /// 规范正则（DSH `dsh-session-format`）：`^session(?:\.v([1-9][0-9]*))?\.jsonl$`，
    /// v0 没有 `.v0` 标签；`.zstd` 后缀表示压缩编码。
    /// - Parameter fileName: 文件名（不含目录）。
    /// - Returns: 世代号与是否压缩；非规范文件名返回 nil。
    static func parseGeneration(fileName: String) -> (generation: Int, isCompressed: Bool)? {
        var name = fileName
        let isCompressed = name.hasSuffix(".zstd")
        if isCompressed {
            name.removeLast(".zstd".count)
        }
        guard name.hasSuffix(".jsonl") else { return nil }
        name.removeLast(".jsonl".count)

        if name == "session" {
            return (0, isCompressed)
        }
        guard name.hasPrefix("session.v") else { return nil }
        let digits = name.dropFirst("session.v".count)
        guard !digits.isEmpty,
              digits.allSatisfy(\.isNumber),
              // 规范名不接受 `.v0`，也不接受前导零。
              digits.first != "0",
              let generation = Int(digits) else {
            return nil
        }
        return (generation, isCompressed)
    }

    // MARK: - 目录遍历

    /// 有界递归收集规范日志文件；跳过隐藏项，避免误入 `.DS_Store` / 临时目录。
    private static func collectLogFiles(
        in directory: URL,
        depth: Int,
        candidatesByDirectory: inout [String: [DeepSeekHarnessSessionLogFile]],
        directoryOrder: inout [String]
    ) throws {
        guard depth < maximumDirectoryDepth else { return }

        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            if isMissingDirectoryError(error) { return }
            throw error
        }

        var subdirectories: [URL] = []
        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDirectory {
                subdirectories.append(entry)
                continue
            }
            guard let parsed = parseGeneration(fileName: entry.lastPathComponent) else { continue }
            let file = DeepSeekHarnessSessionLogFile(
                url: entry,
                generation: parsed.generation,
                isCompressed: parsed.isCompressed
            )
            let key = directory.path
            if candidatesByDirectory[key] == nil {
                candidatesByDirectory[key] = []
                directoryOrder.append(key)
            }
            candidatesByDirectory[key]?.append(file)
        }

        for subdirectory in subdirectories {
            try collectLogFiles(
                in: subdirectory,
                depth: depth + 1,
                candidatesByDirectory: &candidatesByDirectory,
                directoryOrder: &directoryOrder
            )
        }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    private static func isMissingDirectoryError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return (nsError.domain == NSCocoaErrorDomain
            && nsError.code == CocoaError.fileReadNoSuchFile.rawValue)
            || (nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOENT))
    }
}
