import Foundation

/// 数据源标识 — 与 UI Tab、Bookmark key 一一对应
/// 新增 provider 在此加 case，然后在 ProviderRegistry.allProviders 注册即可
enum ProviderID: String, Sendable, CaseIterable, Hashable, Codable {
    case claude
    case codex
}
