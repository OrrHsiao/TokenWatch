import Foundation
@testable import TokenWatch

/// DSH provider 测试的公共装配工具。
enum DeepSeekHarnessTestSupport {
    /// 创建独立临时目录，调用方负责清理。
    static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dsh-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 在 `root/sessions/--tmp-project--/<sessionDirectory>/` 下写入日志文件。
    /// - Returns: 写入的日志文件描述。
    @discardableResult
    static func writeSessionLog(
        root: URL,
        sessionDirectory: String,
        fileName: String,
        contents: Data
    ) throws -> DeepSeekHarnessSessionLogFile {
        let directory = root
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("--tmp-project--", isDirectory: true)
            .appendingPathComponent(sessionDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName)
        try contents.write(to: url)
        guard let parsed = DeepSeekHarnessScanner.parseGeneration(fileName: fileName) else {
            throw DeepSeekHarnessTestSupportError.invalidFixtureFileName(fileName)
        }
        return DeepSeekHarnessSessionLogFile(
            url: url,
            generation: parsed.generation,
            isCompressed: parsed.isCompressed
        )
    }

    /// 用系统 reader 打开快照并构建解析状态。
    static func buildState(
        file: DeepSeekHarnessSessionLogFile,
        previous: DeepSeekHarnessSessionLogState? = nil,
        fileReader: any JSONLFileReading = SystemJSONLFileReader(),
        parser: DeepSeekHarnessSessionLogParser = DeepSeekHarnessSessionLogParser()
    ) throws -> DeepSeekHarnessSessionLogState {
        let snapshot = try fileReader.openSnapshot(for: file.url)
        defer { snapshot.stream.close() }
        return try parser.buildState(file: file, snapshot: snapshot, previous: previous)
    }

    /// 构建会话 header 行。
    static func headerLine(
        id: String,
        version: Int = 4,
        cwd: String = "/tmp/project",
        isSeeded: Bool = false,
        origin: String? = nil,
        delegationDepth: Int = 0,
        parentSession: String? = nil
    ) -> String {
        var payload: [String: Any] = [
            "type": "session",
            "version": version,
            "id": id,
            "createdAt": 1_790_757_477_847,
            "cwd": cwd,
            "isSeeded": isSeeded,
            "delegationDepth": delegationDepth,
        ]
        if let origin { payload["origin"] = origin }
        if let parentSession { payload["parentSession"] = parentSession }
        let data = try! JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )
        return String(decoding: data, as: UTF8.self)
    }

    /// 构建 `assistant/message` 事件行。
    static func assistantMessageLine(
        sequence: Int,
        time: Double,
        turn: Int,
        step: Int,
        messageID: String?,
        model: String = "deepseek-v4.1-flash",
        provider: String = "opencode-go",
        inputTokens: Int,
        outputTokens: Int,
        cacheReadTokens: Int = 0,
        cacheWriteTokens: Int = 0,
        reasoningTokens: Int? = nil,
        includesStreamUsage: Bool = true
    ) -> String {
        var usage: [String: Any] = [
            "inputTokens": inputTokens,
            "outputTokens": outputTokens,
            "totalTokens": inputTokens + outputTokens + cacheReadTokens,
            "cacheReadTokens": cacheReadTokens,
        ]
        if cacheWriteTokens > 0 { usage["cacheWriteTokens"] = cacheWriteTokens }
        if let reasoningTokens { usage["reasoningTokens"] = reasoningTokens }

        var message: [String: Any] = [
            "role": "assistant",
            "source": ["kind": "model", "provider": provider, "model": model],
        ]
        if let messageID { message["id"] = messageID }

        var data: [String: Any] = [
            "turn": turn,
            "step": step,
            "message": message,
            "usage": usage,
        ]
        if includesStreamUsage {
            data["stream"] = [
                [
                    "type": "chunk",
                    "time": time,
                    "chunk": ["type": "usage", "usage": usage],
                ],
            ]
        }
        return jsonLine([
            "type": "assistant/message",
            "seq": sequence,
            "time": time,
            "data": data,
        ])
    }

    /// 构建 `assistant/attempt` 事件行；用量只存在于 stream 末尾的 usage chunk。
    static func assistantAttemptLine(
        sequence: Int,
        time: Double,
        turn: Int,
        step: Int,
        inputTokens: Int,
        outputTokens: Int,
        cacheReadTokens: Int = 0,
        trailingChunks: [[String: Any]] = []
    ) -> String {
        var stream: [[String: Any]] = [
            [
                "type": "chunk",
                "time": time,
                "chunk": [
                    "type": "usage",
                    "usage": [
                        "inputTokens": inputTokens,
                        "outputTokens": outputTokens,
                        "cacheReadTokens": cacheReadTokens,
                    ],
                ],
            ],
        ]
        stream.append(contentsOf: trailingChunks)
        return jsonLine([
            "type": "assistant/attempt",
            "seq": sequence,
            "time": time,
            "data": ["turn": turn, "step": step, "stream": stream],
        ])
    }

    /// 构建 `llm/retry-started` 事件行。
    static func retryStartedLine(sequence: Int, time: Double, turn: Int, step: Int) -> String {
        jsonLine([
            "type": "llm/retry-started",
            "seq": sequence,
            "time": time,
            "data": ["retryId": "retry-\(sequence)", "turn": turn, "step": step, "retry": 1],
        ])
    }

    /// 构建 `session/end-seed` 事件行。
    static func endSeedLine(sequence: Int, time: Double, inherited: Bool) -> String {
        jsonLine([
            "type": "session/end-seed",
            "seq": sequence,
            "time": time,
            "data": inherited ? ["inherited": true] : [:],
        ])
    }

    /// 把日志行拼成文件内容（每行以换行结尾）。
    static func logContents(_ lines: [String]) -> Data {
        Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    /// 汇总一组条目的四个计费桶。
    static func totals(of entries: [ParsedUsageEntry]) -> (
        input: Int,
        output: Int,
        cacheRead: Int,
        cacheWrite: Int
    ) {
        entries.reduce(into: (0, 0, 0, 0)) { result, entry in
            result.0 += entry.usage.inputTokens
            result.1 += entry.usage.outputTokens
            result.2 += entry.usage.cacheReadInputTokens
            result.3 += entry.usage.totalCacheCreationTokens
        }
    }

    private static func jsonLine(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}

enum DeepSeekHarnessTestSupportError: Error {
    case invalidFixtureFileName(String)
}
