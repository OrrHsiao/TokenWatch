import Foundation
import os.log

struct CatalogPricingEntry: Sendable {
    let pricing: ModelPricing
    let explicitFastMultiplier: Double?
}

/// 解码并查询 ccusage 固定版本的 LiteLLM 离线价格快照。
struct LiteLLMPriceCatalog: Sendable {
    static let shared = Self.loadEmbeddedCatalog()

    let entries: [String: CatalogPricingEntry]

    private let prefixCandidates: [(key: String, pricing: ModelPricing)]

    private static let logger = Logger(
        subsystem: "com.xiaoao.TokenWatch",
        category: "LiteLLMPriceCatalog"
    )

    private struct RawEntry: Decodable {
        let i: Double?
        let o: Double?
        let cc: Double?
        let cr: Double?
        let ia: Double?
        let oa: Double?
        let cca: Double?
        let cra: Double?
        let ctx: Int?
        let fast: Double?
    }

    /// 解码 compact LiteLLM JSON，并仅保留 ccusage embedded 前缀的完整价格条目。
    /// - Parameter data: 单价单位为 per-token USD 的 compact JSON 数据。
    init(data: Data) throws {
        let raw = try JSONDecoder().decode([String: RawEntry].self, from: data)
        var decoded: [String: CatalogPricingEntry] = [:]
        for (modelID, entry) in raw where Self.isEmbeddedModel(modelID) {
            guard let inputPerToken = entry.i, let outputPerToken = entry.o else { continue }
            let input = inputPerToken * 1_000_000.0
            let output = outputPerToken * 1_000_000.0
            let cacheReadIsExplicit = entry.cr != nil
            let pricing = ModelPricing(
                modelID: modelID.lowercased(),
                displayName: modelID,
                inputPrice: input,
                outputPrice: output,
                cacheReadPrice: entry.cr.map { $0 * 1_000_000.0 } ?? input * 0.1,
                cacheWritePrice: entry.cc.map { $0 * 1_000_000.0 } ?? input * 1.25,
                cacheReadPriceIsExplicit: cacheReadIsExplicit,
                inputPriceAbove200k: entry.ia.map { $0 * 1_000_000.0 },
                outputPriceAbove200k: entry.oa.map { $0 * 1_000_000.0 },
                cacheReadPriceAbove200k: entry.cra.map { $0 * 1_000_000.0 },
                cacheWritePriceAbove200k: entry.cca.map { $0 * 1_000_000.0 },
                fastMultiplier: entry.fast ?? 1.0
            )
            decoded[modelID.lowercased()] = CatalogPricingEntry(
                pricing: pricing,
                explicitFastMultiplier: entry.fast
            )
        }
        entries = decoded
        prefixCandidates = Self.makePrefixCandidates(from: decoded)
    }

    private init(entries: [String: CatalogPricingEntry]) {
        self.entries = entries
        self.prefixCandidates = Self.makePrefixCandidates(from: entries)
    }

    /// 判断模型 ID 是否属于 ccusage 嵌入快照的 provider 前缀集合。
    /// - Parameter modelID: LiteLLM 模型 ID。
    /// - Returns: 该条目是否应被嵌入。
    static func isEmbeddedModel(_ modelID: String) -> Bool {
        [
            "claude-", "anthropic.", "anthropic/", "us.anthropic.",
            "eu.anthropic.", "global.anthropic.", "jp.anthropic.",
            "au.anthropic.", "gpt-", "openai/", "azure/", "zai/",
            "openrouter/openai/",
        ].contains { modelID.hasPrefix($0) }
    }

    /// 按标准化模型 ID 查找价格，保留基线 PricingTable 使用的精确/前缀兼容语义。
    /// - Parameter modelID: 已转换为小写的模型 ID。
    /// - Returns: 匹配价格；无匹配时返回 nil。
    func pricing(forNormalized modelID: String) -> ModelPricing? {
        if let entry = entries[modelID] {
            return entry.pricing
        }
        for (key, pricing) in prefixCandidates {
            guard modelID.hasPrefix(key) else { continue }
            let suffix = String(modelID.dropFirst(key.count))
            if suffix.isEmpty { return pricing }
            if PricingTable.suffixStartsWithNumericVersion(candidate: key, suffix: suffix) {
                continue
            }
            return pricing
        }
        return nil
    }

    private static func loadEmbeddedCatalog() -> LiteLLMPriceCatalog {
        guard let url = Bundle.main.url(forResource: "litellm_prices", withExtension: "json") else {
            logger.warning("LiteLLM 定价快照未找到，catalog 将始终返回 nil")
            return LiteLLMPriceCatalog(entries: [:])
        }
        do {
            let catalog = try LiteLLMPriceCatalog(data: Data(contentsOf: url))
            logger.info("LiteLLM 定价快照加载完成，共 \(catalog.entries.count) 条")
            return catalog
        } catch {
            logger.error("LiteLLM 定价快照解码失败: \(error.localizedDescription)")
            return LiteLLMPriceCatalog(entries: [:])
        }
    }

    private static func makePrefixCandidates(
        from entries: [String: CatalogPricingEntry]
    ) -> [(key: String, pricing: ModelPricing)] {
        entries
            .sorted { lhs, rhs in
                if lhs.key.count != rhs.key.count {
                    return lhs.key.count > rhs.key.count
                }
                return lhs.key > rhs.key
            }
            .map { ($0.key, $0.value.pricing) }
    }
}
