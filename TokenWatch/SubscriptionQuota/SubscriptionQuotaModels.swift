import Foundation

/// 订阅额度的来源工具；状态栏与弹窗都按此顺序固定展示。
enum SubscriptionQuotaProvider: String, CaseIterable, Sendable {
    case claude
    case codex

    /// 固定产品名，不随界面语言翻译。
    var displayName: String {
        switch self {
        case .claude:
            return "Claude"
        case .codex:
            return "Codex"
        }
    }
}

/// 额度窗口；展示顺序固定为 5 小时、一周，不按紧张程度轮换。
enum SubscriptionQuotaWindowKind: String, CaseIterable, Sendable {
    case fiveHour
    case sevenDay
}

/// 单个额度窗口在来源快照中的值。
struct SubscriptionQuotaWindow: Equatable, Sendable {
    /// 来源报告的已用百分比，已夹到 0...100。
    let usedPercent: Double
    /// 来源报告的重置时间；nil 表示来源未提供，界面显示“重置时间未知”。
    let resetsAt: Date?

    /// 仅接受有限数值，避免把缺失或损坏字段误写成 0% 或 100%。
    /// - Parameters:
    ///   - usedPercent: 来源的已用百分比。
    ///   - resetsAt: 来源的重置时间。
    init?(usedPercent: Double?, resetsAt: Date?) {
        guard let usedPercent, usedPercent.isFinite else { return nil }
        self.usedPercent = min(max(usedPercent, 0), 100)
        self.resetsAt = resetsAt
    }

    /// 剩余百分比；界面统一表达“剩余”。
    var remainingPercent: Double {
        100 - usedPercent
    }
}

/// 一次来源记录中的额度快照。
///
/// 快照只来自服务端结果在本地留下的缓存或日志，不能由 token 数或费用推导。
struct SubscriptionQuotaSnapshot: Equatable, Sendable {
    let provider: SubscriptionQuotaProvider
    /// 快照所属账号；来源未记录时为 nil。
    let accountID: String?
    /// 额度桶标识（Codex `limit_id`）；Claude 无此概念时为 nil。
    let bucketID: String?
    /// 来源记录时间（Claude `fetchedAtMs` / Codex 事件时间），不是 App 读取文件的时刻。
    let recordedAt: Date
    let windows: [SubscriptionQuotaWindowKind: SubscriptionQuotaWindow]
}

/// 一次成功读取的结果；读取失败通过抛错表达，由 store 保留最后有效值。
enum SubscriptionQuotaReadResult: Equatable, Sendable {
    /// 未授权来源文件或目录。
    case notAuthorized
    /// 来源可读，但没有当前账号可用的额度记录。
    case noRecord
    case snapshot(SubscriptionQuotaSnapshot)
}

/// 单个工具的额度状态；两个工具互不影响。
struct SubscriptionQuotaProviderState: Equatable, Sendable {
    /// 最近一次成功读取的结果；nil 表示尚未成功读取过。
    var result: SubscriptionQuotaReadResult?
    /// 最近一次读取是否失败；失败时 result 继续保留最后有效值并照常计龄。
    var lastReadFailed: Bool

    static let initial = SubscriptionQuotaProviderState(result: nil, lastReadFailed: false)
}

/// 额度来源中的数值字段可能是整数、浮点或字符串，统一宽容解码为有限 Double。
struct SubscriptionQuotaLossyNumber: Decodable, Sendable {
    let value: Double?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
        } else if let number = try? container.decode(Double.self) {
            value = number.isFinite ? number : nil
        } else if let text = try? container.decode(String.self),
                  let number = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)),
                  number.isFinite {
            value = number
        } else {
            value = nil
        }
    }
}

/// 额度重置时间兼容 ISO 8601 字符串、Unix 秒和 Unix 毫秒。
struct SubscriptionQuotaLossyDate: Decodable, Sendable {
    let date: Date?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            date = nil
        } else if let text = try? container.decode(String.self) {
            date = CodexNormalizedTimestamp.parse(text)?.date
        } else if let number = try? container.decode(Double.self), number.isFinite, number > 0 {
            date = CodexNormalizedTimestamp.parse(UInt64(min(number, Double(UInt64.max / 2))))?.date
        } else {
            date = nil
        }
    }
}
