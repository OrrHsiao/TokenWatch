import Foundation

/// DSH 会话日志首行 header（v0–v4 的字段并集）。
///
/// 必填字段随版本变化：v0 没有 `isSeeded`，因此除 `id` 外全部按可选处理，
/// 缺失时使用保守默认值，避免因格式演进整体解析失败。
struct DeepSeekHarnessSessionHeader: Decodable, Sendable {
    let type: String?
    let version: Int?
    let id: String
    let createdAtMilliseconds: Double?
    let cwd: String?
    let parentSession: String?
    let isSeeded: Bool?
    let origin: String?
    let delegationDepth: Int?

    enum CodingKeys: String, CodingKey {
        case type
        case version
        case id
        case createdAtMilliseconds = "createdAt"
        case cwd
        case parentSession
        case isSeeded
        case origin
        case delegationDepth
    }

    /// 是否为子代理会话（fork 或独立 subagent）。
    var isSubagentSession: Bool {
        origin == "subagent" || (delegationDepth ?? 0) > 0
    }
}

/// 单条会话事件；只声明用量统计需要的字段，其余（content/tools 等）由解码器跳过。
struct DeepSeekHarnessSessionEvent: Decodable, Sendable {
    let type: String
    let seq: Int?
    let timeMilliseconds: Double?
    let data: DeepSeekHarnessEventData?

    enum CodingKeys: String, CodingKey {
        case type
        case seq
        case timeMilliseconds = "time"
        case data
    }
}

/// 事件 `data` 字段中与用量相关的子集。
struct DeepSeekHarnessEventData: Decodable, Sendable {
    let turn: Int?
    let step: Int?
    /// `session/end-seed` 的 fork 继承标记。
    let inherited: Bool?
    /// `model/selection` / `compaction/summary` 的直接模型字段。
    let provider: String?
    let model: String?
    let usage: DeepSeekHarnessTokenUsage?
    let stream: [DeepSeekHarnessStreamRecord]?
    let message: DeepSeekHarnessAssistantMessage?
}

/// `assistant/message` 的 message 子结构。
struct DeepSeekHarnessAssistantMessage: Decodable, Sendable {
    let id: String?
    let source: DeepSeekHarnessMessageSource?
}

/// 消息来源（模型与上游 route）。
struct DeepSeekHarnessMessageSource: Decodable, Sendable {
    let kind: String?
    let provider: String?
    let model: String?
}

/// v3/v4 内嵌的流式记录。
struct DeepSeekHarnessStreamRecord: Decodable, Sendable {
    let type: String?
    let chunk: DeepSeekHarnessStreamChunk?
}

/// 流式 chunk；用量统计只关心 `type == "usage"` 的 chunk。
struct DeepSeekHarnessStreamChunk: Decodable, Sendable {
    let type: String?
    let usage: DeepSeekHarnessTokenUsage?
}

/// DSH wire 层的 `TokenUsage`。
///
/// 注意 `inputTokens` 是**未命中缓存的输入**（uncached input），不是 prompt 总量；
/// `reasoningTokens` 已包含在 `outputTokens` 内（当前构建也不再产出该字段）。
/// `totalTokens` 由适配器自定义（DeepSeek route 自算、pi-ai route 原样透传），口径不统一，
/// 这里只保留解码用于交叉验证，统计一律自行重算四个计费桶。
struct DeepSeekHarnessTokenUsage: Decodable, Sendable, Equatable {
    let inputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?
    let cacheReadTokens: Int?
    let cacheWriteTokens: Int?
    let reasoningTokens: Int?

    /// usage 对象是否至少提供了一个计数，用于过滤 `{}` 这类空对象。
    var hasAnyCount: Bool {
        inputTokens != nil
            || outputTokens != nil
            || totalTokens != nil
            || cacheReadTokens != nil
            || cacheWriteTokens != nil
    }
}

/// 一次计费样本的四个计费桶；`reasoningTokens` 是展示维度，不参与相等性判断。
struct DeepSeekHarnessUsageBuckets: Codable, Sendable, Equatable {
    /// 未命中缓存的输入 token。
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheWriteTokens: Int

    static let zero = DeepSeekHarnessUsageBuckets(
        inputTokens: 0,
        outputTokens: 0,
        cacheReadTokens: 0,
        cacheWriteTokens: 0
    )

    /// 是否四项全为 0（例如失败尝试的占位样本），用于避免产生空记录。
    var isZero: Bool {
        inputTokens == 0 && outputTokens == 0 && cacheReadTokens == 0 && cacheWriteTokens == 0
    }
}

/// 从单个事件中提取的用量样本。
struct DeepSeekHarnessUsageSample: Sendable, Equatable {
    let buckets: DeepSeekHarnessUsageBuckets
    /// `reasoningTokens` 之上限已由 `outputTokens` 覆盖，仅作展示。
    let reasoningTokens: Int
    let model: String?
    let route: String?
    let messageID: String?
}

enum DeepSeekHarnessUsageSampler {
    /// 载量事件类型白名单：与 DSH `usageOf()` 一致，只有这两类事件参与 token 统计。
    ///
    /// `compaction/summary` 虽然在自己的 `data.usage` 中带有用量，但 DSH 官方的
    /// `tokenUsage` 投影并不折叠它，为保证与 DSH 自身口径逐 token 对齐，这里同样不计入。
    static let accountedEventTypes: Set<String> = [
        "assistant/message",
        "assistant/attempt",
    ]

    /// 按 DSH 官方口径从事件中取样用量。
    /// - Parameter event: 单条会话事件。
    /// - Returns: 可取样的用量；非计费事件或缺少用量时返回 nil。
    static func sample(from event: DeepSeekHarnessSessionEvent) -> DeepSeekHarnessUsageSample? {
        guard accountedEventTypes.contains(event.type), let data = event.data else { return nil }

        let usage: DeepSeekHarnessTokenUsage?
        if event.type == "assistant/message", let direct = data.usage {
            usage = direct
        } else {
            // v3/v4 的 assistant/attempt 只把用量放在 stream 末尾的 usage chunk 中。
            usage = lastStreamUsage(in: data.stream)
        }
        guard let usage, usage.hasAnyCount else { return nil }

        let source = data.message?.source
        let model = source?.model ?? data.model
        let route = source?.provider ?? data.provider
        return DeepSeekHarnessUsageSample(
            buckets: DeepSeekHarnessUsageBuckets(
                inputTokens: usage.inputTokens ?? 0,
                outputTokens: usage.outputTokens ?? 0,
                cacheReadTokens: usage.cacheReadTokens ?? 0,
                cacheWriteTokens: usage.cacheWriteTokens ?? 0
            ),
            reasoningTokens: usage.reasoningTokens ?? 0,
            model: model,
            route: route,
            messageID: data.message?.id
        )
    }

    /// 取 stream 中**最后一个** `type == "usage"` 的 chunk。
    ///
    /// DSH 的口径是「优先 `data.usage`，缺失时取 stream 末尾的 usage chunk」，
    /// 绝不能累加多个 usage chunk。
    static func lastStreamUsage(
        in stream: [DeepSeekHarnessStreamRecord]?
    ) -> DeepSeekHarnessTokenUsage? {
        guard let stream else { return nil }
        for record in stream.reversed() {
            guard record.type == "chunk",
                  record.chunk?.type == "usage",
                  let usage = record.chunk?.usage else { continue }
            return usage
        }
        return nil
    }
}
