import Foundation
import os.log

/// Provider 最近一次成功聚合的可恢复统计快照。
struct ProviderStatsSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let providerID: ProviderID
    let stats: AggregatedStats
    let generatedAt: Date
    let dataRootPath: String
    let timeZoneIdentifier: String
    let sourceRevision: String?

    /// 创建使用当前 schema 的统计快照。
    /// - Parameters:
    ///   - providerID: 生成统计的 provider。
    ///   - stats: 最近一次成功完成的聚合结果。
    ///   - generatedAt: 聚合结果生成时间。
    ///   - dataRootPath: 生成统计时使用的数据根路径。
    ///   - timeZoneIdentifier: 生成统计时使用的时区标识。
    ///   - sourceRevision: 生成统计时的数据源清单摘要；无法提供时为 `nil`。
    ///   - schemaVersion: 快照结构版本；默认为当前版本。
    init(
        providerID: ProviderID,
        stats: AggregatedStats,
        generatedAt: Date,
        dataRootPath: String,
        timeZoneIdentifier: String,
        sourceRevision: String? = nil,
        schemaVersion: Int = ProviderStatsSnapshot.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.providerID = providerID
        self.stats = stats
        self.generatedAt = generatedAt
        self.dataRootPath = dataRootPath
        self.timeZoneIdentifier = timeZoneIdentifier
        self.sourceRevision = sourceRevision
    }
}

/// Provider 聚合统计快照的持久化接口。
protocol ProviderStatsSnapshotStoring: Sendable {
    /// 读取 provider 的当前版本快照；缺失、损坏或不兼容时返回 `nil`。
    /// - Parameter providerID: 要读取的 provider。
    /// - Returns: 可恢复的当前版本快照，或 `nil`。
    func load(for providerID: ProviderID) -> ProviderStatsSnapshot?

    /// 原子替换 provider 已保存的快照。
    /// - Parameter snapshot: 要持久化的完整聚合统计。
    func save(_ snapshot: ProviderStatsSnapshot) throws
}

/// 将每个 provider 的最终聚合统计保存为独立 JSON 文件。
struct SystemProviderStatsSnapshotStore: ProviderStatsSnapshotStoring, Sendable {
    private let directoryURL: URL
    private let logger = Logger(
        subsystem: "com.xiaoao.TokenWatch",
        category: "ProviderStatsSnapshotStore"
    )

    /// 创建使用应用 Cache 目录的快照存储。
    init() {
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
        let baseDirectory: URL
        if isTesting {
            baseDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(
                    "TokenWatchTestCaches-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)",
                    isDirectory: true
                )
        } else {
            baseDirectory = FileManager.default.urls(
                for: .cachesDirectory,
                in: .userDomainMask
            ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        }
        directoryURL = baseDirectory.appendingPathComponent(
            "TokenWatch/ProviderStatsSnapshots",
            isDirectory: true
        )
    }

    /// 创建使用指定目录的快照存储，供测试或自定义容器使用。
    /// - Parameter directoryURL: 每个 provider JSON 文件所在的目录。
    init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    func load(for providerID: ProviderID) -> ProviderStatsSnapshot? {
        let fileURL = fileURL(for: providerID)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let snapshot = try JSONDecoder().decode(ProviderStatsSnapshot.self, from: data)
            guard snapshot.schemaVersion == ProviderStatsSnapshot.currentSchemaVersion else {
                logger.info(
                    "统计快照版本不兼容: \(snapshot.schemaVersion) (\(providerID.rawValue))"
                )
                return nil
            }
            guard snapshot.providerID == providerID else {
                logger.warning("统计快照 provider 不匹配 (\(providerID.rawValue))")
                return nil
            }
            return snapshot
        } catch {
            logger.warning(
                "读取统计快照失败 (\(providerID.rawValue)): \(error.localizedDescription)"
            )
            return nil
        }
    }

    func save(_ snapshot: ProviderStatsSnapshot) throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL(for: snapshot.providerID), options: .atomic)
        logger.info("成功写入统计快照 (\(snapshot.providerID.rawValue))")
    }

    private func fileURL(for providerID: ProviderID) -> URL {
        directoryURL.appendingPathComponent(
            "\(providerID.rawValue).json",
            isDirectory: false
        )
    }
}
