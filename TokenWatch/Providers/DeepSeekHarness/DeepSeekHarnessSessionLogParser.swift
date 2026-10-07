import Foundation
import os.log

/// 单个会话日志文件的增量解析状态。
///
/// 状态可 Codable 持久化：冷启动后可直接从 `committedByteCount` 继续解压新增帧，
/// 而不必重新解压整个日志。
struct DeepSeekHarnessSessionLogState: Codable, Sendable, Equatable {
    /// 会话 id（header `id`）。
    var sessionID: String
    var cwd: String?
    var isSubagent: Bool
    var generation: Int
    var isSeeded: Bool
    /// header 是否已解析；首行可能因分帧恰好落在批次边界而延后。
    var hasParsedHeader: Bool
    /// 构建本状态时的文件元数据，用于判断能否增量续读。
    var metadata: JSONLFileMetadata
    /// 已完整解码的压缩字节偏移。
    var committedByteCount: UInt64
    /// 已解码但尚未换行结尾的尾部明文。
    var pendingLineBytes: Data
    /// fork 继承前缀中最后一个 `session/end-seed{inherited:true}` 的下标。
    var inheritedEventCount: Int?
    /// 下一条事件的下标；仅在事件缺少 `seq` 时用于兜底编号。
    var nextEventIndex: Int
    var folder: DeepSeekHarnessUsageFolder

    /// header 缺失时的占位会话 id。
    static let unknownSessionID = "unknown-session"
}

/// DSH 会话日志解析器：增量解码 + 事件折叠 + 统一条目投影。
struct DeepSeekHarnessSessionLogParser: Sendable {
    /// 当前已确认支持的最大会话格式版本。
    static let supportedMaximumFormatVersion = 4

    private static let logger = Logger(
        subsystem: "com.xiaoao.TokenWatch",
        category: "DeepSeekHarnessParser"
    )
    /// 未知模型名的兜底展示值，与其它 provider 保持一致。
    static let unknownModelName = "unknown"

    private let decoder = JSONDecoder()

    /// 增量迁移判定。
    enum Transition: Equatable {
        /// 源未变化，可原样复用。
        case reuse
        /// 从指定压缩偏移续读。
        case append(fromByteOffset: UInt64)
        /// 重新从 0 解析。
        case rebuild
    }

    /// 判断本次是否需要重新解析整个日志。
    ///
    /// fork 型子代理（`isSeeded`）必须重建：其日志物理上包含父会话事件前缀，
    /// 而前缀边界由日志中最后一个 `inherited` 标记决定，只有从头扫描才能确定。
    static func transition(
        previous: DeepSeekHarnessSessionLogState?,
        file: DeepSeekHarnessSessionLogFile,
        metadata: JSONLFileMetadata
    ) -> Transition {
        guard let previous else { return .rebuild }
        guard previous.generation == file.generation,
              previous.hasParsedHeader,
              !previous.isSeeded,
              let previousIdentity = previous.metadata.identity,
              let newIdentity = metadata.identity,
              previousIdentity == newIdentity else {
            return .rebuild
        }
        if metadata.size == previous.metadata.size,
           metadata.modificationDate == previous.metadata.modificationDate {
            return .reuse
        }
        guard metadata.size >= previous.committedByteCount else { return .rebuild }
        return .append(fromByteOffset: previous.committedByteCount)
    }

    /// 构建（或增量更新）单个日志文件的解析状态。
    /// - Parameters:
    ///   - file: 已按世代规则选出的日志文件。
    ///   - snapshot: 同一 descriptor 的文件元数据与字节流。
    ///   - previous: 上一次解析状态；nil 表示冷启动。
    /// - Returns: 最新的折叠状态。
    func buildState(
        file: DeepSeekHarnessSessionLogFile,
        snapshot: JSONLFileSnapshot,
        previous: DeepSeekHarnessSessionLogState?
    ) throws -> DeepSeekHarnessSessionLogState {
        let transition = Self.transition(
            previous: previous,
            file: file,
            metadata: snapshot.metadata
        )
        let startOffset: UInt64
        var state: DeepSeekHarnessSessionLogState
        switch transition {
        case .reuse:
            return previous ?? Self.makeEmptyState(file: file, metadata: snapshot.metadata)
        case .append(let offset):
            startOffset = offset
            state = previous ?? Self.makeEmptyState(file: file, metadata: snapshot.metadata)
            state.metadata = snapshot.metadata
        case .rebuild:
            startOffset = 0
            state = Self.makeEmptyState(file: file, metadata: snapshot.metadata)
        }

        let encoding = file.isCompressed ? DeepSeekHarnessLogEncoding.zstd : .plaintext
        let chunk = try DeepSeekHarnessSessionLogDecoder.decode(
            stream: snapshot.stream,
            fromOffset: startOffset,
            encoding: encoding,
            pendingLineBytes: startOffset == 0 ? Data() : state.pendingLineBytes
        )

        var nextEventIndex = state.nextEventIndex
        var eventLines = chunk.lines[...]
        if !state.hasParsedHeader {
            // 首行必须是 session header；解析失败说明选中了非 DSH 日志，放弃本轮剩余行。
            guard let headerLine = eventLines.first,
                  Self.parseHeader(headerLine, into: &state, decoder: decoder) else {
                state.pendingLineBytes = chunk.pendingLineBytes
                state.committedByteCount = startOffset + chunk.consumedByteCount
                state.nextEventIndex = nextEventIndex
                return state
            }
            state.hasParsedHeader = true
            eventLines = eventLines.dropFirst()
        }

        for line in eventLines {
            guard let event = try? decoder.decode(DeepSeekHarnessSessionEvent.self, from: line) else {
                // 前向兼容：未知或损坏的单个事件必须跳过，不能中断整个会话的统计。
                Self.logger.debug(
                    "跳过无法解析的 DSH 事件行（\(file.url.lastPathComponent, privacy: .public)）"
                )
                continue
            }
            let eventIndex = event.seq ?? nextEventIndex
            nextEventIndex = eventIndex + 1
            Self.apply(event: event, index: eventIndex, state: &state)
        }

        state.pendingLineBytes = chunk.pendingLineBytes
        state.committedByteCount = startOffset + chunk.consumedByteCount
        state.nextEventIndex = nextEventIndex
        return state
    }

