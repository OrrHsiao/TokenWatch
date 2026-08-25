import Foundation
import os.log

/// 按 ccusage 来源优先级组装并查询离线模型定价。
struct PricingTable: Sendable {
    private let primary: [String: ModelPricing]
    private let fallback: [String: ModelPricing]

    private static let logger = Logger(
        subsystem: "com.xiaoao.TokenWatch",
        category: "PricingTable"
    )

    static let shared: PricingTable = loadBundled()

    /// 组装 LiteLLM、builtin 与 models.dev 定价来源。
    /// - Parameters:
    ///   - liteLLMEntries: 作为 primary 基础的过滤后 LiteLLM 条目。
    ///   - modelsDevEntries: 仅在 primary 与 alias 都未命中时查询的 fallback。
    ///   - builtins: 覆盖 LiteLLM 同 key 整条记录的 ccusage builtin。
    init(
        liteLLMEntries: [String: CatalogPricingEntry],
        modelsDevEntries: [String: ModelPricing],
        builtins: [String: ModelPricing] = Self.builtinPrices
    ) {
        var assembled: [String: CatalogPricingEntry] = [:]
        for (key, entry) in liteLLMEntries {
            let override = Self.builtinFastMultiplier(for: key)
            let fast = entry.explicitFastMultiplier ?? override ?? entry.pricing.fastMultiplier
            assembled[key.lowercased()] = CatalogPricingEntry(
                pricing: Self.replacingFastMultiplier(entry.pricing, with: fast),
                explicitFastMultiplier: entry.explicitFastMultiplier
            )
        }
        for (key, builtin) in builtins {
            // ccusage 在 LiteLLM 之后 insert builtin：同 key 时整条覆盖，
            // 不保留 LiteLLM 的 provider_specific fast。
            assembled[key.lowercased()] = CatalogPricingEntry(
                pricing: builtin,
                explicitFastMultiplier: nil
            )
        }
        var prices = assembled.mapValues(\.pricing)
        for (key, value) in prices {
            prices[key] = Self.applyingLongContextOverlay(value, modelID: key)
        }
        primary = prices
        fallback = Dictionary(
            uniqueKeysWithValues: modelsDevEntries.map { ($0.key.lowercased(), $0.value) }
        )
    }

    /// 查询模型定价，依次尝试 primary exact、alias、primary fuzzy 与 fallback。
    /// - Parameter modelID: 原始模型 ID，匹配时不区分大小写。
    /// - Returns: 确定性选出的定价；没有候选时返回 `nil`。
    func pricing(for modelID: String) -> ModelPricing? {
        let model = modelID.lowercased()
        guard !model.isEmpty else { return nil }
        if let exact = primary[model] { return exact }

        let alias = Self.alias(for: model)
        if alias != model, let aliased = Self.find(alias, in: primary) {
            return Self.scopingFastMultiplier(aliased, requestedModel: model)
        }
        if let direct = Self.find(model, in: primary) {
            return Self.scopingFastMultiplier(direct, requestedModel: model)
        }

        return Self.find(alias, in: fallback).map {
            Self.scopingFastMultiplier($0, requestedModel: model)
        }
    }

    /// 使用共享离线定价表查询模型价格。
    /// - Parameter modelID: 原始模型 ID。
    /// - Returns: 匹配的定价；没有候选时返回 `nil`。
    static func pricing(for modelID: String) -> ModelPricing? {
        shared.pricing(for: modelID)
    }

    /// 按 schema、匹配类型和模型 ID 排序，序列化生产实际使用的 fast 映射。
    static var canonicalFastMultiplierOverrides: Data {
        let schema = ["schema\tfast-multiplier-production-v2"]
        let exact = fastExactOverrides
            .sorted { $0.key < $1.key }
            .map { "exact\t\($0.key)\t\($0.value)" }
        let prefixes = fastPrefixOverrides
            .sorted { $0.modelID < $1.modelID }
            .map { "prefix\t\($0.modelID)\t\($0.multiplier)" }
        return Data((schema + exact + prefixes).joined(separator: "\n").utf8)
    }

