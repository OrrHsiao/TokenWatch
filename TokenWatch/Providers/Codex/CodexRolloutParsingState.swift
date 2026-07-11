import Foundation

/// 可跨 JSONL 批次保存并恢复的 Codex 行级解析状态。
struct CodexParserCheckpoint: Sendable {
    var currentModel: CodexModelState?
    var sessionID: String
    var cwd: String?
    var previousTotals: CodexTokenCounts?
    var replaySecond: String?
    var isSkippingReplay: Bool

    /// 创建文件起点 checkpoint，并按 replay 预检结果初始化跳过状态。
    static func initial(
        sessionID: String,
        replaySecond: String?
    ) -> CodexParserCheckpoint {
        CodexParserCheckpoint(
            currentModel: nil,
            sessionID: sessionID,
            cwd: nil,
            previousTotals: nil,
            replaySecond: replaySecond,
            isSkippingReplay: replaySecond != nil
        )
    }

    /// 消费单条 rollout record，更新 checkpoint 并在有效 token_count 时返回候选。
    /// - Parameters:
    ///   - record: 已解码的 Codex rollout 行。
    ///   - sourceOffset: 该行在源文件中的绝对起始 byte offset。
    ///   - pricingSpeed: 映射到 Codex usage service tier 的计价速度。
    /// - Returns: 可计费用量候选；元数据、无效或零用量行返回 nil。
    mutating func consume(
        _ record: CodexRecord,
        sourceOffset: UInt64,
        pricingSpeed: CodexPricingSpeed
    ) -> CodexUsageCandidate? {
        switch record.payload {
        case .sessionMeta(let meta):
            sessionID = meta.id
            cwd = meta.cwd
            return nil

        case .turnContext(let context):
            if let model = context.preferredModel {
                _ = CodexModelResolver.resolve(
                    parsedModel: model,
                    eventDate: record.normalizedTimestamp?.date,
                    current: &currentModel
                )
            }
            return nil

        case .eventMsg(let event):
            guard event.type == "token_count",
                  let timestamp = record.normalizedTimestamp else {
                return nil
            }

            if isSkippingReplay, let replaySecond {
                if timestamp.key.prefix(19) == replaySecond {
                    if let total = event.info?.totalTokenUsage {
                        previousTotals = total
                    }
                    return nil
                }
                isSkippingReplay = false
            }

            guard let info = event.info else { return nil }
            let delta = info.lastTokenUsage
                ?? info.totalTokenUsage.map { $0.subtracting(previousTotals ?? .zero) }
            if let total = info.totalTokenUsage {
                previousTotals = total
            }
            guard let delta, !delta.isAllZero else { return nil }

            let model = CodexModelResolver.resolve(
                parsedModel: event.preferredModel ?? info.preferredModel,
                eventDate: timestamp.date,
                current: &currentModel
            )
            return CodexUsageCandidate.make(
                sessionID: sessionID,
                timestamp: timestamp,
                sourceOffset: sourceOffset,
                model: model,
                cwd: cwd,
                counts: delta,
                pricingSpeed: pricingSpeed
            )

        case .unknown:
            return nil
        }
    }
}

extension CodexUsageCandidate {
    /// 将 Codex 原始计数归一化为 billing entry 与跨文件去重键。
    static func make(
        sessionID: String,
        timestamp: CodexNormalizedTimestamp,
        sourceOffset: UInt64,
        model: String,
        cwd: String?,
        counts: CodexTokenCounts,
        pricingSpeed: CodexPricingSpeed
    ) -> CodexUsageCandidate {
        let normalized = counts.normalizedForBilling
        let messageID = "\(sessionID):\(timestamp.key)"
        let recordUUID = "\(messageID):\(sourceOffset)"
        let usage = TokenUsage(
            inputTokens: normalized.pureInput,
            cacheCreationInputTokens: 0,
            cacheReadInputTokens: normalized.cachedInput,
            outputTokens: normalized.output,
            reasoningTokens: normalized.reasoning,
            serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
            serviceTier: pricingSpeed == .fast ? "fast" : "",
            cacheCreation: nil,
            inferenceGeo: "",
            iterations: [],
            speed: ""
        )
        let entry = ParsedUsageEntry(
            recordUUID: recordUUID,
            messageId: messageID,
            requestId: nil,
            sessionID: sessionID,
            timestamp: timestamp.date,
            model: model,
            cwd: cwd,
            agentId: nil,
            usage: usage,
            isSubagent: false,
            isSidechain: false,
            provider: .codex,
            upstreamProviderID: nil,
            upstreamCost: nil
        )
        return CodexUsageCandidate(
            entry: entry,
            dedupKey: CodexEventDedupKey(
                timestampKey: timestamp.key,
                model: model,
                rawInput: normalized.rawInput,
                cachedInput: normalized.cachedInput,
                output: normalized.output,
                reasoning: normalized.reasoning,
                total: normalized.total
            )
        )
    }
}