    /// 把折叠状态投影为统一用量条目。
    /// - Parameter state: 单个日志文件的解析状态。
    /// - Returns: 去重后的 `ParsedUsageEntry`（顺序按时间戳稳定排序）。
    func project(_ state: DeepSeekHarnessSessionLogState) -> [ParsedUsageEntry] {
        guard state.hasParsedHeader else { return [] }
        let sessionID = state.sessionID
        return state.folder.records.map { record in
            let synthesizedID = "\(sessionID):\(record.recordKey)"
            return ParsedUsageEntry(
                recordUUID: record.recordKey,
                messageId: record.messageID ?? synthesizedID,
                requestId: nil,
                sessionID: sessionID,
                timestamp: Date(timeIntervalSince1970: record.timestampMilliseconds / 1000),
                model: record.model ?? Self.unknownModelName,
                upstreamModelID: record.model,
                cwd: state.cwd,
                agentId: nil,
                usage: Self.makeTokenUsage(record),
                isSubagent: state.isSubagent,
                isSidechain: false,
                hasSourceMessageID: record.messageID != nil,
                provider: .deepSeekHarness,
                upstreamProviderID: record.route,
                upstreamCost: nil
            )
        }
    }

    // MARK: - 事件处理

    /// 解析首行 header。
    /// - Returns: 是否解析成功。
    private static func parseHeader(
        _ line: Data,
        into state: inout DeepSeekHarnessSessionLogState,
        decoder: JSONDecoder
    ) -> Bool {
        guard let header = try? decoder.decode(DeepSeekHarnessSessionHeader.self, from: line) else {
            logger.error("DSH 会话日志首行无法解析为 header，跳过该文件")
            return false
        }
        state.sessionID = header.id
        state.cwd = header.cwd
        state.isSubagent = header.isSubagentSession
        state.isSeeded = header.isSeeded ?? false
        if let version = header.version, version > supportedMaximumFormatVersion {
            // 新版本可能引入未知事件；按已知契约尽力解析并记录警告，而不是丢弃整个会话。
            logger.warning(
                "DSH 会话格式版本 \(version) 高于已知的 \(supportedMaximumFormatVersion)，按已知契约尽力解析"
            )
        }
        return true
    }

    /// 应用单条事件到折叠状态。
    private static func apply(
        event: DeepSeekHarnessSessionEvent,
        index: Int,
        state: inout DeepSeekHarnessSessionLogState
    ) {
        if event.type == "llm/retry-started" {
            state.folder.noteRetryStarted(
                turn: event.data?.turn,
                step: event.data?.step
            )
            return
        }

        // fork 继承前缀：每遇到一个 inherited 标记就丢弃此前累计的用量，
        // 使最终结果等价于「只统计最后一个标记之后的事件」（与 DSH 校验器
        // `lastInheritedMarker === inheritedEventCount` 的口径一致）。
        if event.type == "session/end-seed", event.data?.inherited == true {
            state.folder = DeepSeekHarnessUsageFolder()
            state.inheritedEventCount = index
            return
        }

        if let provider = event.data?.provider, let model = event.data?.model {
            state.folder.noteSource(provider: provider, model: model)
        }
        if DeepSeekHarnessUsageSampler.accountedEventTypes.contains(event.type) {
            state.folder.fold(event)
        }
    }

    private static func makeEmptyState(
        file: DeepSeekHarnessSessionLogFile,
        metadata: JSONLFileMetadata
    ) -> DeepSeekHarnessSessionLogState {
        DeepSeekHarnessSessionLogState(
            sessionID: DeepSeekHarnessSessionLogState.unknownSessionID,
            cwd: nil,
            isSubagent: false,
            generation: file.generation,
            isSeeded: false,
            hasParsedHeader: false,
            metadata: metadata,
            committedByteCount: 0,
            pendingLineBytes: Data(),
            inheritedEventCount: nil,
            nextEventIndex: 0,
            folder: DeepSeekHarnessUsageFolder()
        )
    }

    /// 把折叠记录转换为统一的 `TokenUsage`。
    ///
    /// `cacheWriteTokens` 走扁平 5m 桶（`cacheCreation = nil`）；`reasoningTokens`
    /// 只作展示，已包含在 output 内，不参与总量计算。
    private static func makeTokenUsage(_ record: DeepSeekHarnessUsageRecord) -> TokenUsage {
        TokenUsage(
            inputTokens: record.buckets.inputTokens,
            cacheCreationInputTokens: record.buckets.cacheWriteTokens,
            cacheReadInputTokens: record.buckets.cacheReadTokens,
            outputTokens: record.buckets.outputTokens,
            reasoningTokens: record.reasoningTokens,
            serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
            serviceTier: "",
            cacheCreation: nil,
            inferenceGeo: "",
            iterations: [],
            speed: ""
        )
    }
}
