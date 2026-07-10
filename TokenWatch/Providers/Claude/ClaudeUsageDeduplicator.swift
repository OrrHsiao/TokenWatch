import Foundation

/// 复刻 ccusage v20.0.16 daily.rs 的 exact-first / sidechain-fallback 单遍索引。
enum ClaudeUsageDeduplicator {
    private struct ExactKey: Hashable {
        let messageID: String
        let requestID: String?
    }

    /// 按输入顺序单遍选择 Claude daily winners；缺 source ID 的记录完全绕过索引。
    /// - Parameters:
    ///   - candidates: scanner 顺序收集、尚未全局去重的候选记录。
    ///   - costResolver: magnitude 平局时使用的默认 Auto 成本解析器。
    /// - Returns: 保持首次 winner 位置的去重结果。
    static func deduplicate(
        _ candidates: [ParsedUsageEntry],
        costResolver: UsageCostResolver = UsageCostResolver()
    ) -> [ParsedUsageEntry] {
        var winners: [ParsedUsageEntry] = []
        var exactIndexes: [ExactKey: [Int]] = [:]
        var messageIndexes: [String: [Int]] = [:]

        for candidate in candidates {
            guard candidate.hasSourceMessageID else {
                winners.append(candidate)
                continue
            }

            let exactKey = ExactKey(
                messageID: candidate.messageId,
                requestID: candidate.requestId
            )
            let exactIndex = exactIndexes[exactKey]?.first { index in
                winners[index].messageId == candidate.messageId
                    && winners[index].requestId == candidate.requestId
            }
            let replayIndex = exactIndex == nil
                ? messageIndexes[candidate.messageId]?.first { index in
                    let existing = winners[index]
                    return existing.messageId == candidate.messageId
                        && (candidate.isSidechain || existing.isSidechain)
                }
                : nil

            if let index = exactIndex ?? replayIndex {
                if shouldReplace(
                    winners[index],
                    with: candidate,
                    costResolver: costResolver
                ) {
                    winners[index] = candidate
                }
                // pinned daily.rs 在 replacement 分支不会为 replacement 的新 key 回填索引。
                continue
            }

            let index = winners.count
            winners.append(candidate)
            exactIndexes[exactKey, default: []].append(index)
            messageIndexes[candidate.messageId, default: []].append(index)
        }
        return winners
    }

    private static func shouldReplace(
        _ existing: ParsedUsageEntry,
        with candidate: ParsedUsageEntry,
        costResolver: UsageCostResolver
    ) -> Bool {
        if existing.isSidechain != candidate.isSidechain {
            return existing.isSidechain && !candidate.isSidechain
        }

        let existingMagnitude = magnitude(existing.usage)
        let candidateMagnitude = magnitude(candidate.usage)
        if existingMagnitude != candidateMagnitude {
            return candidateMagnitude > existingMagnitude
        }

        let existingCost = costResolver.resolvedCost(for: existing)
        let candidateCost = costResolver.resolvedCost(for: candidate)
        if existingCost != candidateCost {
            return candidateCost > existingCost
        }

        return existing.usage.speed.isEmpty && !candidate.usage.speed.isEmpty
    }

    private static func magnitude(_ usage: TokenUsage) -> Int {
        let cacheCreationTokens: Int
        if let cacheCreation = usage.cacheCreation {
            cacheCreationTokens = saturatingAdd(
                cacheCreation.ephemeral5mInputTokens,
                cacheCreation.ephemeral1hInputTokens
            )
        } else {
            cacheCreationTokens = usage.cacheCreationInputTokens
        }

        return [
            usage.inputTokens,
            usage.outputTokens,
            usage.cacheReadInputTokens,
            cacheCreationTokens,
        ].reduce(0, saturatingAdd)
    }

    private static func saturatingAdd(_ lhs: Int, _ rhs: Int) -> Int {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        guard overflow else { return sum }
        return rhs >= 0 ? .max : .min
    }
}
