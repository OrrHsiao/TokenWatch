import Foundation
import os.log

/// pi-ai 定价目录中的单个模型条目（只声明计价相关字段）。
struct DeepSeekHarnessPiAiModel: Decodable, Sendable {
    struct Cost: Decodable, Sendable {
        let input: Double
        let output: Double
        let cacheRead: Double?
        let cacheWrite: Double?
    }

    let id: String?
    let name: String?
    let provider: String?
    let cost: Cost?
}

/// pi-ai 目录文件：`{ "<api>": { "<modelId>": { ... } } }`。
struct DeepSeekHarnessPiAiCatalogFile: Decodable, Sendable {
    let modelsByAPI: [String: [String: DeepSeekHarnessPiAiModel]]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        modelsByAPI = try container.decode([String: [String: DeepSeekHarnessPiAiModel]].self)
    }
}

/// 解析后的 DSH 定价目录。
struct DeepSeekHarnessPriceCatalog: Sendable {
    /// 键为 `"<provider>/<model>"`，用于按 route 精确命中。
    let pricingByRouteAndModel: [String: ModelPricing]
    /// 键为 `"<model>"`，用于 route 未知时兜底。
    let pricingByModel: [String: ModelPricing]

    static let empty = DeepSeekHarnessPriceCatalog(
        pricingByRouteAndModel: [:],
        pricingByModel: [:]
    )

    /// 按候选键查询：先 route 精确，再模型名兜底。
    /// - Parameter key: 已规范化为小写的候选键。
    /// - Returns: 命中的定价；未命中返回 nil。
    func pricing(forKey key: String) -> ModelPricing? {
        pricingByRouteAndModel[key] ?? pricingByModel[key]
    }

    /// 从 pi-ai 目录文件构建。
    /// - Parameter files: `(provider 名, 文件内容)` 列表；provider 名取文件名（与模型 `provider` 字段一致）。
    /// - Returns: 解析后的目录；单个文件损坏时跳过该文件。
    static func parse(files: [(provider: String, data: Data)]) -> DeepSeekHarnessPriceCatalog {
        let decoder = JSONDecoder()
        var byRouteAndModel: [String: ModelPricing] = [:]
        var byModel: [String: ModelPricing] = [:]
        var modelProviderPriority: [String: String] = [:]

        for file in files {
            guard let catalogFile = try? decoder.decode(
                DeepSeekHarnessPiAiCatalogFile.self,
                from: file.data
            ) else { continue }

            for (_, models) in catalogFile.modelsByAPI {
                for (modelID, model) in models {
                    guard let cost = model.cost else { continue }
                    let resolvedModelID = model.id ?? modelID
                    let provider = model.provider ?? file.provider
                    let pricing = ModelPricing(
                        modelID: resolvedModelID,
                        displayName: model.name ?? resolvedModelID,
                        inputPrice: cost.input,
                        outputPrice: cost.output,
                        cacheReadPrice: cost.cacheRead ?? 0,
                        cacheWritePrice: cost.cacheWrite ?? 0,
                        cacheReadPriceIsExplicit: cost.cacheRead != nil
                    )
                    byRouteAndModel["\(provider)/\(resolvedModelID)".lowercased()] = pricing

                    let modelKey = resolvedModelID.lowercased()
                    // 同一模型可能被多个 provider 提供：官方 deepseek 优先，其次取字典序最小者，
                    // 保证同一输入永远命中同一条价格。
                    let existingPriority = modelProviderPriority[modelKey]
                    let shouldReplace: Bool
                    if let existingPriority {
                        if existingPriority == "deepseek", provider != "deepseek" {
                            shouldReplace = false
                        } else if provider == "deepseek", existingPriority != "deepseek" {
                            shouldReplace = true
                        } else {
                            shouldReplace = provider < existingPriority
                        }
                    } else {
                        shouldReplace = true
                    }
                    if shouldReplace {
                        byModel[modelKey] = pricing
                        modelProviderPriority[modelKey] = provider
                    }
                }
            }
        }

        return DeepSeekHarnessPriceCatalog(
            pricingByRouteAndModel: byRouteAndModel,
            pricingByModel: byModel
        )
    }
}

