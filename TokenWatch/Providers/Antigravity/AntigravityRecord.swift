import Foundation

/// SQLite 扫描产出的单次生成原始数据（Protobuf blob 未解码）
struct AntigravityRawGenerationRow: Sendable {
    let trajectoryID: String
    let genIdx: Int64
    let dataBlob: Data
}

/// SQLite 扫描产出的步骤时间戳数据
struct AntigravityStepTimestampRow: Sendable {
    let stepIdx: Int64
    let timestamp: Date
}

/// 单个会话数据库的扫描原始结果
struct AntigravityConversationScanResult: Sendable {
    let conversationID: String
    let databaseURL: URL
    let workspacePath: String?
    let generations: [AntigravityRawGenerationRow]
    let stepTimestamps: [Int64: Date]

    init(
        conversationID: String,
        databaseURL: URL,
        workspacePath: String? = nil,
        generations: [AntigravityRawGenerationRow],
        stepTimestamps: [Int64: Date]
    ) {
        self.conversationID = conversationID
        self.databaseURL = databaseURL
        self.workspacePath = workspacePath
        self.generations = generations
        self.stepTimestamps = stepTimestamps
    }
}
