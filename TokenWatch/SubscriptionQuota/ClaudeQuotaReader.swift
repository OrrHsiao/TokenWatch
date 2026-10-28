import Foundation
import os.log

/// 解析 Claude Code `~/.claude.json` 中的 `cachedUsageUtilization`。
///
/// 该文件包含大量与额度无关的配置。解码模型只声明额度缓存与当前登录账号 ID，
/// 其余字段既不进入额度模型，也不会写入日志。
enum ClaudeQuotaParser {
    private static let logger = Logger(subsystem: "com.xiaoao.TokenWatch", category: "ClaudeQuotaParser")

    /// 从配置文件内容中提取当前账号的额度快照。
    /// - Parameter data: `.claude.json` 的完整内容。
    /// - Returns: 有效快照；缓存缺失、缺少来源时间或属于其他账号时返回 `.noRecord`。
    /// - Throws: 文件不是 JSON 对象（例如写入中的半截文件）时抛出，由调用方保留最后有效值。
    static func parse(_ data: Data) throws -> SubscriptionQuotaReadResult {
        let fields = try JSONDecoder().decode(ClaudeConfigQuotaFields.self, from: data)
        guard let cache = fields.cachedUsage else {
            return .noRecord
        }
        guard let fetchedAtMs = cache.fetchedAtMs, fetchedAtMs > 0 else {
            // 没有来源获取时间就无法判断新旧；不能用读文件时刻替代。
            logger.info("Claude 额度缓存缺少 fetchedAtMs，按无记录处理")
            return .noRecord
        }
        // 账号切换后缓存可能仍是旧账号的结果；两边都有 ID 且不同时不展示。
        if let cachedAccount = cache.accountID,
           let currentAccount = fields.currentAccountID,
           cachedAccount != currentAccount {
            logger.info("Claude 额度缓存与当前登录账号不一致，忽略该缓存")
            return .noRecord
        }

        var windows: [SubscriptionQuotaWindowKind: SubscriptionQuotaWindow] = [:]
        windows[.fiveHour] = cache.fiveHour.flatMap {
            SubscriptionQuotaWindow(usedPercent: $0.utilization, resetsAt: $0.resetsAt)
        }
        windows[.sevenDay] = cache.sevenDay.flatMap {
            SubscriptionQuotaWindow(usedPercent: $0.utilization, resetsAt: $0.resetsAt)
        }
        guard !windows.isEmpty else {
            return .noRecord
        }

        return .snapshot(SubscriptionQuotaSnapshot(
            provider: .claude,
            accountID: cache.accountID ?? fields.currentAccountID,
            bucketID: nil,
            recordedAt: Date(timeIntervalSince1970: fetchedAtMs / 1_000),
            windows: windows
        ))
    }
}

/// 只声明额度需要的顶层字段；子结构损坏时降级为 nil，不让整份配置解析失败。
private struct ClaudeConfigQuotaFields: Decodable {
    let cachedUsage: ClaudeCachedUsage?
    let currentAccountID: String?

    private enum CodingKeys: String, CodingKey {
        case cachedUsageUtilization
        case oauthAccount
    }

    private enum AccountCodingKeys: String, CodingKey {
        case accountUuid
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cachedUsage = try? container.decodeIfPresent(
            ClaudeCachedUsage.self,
            forKey: .cachedUsageUtilization
        )
        let account = try? container.nestedContainer(
            keyedBy: AccountCodingKeys.self,
            forKey: .oauthAccount
        )
        currentAccountID = try? account?.decodeIfPresent(String.self, forKey: .accountUuid)
    }
}

private struct ClaudeCachedUsage: Decodable {
    let fetchedAtMs: Double?
    let accountID: String?
    let fiveHour: ClaudeUsageWindow?
    let sevenDay: ClaudeUsageWindow?

    private enum CodingKeys: String, CodingKey {
        case fetchedAtMs
        case accountUuid
        case utilization
    }

    private enum UtilizationCodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fetchedAtMs = (try? container.decodeIfPresent(
            SubscriptionQuotaLossyNumber.self,
            forKey: .fetchedAtMs
        ))?.value
        accountID = try? container.decodeIfPresent(String.self, forKey: .accountUuid)
        let utilization = try? container.nestedContainer(
            keyedBy: UtilizationCodingKeys.self,
            forKey: .utilization
        )
        // 两个窗口独立容错：一个窗口损坏不影响另一个。
        fiveHour = try? utilization?.decodeIfPresent(ClaudeUsageWindow.self, forKey: .fiveHour)
        sevenDay = try? utilization?.decodeIfPresent(ClaudeUsageWindow.self, forKey: .sevenDay)
    }
}

private struct ClaudeUsageWindow: Decodable {
    /// 已用百分比；时间未知与使用率缺失分开处理。
    let utilization: Double?
    let resetsAt: Date?

    private enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        utilization = (try? container.decodeIfPresent(
            SubscriptionQuotaLossyNumber.self,
            forKey: .utilization
        ))?.value
        resetsAt = (try? container.decodeIfPresent(
            SubscriptionQuotaLossyDate.self,
            forKey: .resetsAt
        ))?.date
    }
}

/// 读取用户授权的 `.claude.json`，并在文件未变化时复用上次解析结果。
final class ClaudeQuotaFileReader: @unchecked Sendable {
    private struct CachedParse {
        let path: String
        let size: UInt64
        let modificationDate: Date?
        let result: SubscriptionQuotaReadResult
    }

    private let lock = NSLock()
    private var cachedParse: CachedParse?

    /// 读取并解析额度缓存。
    /// - Parameter fileURL: 已开始 security-scoped 访问的 `.claude.json`。
    /// - Returns: 当前账号的额度读取结果。
    /// - Throws: 文件暂不可读或内容不是完整 JSON 时抛出。
    func read(fileURL: URL) throws -> SubscriptionQuotaReadResult {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let modificationDate = attributes[.modificationDate] as? Date

        lock.lock()
        if let cachedParse,
           cachedParse.path == fileURL.path,
           cachedParse.size == size,
           cachedParse.modificationDate == modificationDate {
            lock.unlock()
            return cachedParse.result
        }
        lock.unlock()

        let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        let result = try ClaudeQuotaParser.parse(data)

        lock.lock()
        cachedParse = CachedParse(
            path: fileURL.path,
            size: size,
            modificationDate: modificationDate,
            result: result
        )
        lock.unlock()
        return result
    }
}