    private static func loadBundled() -> PricingTable {
        load(
            liteLLMURL: Bundle.appResourceBundle.url(
                forResource: "litellm_prices",
                withExtension: "json"
            ),
            modelsDevURL: Bundle.appResourceBundle.url(
                forResource: "models-dev-pricing",
                withExtension: "json"
            )
        )
    }

    /// 从指定的两个离线资源组装定价表，与 bundle 初始化共用读取路径。
    static func load(liteLLMURL: URL?, modelsDevURL: URL?) -> PricingTable {
        PricingTable(
            liteLLMEntries: loadLiteLLM(from: liteLLMURL),
            modelsDevEntries: loadModelsDev(from: modelsDevURL)
        )
    }

    private static func loadLiteLLM(
        from url: URL?
    ) -> [String: CatalogPricingEntry] {
        guard let url else {
            logger.error("LiteLLM 离线定价资源缺失")
            return [:]
        }
        do {
            return try LiteLLMPriceCatalog(data: Data(contentsOf: url)).entries
        } catch {
            logger.error("LiteLLM 离线定价资源读取失败：\(error.localizedDescription)")
            return [:]
        }
    }

    private static func loadModelsDev(from url: URL?) -> [String: ModelPricing] {
        guard let url else {
            logger.error("models.dev 离线定价资源缺失")
            return [:]
        }
        do {
            return try ModelsDevPriceCatalog(data: Data(contentsOf: url)).entries
        } catch {
            logger.error("models.dev 离线定价资源读取失败：\(error.localizedDescription)")
            return [:]
        }
    }

    private static func find(
        _ model: String,
        in entries: [String: ModelPricing]
    ) -> ModelPricing? {
        guard !model.isEmpty else { return nil }
        if let exact = entries[model] { return exact }
        return entries
            .filter { keyMatches(candidate: $0.key, model: model) }
            .sorted {
                if $0.key.count != $1.key.count {
                    return $0.key.count > $1.key.count
                }
                return $0.key < $1.key
            }
            .first?
            .value
    }

    private static func keyMatches(candidate: String, model: String) -> Bool {
        if containsPricingKey(model, key: candidate)
            || containsPricingKey(candidate, key: model) {
            return true
        }
        let normalizedCandidate = normalizeSeparators(candidate)
        let normalizedModel = normalizeSeparators(model)
        return containsPricingKey(normalizedModel, key: normalizedCandidate)
            || containsPricingKey(normalizedCandidate, key: normalizedModel)
    }

    private static func containsPricingKey(_ value: String, key: String) -> Bool {
        guard !key.isEmpty else { return false }
        var search = value.startIndex..<value.endIndex
        while let range = value.range(of: key, range: search) {
            let before = range.lowerBound == value.startIndex
                ? nil
                : value[value.index(before: range.lowerBound)]
            let suffix = String(value[range.upperBound...])
            let validBefore = before.map { !$0.isLetter && !$0.isNumber } ?? true
            if validBefore && suffixAllowsMatch(key: key, suffix: suffix) {
                return true
            }
            search = range.upperBound..<value.endIndex
        }
        return false
    }

    private static func suffixAllowsMatch(key: String, suffix: String) -> Bool {
        guard let separator = suffix.first else { return true }
        guard !separator.isLetter && !separator.isNumber else { return false }
        return !suffixStartsWithNumericVersion(key: key, suffix: suffix)
    }

    private static func suffixStartsWithNumericVersion(
        key: String,
        suffix: String
    ) -> Bool {
        guard key.last?.isNumber == true,
              suffix.first == "-" || suffix.first == "." else { return false }
        let rest = suffix.dropFirst()
        let digits = rest.prefix { $0.isNumber }
        guard !digits.isEmpty else { return false }
        let afterDigits = rest.dropFirst(digits.count).first
        let dateLike = digits.count == 8
            && (afterDigits.map { !$0.isLetter && !$0.isNumber } ?? true)
        return !dateLike
    }

    /// 保留 LiteLLMPriceCatalog 迁移期间依赖的版本号守卫入口。
    static func suffixStartsWithNumericVersion(
        candidate: String,
        suffix: String
    ) -> Bool {
        suffixStartsWithNumericVersion(key: candidate, suffix: suffix)
    }

