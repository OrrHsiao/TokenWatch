import Foundation

/// DSH 内置的 DeepSeek 系列价格快照。
///
/// ## 为什么需要内置快照
///
/// DSH 自带一份 pi-ai 定价目录（`~/.dsh/profiles/node_modules/@earendil-works/pi-ai/...`），
/// 本模块会在可读时动态加载它并**优先使用**。但在 App Sandbox 下该路径通常是
/// pnpm 符号链接（指向 `~/.npm/_npx/...`），已超出用户授权的 `~/.dsh` 范围，
/// 读取会被系统拒绝。为保证费用列不恒为 0，这里内置一份从 DSH 随包 catalog
/// 抄录的快照作为兜底。
///
/// ## 数据来源与口径
///
/// - 来源：DeepSeek Harness 桌面版内置的 pi-ai provider 数据（本地实测版本，
///   2026-09-29 构建）。键为 `"<route>/<model>"`，另有按模型名的通用兜底键。
/// - 单位：**USD / 1M tokens**（与 pi-ai 目录一致，已用 `anthropic/claude-haiku-4-5`
///   等已知模型交叉验证）。
/// - DSH 的 route 名是自由配置：本机观测到 `opencode-go`、`deepseek-official`
///   等；模型名同样自由（例如 `deepseek-v4.1-flash` 只存在于 DSH 自己的 catalog）。
/// - 价格为快照，会随 DSH 升级变化；动态目录可用时始终以动态数据为准。
enum DeepSeekHarnessBuiltinPrices {
    /// 按 route 精确匹配的价格表。
    static let pricingByRouteAndModel: [String: ModelPricing] = {
        var result: [String: ModelPricing] = [:]
        for entry in entries {
            guard let route = entry.route else { continue }
            result["\(route)/\(entry.model)".lowercased()] = makePricing(entry)
        }
        return result
    }()

    /// 按模型名匹配的兜底价格表。
    ///
    /// 只有未绑定 route 的条目（`route == nil`）参与，避免 route 专属价污染
    /// 「无 route 信息」时的通用兜底；列表按通用性排序，同名条目以最后一条为准。
    static let pricingByModel: [String: ModelPricing] = {
        var result: [String: ModelPricing] = [:]
        for entry in entries where entry.route == nil {
            result[entry.model.lowercased()] = makePricing(entry)
        }
        return result
    }()

    private struct Entry {
        let route: String?
        let model: String
        let input: Double
        let output: Double
        let cacheRead: Double
    }

    private static func makePricing(_ entry: Entry) -> ModelPricing {
        ModelPricing(
            modelID: entry.model,
            displayName: entry.model,
            inputPrice: entry.input,
            outputPrice: entry.output,
            cacheReadPrice: entry.cacheRead,
            cacheWritePrice: 0
        )
    }

    /// route 专属价格在前，通用价格在后（后者供无 route 信息时兜底）。
    private static let entries: [Entry] = [
        // opencode-go（本机 DSH 默认 route）
        Entry(route: "opencode-go", model: "deepseek-v4.1-flash", input: 0.15, output: 0.6, cacheRead: 0.003),
        Entry(route: "opencode-go", model: "deepseek-v4-flash", input: 0.15, output: 0.6, cacheRead: 0.003),
        Entry(route: "opencode-go", model: "deepseek-v4-flash-vision-exp", input: 0.15, output: 0.6, cacheRead: 0.003),
        Entry(route: "opencode-go", model: "deepseek-v4-pro", input: 0.66, output: 1.98, cacheRead: 0.022),
        // opencode（官方 zen 路由，价格高于 opencode-go）
        Entry(route: "opencode", model: "deepseek-v4.1-flash", input: 0.3, output: 1.2, cacheRead: 0.006),
        Entry(route: "opencode", model: "deepseek-v4-flash", input: 0.14, output: 0.28, cacheRead: 0.028),
        Entry(route: "opencode", model: "deepseek-v4-flash-vision-exp", input: 0.14, output: 0.28, cacheRead: 0.028),
        Entry(route: "opencode", model: "deepseek-v4-pro", input: 1.74, output: 3.84, cacheRead: 0.145),
        // DeepSeek 官方 route（DSH 中显示为 deepseek-official）
        Entry(route: "deepseek-official", model: "deepseek-flash", input: 0.3, output: 1.2, cacheRead: 0.006),
        Entry(route: "deepseek-official", model: "deepseek-v4-pro", input: 1.32, output: 3.96, cacheRead: 0.044),
        Entry(route: "deepseek", model: "deepseek-flash", input: 0.3, output: 1.2, cacheRead: 0.006),
        Entry(route: "deepseek", model: "deepseek-v4-flash", input: 0.14, output: 0.28, cacheRead: 0.0028),
        Entry(route: "deepseek", model: "deepseek-v4-flash-vision-exp", input: 0.14, output: 0.28, cacheRead: 0.0028),
        Entry(route: "deepseek", model: "deepseek-v4-pro", input: 1.32, output: 3.96, cacheRead: 0.044),
        // 通用兜底：无 route 信息时按官方价估算
        Entry(route: nil, model: "deepseek-flash", input: 0.3, output: 1.2, cacheRead: 0.006),
        Entry(route: nil, model: "deepseek-v4-flash", input: 0.14, output: 0.28, cacheRead: 0.0028),
        Entry(route: nil, model: "deepseek-v4-flash-vision-exp", input: 0.14, output: 0.28, cacheRead: 0.0028),
        Entry(route: nil, model: "deepseek-v4.1-flash", input: 0.3, output: 1.2, cacheRead: 0.006),
        Entry(route: nil, model: "deepseek-v4-pro", input: 1.32, output: 3.96, cacheRead: 0.044),
    ]
}