/// DSH 定价来源的线程安全缓存。
///
/// 分两层：
/// 1. **动态目录**：DSH 捆绑的 `@earendil-works/pi-ai` 提供 39 个 provider 的模型价格
///    （纯 JSON）。读取位置已随数据根授权，不需要网络也不依赖 DSH 运行；但该路径
///    在 pnpm 安装下是符号链接，可能因 App Sandbox 授权范围而不可读。
/// 2. **内置快照**：`DeepSeekHarnessBuiltinPrices` 抄录的 DeepSeek 系列价格，
///    在动态目录不可用（沙盒拒绝、profile 未安装）时兜底，保证费用列不恒为 0。
///
/// 目录属于 profile 依赖树，会随 profile 重装/升级变化，因此动态加载只做「尽量读取」。
final class DeepSeekHarnessPriceCatalogStore: @unchecked Sendable {
    /// pi-ai 数据目录相对 `~/.dsh` 的候选位置。
    static let catalogRelativePaths = [
        "profiles/node_modules/@earendil-works/pi-ai/dist/providers/data",
        "profiles/desktop/node_modules/@earendil-works/pi-ai/dist/providers/data",
        "profiles/web/node_modules/@earendil-works/pi-ai/dist/providers/data",
    ]

    static let shared = DeepSeekHarnessPriceCatalogStore()

    private static let logger = Logger(
        subsystem: "com.xiaoao.TokenWatch",
        category: "DeepSeekHarnessPriceCatalog"
    )

    private let lock = NSLock()
    /// 动态加载的 pi-ai 目录；优先于内置快照。
    private var dynamicCatalog: DeepSeekHarnessPriceCatalog = .empty
    /// 内置兜底快照。
    private let builtinCatalog = DeepSeekHarnessPriceCatalog(
        pricingByRouteAndModel: DeepSeekHarnessBuiltinPrices.pricingByRouteAndModel,
        pricingByModel: DeepSeekHarnessBuiltinPrices.pricingByModel
    )
    private var loadedRootPath: String?

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// 已加载的动态目录 route×model 条目数。
    var debugEntryCount: Int {
        withLock { dynamicCatalog.pricingByRouteAndModel.count }
    }

    /// 内置快照的 route×model 条目数。
    var debugBuiltinEntryCount: Int {
        builtinCatalog.pricingByRouteAndModel.count
    }

    /// 从 DSH 主目录刷新定价目录。
    ///
    /// 同一根目录只加载一次；`dshHomeURL` 为 nil 时不改变现有目录，
    /// 避免用户在设置页切换数据源时把已加载的价格清空。
    /// - Parameter dshHomeURL: `~/.dsh`，由 DSH provider 在扫描时提供。
    func refresh(dshHomeURL: URL?) {
        guard let dshHomeURL else { return }
        let rootPath = dshHomeURL.path
        if withLock({ loadedRootPath == rootPath }) { return }

        let files = loadCatalogFiles(dshHome: dshHomeURL)
        guard !files.isEmpty else {
            Self.logger.info(
                "未读取到 DSH 自带的 pi-ai 定价目录（\(rootPath, privacy: .public)），使用内置 DeepSeek 价格快照"
            )
            withLock { loadedRootPath = rootPath }
            return
        }
        let parsed = DeepSeekHarnessPriceCatalog.parse(files: files)
        withLock {
            dynamicCatalog = parsed
            loadedRootPath = rootPath
        }
        Self.logger.info(
            "已加载 DSH 定价目录：\(files.count) 个 provider，\(parsed.pricingByRouteAndModel.count) 条 route×model 价格"
        )
    }

    /// 直接安装一个目录内容（供测试注入，避免依赖本机 DSH 安装）。
    func install(catalog: DeepSeekHarnessPriceCatalog, rootPath: String?) {
        withLock {
            dynamicCatalog = catalog
            loadedRootPath = rootPath
        }
    }

    /// 按键查询价格：键可以是 `"<route>/<model>"` 也可以是 `"<model>"`。
    /// - Parameter key: 由 `DeepSeekHarnessPricingCandidateResolver` 生成的候选键。
    /// - Returns: 命中的定价；未命中返回 nil。
    func pricing(forKey key: String) -> ModelPricing? {
        let normalized = key.lowercased()
        guard !normalized.isEmpty else { return nil }
        return withLock {
            dynamicCatalog.pricing(forKey: normalized)
                ?? builtinCatalog.pricing(forKey: normalized)
        }
    }

    /// 读取所有候选目录下的 `*.json`；返回 `(provider 文件名, 内容)`。
    private func loadCatalogFiles(dshHome: URL) -> [(provider: String, data: Data)] {
        for relativePath in Self.catalogRelativePaths {
            let directoryURL = dshHome.appendingPathComponent(relativePath, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  let entries = try? fileManager.contentsOfDirectory(
                      at: directoryURL,
                      includingPropertiesForKeys: nil,
                      options: [.skipsHiddenFiles]
                  ) else {
                continue
            }
            let files: [(provider: String, data: Data)] = entries
                .filter { $0.pathExtension.lowercased() == "json" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                .compactMap { url in
                    guard let data = try? Data(contentsOf: url) else { return nil }
                    return (url.deletingPathExtension().lastPathComponent, data)
                }
            if !files.isEmpty {
                return files
            }
        }
        return []
    }

    @discardableResult
    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
