import Foundation

/// 没有 provider-specific cache scope 的 parser 使用此单一值。
struct JSONLUnscopedCacheScope: Sendable, Equatable {
    static let shared = JSONLUnscopedCacheScope()

    private init() {}
}

/// 统一协调 scanner 已列出文件的 snapshot、state cache、last-good 与 prune。
/// Provider 只通过 build/project closure 定义状态迁移和候选投影。
/// 支持多核并发解析（阶段 2）与磁盘持久化缓存（阶段 1）。
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

    // 磁盘持久化在内存中的同层镜像与已加载标记
    private var diskEntries: Any?
    private var isDiskCacheLoaded = false

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

    /// 这是 listed-file 协调循环。
    /// 并发处理所有文件，只有 build 完整成功才原子替换 state；
    /// 失败时只投影同 scope last-good，scanner 未列出的 key 在本轮末尾 prune。
    func loadListedFiles<FileInfo: Sendable, Candidate: Codable & Sendable>(
        _ files: [FileInfo],
        scope: Scope,
        diskStore: (any JSONLDiskCacheStoring<Candidate>)? = nil,
        cacheKey: @escaping @Sendable (FileInfo) -> String,
        urlForFile: @escaping @Sendable (FileInfo) -> URL,
        build: @escaping @Sendable (FileInfo, JSONLFileSnapshot, State?) throws -> State,
        project: @escaping @Sendable (State) -> [Candidate],
        onFailure: @escaping @Sendable (FileInfo, Error, Bool) -> Void
    ) -> [Candidate] {
        guard !files.isEmpty else {
            prune(keeping: [])
            return []
        }

        // 1. 延迟（仅首次）从磁盘加载缓存条目
        let initialDiskEntries: [String: JSONLDiskCacheEntry<Candidate>]
        if let diskStore {
            initialDiskEntries = withLock {
                if !isDiskCacheLoaded {
                    let loaded = diskStore.loadAll()
                    diskEntries = loaded
                    isDiskCacheLoaded = true
                    return loaded
                } else if let existing = diskEntries as? [String: JSONLDiskCacheEntry<Candidate>] {
                    return existing
                } else {
                    let loaded = diskStore.loadAll()
                    diskEntries = loaded
                    return loaded
                }
            }
        } else {
            initialDiskEntries = [:]
        }

        var listedKeys = Set<String>()
        var currentDiskEntries = initialDiskEntries
        var isDiskCacheDirty = false
        var allCandidates = [Candidate]()
        let scopeId = String(describing: scope)

        // 2. 顺序处理所有列出的文件，避免 GCD 线程饥饿与死锁
        for fileInfo in files {
            let key = cacheKey(fileInfo)
            listedKeys.insert(key)

            do {
                let snapshot = try fileReader.openSnapshot(
                    for: urlForFile(fileInfo)
                )
                defer { snapshot.stream.close() }

                // a. 先查内存 State 命中
                if let unchanged = unchangedState(
                    for: key,
                    matching: snapshot.metadata,
                    scope: scope
                ) {
                    allCandidates.append(contentsOf: project(unchanged))
                    continue
                }

                // b. 再查磁盘缓存 命中 (无需重新解析 JSONL 行)
                if let diskEntry = currentDiskEntries[key],
                   diskEntry.metadata == snapshot.metadata,
                   diskEntry.scopeIdentifier == scopeId {
                    withLock { cacheHitCount += 1 }
                    allCandidates.append(contentsOf: diskEntry.candidates)
                    continue
                }

                // c. 未命中（新文件/已追加），进行增量或重新构建
                let previous = cachedState(for: key, scope: scope)
                let next = try build(fileInfo, snapshot, previous)
                let candidates = project(next)

                withLock {
                    cachedFiles[key] = CachedFile(
                        metadata: snapshot.metadata,
                        scope: scope,
                        state: next
                    )
                }

                if diskStore != nil {
                    let entry = JSONLDiskCacheEntry(
                        key: key,
                        scopeIdentifier: scopeId,
                        metadata: snapshot.metadata,
                        candidates: candidates
                    )
                    currentDiskEntries[key] = entry
                    isDiskCacheDirty = true
                    allCandidates.append(contentsOf: candidates)
                } else {
                    allCandidates.append(contentsOf: candidates)
                }
            } catch {
                let lastGood = cachedState(for: key, scope: scope)
                let reused: Bool
                if let lastGood {
                    allCandidates.append(contentsOf: project(lastGood))
                    reused = true
                } else if let diskEntry = currentDiskEntries[key],
                          diskEntry.scopeIdentifier == scopeId {
                    allCandidates.append(contentsOf: diskEntry.candidates)
                    reused = true
                } else {
                    reused = false
                }
                onFailure(fileInfo, error, reused)
            }
        }

        // 3. 内存与磁盘剪枝与保存
        withLock {
            cachedFiles = cachedFiles.filter { listedKeys.contains($0.key) }
            if diskStore != nil {
                let countBefore = currentDiskEntries.count
                currentDiskEntries = currentDiskEntries.filter { listedKeys.contains($0.key) }
                if currentDiskEntries.count != countBefore {
                    isDiskCacheDirty = true
                }
                diskEntries = currentDiskEntries
                if isDiskCacheDirty {
                    diskStore?.saveAll(currentDiskEntries)
                }
            }
        }

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
