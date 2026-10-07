import Foundation

/// 折叠后保留的单次计费记录。
///
/// 与 `ParsedUsageEntry` 相比，这里只保留日志本身能提供的字段；provider、
/// 会话上下文等派生信息在投影阶段补齐，便于磁盘缓存跨版本复用。
struct DeepSeekHarnessUsageRecord: Codable, Sendable, Equatable {
    /// 槽位键：`<turn>:<step>:<attemptIndex>`；无 turn/step 的事件使用 `seq:` 前缀。
    let recordKey: String
    /// 源日志中的 `message.id`；`assistant/attempt` 等事件没有该字段。
    let messageID: String?
    let turn: Int?
    let step: Int?
    let attemptIndex: Int
    let timestampMilliseconds: Double
    let model: String?
    let route: String?
    let buckets: DeepSeekHarnessUsageBuckets
    let reasoningTokens: Int
}

/// DSH 官方 `tokenUsage` 投影的等价折叠状态。
///
/// 语义与 DSH `dsh-token-meter/lib/types/usage-projection.js` 的
/// `tokenUsageProjectionDefinition.apply` 一一对应：
/// - 只有 `assistant/message` 与 `assistant/attempt` 参与统计；
/// - 同一 `(turn, step)` 内后到的样本**替换**先到的；
/// - `llm/retry-started` 关闭当前槽位，使重试产生的新样本改为**累加**；
/// - 完全相同的重复样本按幂等去重。
///
/// 差异：DSH 只维护总量，这里额外保留逐条记录并引入 `attemptIndex`，
/// 使被替换/重试的尝试各自可追踪（总量口径不变）。
struct DeepSeekHarnessUsageFolder: Codable, Sendable, Equatable {
    /// 上一次样本占用的槽位；决定下一个同槽位样本是替换还是新增。
    private struct Slot: Codable, Sendable, Equatable {
        let turn: Int?
        let step: Int?
        let recordKey: String
        let buckets: DeepSeekHarnessUsageBuckets

        /// 与给定样本是否属于同一替换槽位（turn/step 均相等，含都为 nil 的情况）。
        func matches(turn: Int?, step: Int?) -> Bool {
            self.turn == turn && self.step == step
        }
    }

    private var lastSlot: Slot?
    /// 每个 `(turn, step)` 已发生的重试次数，用于派生 attemptIndex。
    private var retryCounts: [String: Int] = [:]
    private var recordsByKey: [String: DeepSeekHarnessUsageRecord] = [:]
    /// 会话内最近一次已知的模型与上游 route，用于归属不含 source 的事件。
    private var lastKnownModel: String?
    private var lastKnownRoute: String?

    /// 当前生效的逐条记录，按时间戳稳定排序。
    var records: [DeepSeekHarnessUsageRecord] {
        recordsByKey.values.sorted {
            if $0.timestampMilliseconds != $1.timestampMilliseconds {
                return $0.timestampMilliseconds < $1.timestampMilliseconds
            }
            return $0.recordKey < $1.recordKey
        }
    }

    var recordCount: Int { recordsByKey.count }

    /// 记录事件中出现的模型/route，供后续无 source 的事件归属。
    mutating func noteSource(provider: String?, model: String?) {
        if let model, !model.isEmpty { lastKnownModel = model }
        if let provider, !provider.isEmpty { lastKnownRoute = provider }
    }

    /// 处理 `llm/retry-started`：关闭匹配的替换槽位，并推进该槽位的尝试序号。
    /// - Parameters:
    ///   - turn: 重试所属 turn。
    ///   - step: 重试所属 step。
    mutating func noteRetryStarted(turn: Int?, step: Int?) {
        guard let turn, let step else { return }
        let key = Self.slotKey(turn: turn, step: step)
        retryCounts[key, default: 0] += 1
        if let lastSlot, lastSlot.matches(turn: turn, step: step) {
            // 关闭替换槽位：重试后的新样本将作为一次额外计费尝试累加。
            self.lastSlot = nil
        }
    }

    /// 折叠一条事件的用量样本。
    /// - Parameter event: 已确认携带用量的会话事件。
    mutating func fold(_ event: DeepSeekHarnessSessionEvent) {
        guard let sample = DeepSeekHarnessUsageSampler.sample(from: event) else { return }

        let data = event.data
        noteSource(provider: sample.route, model: sample.model)
        let turn = data?.turn
        let step = data?.step
        let attemptIndex = attemptIndex(for: turn, step: step)
        let recordKey = Self.recordKey(
            turn: turn,
            step: step,
            attemptIndex: attemptIndex,
            sequence: event.seq,
            timestampMilliseconds: event.timeMilliseconds
        )

        if let lastSlot, lastSlot.matches(turn: turn, step: step) {
            if lastSlot.buckets == sample.buckets {
                // 幂等去重：完全相同的重复样本不重复计数。
                return
            }
            // 同槽位替换：总量减去旧样本，逐条记录同步移除。
            recordsByKey.removeValue(forKey: lastSlot.recordKey)
        }

        let timestampMilliseconds = event.timeMilliseconds ?? 0
        // 全 0 样本（失败尝试）不产生记录，但同样占用槽位，保证后续替换语义一致。
        if !sample.buckets.isZero {
            recordsByKey[recordKey] = DeepSeekHarnessUsageRecord(
                recordKey: recordKey,
                messageID: sample.messageID,
                turn: turn,
                step: step,
                attemptIndex: attemptIndex,
                timestampMilliseconds: timestampMilliseconds,
                model: sample.model ?? lastKnownModel,
                route: sample.route ?? lastKnownRoute,
                buckets: sample.buckets,
                reasoningTokens: sample.reasoningTokens
            )
        }
        lastSlot = Slot(
            turn: turn,
            step: step,
            recordKey: recordKey,
            buckets: sample.buckets
        )
    }

    /// 当前 `(turn, step)` 的尝试序号；无 turn/step 时返回 0。
    private func attemptIndex(for turn: Int?, step: Int?) -> Int {
        guard let turn, let step else { return 0 }
        return retryCounts[Self.slotKey(turn: turn, step: step)] ?? 0
    }

    private static func slotKey(turn: Int, step: Int) -> String {
        "\(turn):\(step)"
    }

    private static func recordKey(
        turn: Int?,
        step: Int?,
        attemptIndex: Int,
        sequence: Int?,
        timestampMilliseconds: Double?
    ) -> String {
        if let turn, let step {
            return "\(turn):\(step):\(attemptIndex)"
        }
        // 无 turn/step 的事件（当前版本不存在）彼此独立，用 seq 保证唯一性。
        let sequencePart = sequence.map(String.init) ?? "t\(timestampMilliseconds ?? 0)"
        return "seq:\(sequencePart)"
    }
}
