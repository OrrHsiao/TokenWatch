import Foundation

/// 每百万 token 的离线模型价格及 ccusage 计价元数据。
struct ModelPricing: Sendable {
    let modelID: String
    let displayName: String
    let inputPrice: Double
    let outputPrice: Double
    let cacheReadPrice: Double
    let cacheWritePrice: Double
    let cacheReadPriceIsExplicit: Bool
    let inputPriceAbove200k: Double?
    let outputPriceAbove200k: Double?
    let cacheReadPriceAbove200k: Double?
    let cacheWritePriceAbove200k: Double?
    let longContextThreshold: Int?
    let fastMultiplier: Double

    init(
        modelID: String,
        displayName: String,
        inputPrice: Double,
        outputPrice: Double,
        cacheReadPrice: Double,
        cacheWritePrice: Double,
        cacheReadPriceIsExplicit: Bool = true,
        inputPriceAbove200k: Double? = nil,
        outputPriceAbove200k: Double? = nil,
        cacheReadPriceAbove200k: Double? = nil,
        cacheWritePriceAbove200k: Double? = nil,
        longContextThreshold: Int? = nil,
        fastMultiplier: Double = 1.0
    ) {
        self.modelID = modelID
        self.displayName = displayName
        self.inputPrice = inputPrice
        self.outputPrice = outputPrice
        self.cacheReadPrice = cacheReadPrice
        self.cacheWritePrice = cacheWritePrice
        self.cacheReadPriceIsExplicit = cacheReadPriceIsExplicit
        self.inputPriceAbove200k = inputPriceAbove200k
        self.outputPriceAbove200k = outputPriceAbove200k
        self.cacheReadPriceAbove200k = cacheReadPriceAbove200k
        self.cacheWritePriceAbove200k = cacheWritePriceAbove200k
        self.longContextThreshold = longContextThreshold
        self.fastMultiplier = fastMultiplier
    }
}
