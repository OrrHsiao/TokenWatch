import Foundation
import os.log

/// LiteLLM 全表定价兜底
///
/// PricingTable 仅维护 ~12 条手写「短名」(用于稳定 displayName / 200k tier / fast multiplier 元数据);
/// 当用户传入的 modelID 在 PricingTable 中精确 / 前缀都查不到时,回退查这个全表。
/// 数据来源:LiteLLM `model_prices_and_context_window.json`,编译时嵌入(见 `litellm_prices.json`)。
///
/// 设计取舍:
/// - 编译时嵌入 → 可在 Sandbox 中可靠加载,无网络依赖,版本随 App 一同发布
/// - 用 per-1M USD 单位与 PricingTable 对齐,加载时已完成 ×1e6 转换
/// - 复用 PricingTable 的「精确 → 前缀 + 版本号守卫」匹配规则,保持 lookup 行为一致
/// - displayName 缺失,直接复用原始 modelID(LiteLLM JSON 不带 displayName 字段)
struct LiteLLMPriceCatalog: Sendable {

    /// 进程内单例;JSON 解析较重,仅在首次访问时执行一次
    static let shared = LiteLLMPriceCatalog()

    /// 标准化 modelID → 定价(已转换为 per-1M USD)
    private let prices: [String: ModelPricing]

    /// 候选 key 按长度倒序的预排序数组(长 key 优先匹配)
    /// 与 PricingTable 同样的策略:模块加载时构造一次,避免每次查找都重排
    private let prefixCandidates: [(key: String, pricing: ModelPricing)]

    private static let logger = Logger(subsystem: "com.xiaoao.TokenWatch", category: "LiteLLMPriceCatalog")

    /// 嵌入资源中每个条目的紧凑字段名
    /// 与 `Pricing/litellm_prices.json` 的写入端保持一致
    private struct RawEntry: Decodable {
        let i: Double           // input_cost per-1M
        let o: Double           // output_cost per-1M
        let cr: Double?         // cache_read_cost per-1M
        let cw: Double?         // cache_creation_cost per-1M
        let i200: Double?       // input_cost_above_200k per-1M
        let o200: Double?       // output_cost_above_200k per-1M
        let cr200: Double?      // cache_read_cost_above_200k per-1M
        let cw200: Double?      // cache_creation_cost_above_200k per-1M
        let f: Double?          // fast multiplier (provider_specific_entry.fast)
    }

    private init() {
        let loaded = Self.loadEmbeddedPrices()
        self.prices = loaded
        self.prefixCandidates = loaded
            .sorted { lhs, rhs in
                if lhs.key.count != rhs.key.count {
                    return lhs.key.count > rhs.key.count
                }
                return lhs.key > rhs.key
            }
            .map { ($0.key, $0.value) }
        Self.logger.info("LiteLLM 定价表加载完成,共 \(loaded.count) 条")
    }

    /// 从 main bundle 加载嵌入资源 `litellm_prices.json`
    /// 失败返回空字典 → catalog 退化为「永远 miss」,不会影响主流程
    private static func loadEmbeddedPrices() -> [String: ModelPricing] {
        guard let url = Bundle.main.url(forResource: "litellm_prices", withExtension: "json") else {
            logger.warning("LiteLLM 兜底资源未找到(litellm_prices.json),catalog 将始终返回 nil")
            return [:]
        }
        do {
            let data = try Data(contentsOf: url)
            let raw = try JSONDecoder().decode([String: RawEntry].self, from: data)
            var out: [String: ModelPricing] = [:]
            out.reserveCapacity(raw.count)
            for (modelID, entry) in raw {
                // LiteLLM JSON 中 cache_read / cache_write 缺失时退化为 0(LiteLLM 上游本就如此处理)
                out[modelID] = ModelPricing(
                    modelID: modelID,
                    displayName: modelID,
                    inputPrice: entry.i,
                    outputPrice: entry.o,
                    cacheReadPrice: entry.cr ?? 0,
                    cacheWritePrice: entry.cw ?? 0,
                    inputPriceAbove200k: entry.i200,
                    outputPriceAbove200k: entry.o200,
                    cacheReadPriceAbove200k: entry.cr200,
                    cacheWritePriceAbove200k: entry.cw200,
                    fastMultiplier: entry.f ?? 1.0
                )
            }
            return out
        } catch {
            logger.error("LiteLLM 定价表解析失败: \(error.localizedDescription)")
            return [:]
        }
    }

    /// 查找定价
    /// 复用 PricingTable 的「精确 → 前缀 + 版本号守卫」匹配语义
    /// - Parameter modelID: 已 lowercased 的模型名
    /// - Returns: 匹配的定价条目,未找到返回 nil
    func pricing(forNormalized modelID: String) -> ModelPricing? {
        if let pricing = prices[modelID] {
            return pricing
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
}
