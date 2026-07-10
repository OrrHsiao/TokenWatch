import Foundation

/// 供 Codex event identity 与展示共用的规范化时间。
struct CodexNormalizedTimestamp: Sendable, Equatable {
    let key: String
    let date: Date

    /// 按 ccusage 的 RFC3339 规则规范字符串时间。
    static func parse(_ text: String) -> CodexNormalizedTimestamp? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let date = ISO8601DateFormatterHelper.parse(trimmed) else {
            return nil
        }
        return make(date: date)
    }

    /// 按 pinned ccusage 的数字分界规范 Unix 秒或 Unix 毫秒，并夹到 Int64 毫秒范围。
    static func parse(_ raw: UInt64) -> CodexNormalizedTimestamp? {
        let milliseconds: UInt64
        if raw > 10_000_000_000 {
            milliseconds = raw
        } else {
            let product = raw.multipliedReportingOverflow(by: 1_000)
            milliseconds = product.overflow ? .max : product.partialValue
        }
        let clamped = min(milliseconds, UInt64(Int64.max))
        return make(date: Date(timeIntervalSince1970: Double(clamped) / 1_000))
    }

    private static func make(date: Date) -> CodexNormalizedTimestamp? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let key = formatter.string(from: date)
        guard !key.isEmpty else { return nil }
        return CodexNormalizedTimestamp(key: key, date: date)
    }
}

private struct CodexTimestampValue: Decodable {
    let normalized: CodexNormalizedTimestamp?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            normalized = nil
        } else if let text = try? container.decode(String.self) {
            normalized = CodexNormalizedTimestamp.parse(text)
        } else if let raw = try? container.decode(UInt64.self) {
            normalized = CodexNormalizedTimestamp.parse(raw)
        } else {
            normalized = nil
        }
    }
}

/// Codex JSONL(`~/.codex/sessions/.../rollout-*.jsonl`)中每一行的顶层结构
/// 仅解析 token 统计需要的 type:session_meta / turn_context / event_msg
/// 其余 type(response_item / function_call / 等)归为 .unknown 并跳过
struct CodexRecord: Decodable, Sendable {
    let normalizedTimestamp: CodexNormalizedTimestamp?
    let type: String
    let payload: CodexPayload

    var timestamp: Date? { normalizedTimestamp?.date }

    enum CodingKeys: String, CodingKey {
        case timestamp, type, payload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)

        normalizedTimestamp = (try? container.decode(
            CodexTimestampValue.self,
            forKey: .timestamp
        ))?.normalized

        // payload 形态由 type 决定 — 解码失败的子结构降级为 .unknown,
        // 保持单行损坏不阻断后续行(参考 Claude JSONL 的容错风格)
        switch type {
        case "session_meta":
            if let meta = try? container.decode(CodexSessionMeta.self, forKey: .payload) {
                payload = .sessionMeta(meta)
            } else {
                payload = .unknown
            }
        case "turn_context":
            if let ctx = try? container.decode(CodexTurnContext.self, forKey: .payload) {
                payload = .turnContext(ctx)
            } else {
                payload = .unknown
            }
        case "event_msg":
            if let evt = try? container.decode(CodexEventMsg.self, forKey: .payload) {
                payload = .eventMsg(evt)
            } else {
                payload = .unknown
            }
        default:
            payload = .unknown
        }
    }
}

/// 按 type 分发后的 payload
enum CodexPayload: Sendable {
    case sessionMeta(CodexSessionMeta)
    case turnContext(CodexTurnContext)
    case eventMsg(CodexEventMsg)
    case unknown
}

/// session_meta.payload — 整个 rollout 文件首行,提供 sessionId / cwd
struct CodexSessionMeta: Decodable, Sendable {
    let id: String
    let cwd: String?
    let modelProvider: String?

    enum CodingKeys: String, CodingKey {
        case id, cwd
        case modelProvider = "model_provider"
    }
}

/// turn_context.payload — 每轮对话开始,标明此后 token_count 归属的 model
struct CodexTurnContext: Decodable, Sendable {
    let model: String?
    let modelName: String?
    let metadata: CodexModelMetadata?

    enum CodingKeys: String, CodingKey {
        case model
        case modelName = "model_name"
        case metadata
    }

    var preferredModel: String? {
        codexPreferredModel(model: model, modelName: modelName, metadata: metadata)
    }
}

/// event_msg.payload — 包一层 type 才到我们关心的 token_count
struct CodexEventMsg: Decodable, Sendable {
    let type: String                 // 只关心 "token_count"
    let info: CodexTokenCountInfo?
    let model: String?
    let modelName: String?
    let metadata: CodexModelMetadata?

    enum CodingKeys: String, CodingKey {
        case type, info, model, metadata
        case modelName = "model_name"
    }

    var preferredModel: String? {
        codexPreferredModel(model: model, modelName: modelName, metadata: metadata)
    }
}

/// token_count.info — 心跳事件该字段为 null
struct CodexTokenCountInfo: Decodable, Sendable {
    let lastTokenUsage: CodexTokenCounts?
    let totalTokenUsage: CodexTokenCounts?
    let model: String?
    let modelName: String?
    let metadata: CodexModelMetadata?

