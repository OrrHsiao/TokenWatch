import Foundation

/// opencode SQLite 中消息 `data` JSON blob 的 Decodable 模型
/// 仅解码 token 统计需要的子树,其余字段忽略
///
/// 字段来源(两代 schema 的模型字段位置不同,由 Parser 兼容):
/// - 旧版 v1.17.5(`message` 表):顶层 `modelID` / `providerID` / `path`
/// - 2.0(`session_message` 表):模型在 `model.id` / `model.providerID`,无 `path`;角色由表的 `type` 列给出
struct OpenCodeMessageData: Decodable {
    let modelID: String?
    let providerID: String?
    let model: OpenCodeModelRef?
    let cost: Double?
    let tokens: OpenCodeTokens?
    let path: OpenCodePath?

    enum CodingKeys: String, CodingKey {
        case modelID, providerID, model, cost, tokens, path
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modelID = container.nonEmptyString(forKey: .modelID)
        providerID = container.nonEmptyString(forKey: .providerID)
        model = try? container.decode(OpenCodeModelRef.self, forKey: .model)
        cost = try? container.decode(Double.self, forKey: .cost)
        tokens = try? container.decode(OpenCodeTokens.self, forKey: .tokens)
        path = try? container.decode(OpenCodePath.self, forKey: .path)
    }
}

/// 2.0 `data.model` 子结构:模型 ID 与上游 provider(旧版对应顶层 modelID / providerID)
struct OpenCodeModelRef: Decodable {
    let id: String?
    let providerID: String?

    enum CodingKeys: String, CodingKey {
        case id, providerID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.nonEmptyString(forKey: .id)
        providerID = container.nonEmptyString(forKey: .providerID)
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
        let known = [input, output, cache.read, cache.write]
            .reduce(0, Self.saturatingAdd)
        let missing = max(total - known, 0)
        return Self.saturatingAdd(output, missing)
    }

    /// 已应用 total fallback 后仍全 0 才是可跳过的空 usage。
    var isAllZero: Bool {
        // pinned OpenCode adapter 不把 tokens.reasoning 映射到 TokenUsageRaw；
        // total 若包含它，会由 total fallback 以 output rate 计价。
        input == 0 && billableOutputTokens == 0
            && cache.read == 0 && cache.write == 0
    }

    /// token 字段均为非负 Int；复合极值相加溢出时夹到 Int.max。
    private static func saturatingAdd(_ lhs: Int, _ rhs: Int) -> Int {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int.max : sum
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
