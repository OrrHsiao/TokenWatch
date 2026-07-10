import Foundation

/// 没有 provider-specific cache scope 的 parser 使用此单一值。
struct JSONLUnscopedCacheScope: Sendable, Equatable {
    static let shared = JSONLUnscopedCacheScope()

    private init() {}
}

/// 统一协调 scanner 已列出文件的 snapshot、state cache、last-good 与 prune。
/// Provider 只通过 build/project closure 定义状态迁移和候选投影。
final class JSONLLastGoodCacheCoordinator<
    State: Sendable,
    Scope: Sendable & Equatable
>: @unchecked Sendable {
    private struct CachedFile {
        let metadata: JSONLFileMetadata
        let scope: Scope
        let state: State
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

    /// 返回同 scope 的只读 state 副本，供 parser 的定向 debug accessor 转发。
    func cachedState(for key: String, scope: Scope) -> State? {
        withLock {
            guard let cached = cachedFiles[key], cached.scope == scope else {
                return nil
            }
            return cached.state
        }
    }

    /// 这是唯一 listed-file 协调循环。只有 build 完整成功才原子替换 state；
    /// 失败时只投影同 scope last-good，scanner 未列出的 key 在本轮末尾 prune。
    func loadListedFiles<FileInfo, Candidate: Sendable>(
        _ files: [FileInfo],
        scope: Scope,
        cacheKey: (FileInfo) -> String,
        urlForFile: (FileInfo) -> URL,
        build: (FileInfo, JSONLFileSnapshot, State?) throws -> State,
        project: (State) -> [Candidate],
        onFailure: (FileInfo, Error, Bool) -> Void
    ) -> [Candidate] {
        var allCandidates: [Candidate] = []
        var listedKeys: Set<String> = []

        for fileInfo in files {
            let key = cacheKey(fileInfo)
            listedKeys.insert(key)

            do {
                let snapshot = try fileReader.openSnapshot(
                    for: urlForFile(fileInfo)
                )
                defer { snapshot.stream.close() }

                if let unchanged = unchangedState(
                    for: key,
                    matching: snapshot.metadata,
                    scope: scope
                ) {
                    allCandidates.append(contentsOf: project(unchanged))
                    continue
                }

                let previous = cachedState(for: key, scope: scope)
                let next = try build(fileInfo, snapshot, previous)
                store(
                    next,
                    metadata: snapshot.metadata,
                    scope: scope,
                    for: key
                )
                allCandidates.append(contentsOf: project(next))
            } catch {
                let lastGood = cachedState(for: key, scope: scope)
                if let lastGood {
                    allCandidates.append(contentsOf: project(lastGood))
                }
                onFailure(fileInfo, error, lastGood != nil)
            }
        }

        prune(keeping: listedKeys)
        return allCandidates
    }

    private func unchangedState(
        for key: String,
        matching metadata: JSONLFileMetadata,
        scope: Scope
    ) -> State? {
        withLock {
            // 没有 descriptor identity 时无法证明两次 snapshot 指向同一文件。
            guard metadata.identity != nil,
                  let cached = cachedFiles[key],
                  cached.metadata == metadata,
                  cached.scope == scope else {
                return nil
            }
            cacheHitCount += 1
            return cached.state
        }
    }

    private func store(
        _ state: State,
        metadata: JSONLFileMetadata,
        scope: Scope,
        for key: String
    ) {
        withLock {
            cachedFiles[key] = CachedFile(
                metadata: metadata,
                scope: scope,
                state: state
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
