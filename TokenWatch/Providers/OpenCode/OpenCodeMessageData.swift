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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = (try? container.decode(String.self, forKey: .role)) ?? ""
        modelID = container.nonEmptyString(forKey: .modelID)
        providerID = container.nonEmptyString(forKey: .providerID)
        cost = try? container.decode(Double.self, forKey: .cost)
        tokens = try? container.decode(OpenCodeTokens.self, forKey: .tokens)
        path = try? container.decode(OpenCodePath.self, forKey: .path)
    }
}

/// `data.tokens` 子结构。OpenCode 历史数据可能只写 `total`，
/// 因此所有子字段都按 ccusage 的 serde default 语义宽容解码。
struct OpenCodeTokens: Decodable {
    let input: Int
    let output: Int
    let reasoning: Int
    let total: Int
    let cache: OpenCodeCache

    enum CodingKeys: String, CodingKey {
        case input, output, reasoning, total, cache
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        input = container.lenientUnsignedInt(forKey: .input)
        output = container.lenientUnsignedInt(forKey: .output)
        reasoning = container.lenientUnsignedInt(forKey: .reasoning)
        total = container.lenientUnsignedInt(forKey: .total)
        cache = (try? container.decode(OpenCodeCache.self, forKey: .cache)) ?? .zero
    }

    /// ccusage `apply_total_token_fallback` 将 total 中未被已知类别覆盖的余量
    /// 按 output rate 计费。TokenWatch 没有 extra-total 维度，因此并入 output。
    var billableOutputTokens: Int {
        let known = input + output + cache.read + cache.write
        return output + max(total - known, 0)
    }

    /// 已应用 total fallback 后仍全 0 才是可跳过的空 usage。
    var isAllZero: Bool {
        // pinned OpenCode adapter 不把 tokens.reasoning 映射到 TokenUsageRaw；
        // total 若包含它，会由 total fallback 以 output rate 计价。
        input == 0 && billableOutputTokens == 0
            && cache.read == 0 && cache.write == 0
    }
}

/// `data.tokens.cache` 子结构
struct OpenCodeCache: Decodable {
    let read: Int
    let write: Int

    enum CodingKeys: String, CodingKey {
        case read, write
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        read = container.lenientUnsignedInt(forKey: .read)
        write = container.lenientUnsignedInt(forKey: .write)
    }

    private init(read: Int, write: Int) {
        self.read = read
        self.write = write
    }

    static let zero = OpenCodeCache(read: 0, write: 0)
}

/// `data.path` 子结构 — 仅取 cwd
struct OpenCodePath: Decodable {
    let cwd: String?
}

private struct LenientUnsignedInt: Decodable {
    let value: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(UInt64.self)) ?? 0
        value = Int(min(raw, UInt64(Int.max)))
    }
}

private extension KeyedDecodingContainer {
    func lenientUnsignedInt(forKey key: Key) -> Int {
        guard contains(key), (try? decodeNil(forKey: key)) != true else { return 0 }
        return (try? decode(LenientUnsignedInt.self, forKey: key).value) ?? 0
    }

    func nonEmptyString(forKey key: Key) -> String? {
        guard let value = try? decode(String.self, forKey: key) else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
