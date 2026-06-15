import Foundation

/// opencode SQLite 中 `message.data` JSON blob 的 Decodable 模型
/// 仅解码 token 统计需要的子树,其余字段忽略
///
/// 字段来源:opencode v1.17.5 schema(`message` 表 `data` 列,role=assistant)
struct OpenCodeMessageData: Decodable {
    let role: String
    let modelID: String?
    let providerID: String?
    let cost: Double?
    let tokens: OpenCodeTokens?
    let path: OpenCodePath?

    enum CodingKeys: String, CodingKey {
        case role, modelID, providerID, cost, tokens, path
    }
}

/// `data.tokens` 子结构 — 含 5 类 token
struct OpenCodeTokens: Decodable {
    let input: Int
    let output: Int
    let reasoning: Int
    let cache: OpenCodeCache

    enum CodingKeys: String, CodingKey {
        case input, output, reasoning, cache
    }

    /// 5 维全 0 视为 placeholder,Parser 跳过
    var isAllZero: Bool {
        input == 0 && output == 0 && reasoning == 0
            && cache.read == 0 && cache.write == 0
    }
}

/// `data.tokens.cache` 子结构
struct OpenCodeCache: Decodable {
    let read: Int
    let write: Int
}

/// `data.path` 子结构 — 仅取 cwd
struct OpenCodePath: Decodable {
    let cwd: String?
}