    private static func normalizeSeparators(_ value: String) -> String {
        value.replacingOccurrences(of: ".", with: "-")
            .replacingOccurrences(of: "@", with: "-")
    }

    private static func alias(for model: String) -> String {
        switch model {
        case "gpt-5.3-spark":
            return "gpt-5.3-codex-spark"
        case "gpt-5.6":
            return "gpt-5.6-sol"
        default:
            if model.hasSuffix("/gpt-5.6") || model.hasSuffix(":gpt-5.6") {
                return "\(model)-sol"
            }
            return model
        }
    }
}

private extension PricingTable {
    struct LongContextRates {
        let input: Double
        let output: Double
        let cacheWrite: Double?
        let cacheRead: Double?
    }

    static let fastExactOverrides: [String: Double] = [
        "gpt-5.6-luna": 2.0,
        "gpt-5.6-sol": 2.0,
        "gpt-5.6-terra": 2.0,
        "gpt-5.5": 2.5,
        "gpt-5.4": 2.0,
        "gpt-5.3-codex": 2.0,
    ]

    static let fastPrefixOverrides: [(modelID: String, multiplier: Double)] = [
        ("claude-opus-4-8", 2.0),
        ("claude-opus-5", 2.0),
    ]

    static let builtinPrices: [String: ModelPricing] = {
        func p(
            _ id: String,
            _ input: Double,
            _ output: Double,
            _ cacheRead: Double,
            _ cacheWrite: Double,
            inputAbove: Double? = nil,
            outputAbove: Double? = nil,
            cacheReadAbove: Double? = nil,
            cacheWriteAbove: Double? = nil,
            longContextThreshold: Int? = nil
        ) -> ModelPricing {
            ModelPricing(
                modelID: id,
                displayName: id,
                inputPrice: input,
                outputPrice: output,
                cacheReadPrice: cacheRead,
                cacheWritePrice: cacheWrite,
                cacheReadPriceIsExplicit: true,
                inputPriceAbove200k: inputAbove,
                outputPriceAbove200k: outputAbove,
                cacheReadPriceAbove200k: cacheReadAbove,
                cacheWritePriceAbove200k: cacheWriteAbove,
                longContextThreshold: longContextThreshold,
                fastMultiplier: builtinFastMultiplier(for: id) ?? 1.0
            )
        }

        let claude35Haiku = p("claude-3-5-haiku", 0.8, 4, 0.08, 1)
        let gpt51 = p("gpt-5.1", 1.25, 10, 0.125, 1.25)
        let gpt52Codex = p("gpt-5.2-codex", 1.75, 14, 0.175, 1.75)

        return [
            "claude-opus-4-5": p("claude-opus-4-5", 5, 25, 0.5, 6.25),
            "claude-opus-4-6": p("claude-opus-4-6", 5, 25, 0.5, 6.25),
            "claude-opus-4-7": p("claude-opus-4-7", 5, 25, 0.5, 6.25),
            "claude-opus-4-8": p("claude-opus-4-8", 5, 25, 0.5, 6.25),
            "claude-opus-5": p("claude-opus-5", 5, 25, 0.5, 6.25),
            "claude-sonnet-5": p("claude-sonnet-5", 2, 10, 0.2, 2.5),
            "claude-haiku-4-5": p("claude-haiku-4-5", 1, 5, 0.1, 1.25),
            "claude-opus-4": p("claude-opus-4", 15, 75, 1.5, 18.75),
            "claude-sonnet-4-6": p("claude-sonnet-4-6", 3, 15, 0.3, 3.75),
            "claude-sonnet-4": p(
                "claude-sonnet-4", 3, 15, 0.3, 3.75,
                inputAbove: 6, outputAbove: 22.5,
                cacheReadAbove: 0.6, cacheWriteAbove: 7.5
            ),
            "claude-3-5-haiku": claude35Haiku,
            "claude-3-5-haiku-20241022": ModelPricing(
                modelID: "claude-3-5-haiku-20241022",
                displayName: "claude-3-5-haiku-20241022",
                inputPrice: claude35Haiku.inputPrice,
                outputPrice: claude35Haiku.outputPrice,
                cacheReadPrice: claude35Haiku.cacheReadPrice,
                cacheWritePrice: claude35Haiku.cacheWritePrice
            ),
            "claude-3-opus": p("claude-3-opus", 15, 75, 1.5, 18.75),
            "claude-3-sonnet": p("claude-3-sonnet", 3, 15, 0.3, 3.75),
            "claude-3-haiku": p("claude-3-haiku", 0.25, 1.25, 0.03, 0.3),
            "gpt-5": p("gpt-5", 1.25, 10, 0.125, 1.25),
            "gpt-5.5": p("gpt-5.5", 5, 30, 0.5, 5),
            // xAI 在 prompt 达到 200K 时对整条请求使用 long-context 价格。
            // PricingEngine 的阈值判断为严格大于，因此这里用 199,999 表达包含边界。
            // xAI 未公布独立 cache-write 价，该字段沿用 catalog 的 input × 1.25 fallback。
            "grok-4.3": p(
                "grok-4.3", 1.25, 2.5, 0.2, 1.5625,
                inputAbove: 2.5, outputAbove: 5,
                cacheReadAbove: 0.4, longContextThreshold: 199_999
            ),
            "grok-4.20-multi-agent-0309": p(
                "grok-4.20-multi-agent-0309", 1.25, 2.5, 0.2, 1.5625,
                inputAbove: 2.5, outputAbove: 5,
                cacheReadAbove: 0.4, longContextThreshold: 199_999
            ),
            "grok-4.20-0309-reasoning": p(
                "grok-4.20-0309-reasoning", 1.25, 2.5, 0.2, 1.5625,
                inputAbove: 2.5, outputAbove: 5,
                cacheReadAbove: 0.4, longContextThreshold: 199_999
            ),
            "grok-4.20-0309-non-reasoning": p(
                "grok-4.20-0309-non-reasoning", 1.25, 2.5, 0.2, 1.5625,
                inputAbove: 2.5, outputAbove: 5,
                cacheReadAbove: 0.4, longContextThreshold: 199_999
            ),
            "grok-4.5": p(
                "grok-4.5", 2, 6, 0.3, 2.5,
                inputAbove: 4, outputAbove: 12,
                cacheReadAbove: 0.6, longContextThreshold: 199_999
            ),
            "grok-4.6": p(
                "grok-4.6", 2, 6, 0.5, 2.5,
                inputAbove: 4, outputAbove: 12,
                cacheReadAbove: 1, longContextThreshold: 199_999
            ),
            "grok-build-0.1": p(
                "grok-build-0.1", 1, 2, 0.2, 1.25,
                inputAbove: 2, outputAbove: 4,
                cacheReadAbove: 0.4, longContextThreshold: 199_999
            ),
            // Moonshot 未公布独立 cache-write 价，沿用相同 catalog fallback。
            "moonshot/kimi-k2.5": p("moonshot/kimi-k2.5", 0.6, 3, 0.1, 0.75),
            "moonshot/kimi-k2.6": p("moonshot/kimi-k2.6", 0.95, 4, 0.16, 1.1875),
            "moonshot/kimi-k2.7-code": p(
                "moonshot/kimi-k2.7-code", 0.95, 4, 0.19, 1.1875
            ),
            "moonshot/kimi-k3": p("moonshot/kimi-k3", 3, 15, 0.3, 3.75),
            "gpt-5.1": gpt51,
            "gpt-5.1-codex": ModelPricing(
                modelID: "gpt-5.1-codex",
                displayName: "gpt-5.1-codex",
                inputPrice: gpt51.inputPrice,
                outputPrice: gpt51.outputPrice,
                cacheReadPrice: gpt51.cacheReadPrice,
                cacheWritePrice: gpt51.cacheWritePrice
            ),
            "gpt-5.2-codex": gpt52Codex,
            "gpt-5.3-codex": p("gpt-5.3-codex", 1.75, 14, 0.175, 1.75),
            "gpt-5.2": p("gpt-5.2", 1.75, 14, 0.175, 1.75),
            "gpt-5.4": p("gpt-5.4", 2.5, 15, 0.25, 2.5),
            "gpt-5.4-mini": p("gpt-5.4-mini", 0.75, 4.5, 0.075, 0.75),
            "gpt-5.4-nano": p("gpt-5.4-nano", 0.2, 1.25, 0.02, 0.2),
            "gpt-5.6-sol": p("gpt-5.6-sol", 4, 20, 0.4, 5),
            "gpt-5.6-terra": p("gpt-5.6-terra", 2, 12, 0.2, 2.5),
            "gpt-5.6-luna": p("gpt-5.6-luna", 0.2, 1.2, 0.02, 0.25),
            // Google 仅公布 cached-input 与 token-hour storage；当前 schema 无法表达 storage，
            // cacheWrite 仍沿用 catalog fallback。
            "gemini-3.5-flash": p("gemini-3.5-flash", 1.5, 9, 0.15, 1.875),
            "gemini-3.5-flash-lite": p(
                "gemini-3.5-flash-lite", 0.3, 2.5, 0.03, 0.375
            ),
            // 官方 Standard 限时价有效至 2026-12-31，到期后需重新核验。
            "gemini-3.6-flash": p(
                "gemini-3.6-flash", 0.75, 3.75, 0.075, 0.9375
            ),
            "gemini-3.7-flash": p(
                "gemini-3.7-flash", 0.75, 3.75, 0.075, 0.9375
            ),
            "glm-4.5": p("glm-4.5", 0.6, 2.2, 0.11, 0),
            "zai/glm-4.5": p("zai/glm-4.5", 0.6, 2.2, 0.11, 0),
            "zai/glm-4.5-x": p("zai/glm-4.5-x", 2.2, 8.9, 0.45, 0),
            "zai/glm-4.5-air": p("zai/glm-4.5-air", 0.2, 1.1, 0.03, 0),
            "zai/glm-4.5-airx": p("zai/glm-4.5-airx", 1.1, 4.5, 0.22, 0),
            "zai/glm-4.5v": p("zai/glm-4.5v", 0.6, 1.8, 0.11, 0),
            "zai/glm-4-32b-0414-128k": p("zai/glm-4-32b-0414-128k", 0.1, 0.1, 0, 0),
            "zai/glm-4.5-flash": p("zai/glm-4.5-flash", 0, 0, 0, 0),
            "glm-4.6": p("glm-4.6", 0.6, 2.2, 0.11, 0),
            "glm-4.7": p("glm-4.7", 0.6, 2.2, 0.11, 0),
            "glm-5": p("glm-5", 1, 3.2, 0.2, 0),
            "glm-5-turbo": p("glm-5-turbo", 1.2, 4, 0.24, 0),
            "glm-5.1": p("glm-5.1", 1.4, 4.4, 0.26, 0),
            "glm-5.2": p("glm-5.2", 1.4, 4.4, 0.26, 0),
            "glm-5.3": p("glm-5.3", 1.4, 4.4, 0.26, 0),
        ]
    }()

