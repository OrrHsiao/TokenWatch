import Foundation
@testable import TokenWatch

/// 测试专用的完整业务快照，避免 production 的 dedupKey 相等语义掩盖字段差异。
struct ParsedUsageEntryDeepSnapshot: Equatable {
    let recordUUID: String
    let messageId: String
    let requestId: String?
    let sessionID: String
    let timestamp: Date?
    let model: String
    let cwd: String?
    let agentId: String?
    let inputTokens: Int
    let flatCacheCreationTokens: Int
    let cacheReadTokens: Int
    let outputTokens: Int
    let reasoningTokens: Int
    let cacheCreation1hTokens: Int?
    let cacheCreation5mTokens: Int?
    let webSearchRequests: Int
    let webFetchRequests: Int
    let serviceTier: String
    let inferenceGeo: String
    let iterations: [String]
    let speed: String
    let isSubagent: Bool
    let isSidechain: Bool
    let hasSourceMessageID: Bool
    let provider: ProviderID
    let upstreamProviderID: String?
    let upstreamCost: Double?

    init(_ entry: ParsedUsageEntry) {
        recordUUID = entry.recordUUID
        messageId = entry.messageId
        requestId = entry.requestId
        sessionID = entry.sessionID
        timestamp = entry.timestamp
        model = entry.model
        cwd = entry.cwd
        agentId = entry.agentId
        inputTokens = entry.usage.inputTokens
        flatCacheCreationTokens = entry.usage.cacheCreationInputTokens
        cacheReadTokens = entry.usage.cacheReadInputTokens
        outputTokens = entry.usage.outputTokens
        reasoningTokens = entry.usage.reasoningTokens
        cacheCreation1hTokens = entry.usage.cacheCreation?.ephemeral1hInputTokens
        cacheCreation5mTokens = entry.usage.cacheCreation?.ephemeral5mInputTokens
        webSearchRequests = entry.usage.serverToolUse.webSearchRequests
        webFetchRequests = entry.usage.serverToolUse.webFetchRequests
        serviceTier = entry.usage.serviceTier
        inferenceGeo = entry.usage.inferenceGeo
        iterations = entry.usage.iterations
        speed = entry.usage.speed
        isSubagent = entry.isSubagent
        isSidechain = entry.isSidechain
        hasSourceMessageID = entry.hasSourceMessageID
        provider = entry.provider
        upstreamProviderID = entry.upstreamProviderID
        upstreamCost = entry.upstreamCost
    }

    static func sorted(_ entries: [ParsedUsageEntry]) -> [ParsedUsageEntryDeepSnapshot] {
        entries.map(ParsedUsageEntryDeepSnapshot.init).sorted { lhs, rhs in
            lhs.stableKey < rhs.stableKey
        }
    }

    private var stableKey: String {
        [
            provider.rawValue,
            sessionID,
            messageId,
            requestId ?? "",
            recordUUID,
        ].joined(separator: "|")
    }
}
