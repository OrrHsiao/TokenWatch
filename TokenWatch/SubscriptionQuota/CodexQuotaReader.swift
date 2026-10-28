import Foundation
import os.log

/// Codex rollout 中一次可用的额度事件。
struct CodexQuotaEvent: Equatable, Sendable {
    /// 事件 `timestamp`：观察到快照的时刻，不保证每个事件都重新获取了服务端额度。
    let recordedAt: Date
    let bucketID: String
    let windows: [SubscriptionQuotaWindowKind: SubscriptionQuotaWindow]
}

/// 从 Codex rollout JSONL 的 `token_count.rate_limits` 读取最新额度快照。
///
/// 额度读取与 token 统计完全独立：不经过 `CodexParserCheckpoint` 的用量去重与增量缓存，
/// 因此 `info == nil` 的纯额度事件同样可以更新额度，额度事件也永远不会计入 token 消费；
/// 原 token 统计缓存无需升级版本。
///
/// 账号策略：rollout 只在 `session_meta.creator_account_id` 记录会话创建者账号，
/// 无法得知当前登录账号（首版不读取 `auth.json`）。因此只展示按事件时间最新的一条事件，
/// 两个窗口都取自同一事件，不跨事件、跨账号或跨额度桶拼接；缺少账号字段的旧日志按
/// “未知账号”处理，仅在它本身就是最新事件时展示。
final class CodexQuotaReader: @unchecked Sendable {
    /// Codex 主额度桶；旧日志缺少 `limit_id` 时只有这一个桶。
    static let defaultBucketID = "codex"
    static let fiveHourWindowMinutes = 300
    static let sevenDayWindowMinutes = 10_080

    struct Configuration: Sendable {
        /// 每次向前读取的字节数。
        var tailChunkSize = 64 * 1024
        /// 单个文件最多向前读取的字节数；额度事件通常位于文件尾部。
        var maxTailBytes: UInt64 = 4 * 1024 * 1024
        /// `session_meta` 首行可能包含较长的系统指令，最多读取这么多字节寻找换行。
        var maxSessionMetaBytes = 1024 * 1024
        /// 文件修改时间与事件时间的容差，覆盖写入延迟和时钟误差。
        var modificationTimeTolerance: TimeInterval = 5 * 60
        /// 尚未找到任何额度事件时最多检查的文件数，避免为旧日志读完整个历史。
        var maxFilesWithoutSnapshot = 40
    }

    private struct FileFingerprint: Equatable {
        let size: UInt64
        let modificationDate: Date
    }

    private struct CachedFileScan {
        let fingerprint: FileFingerprint
        let event: CodexQuotaEvent?
        /// nil 表示尚未读取首行；`.some(nil)` 表示首行没有账号字段。
        var accountID: String??
    }

    private struct CandidateFile {
        let url: URL
        let cacheKey: String
        let fingerprint: FileFingerprint
    }

    private static let rateLimitsMarker = Data("\"rate_limits\"".utf8)
    private static let tokenCountMarker = Data("\"token_count\"".utf8)
    private static let newline: UInt8 = 0x0A

    private let scanner: CodexRolloutScanner
    private let configuration: Configuration
    private let logger = Logger(subsystem: "com.xiaoao.TokenWatch", category: "CodexQuotaReader")
    private let lock = NSLock()
    private var cache: [String: CachedFileScan] = [:]

    init(
        scanner: CodexRolloutScanner = CodexRolloutScanner(),
        configuration: Configuration = Configuration()
    ) {
        self.scanner = scanner
        self.configuration = configuration
    }

    /// 读取 Codex 数据根下按事件时间最新的额度快照。
    /// - Parameter codexRoot: 已开始 security-scoped 访问的 Codex 数据根。
    /// - Returns: 最新快照；没有任何可用额度事件时返回 `.noRecord`。
    /// - Throws: 无法枚举 rollout 目录时抛出；单个文件读取失败只跳过该文件。
    func read(codexRoot: URL) throws -> SubscriptionQuotaReadResult {
        let files = try scanner.scanAll(in: codexRoot)
        // 先按修改时间倒序：文件修改时间不早于其中任何事件的写入时间，
        // 因此一旦文件修改时间早于已找到的最新事件，后续文件都不可能更新。
        let candidates = files.compactMap(candidateFile(for:)).sorted {
            $0.fingerprint.modificationDate > $1.fingerprint.modificationDate
        }

        var best: (event: CodexQuotaEvent, file: CandidateFile)?
        var filesWithoutSnapshot = 0
        for candidate in candidates {
            if let best,
               candidate.fingerprint.modificationDate
                < best.event.recordedAt.addingTimeInterval(-configuration.modificationTimeTolerance) {
                break
            }
            if best == nil, filesWithoutSnapshot >= configuration.maxFilesWithoutSnapshot {
                break
            }
            guard let event = latestEvent(in: candidate) else {
                filesWithoutSnapshot += 1
                continue
            }
            if best.map({ event.recordedAt > $0.event.recordedAt }) ?? true {
                best = (event, candidate)
            }
        }
        pruneCache(keeping: Set(candidates.map(\.cacheKey)))

        guard let best else {
            logger.info("Codex rollout 中没有可用的额度事件")
            return .noRecord
        }
        return .snapshot(SubscriptionQuotaSnapshot(
            provider: .codex,
            accountID: accountID(for: best.file),
            bucketID: best.event.bucketID,
            recordedAt: best.event.recordedAt,
            windows: best.event.windows
        ))
    }

