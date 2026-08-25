import Foundation
import os.log

/// 磁盘持久化记录，保存单个 JSONL 文件的元数据与完整增量解析状态。
struct JSONLDiskCacheEntry<State: Codable & Sendable>: Codable, Sendable {
    let key: String
    let scopeIdentifier: String
    let metadata: JSONLFileMetadata
    let state: State
}

/// 磁盘持久化 Payload 包裹体
struct JSONLDiskCachePayload<State: Codable & Sendable>: Codable, Sendable {
    let version: Int
    var entries: [String: JSONLDiskCacheEntry<State>]
}

/// 磁盘缓存存储接口
protocol JSONLDiskCacheStoring<State>: Sendable {
    associatedtype State: Codable & Sendable
    func loadAll() -> [String: JSONLDiskCacheEntry<State>]
    func saveAll(_ entries: [String: JSONLDiskCacheEntry<State>])
}

/// 默认以 JSON 格式存储在沙盒 Cache 目录的磁盘缓存管理对象。
final class SystemJSONLDiskCacheStore<State: Codable & Sendable>: JSONLDiskCacheStoring, @unchecked Sendable {
    private let fileURL: URL
    private let logger = Logger(subsystem: "com.xiaoao.TokenWatch", category: "JSONLDiskCacheStore")
    /// 磁盘缓存编码版本，按 provider 注入：单个 provider 的解析规则变化
    /// 只提升对应 store 的版本，避免全局 bump 连带失效其他 provider 的缓存。
    private let currentVersion: Int
    /// 仅包含 provider 已确认与当前解析状态语义兼容的旧版本。
    /// 不能按版本大小推断兼容性，否则可能复用结构可解码但内容已缺失的缓存。
    private let compatibleCacheVersions: Set<Int>

    init(
        namespace: String,
        cacheVersion: Int,
        compatibleCacheVersions: Set<Int> = []
    ) {
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
        let baseDir: URL
        if isTesting {
            baseDir = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("TokenWatchTestCaches-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        } else {
            baseDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
        }
        let folderURL = baseDir.appendingPathComponent("TokenWatch/JSONLCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        self.fileURL = folderURL.appendingPathComponent("\(namespace).json")
        self.currentVersion = cacheVersion
        self.compatibleCacheVersions = compatibleCacheVersions
    }

    init(
        fileURL: URL,
        cacheVersion: Int = 2,
        compatibleCacheVersions: Set<Int> = []
    ) {
        self.fileURL = fileURL
        self.currentVersion = cacheVersion
        self.compatibleCacheVersions = compatibleCacheVersions
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    func loadAll() -> [String: JSONLDiskCacheEntry<State>] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return [:]
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            let payload = try decoder.decode(JSONLDiskCachePayload<State>.self, from: data)
            let isCurrentVersion = payload.version == currentVersion
            guard isCurrentVersion || compatibleCacheVersions.contains(payload.version) else {
                logger.info(
                    "磁盘缓存版本不兼容 (\(payload.version) -> \(self.currentVersion))，忽略并重建 (\(self.fileURL.lastPathComponent))"
                )
                return [:]
            }
            if isCurrentVersion {
                logger.info(
                    "成功载入磁盘缓存: \(payload.entries.count) 项文件记录 (\(self.fileURL.lastPathComponent), v\(self.currentVersion))"
                )
            } else {
                logger.info(
                    "成功载入兼容磁盘缓存: \(payload.entries.count) 项文件记录 (\(self.fileURL.lastPathComponent), v\(payload.version) -> v\(self.currentVersion))"
                )
            }
            return payload.entries
        } catch {
            logger.warning("读取磁盘缓存失败 (\(self.fileURL.lastPathComponent)): \(error.localizedDescription)")
            return [:]
        }
    }

    func saveAll(_ entries: [String: JSONLDiskCacheEntry<State>]) {
        do {
            let payload = JSONLDiskCachePayload(version: currentVersion, entries: entries)
            let encoder = JSONEncoder()
            let data = try encoder.encode(payload)
            try data.write(to: fileURL, options: .atomic)
            logger.info(
                "成功写回磁盘缓存: \(entries.count) 项记录 (\(self.fileURL.lastPathComponent), v\(self.currentVersion))"
            )
        } catch {
            logger.error("保存磁盘缓存失败 (\(self.fileURL.lastPathComponent)): \(error.localizedDescription)")
        }
    }
}
