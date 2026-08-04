import CryptoKit
import Foundation

/// 没有 provider-specific cache scope 的 parser 使用此单一值。
struct JSONLUnscopedCacheScope: Sendable, Equatable {
    static let shared = JSONLUnscopedCacheScope()

    private init() {}
}

/// 统一协调 scanner 已列出文件的 snapshot、state cache、last-good 与 prune。
/// Provider 只通过 build/project closure 定义状态迁移和候选投影。
/// 文件保持顺序处理；磁盘缓存持久化完整 state，供冷启动继续增量解析。
struct JSONLLastGoodCacheLoadResult<Candidate: Sendable>: Sendable {
    /// 全量 unchanged 且调用方允许跳过物化时为 nil。
    let candidates: [Candidate]?
    let didChange: Bool
    let sourceRevision: String
}

final class JSONLLastGoodCacheCoordinator<
    State: Codable & Sendable,
    Scope: Sendable & Equatable
>: @unchecked Sendable {
    private struct CachedFile {
        let metadata: JSONLFileMetadata
        let scope: Scope
        let state: State
    }

    private struct SourceRevisionFile {
        let key: String
        let metadata: JSONLFileMetadata?
        let stateComponent: Data
    }

    private let fileReader: any JSONLFileReading
    private let lock = NSLock()
    private var cachedFiles: [String: CachedFile] = [:]
    private var cacheHitCount = 0

    // 磁盘持久化在内存中的同层镜像与已加载标记
    private var diskEntries: [String: JSONLDiskCacheEntry<State>]?
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

    /// 顺序协调 listed files，并始终物化候选以保持现有 parser 调用语义。
    func loadListedFiles<FileInfo: Sendable, Candidate: Sendable>(
        _ files: [FileInfo],
        scope: Scope,
        diskStore: (any JSONLDiskCacheStoring<State>)? = nil,
        cacheKey: @escaping @Sendable (FileInfo) -> String,
        urlForFile: @escaping @Sendable (FileInfo) -> URL,
        build: @escaping @Sendable (FileInfo, JSONLFileSnapshot, State?) throws -> State,
        project: @escaping @Sendable (State) -> [Candidate],
        sourceRevisionComponent: @escaping @Sendable (State) -> Data = { _ in Data() },
        onFailure: @escaping @Sendable (FileInfo, Error, Bool) -> Void
    ) -> [Candidate] {
        loadListedFilesWithChangeStatus(
            files,
            scope: scope,
            diskStore: diskStore,
            materializeCandidatesWhenUnchanged: true,
            cacheKey: cacheKey,
            urlForFile: urlForFile,
            build: build,
            project: project,
            sourceRevisionComponent: sourceRevisionComponent,
            onFailure: onFailure
        ).candidates ?? []
    }

    /// 返回本轮是否观察到数据变化；全量 unchanged 时可跳过昂贵的候选投影。
    /// - Parameter materializeCandidatesWhenUnchanged: false 时，全量命中且无 prune
    ///   会返回 nil candidates，供上层直接复用已聚合快照。
    func loadListedFilesWithChangeStatus<
        FileInfo: Sendable,
        Candidate: Sendable
    >(
        _ files: [FileInfo],
        scope: Scope,
        diskStore: (any JSONLDiskCacheStoring<State>)? = nil,
        materializeCandidatesWhenUnchanged: Bool,
        cacheKey: @escaping @Sendable (FileInfo) -> String,
        urlForFile: @escaping @Sendable (FileInfo) -> URL,
        build: @escaping @Sendable (FileInfo, JSONLFileSnapshot, State?) throws -> State,
        project: @escaping @Sendable (State) -> [Candidate],
        sourceRevisionComponent: @escaping @Sendable (State) -> Data = { _ in Data() },
        onFailure: @escaping @Sendable (FileInfo, Error, Bool) -> Void
    ) -> JSONLLastGoodCacheLoadResult<Candidate> {
        // 1. 延迟（仅首次）从磁盘加载完整 state。
        let initialDiskEntries: [String: JSONLDiskCacheEntry<State>]
        if let diskStore {
            initialDiskEntries = withLock {
                if !isDiskCacheLoaded {
                    let loaded = diskStore.loadAll()
                    diskEntries = loaded
                    isDiskCacheLoaded = true
                    return loaded
                }
                return diskEntries ?? [:]
            }
        } else {
            initialDiskEntries = [:]
        }
        let scopeId = String(describing: scope)

        guard !files.isEmpty else {
            let hadCachedFiles = withLock { !cachedFiles.isEmpty }
            let didChange = hadCachedFiles || !initialDiskEntries.isEmpty
            withLock {
                cachedFiles.removeAll()
                if let diskStore {
                    let emptyDiskEntries: [String: JSONLDiskCacheEntry<State>] = [:]
                    diskEntries = emptyDiskEntries
                    isDiskCacheLoaded = true
                    if !initialDiskEntries.isEmpty {
                        // scanner 已确认没有可用文件，覆盖旧状态，避免删除日志后保留用量。
                        diskStore.saveAll(emptyDiskEntries)
                    }
                }
            }
            return JSONLLastGoodCacheLoadResult(
                candidates: materializeCandidatesWhenUnchanged || didChange ? [] : nil,
                didChange: didChange,
                sourceRevision: makeSourceRevision(
                    scopeIdentifier: scopeId,
                    files: []
                )
            )
        }

        var listedKeys = Set<String>()
        var currentDiskEntries = initialDiskEntries
        var isDiskCacheDirty = false
        var didChange = false
        var statesForProjection: [State] = []
        statesForProjection.reserveCapacity(files.count)
        var sourceRevisionFiles: [SourceRevisionFile] = []
        sourceRevisionFiles.reserveCapacity(files.count)

        // 2. 顺序处理所有列出的文件，避免 GCD 线程饥饿与死锁。
        for fileInfo in files {
            let key = cacheKey(fileInfo)
            listedKeys.insert(key)
            var observedMetadata: JSONLFileMetadata?

            do {
                let snapshot = try fileReader.openSnapshot(
                    for: urlForFile(fileInfo)
                )
                defer { snapshot.stream.close() }
                observedMetadata = snapshot.metadata

                // a. 先查内存 state 命中。
                if let unchanged = unchangedState(
                    for: key,
                    matching: snapshot.metadata,
                    scope: scope
                ) {
                    statesForProjection.append(unchanged)
                    sourceRevisionFiles.append(SourceRevisionFile(
                        key: key,
                        metadata: snapshot.metadata,
                        stateComponent: sourceRevisionComponent(unchanged)
                    ))
                    continue
                }

                // b. 再查磁盘 state 命中；恢复到内存后无需读取 JSONL 行。
                if snapshot.metadata.identity != nil,
                   let diskEntry = currentDiskEntries[key],
                   diskEntry.metadata == snapshot.metadata,
                   diskEntry.scopeIdentifier == scopeId {
                    withLock { cacheHitCount += 1 }
                    store(
                        diskEntry.state,
                        metadata: snapshot.metadata,
                        scope: scope,
                        for: key
                    )
                    statesForProjection.append(diskEntry.state)
                    sourceRevisionFiles.append(SourceRevisionFile(
                        key: key,
                        metadata: snapshot.metadata,
                        stateComponent: sourceRevisionComponent(diskEntry.state)
                    ))
                    continue
                }

                // c. 新文件或发生变化；冷启动时磁盘 state 同样可作为增量 previous。
                didChange = true
                let previous = cachedState(for: key, scope: scope)
                    ?? currentDiskEntries[key].flatMap { entry in
                        entry.scopeIdentifier == scopeId ? entry.state : nil
                    }
                let next = try build(fileInfo, snapshot, previous)
                store(next, metadata: snapshot.metadata, scope: scope, for: key)
                statesForProjection.append(next)
                sourceRevisionFiles.append(SourceRevisionFile(
                    key: key,
                    metadata: snapshot.metadata,
                    stateComponent: sourceRevisionComponent(next)
                ))

                if diskStore != nil {
                    currentDiskEntries[key] = JSONLDiskCacheEntry(
                        key: key,
                        scopeIdentifier: scopeId,
                        metadata: snapshot.metadata,
                        state: next
                    )
                    isDiskCacheDirty = true
                }
            } catch {
                didChange = true
                let lastGood = cachedState(for: key, scope: scope)
                    ?? currentDiskEntries[key].flatMap { entry in
                        entry.scopeIdentifier == scopeId ? entry.state : nil
                    }
                if let lastGood {
                    statesForProjection.append(lastGood)
                }
                sourceRevisionFiles.append(SourceRevisionFile(
                    key: key,
                    metadata: observedMetadata,
                    stateComponent: lastGood.map(sourceRevisionComponent) ?? Data()
                ))
                onFailure(fileInfo, error, lastGood != nil)
            }
        }

        // 3. 内存与磁盘 prune；只有 state 成功构建或 key 被删除时才写回。
        withLock {
            let cachedCountBefore = cachedFiles.count
            cachedFiles = cachedFiles.filter { listedKeys.contains($0.key) }
            if cachedFiles.count != cachedCountBefore {
                didChange = true
            }
            if diskStore != nil {
                let countBefore = currentDiskEntries.count
                currentDiskEntries = currentDiskEntries.filter {
                    listedKeys.contains($0.key)
                }
                if currentDiskEntries.count != countBefore {
                    isDiskCacheDirty = true
                    didChange = true
                }
                diskEntries = currentDiskEntries
                if isDiskCacheDirty {
                    diskStore?.saveAll(currentDiskEntries)
                }
            }
        }

        let shouldMaterialize = materializeCandidatesWhenUnchanged || didChange
        let candidates = shouldMaterialize
            ? statesForProjection.flatMap(project)
            : nil
        return JSONLLastGoodCacheLoadResult(
            candidates: candidates,
            didChange: didChange,
            sourceRevision: makeSourceRevision(
                scopeIdentifier: scopeId,
                files: sourceRevisionFiles
            )
        )
    }

    /// 以稳定排序和定长整数编码生成跨进程一致的数据源 revision。
    private func makeSourceRevision(
        scopeIdentifier: String,
        files: [SourceRevisionFile]
    ) -> String {
        var payload = Data()

        func appendUInt64(_ value: UInt64) {
            var bigEndian = value.bigEndian
            withUnsafeBytes(of: &bigEndian) { bytes in
                payload.append(contentsOf: bytes)
            }
        }

        func appendFramed(_ data: Data) {
            appendUInt64(UInt64(data.count))
            payload.append(data)
        }

        appendFramed(Data(scopeIdentifier.utf8))
        for file in files.sorted(by: { $0.key < $1.key }) {
            appendFramed(Data(file.key.utf8))
            if let metadata = file.metadata {
                payload.append(1)
                if let identity = metadata.identity {
                    payload.append(1)
                    appendUInt64(identity.deviceID)
                    appendUInt64(identity.fileID)
                } else {
                    payload.append(0)
                }
                appendUInt64(metadata.size)
                appendUInt64(
                    metadata.modificationDate.timeIntervalSince1970.bitPattern
                )
            } else {
                payload.append(0)
            }
            appendFramed(file.stateComponent)
        }

        return SHA256.hash(data: payload)
            .map { String(format: "%02x", $0) }
            .joined()
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

    @discardableResult
    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
