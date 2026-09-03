import Foundation

/// Protobuf Wire Type 常量定义
enum ProtobufWireType: Int, Sendable {
    case varint = 0
    case fixed64 = 1
    case lengthDelimited = 2
    case fixed32 = 5
}

/// 解析出的单项 Protobuf 字段值
enum ProtobufValue: Sendable {
    case varint(UInt64)
    case fixed64(UInt64)
    case lengthDelimited(Data)
    case fixed32(UInt32)

    var asVarint: UInt64? {
        if case .varint(let val) = self { return val }
        return nil
    }

    var asData: Data? {
        if case .lengthDelimited(let data) = self { return data }
        return nil
    }

    var asString: String? {
        guard let data = asData else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// 解析后的单个 Protobuf 字段
struct ProtobufField: Sendable {
    let tag: Int
    let wireType: ProtobufWireType
    let value: ProtobufValue
}

/// 解码得到的 Antigravity 单次用量统计明细
struct AntigravityUsageMetadata: Sendable {
    let promptTokens: Int
    let cachedContentTokens: Int
    let thoughtsTokens: Int
    let candidatesTokens: Int
    let totalTokens: Int
    let botMessageId: String?
}

/// 解码得到的 Antigravity 单次生成上下文与元数据
struct AntigravityGenerationPayload: Sendable {
    let modelID: String
    let modelDisplayName: String?
    let requestId: String?
    let trajectoryId: String?
    let lastStepIndex: Int64?
    let usage: AntigravityUsageMetadata?
}

/// 纯 Swift 轻量级 Protobuf Wire Reader
///
/// 设计原因：
/// 避免引入庞大的 SwiftProtobuf 或 SPM 外部二进制依赖，只读取 Antigravity 关注的已知 Tag。
/// 遇到未知 Tag 或损坏数据时具备防御性跳过机制，确保解析过程不会崩溃。
enum AntigravityProtoReader {

    /// 读取 Varint（无符号 64 位整数）
    /// - Parameters:
    ///   - data: 待解码的数据块
    ///   - offset: 当前读取位置（入参/出参）
    /// - Returns: 解码出的 UInt64；若数据截断或格式非法返回 nil
    static func decodeVarint(from data: Data, offset: inout Int) -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0

        while offset < data.count {
            let byte = data[offset]
            offset += 1
            result |= UInt64(byte & 0x7F) << shift
            if (byte & 0x80) == 0 {
                return result
            }
            shift += 7
            if shift >= 64 {
                // 非法 varint（超过 64 位），防止溢出
                return nil
            }
        }
        return nil
    }

    /// 解析二进制数据块的所有直接子字段
    /// - Parameter data: Protobuf 二进制数据
    /// - Returns: 字段列表
    static func parseFields(from data: Data) -> [ProtobufField] {
        var fields: [ProtobufField] = []
        var offset = 0

        while offset < data.count {
            guard let key = decodeVarint(from: data, offset: &offset) else { break }
            let tag = Int(key >> 3)
            let wireTypeRaw = Int(key & 0x07)
            guard let wireType = ProtobufWireType(rawValue: wireTypeRaw) else { break }

            switch wireType {
            case .varint:
                guard let val = decodeVarint(from: data, offset: &offset) else { return fields }
                fields.append(ProtobufField(tag: tag, wireType: wireType, value: .varint(val)))

            case .fixed64:
                guard offset + 8 <= data.count else { return fields }
                let sub = data.subdata(in: offset..<(offset + 8))
                offset += 8
                let val = sub.withUnsafeBytes { $0.load(as: UInt64.self) }
                fields.append(ProtobufField(tag: tag, wireType: wireType, value: .fixed64(val)))

            case .lengthDelimited:
                guard let length = decodeVarint(from: data, offset: &offset) else { return fields }
                let len = Int(length)
                guard offset + len <= data.count else { return fields }
                let slice = data.subdata(in: offset..<(offset + len))
                offset += len
                fields.append(ProtobufField(tag: tag, wireType: wireType, value: .lengthDelimited(slice)))

            case .fixed32:
                guard offset + 4 <= data.count else { return fields }
                let sub = data.subdata(in: offset..<(offset + 4))
                offset += 4
                let val = sub.withUnsafeBytes { $0.load(as: UInt32.self) }
                fields.append(ProtobufField(tag: tag, wireType: wireType, value: .fixed32(val)))
            }
        }

        return fields
    }

    /// 从 steps.metadata 中提取执行步骤时间戳
    ///
    /// 结构映射：
    /// `steps.metadata` -> Tag 1 (google.protobuf.Timestamp) -> Tag 1 (seconds: int64), Tag 2 (nanos: int32)
    /// - Parameter metadataBlob: steps 表中的 metadata 字段
    /// - Returns: UTC Date 对象，失败返回 nil
    static func decodeStepTimestamp(from metadataBlob: Data) -> Date? {
        let fields = parseFields(from: metadataBlob)
        guard let timestampData = fields.first(where: { $0.tag == 1 })?.value.asData else {
            return nil
        }
        let tsFields = parseFields(from: timestampData)
        guard let seconds = tsFields.first(where: { $0.tag == 1 })?.value.asVarint else {
            return nil
        }
        let nanos = tsFields.first(where: { $0.tag == 2 })?.value.asVarint ?? 0

        let timeInterval = Double(seconds) + (Double(nanos) / 1_000_000_000.0)
        return Date(timeIntervalSince1970: timeInterval)
    }

    /// 从 UsageMetadata 二进制 Blob 中提取用量数字
    ///
    /// 字段映射（源自 Google Vertex AI / Gemini UsageMetadata）：
    /// - Tag 2: prompt_token_count (非缓存输入 tokens)
    /// - Tag 5: cached_content_token_count (缓存命中读取 tokens)
    /// - Tag 9: thoughts_token_count (思考/思维链 reasoning tokens)
    /// - Tag 10: candidates_token_count (模型生成回复 tokens)
    /// - Tag 3: total_token_count (总输出 tokens = candidates + thoughts)
    /// - Tag 7: bot_message_id (助手消息唯一 ID)
    static func decodeUsageMetadata(from data: Data) -> AntigravityUsageMetadata {
        let fields = parseFields(from: data)
        var promptTokens = 0
        var cachedContentTokens = 0
        var thoughtsTokens = 0
        var candidatesTokens = 0
        var totalTokens = 0
        var botMessageId: String?

        for field in fields {
            switch field.tag {
            case 2:
                if let v = field.value.asVarint { promptTokens = Int(v) }
            case 5:
                if let v = field.value.asVarint { cachedContentTokens = Int(v) }
            case 9:
                if let v = field.value.asVarint { thoughtsTokens = Int(v) }
            case 10:
                if let v = field.value.asVarint { candidatesTokens = Int(v) }
            case 3:
                if let v = field.value.asVarint { totalTokens = Int(v) }
            case 7:
                botMessageId = field.value.asString
            default:
                break
            }
        }

        // 如果 totalTokens 未显式赋值，以 candidates + thoughts 兜底
        let resolvedTotal = totalTokens > 0 ? totalTokens : (candidatesTokens + thoughtsTokens)

        return AntigravityUsageMetadata(
            promptTokens: promptTokens,
            cachedContentTokens: cachedContentTokens,
            thoughtsTokens: thoughtsTokens,
            candidatesTokens: candidatesTokens,
            totalTokens: resolvedTotal,
            botMessageId: botMessageId
        )
    }

    /// 从 gen_metadata.data 二进制 Blob 中解码完整生成元数据
    /// - Parameter data: gen_metadata 表中的 data 列
    /// - Returns: 解码后的生成负载；若未找到模型或有效载荷返回 nil
    static func decodeGenerationPayload(from data: Data) -> AntigravityGenerationPayload? {
        let topFields = parseFields(from: data)
        // Tag 1 是 GenerationPayload 主消息体
        guard let sub1Data = topFields.first(where: { $0.tag == 1 })?.value.asData else {
            return nil
        }

        let sub1Fields = parseFields(from: sub1Data)

        var modelID = ""
        var modelDisplayName: String?
        var requestId: String?
        var trajectoryId: String?
        var lastStepIndex: Int64?
        var usage: AntigravityUsageMetadata?

        for field in sub1Fields {
            switch field.tag {
            case 19:
                modelID = field.value.asString ?? ""
            case 21:
                modelDisplayName = field.value.asString
            case 20:
                // Key-Value 元数据项：Tag 1=key, Tag 2=value
                if let kvData = field.value.asData {
                    let kvFields = parseFields(from: kvData)
                    let k = kvFields.first(where: { $0.tag == 1 })?.value.asString
                    let v = kvFields.first(where: { $0.tag == 2 })?.value.asString
                    if let k, let v {
                        switch k {
                        case "request_id":
                            requestId = v
                        case "trajectory_id":
                            trajectoryId = v
                        case "last_step_index":
                            lastStepIndex = Int64(v)
                        default:
                            break
                        }
                    }
                }
            case 4:
                // Tag 4 为核心 UsageMetadata
                if let uData = field.value.asData {
                    usage = decodeUsageMetadata(from: uData)
                }
            case 17:
                // 若 Tag 4 缺失，Tag 17 中的 Tag 2 可作为回退数据源
                if usage == nil, let f17Data = field.value.asData {
                    let f17Fields = parseFields(from: f17Data)
                    if let uData = f17Fields.first(where: { $0.tag == 2 })?.value.asData {
                        usage = decodeUsageMetadata(from: uData)
                    }
                }
            default:
                break
            }
        }

        guard !modelID.isEmpty || usage != nil else {
            return nil
        }

        return AntigravityGenerationPayload(
            modelID: modelID,
            modelDisplayName: modelDisplayName,
            requestId: requestId,
            trajectoryId: trajectoryId,
            lastStepIndex: lastStepIndex,
            usage: usage
        )
    }

    /// 从 trajectory_metadata_blob 的 data blob 中提取 workspace / cwd 路径
    /// 结构：
    /// Tag 1 (submessage): Tag 1 (string: file URI) 或 Tag 2 (string: file URI)
    /// 或 Tag 7 (string: file URI)
    static func decodeWorkspacePath(from data: Data) -> String? {
        let fields = parseFields(from: data)
        var rawURI: String?
        for field in fields {
            if field.tag == 1, let subData = field.value.asData {
                let subFields = parseFields(from: subData)
                for sf in subFields {
                    if (sf.tag == 1 || sf.tag == 2), let str = sf.value.asString {
                        if str.hasPrefix("file://") || str.hasPrefix("/") {
                            rawURI = str
                            break
                        }
                    }
                }
            }
            if rawURI != nil { break }
            if field.tag == 7, let str = field.value.asString {
                if str.hasPrefix("file://") || str.hasPrefix("/") {
                    rawURI = str
                    break
                }
            }
        }

        guard let uri = rawURI else { return nil }
        if uri.hasPrefix("file://") {
            if let url = URL(string: uri) {
                return url.path
            }
            let stripped = String(uri.dropFirst("file://".count))
            return stripped.removingPercentEncoding ?? stripped
        }
        return uri
    }
}