    static func builtinFastMultiplier(for modelID: String) -> Double? {
        let canonicalID = modelID.lowercased()
        if let value = fastExactOverrides[canonicalID] { return value }

        return claudeFastMultiplier(for: canonicalID)
    }

    static func claudeFastMultiplier(for modelID: String) -> Double? {
        guard isFirstPartyAnthropicModel(modelID) else { return nil }

        let normalized = normalizeSeparators(modelID.lowercased())
        let parts = normalized.split(whereSeparator: { $0 == "/" || $0 == ":" })
        let modelParts = parts.first == "anthropic" ? parts.dropFirst() : parts[...]

        for part in modelParts {
            for (base, multiplier) in fastPrefixOverrides {
                guard part.hasPrefix(base) else { continue }
                let suffix = part.dropFirst(base.count)
                if suffix.isEmpty || suffix.first == "-" {
                    return multiplier
                }
            }
        }
        return nil
    }

    static func isFirstPartyAnthropicModel(_ modelID: String) -> Bool {
        let model = modelID.lowercased()
        return model.hasPrefix("claude-")
            || model.hasPrefix("anthropic/")
            || model.hasPrefix("anthropic:")
    }

    static func scopingFastMultiplier(
        _ pricing: ModelPricing,
        requestedModel: String
    ) -> ModelPricing {
        guard pricing.fastMultiplier != 1.0,
              claudeFastMultiplier(for: pricing.modelID) != nil,
              !isFirstPartyAnthropicModel(requestedModel) else {
            return pricing
        }
        return replacingFastMultiplier(pricing, with: 1.0)
    }

