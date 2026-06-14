import Foundation

/// JSONL 文件中每一行的顶层结构
/// 不同 record type 字段差异大，使用可选字段 + 类型判断
struct ClaudeRecord: Decodable, Sendable {
    let type: String
    let uuid: String
    let sessionId: String
    let timestamp: Date?
    let parentUuid: String?
    let isSidechain: Bool?
    let cwd: String?
    let gitBranch: String?
    let version: String?
    let userType: String?
    let entrypoint: String?
    let message: ClaudeMessage?
    let subtype: String?
    let agentId: String?
    let slug: String?
    let permissionMode: String?
    /// HTTP request-id，作为去重键的可选拼接部分
    /// 对 DeepSeek/Kimi 等 Anthropic 兼容端点可能为 nil
    let requestId: String?

    enum CodingKeys: String, CodingKey {
        case type, uuid, sessionId, timestamp
        case parentUuid, isSidechain, cwd, gitBranch
        case version, userType, entrypoint
        case message, subtype
        case agentId, slug
        case permissionMode
        case requestId
    }

    /// 自定义解码器：处理 ISO 8601 时间戳、可选字段
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        uuid = try container.decode(String.self, forKey: .uuid)
        sessionId = try container.decode(String.self, forKey: .sessionId)

        if let ts = try container.decodeIfPresent(String.self, forKey: .timestamp) {
            timestamp = ISO8601DateFormatterHelper.parse(ts)
        } else {
            timestamp = nil
        }

        parentUuid = try container.decodeIfPresent(String.self, forKey: .parentUuid)
        isSidechain = try container.decodeIfPresent(Bool.self, forKey: .isSidechain)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        gitBranch = try container.decodeIfPresent(String.self, forKey: .gitBranch)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        userType = try container.decodeIfPresent(String.self, forKey: .userType)
        entrypoint = try container.decodeIfPresent(String.self, forKey: .entrypoint)
        message = try container.decodeIfPresent(ClaudeMessage.self, forKey: .message)
        subtype = try container.decodeIfPresent(String.self, forKey: .subtype)
        agentId = try container.decodeIfPresent(String.self, forKey: .agentId)
        slug = try container.decodeIfPresent(String.self, forKey: .slug)
        permissionMode = try container.decodeIfPresent(String.self, forKey: .permissionMode)
        requestId = try container.decodeIfPresent(String.self, forKey: .requestId)
    }

    /// 判断该记录是否为 assistant 类型且包含 usage 数据
    var hasUsageData: Bool {
        type == "assistant" && message?.usage != nil && message?.model != nil
    }
}

/// ISO 8601 日期解析辅助工具
enum ISO8601DateFormatterHelper {
    /// 兼容带/不带毫秒的 ISO 8601 格式
    static func parse(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
