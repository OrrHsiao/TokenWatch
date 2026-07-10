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
    /// Claude Code 记录顶层提供的单条 USD 成本；显式 0 仍保留。
    let costUSD: Double?

    enum CodingKeys: String, CodingKey {
        case type, uuid, sessionId, timestamp
        case parentUuid, isSidechain, cwd, gitBranch
        case version, userType, entrypoint
        case message, subtype
        case agentId, slug
        case permissionMode
        case requestId, costUSD
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
        costUSD = try container.decodeIfPresent(Double.self, forKey: .costUSD)
    }

    /// 判断该记录是否为 assistant 类型且包含 usage 数据
    var hasUsageData: Bool {
        type == "assistant" && message?.usage != nil && message?.model != nil
    }
}

/// direct 与 AgentProgress 行归一化后的 Claude daily billing 记录。
struct ClaudeNormalizedUsageRecord: Sendable {
    let recordUUID: String?
    let sessionID: String?
    let timestamp: Date
    let version: String?
    let messageID: String?
    let model: String?
    let usage: ClaudeBillingUsage
    let requestID: String?
    let isSidechain: Bool
    let cwd: String?
    let costUSD: Double?

    /// 校验 daily.rs 对 optional 字段“缺失可接受、存在空串无效”的契约。
    var isValidDailyUsageRecord: Bool {
        guard version.map(Self.isSemverPrefix) ?? true else { return false }
        return sessionID?.isEmpty != true
            && requestID?.isEmpty != true
            && messageID?.isEmpty != true
            && model?.isEmpty != true
    }

    private static func isSemverPrefix(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        var index = 0
        guard consumeASCIIDigits(bytes, index: &index), bytes[safe: index] == 0x2E else {
            return false
        }
        index += 1
        guard consumeASCIIDigits(bytes, index: &index), bytes[safe: index] == 0x2E else {
            return false
        }
        index += 1
        return bytes[safe: index].map(isASCIIDigit) ?? false
    }

    private static func consumeASCIIDigits(_ bytes: [UInt8], index: inout Int) -> Bool {
        let start = index
        while bytes[safe: index].map(isASCIIDigit) == true {
            index += 1
        }
        return index > start
    }

    private static func isASCIIDigit(_ byte: UInt8) -> Bool {
        (0x30...0x39).contains(byte)
    }
}

/// 窄 daily envelope 解码器：先尝试 direct，再尝试 `data.message` AgentProgress。
struct ClaudeUsageLine: Decodable, Sendable {
    let normalized: ClaudeNormalizedUsageRecord?

    init(from decoder: Decoder) throws {
        if let direct = try? ClaudeDirectUsageEntry(from: decoder) {
            normalized = direct.normalized
            return
        }
        normalized = try ClaudeAgentProgressEntry(from: decoder).normalized
    }

    /// 在 JSON 解码前逐字节执行 pinned usage marker 与 compact null guard。
    static func passesRawPrefilter(_ line: Data) -> Bool {
        let bytes = Array(line)
        guard firstIndex(of: usageMarker, in: bytes, startingAt: 0) != nil else {
            return false
        }

        var offset = 0
        while let nullIndex = firstIndex(of: nullMarker, in: bytes, startingAt: offset) {
            var fieldEnd = max(nullIndex - 1, 0)
            if bytes[safe: fieldEnd] != quote {
                while fieldEnd > 0, bytes[fieldEnd] != quote {
                    fieldEnd -= 1
                }
            }
            if bytes[safe: fieldEnd] == quote {
                var fieldStart = max(fieldEnd - 1, 0)
                while fieldStart > 0, bytes[fieldStart] != quote {
                    fieldStart -= 1
                }
                if bytes[safe: fieldStart] == quote, fieldStart < fieldEnd {
                    let field = Array(bytes[(fieldStart + 1)..<fieldEnd])
                    if unsupportedNullFields.contains(field) {
                        return false
                    }
                }
            }
            offset = nullIndex + nullMarker.count
        }
        return true
    }

    private static let usageMarker = Array("\"usage\":{".utf8)
    private static let nullMarker = Array(":null".utf8)
    private static let quote: UInt8 = 0x22
    private static let unsupportedNullFields: Set<[UInt8]> = Set([
        "id",
        "cwd",
        "model",
        "speed",
        "costUSD",
        "version",
        "sessionId",
        "requestId",
        "isApiErrorMessage",
        "cache_read_input_tokens",
        "cache_creation_input_tokens",
    ].map { Array($0.utf8) })

    private static func firstIndex(
        of needle: [UInt8],
        in haystack: [UInt8],
        startingAt start: Int
    ) -> Int? {
        guard !needle.isEmpty, start >= 0, haystack.count >= needle.count else {
            return nil
        }
        let lastStart = haystack.count - needle.count
        guard start <= lastStart else { return nil }
        for index in start...lastStart
        where haystack[index..<(index + needle.count)].elementsEqual(needle) {
            return index
        }
        return nil
    }
}