    static func replacingFastMultiplier(
        _ pricing: ModelPricing,
        with fast: Double
    ) -> ModelPricing {
        ModelPricing(
            modelID: pricing.modelID,
            displayName: pricing.displayName,
            inputPrice: pricing.inputPrice,
            outputPrice: pricing.outputPrice,
            cacheReadPrice: pricing.cacheReadPrice,
            cacheWritePrice: pricing.cacheWritePrice,
            cacheReadPriceIsExplicit: pricing.cacheReadPriceIsExplicit,
            inputPriceAbove200k: pricing.inputPriceAbove200k,
            outputPriceAbove200k: pricing.outputPriceAbove200k,
            cacheReadPriceAbove200k: pricing.cacheReadPriceAbove200k,
            cacheWritePriceAbove200k: pricing.cacheWritePriceAbove200k,
            longContextThreshold: pricing.longContextThreshold,
            fastMultiplier: fast
        )
    }

    static func applyingLongContextOverlay(
        _ pricing: ModelPricing,
        modelID: String
    ) -> ModelPricing {
        guard pricing.inputPriceAbove200k == nil,
              pricing.outputPriceAbove200k == nil,
              pricing.cacheReadPriceAbove200k == nil,
              pricing.cacheWritePriceAbove200k == nil,
              let rates = longContextRates(for: modelWithoutDateSuffix(modelID)) else {
            return pricing
        }
        return ModelPricing(
            modelID: pricing.modelID,
            displayName: pricing.displayName,
            inputPrice: pricing.inputPrice,
            outputPrice: pricing.outputPrice,
            cacheReadPrice: pricing.cacheReadPrice,
            cacheWritePrice: pricing.cacheWritePrice,
            cacheReadPriceIsExplicit: pricing.cacheReadPriceIsExplicit,
            inputPriceAbove200k: rates.input,
            outputPriceAbove200k: rates.output,
            cacheReadPriceAbove200k: rates.cacheRead,
            cacheWritePriceAbove200k: rates.cacheWrite,
            longContextThreshold: 272_000,
            fastMultiplier: pricing.fastMultiplier
        )
    }

