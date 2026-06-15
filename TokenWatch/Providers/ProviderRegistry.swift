import Foundation

/// 全部已注册 provider 的静态注册表
/// 新增 provider 在此追加一行即可，UI / ViewModel 自动感知
enum ProviderRegistry {
    /// 顺序即 UI Tab 顺序
    static let allProviders: [any UsageProvider] = [
        ClaudeProvider(),
        CodexProvider(),
        OpenCodeProvider()
    ]

    /// 按 id 查找已注册的 provider 实例
    /// - Parameter id: provider 标识
    /// - Returns: 匹配的 provider；未注册时返回 nil
    static func provider(for id: ProviderID) -> (any UsageProvider)? {
        allProviders.first(where: { $0.id == id })
    }
}
