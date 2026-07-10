import Foundation

/// 解码 ccusage 固定版本的 models.dev 离线价格快照。
struct ModelsDevPriceCatalog: Sendable {
    let entries: [String: ModelPricing]

    private struct RawModel: Decodable {
        let cost: RawCost?
    }

    private struct RawCost: Decodable {
        let input: Double?
        let output: Double?
        let cache_read: Double?
        let cache_write: Double?
    }

    /// 解码 models.dev JSON，忽略缺少 input 或 output 价格的条目。
    /// - Parameter data: 单价单位为 per-million USD 的 models.dev JSON 数据。
    init(data: Data) throws {
        let raw = try JSONDecoder().decode([String: RawModel].self, from: data)
        var decoded: [String: ModelPricing] = [:]
        for (modelID, model) in raw {
            guard let cost = model.cost,
                  let input = cost.input,
                  let output = cost.output else { continue }
            decoded[modelID.lowercased()] = ModelPricing(
                modelID: modelID.lowercased(),
                displayName: modelID,
                inputPrice: input,
                outputPrice: output,
                cacheReadPrice: cost.cache_read ?? input * 0.1,
                cacheWritePrice: cost.cache_write ?? input * 1.25,
                cacheReadPriceIsExplicit: cost.cache_read != nil
            )
        }
        entries = decoded
    }
}