    static func longContextRates(for modelID: String) -> LongContextRates? {
        switch modelID {
        case "gpt-5.6-sol":
            return LongContextRates(input: 8, output: 30, cacheWrite: 10, cacheRead: 0.8)
        case "gpt-5.6-terra":
            return LongContextRates(input: 4, output: 18, cacheWrite: 5, cacheRead: 0.4)
        case "gpt-5.6-luna":
            return LongContextRates(input: 0.4, output: 1.8, cacheWrite: 0.5, cacheRead: 0.04)
        case "gpt-5.5":
            return LongContextRates(input: 10, output: 45, cacheWrite: 10, cacheRead: 1)
        case "gpt-5.4":
            return LongContextRates(input: 5, output: 22.5, cacheWrite: 5, cacheRead: 0.5)
        case "gpt-5.5-pro", "gpt-5.4-pro":
            return LongContextRates(input: 60, output: 270, cacheWrite: nil, cacheRead: nil)
        default:
            return nil
        }
    }

    static func modelWithoutDateSuffix(_ modelID: String) -> String {
        let dashedDate = #"-\d{4}-\d{2}-\d{2}$"#
        let compactDate = #"-\d{8}$"#
        if let range = modelID.range(of: dashedDate, options: .regularExpression) {
            return String(modelID[..<range.lowerBound])
        }
        if let range = modelID.range(of: compactDate, options: .regularExpression) {
            return String(modelID[..<range.lowerBound])
        }
        return modelID
    }
}
