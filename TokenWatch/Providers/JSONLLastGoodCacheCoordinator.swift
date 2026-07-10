import Foundation

/// 没有 provider-specific cache scope 的 parser 使用此单一值。
struct JSONLUnscopedCacheScope: Sendable, Equatable {
    static let shared = JSONLUnscopedCacheScope()

    private init() {}
}

/// 统一协调 scanner 已列出文件的 snapshot、cache hit、last-good 与 prune。
/// `Candidate` 和 `Scope` 由 provider 指定；行解析和全局去重留在 provider。
final class JSONLLastGoodCacheCoordinator<
    Candidate: Sendable,
    Scope: Sendable & Equatable
>: @unchecked Sendable {
    private struct CachedFile {
        let metadata: JSONLFileMetadata
        let scope: Scope
        let candidates: [Candidate]
    }

    private let fileReader: any JSONLFileReading
    private let lock = NSLock()
    private var cachedFiles: [String: CachedFile] = [:]
    private var cacheHitCount = 0

    init(fileReader: any JSONLFileReading) {
        self.fileReader = fileReader
    }

    var debugCachedFileCount: Int {
        withLock { cachedFiles.count }
    }

    var debugCacheHitCount: Int {
        withLock { cacheHitCount }
    }

    /// 读取 scanner 本轮列出的文件，返回仍未做 provider 全局去重的 candidates。
    /// 只有完整 parse 成功才原子替换 cache；失败时仅复用同 scope 的 last-good。
    /// - Parameters:
    ///   - files: scanner 本轮列出的文件描述。
    ///   - scope: provider 定义的 cache 兼容范围。
    ///   - cacheKey: 将文件描述映射为稳定路径 key。
    ///   - urlForFile: 返回文件的实际 URL。
    ///   - parse: 使用已打开 snapshot 完整构建 per-file candidates。
    ///   - onFailure: 报告错误及是否复用了存在的 last-good。
    /// - Returns: 按输入文件顺序汇总的 provider-specific candidates。
    func loadListedFiles<FileInfo>(
        _ files: [FileInfo],
        scope: Scope,
        cacheKey: (FileInfo) -> String,
        urlForFile: (FileInfo) -> URL,
        parse: (FileInfo, JSONLFileSnapshot) throws -> [Candidate],
        onFailure: (FileInfo, Error, Bool) -> Void
    ) -> [Candidate] {
        var allCandidates: [Candidate] = []
        var listedKeys: Set<String> = []

        for fileInfo in files {
            let key = cacheKey(fileInfo)
            listedKeys.insert(key)

            do {
                let snapshot = try fileReader.openSnapshot(for: urlForFile(fileInfo))
                defer { snapshot.stream.close() }

                if let cached = cachedCandidates(
                    for: key,
                    matching: snapshot.metadata,
                    scope: scope
                ) {
                    allCandidates.append(contentsOf: cached)
                    continue
                }

                let parsed = try parse(fileInfo, snapshot)
                store(
                    parsed,
                    metadata: snapshot.metadata,
                    scope: scope,
                    for: key
                )
                allCandidates.append(contentsOf: parsed)
            } catch {
                let lastGood = lastGoodCandidates(for: key, scope: scope)
                if let lastGood {
                    allCandidates.append(contentsOf: lastGood)
                }
                onFailure(fileInfo, error, lastGood != nil)
            }
        }

        prune(keeping: listedKeys)
        return allCandidates
    }

    private func cachedCandidates(
        for key: String,
        matching metadata: JSONLFileMetadata,
        scope: Scope
    ) -> [Candidate]? {
        withLock {
            // 没有 descriptor identity 时无法证明两次 snapshot 指向同一文件。
            guard metadata.identity != nil,
                  let cached = cachedFiles[key],
                  cached.metadata == metadata,
                  cached.scope == scope else {
                return nil
            }
            cacheHitCount += 1
            return cached.candidates
        }
    }

    private func lastGoodCandidates(
        for key: String,
        scope: Scope
    ) -> [Candidate]? {
        withLock {
            guard let cached = cachedFiles[key],
                  cached.scope == scope else {
                return nil
            }
            // Optional array preserves the distinction between no cache and cached empty output.
            return cached.candidates
        }
    }

    private func store(
        _ candidates: [Candidate],
        metadata: JSONLFileMetadata,
        scope: Scope,
        for key: String
    ) {
        withLock {
            cachedFiles[key] = CachedFile(
                metadata: metadata,
                scope: scope,
                candidates: candidates
            )
        }
    }

    private func prune(keeping listedKeys: Set<String>) {
        withLock {
            cachedFiles = cachedFiles.filter { listedKeys.contains($0.key) }
        }
    }

    @discardableResult
    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
