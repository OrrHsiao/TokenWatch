import Foundation

/// 一组数据源在聚合视图中共同暴露的可选用量维度。
///
/// Dashboard 的 token/费用明细行可能同时汇总多个 provider（也可被下拉框收窄到单个），
/// 因此单一 provider 的能力位无法直接决定是否展示某维度：这里按「任一被选中的
/// provider 声明支持即视为该维度可用」求并集。是否真正渲染仍由数值是否大于 0 决定，
/// 这样既不会在支持该维度的数据源上隐藏真实数据，也不会留下恒为 0 的空行。
struct UsageDimensionCapabilities: Sendable, Equatable {
    /// 选中的数据源中是否至少有一个会产出 cache write token。
    let hasCacheWrite: Bool
    /// 选中的数据源中是否至少有一个会产出 reasoning token。
    let hasReasoning: Bool

    /// 没有任何数据源参与聚合时的保守取值。
    static let none = UsageDimensionCapabilities(hasCacheWrite: false, hasReasoning: false)
}

/// 全部已注册 provider 的静态注册表
/// 新增 provider 在此追加一行即可，UI / ViewModel 自动感知
enum ProviderRegistry {
    /// 顺序即 UI Tab 顺序
    static let allProviders: [any UsageProvider] = [
        ClaudeProvider(),
        CodexProvider(),
        OpenCodeProvider(),
        AntigravityProvider(),
        DeepSeekHarnessProvider()
    ]

    /// 按 id 查找已注册的 provider 实例
    /// - Parameter id: provider 标识
    /// - Returns: 匹配的 provider；未注册时返回 nil
    static func provider(for id: ProviderID) -> (any UsageProvider)? {
        allProviders.first(where: { $0.id == id })
    }

    /// 汇总指定数据源的可选维度能力并集。
    /// - Parameter ids: 当前视图选中的数据源标识。
    /// - Returns: 各可选维度是否至少被一个已注册数据源支持；未注册的 id 被忽略。
    static func capabilities(
        for ids: some Sequence<ProviderID>
    ) -> UsageDimensionCapabilities {
        var hasCacheWrite = false
        var hasReasoning = false
        for id in ids {
            guard let provider = provider(for: id) else { continue }
            hasCacheWrite = hasCacheWrite || provider.hasCacheWriteDimension
            hasReasoning = hasReasoning || provider.hasReasoningDimension
        }
        return UsageDimensionCapabilities(
            hasCacheWrite: hasCacheWrite,
            hasReasoning: hasReasoning
        )
    }
}