    enum CodingKeys: String, CodingKey {
        case lastTokenUsage = "last_token_usage"
        case totalTokenUsage = "total_token_usage"
        case model, metadata
        case modelName = "model_name"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastTokenUsage = try? container.decode(CodexTokenCounts.self, forKey: .lastTokenUsage)
        totalTokenUsage = try? container.decode(CodexTokenCounts.self, forKey: .totalTokenUsage)
        model = try? container.decode(String.self, forKey: .model)
        modelName = try? container.decode(String.self, forKey: .modelName)
        metadata = try? container.decode(CodexModelMetadata.self, forKey: .metadata)
    }

    var preferredModel: String? {
        codexPreferredModel(model: model, modelName: modelName, metadata: metadata)
    }
}

struct CodexModelMetadata: Decodable, Sendable {
    let model: String?
}

private func codexPreferredModel(
    model: String?,
    modelName: String?,
    metadata: CodexModelMetadata?
) -> String? {
    [model, modelName, metadata?.model]
        .compactMap { value in
            value.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        .first { !$0.isEmpty }
}

/// 单次 token 计数四元组(+ total)
struct CodexTokenCounts: Decodable, Sendable, Equatable {
    let inputTokens: Int           // 注意:Codex 的 input 已包含 cached_input,计费时需扣减
    let cachedInputTokens: Int
    let outputTokens: Int          // 注意:已包含 reasoning_output_tokens,reasoning 不另行计费
    let reasoningOutputTokens: Int
    let totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case promptTokens = "prompt_tokens"
        case input
        case cachedInputTokens = "cached_input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case cachedTokens = "cached_tokens"
        case outputTokens = "output_tokens"
        case completionTokens = "completion_tokens"
        case output
        case reasoningOutputTokens = "reasoning_output_tokens"
        case reasoningTokens = "reasoning_tokens"
        case totalTokens = "total_tokens"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        inputTokens = Self.firstLossyUnsigned(
            in: c,
            keys: [.inputTokens, .promptTokens, .input]
        ) ?? 0
        cachedInputTokens = Self.firstLossyUnsigned(
            in: c,
            keys: [.cachedInputTokens, .cacheReadInputTokens, .cachedTokens]
        ) ?? 0
        outputTokens = Self.firstLossyUnsigned(
            in: c,
            keys: [.outputTokens, .completionTokens, .output]
        ) ?? 0
        reasoningOutputTokens = Self.firstLossyUnsigned(
            in: c,
            keys: [.reasoningOutputTokens, .reasoningTokens]
        ) ?? 0

        let fallbackTotal = Self.saturatingAdd(
            Self.saturatingAdd(inputTokens, outputTokens),
            reasoningOutputTokens
        )
        let decodedTotal = Self.firstLossyUnsigned(in: c, keys: [.totalTokens])
        if let decodedTotal, decodedTotal > 0 || fallbackTotal == 0 {
            totalTokens = decodedTotal
        } else {
            totalTokens = fallbackTotal
        }
    }

    init(inputTokens: Int, cachedInputTokens: Int, outputTokens: Int,
         reasoningOutputTokens: Int, totalTokens: Int) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.totalTokens = totalTokens
    }

    static let zero = CodexTokenCounts(
        inputTokens: 0, cachedInputTokens: 0,
        outputTokens: 0, reasoningOutputTokens: 0, totalTokens: 0
    )

    var isAllZero: Bool {
        inputTokens == 0 && cachedInputTokens == 0
            && outputTokens == 0 && reasoningOutputTokens == 0
    }

    /// 对累计 usage 做逐字段饱和相减，得到本条 delta。
    func subtracting(_ previous: CodexTokenCounts) -> CodexTokenCounts {
        CodexTokenCounts(
            inputTokens: Self.saturatingSubtract(inputTokens, previous.inputTokens),
            cachedInputTokens: Self.saturatingSubtract(cachedInputTokens, previous.cachedInputTokens),
            outputTokens: Self.saturatingSubtract(outputTokens, previous.outputTokens),
            reasoningOutputTokens: Self.saturatingSubtract(
                reasoningOutputTokens,
                previous.reasoningOutputTokens
            ),
            totalTokens: Self.saturatingSubtract(totalTokens, previous.totalTokens)
        )
    }

    var normalizedForBilling: CodexNormalizedTokenCounts {
        let rawInput = max(0, inputTokens)
        let cachedInput = min(max(0, cachedInputTokens), rawInput)
        return CodexNormalizedTokenCounts(
            rawInput: rawInput,
            pureInput: rawInput - cachedInput,
            cachedInput: cachedInput,
            output: max(0, outputTokens),
            reasoning: max(0, reasoningOutputTokens),
            total: max(0, totalTokens)
        )
    }

    private static func firstLossyUnsigned(
        in container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) -> Int? {
        for key in keys {
            if let value = try? container.decode(UInt64.self, forKey: key) {
                return value > UInt64(Int.max) ? .max : Int(value)
            }
            if let text = try? container.decode(String.self, forKey: key),
               let value = UInt64(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return value > UInt64(Int.max) ? .max : Int(value)
            }
        }
        return nil
    }

    private static func saturatingAdd(_ lhs: Int, _ rhs: Int) -> Int {
        let result = lhs.addingReportingOverflow(rhs)
        return result.overflow ? .max : result.partialValue
    }

    private static func saturatingSubtract(_ lhs: Int, _ rhs: Int) -> Int {
        lhs >= rhs ? lhs - rhs : 0
    }
}

struct CodexNormalizedTokenCounts: Sendable, Equatable {
    let rawInput: Int
    let pureInput: Int
    let cachedInput: Int
    let output: Int
    let reasoning: Int
    let total: Int
}