    /// 解码单行 rollout；只接受主额度桶且至少含一个可识别窗口的 `token_count` 事件。
    /// - Parameter line: 不含换行符的一行 JSON。
    /// - Returns: 额度事件；非额度行、损坏行或半行返回 nil。
    static func decodeQuotaEvent(from line: Data, decoder: JSONDecoder = JSONDecoder()) -> CodexQuotaEvent? {
        guard line.range(of: rateLimitsMarker) != nil,
              line.range(of: tokenCountMarker) != nil,
              let record = try? decoder.decode(CodexRateLimitRecord.self, from: line),
              record.type == "event_msg",
              record.payload?.type == "token_count",
              let rateLimits = record.payload?.rateLimits,
              let recordedAt = record.timestamp else {
            return nil
        }

        let bucketID = rateLimits.limitID ?? defaultBucketID
        guard bucketID == defaultBucketID else { return nil }

        // 按窗口时长识别，不假定 primary / secondary 的固定含义。
        var windows: [SubscriptionQuotaWindowKind: SubscriptionQuotaWindow] = [:]
        for limit in [rateLimits.primary, rateLimits.secondary].compactMap({ $0 }) {
            let kind: SubscriptionQuotaWindowKind
            switch limit.windowMinutes {
            case fiveHourWindowMinutes:
                kind = .fiveHour
            case sevenDayWindowMinutes:
                kind = .sevenDay
            default:
                continue
            }
            guard windows[kind] == nil,
                  let window = SubscriptionQuotaWindow(
                    usedPercent: limit.usedPercent,
                    resetsAt: limit.resetsAt
                  ) else {
                continue
            }
            windows[kind] = window
        }
        guard !windows.isEmpty else { return nil }
        return CodexQuotaEvent(recordedAt: recordedAt, bucketID: bucketID, windows: windows)
    }

    // MARK: - File scanning

    private func candidateFile(for fileInfo: CodexRolloutFileInfo) -> CandidateFile? {
        let url = fileInfo.url
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize,
              let modificationDate = values.contentModificationDate else {
            return nil
        }
        return CandidateFile(
            url: url,
            cacheKey: url.standardizedFileURL.path,
            fingerprint: FileFingerprint(size: UInt64(max(0, size)), modificationDate: modificationDate)
        )
    }

    /// 文件未变化时复用缓存；变化后重新读取尾部，覆盖追加和原文件改写两种情况。
    private func latestEvent(in file: CandidateFile) -> CodexQuotaEvent? {
        lock.lock()
        if let cached = cache[file.cacheKey], cached.fingerprint == file.fingerprint {
            lock.unlock()
            return cached.event
        }
        lock.unlock()

        let event: CodexQuotaEvent?
        do {
            event = try scanTail(of: file)
        } catch {
            logger.warning("Codex rollout 尾部读取失败，跳过: \(file.url.lastPathComponent, privacy: .public)")
            return nil
        }

        lock.lock()
        cache[file.cacheKey] = CachedFileScan(fingerprint: file.fingerprint, event: event, accountID: nil)
        lock.unlock()
        return event
    }

    /// 从文件尾部逐块向前读取，返回文件中最后一条额度事件。
    /// 末尾未写完的半行解码失败后自然跳过，继续检查前面的完整行。
    private func scanTail(of file: CandidateFile) throws -> CodexQuotaEvent? {
        let handle = try FileHandle(forReadingFrom: file.url)
        defer { try? handle.close() }

        let decoder = JSONDecoder()
        var end = file.fingerprint.size
        var scannedBytes: UInt64 = 0
        var carry = Data()
        while end > 0, scannedBytes < configuration.maxTailBytes {
            let length = min(UInt64(configuration.tailChunkSize), end)
            let start = end - length
            try handle.seek(toOffset: start)
            var chunk = try handle.read(upToCount: Int(length)) ?? Data()
            guard !chunk.isEmpty else { break }
            scannedBytes += UInt64(chunk.count)
            chunk.append(carry)

            var lines = chunk.split(separator: Self.newline, omittingEmptySubsequences: false)
            // 起点不是文件开头时，第一段可能是更早一行的后半截，留给下一轮拼接。
            carry = start > 0 && !lines.isEmpty ? Data(lines.removeFirst()) : Data()
            for line in lines.reversed() where !line.isEmpty {
                if let event = Self.decodeQuotaEvent(from: Data(line), decoder: decoder) {
                    return event
                }
            }
            end = start
        }
        return nil
    }