private struct ClaudeDirectUsageEntry: Decodable, Sendable {
    let uuid: String?
    let sessionId: String?
    let timestamp: String
    let version: String?
    let message: ClaudeBillingMessage
    let requestId: String?
    let isSidechain: Bool?
    let cwd: String?
    let costUSD: Double?

    var normalized: ClaudeNormalizedUsageRecord? {
        guard let timestamp = ClaudeDailyTimestampParser.parse(timestamp) else { return nil }
        return ClaudeNormalizedUsageRecord(
            recordUUID: uuid,
            sessionID: sessionId,
            timestamp: timestamp,
            version: version,
            messageID: message.id,
            model: message.model,
            usage: message.usage,
            requestID: requestId,
            isSidechain: isSidechain == true,
            cwd: cwd,
            costUSD: costUSD
        )
    }
}

private struct ClaudeAgentProgressEntry: Decodable, Sendable {
    let data: ClaudeAgentProgressData

    var normalized: ClaudeNormalizedUsageRecord? {
        data.message.normalized
    }
}

private struct ClaudeAgentProgressData: Decodable, Sendable {
    let message: ClaudeAgentProgressMessage
}

private struct ClaudeAgentProgressMessage: Decodable, Sendable {
    let timestamp: String
    let message: ClaudeBillingMessage
    let costUSD: Double?
    let requestId: String?
    let isSidechain: Bool?

    var normalized: ClaudeNormalizedUsageRecord? {
        guard let timestamp = ClaudeDailyTimestampParser.parse(timestamp) else { return nil }
        return ClaudeNormalizedUsageRecord(
            recordUUID: nil,
            sessionID: nil,
            timestamp: timestamp,
            version: nil,
            messageID: message.id,
            model: message.model,
            usage: message.usage,
            requestID: requestId,
            isSidechain: isSidechain == true,
            cwd: nil,
            costUSD: costUSD
        )
    }
}

/// 严格复刻 pinned timestamp 形状：秒或三位毫秒，后接 Z 或 ±HH:MM。
private enum ClaudeDailyTimestampParser {
    static func parse(_ value: String) -> Date? {
        let bytes = Array(value.utf8)
        let milliseconds: Int
        let timezoneStart: Int
        if (bytes.count == 20 || bytes.count == 25),
           bytes[19] == 0x5A || bytes[19] == 0x2B || bytes[19] == 0x2D {
            milliseconds = 0
            timezoneStart = 19
        } else if (bytes.count == 24 || bytes.count == 29), bytes[19] == 0x2E {
            guard let parsedMilliseconds = digits(bytes, range: 20..<23) else { return nil }
            milliseconds = parsedMilliseconds
            timezoneStart = 23
        } else {
            return nil
        }

        guard bytes[4] == 0x2D,
              bytes[7] == 0x2D,
              bytes[10] == 0x54,
              bytes[13] == 0x3A,
              bytes[16] == 0x3A,
              let year = digits(bytes, range: 0..<4),
              let month = digits(bytes, range: 5..<7),
              let day = digits(bytes, range: 8..<10),
              let hour = digits(bytes, range: 11..<13),
              let minute = digits(bytes, range: 14..<16),
              let second = digits(bytes, range: 17..<19),
              hour <= 23,
              minute <= 59,
              second <= 59,
              let timezoneOffset = timezoneOffsetMinutes(Array(bytes[timezoneStart...]))
        else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        )
        guard let localDate = calendar.date(from: components) else { return nil }
        let checked = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: localDate
        )
        guard checked.year == year,
              checked.month == month,
              checked.day == day,
              checked.hour == hour,
              checked.minute == minute,
              checked.second == second
        else {
            return nil
        }

        return localDate.addingTimeInterval(
            Double(milliseconds) / 1_000 - Double(timezoneOffset * 60)
        )
    }

    private static func timezoneOffsetMinutes(_ bytes: [UInt8]) -> Int? {
        if bytes == [0x5A] { return 0 }
        guard bytes.count == 6,
              bytes[0] == 0x2B || bytes[0] == 0x2D,
              bytes[3] == 0x3A,
              let hours = digits(bytes, range: 1..<3),
              let minutes = digits(bytes, range: 4..<6)
        else {
            return nil
        }
        let offset = hours * 60 + minutes
        return bytes[0] == 0x2B ? offset : -offset
    }

    private static func digits(_ bytes: [UInt8], range: Range<Int>) -> Int? {
        guard range.lowerBound >= 0, range.upperBound <= bytes.count else { return nil }
        var value = 0
        for index in range {
            let byte = bytes[index]
            guard (0x30...0x39).contains(byte) else { return nil }
            value = value * 10 + Int(byte - 0x30)
        }
        return value
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