    /// 读取文件首行 `session_meta.creator_account_id`，结果随文件缓存。
    private func accountID(for file: CandidateFile) -> String? {
        lock.lock()
        if let cached = cache[file.cacheKey]?.accountID {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let accountID = readSessionAccountID(from: file.url)
        lock.lock()
        cache[file.cacheKey]?.accountID = .some(accountID)
        lock.unlock()
        return accountID
    }

    private func readSessionAccountID(from url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var firstLine = Data()
        while firstLine.count < configuration.maxSessionMetaBytes {
            guard let chunk = try? handle.read(upToCount: configuration.tailChunkSize),
                  !chunk.isEmpty else {
                break
            }
            if let newlineIndex = chunk.firstIndex(of: Self.newline) {
                firstLine.append(chunk[chunk.startIndex..<newlineIndex])
                break
            }
            firstLine.append(chunk)
        }
        guard let meta = try? JSONDecoder().decode(CodexSessionAccountRecord.self, from: firstLine),
              meta.type == "session_meta" else {
            return nil
        }
        return meta.accountID
    }

    private func pruneCache(keeping keys: Set<String>) {
        lock.lock()
        cache = cache.filter { keys.contains($0.key) }
        lock.unlock()
    }
}

/// rollout 额度行的最小解码模型；只声明额度需要的字段。
private struct CodexRateLimitRecord: Decodable {
    let timestamp: Date?
    let type: String
    let payload: Payload?

    private enum CodingKeys: String, CodingKey {
        case timestamp, type, payload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        timestamp = (try? container.decodeIfPresent(String.self, forKey: .timestamp))
            .flatMap { CodexNormalizedTimestamp.parse($0)?.date }
        payload = try? container.decodeIfPresent(Payload.self, forKey: .payload)
    }

    struct Payload: Decodable {
        let type: String?
        let rateLimits: RateLimits?

        private enum CodingKeys: String, CodingKey {
            case type
            case rateLimits = "rate_limits"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try? container.decodeIfPresent(String.self, forKey: .type)
            rateLimits = try? container.decodeIfPresent(RateLimits.self, forKey: .rateLimits)
        }
    }

    struct RateLimits: Decodable {
        let limitID: String?
        let primary: Limit?
        let secondary: Limit?

        private enum CodingKeys: String, CodingKey {
            case limitID = "limit_id"
            case primary, secondary
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let rawLimitID = try? container.decodeIfPresent(String.self, forKey: .limitID)
            let trimmedLimitID = rawLimitID?.trimmingCharacters(in: .whitespacesAndNewlines)
            limitID = trimmedLimitID?.isEmpty == false ? trimmedLimitID : nil
            // primary / secondary 独立容错：一个窗口损坏不吞掉另一个。
            primary = try? container.decodeIfPresent(Limit.self, forKey: .primary)
            secondary = try? container.decodeIfPresent(Limit.self, forKey: .secondary)
        }
    }

    struct Limit: Decodable {
        let usedPercent: Double?
        let windowMinutes: Int?
        let resetsAt: Date?

        private enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case windowMinutes = "window_minutes"
            case resetsAt = "resets_at"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            usedPercent = (try? container.decodeIfPresent(
                SubscriptionQuotaLossyNumber.self,
                forKey: .usedPercent
            ))?.value
            windowMinutes = (try? container.decodeIfPresent(
                SubscriptionQuotaLossyNumber.self,
                forKey: .windowMinutes
            ))?.value.flatMap { Int(exactly: $0) }
            resetsAt = (try? container.decodeIfPresent(
                SubscriptionQuotaLossyDate.self,
                forKey: .resetsAt
            ))?.date
        }
    }
}

/// rollout 首行 `session_meta` 的账号字段。
private struct CodexSessionAccountRecord: Decodable {
    let type: String
    let accountID: String?

    private enum CodingKeys: String, CodingKey {
        case type, payload
    }

    private enum PayloadCodingKeys: String, CodingKey {
        case creatorAccountID = "creator_account_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        let payload = try? container.nestedContainer(keyedBy: PayloadCodingKeys.self, forKey: .payload)
        let rawAccountID = try? payload?.decodeIfPresent(String.self, forKey: .creatorAccountID)
        accountID = rawAccountID?.isEmpty == false ? rawAccountID : nil
    }
}
