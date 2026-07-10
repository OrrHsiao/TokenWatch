import Foundation

enum CodexPricingSpeed: Sendable, Equatable {
    case standard
    case fast
}

struct CodexServiceTierResolver: Sendable {
    /// 从 Codex TOML 内容读取文档根部的计价速度。
    /// - Parameter contents: `config.toml` 的完整文本。
    /// - Returns: 顶层 `service_tier` 为 `fast` 或 `priority` 时返回 `.fast`，否则返回 `.standard`。
    static func pricingSpeed(in contents: String) -> CodexPricingSpeed {
        var isTopLevel = true
        for line in contents.split(whereSeparator: \.isNewline) {
            let setting = String(line.split(separator: "#", maxSplits: 1).first ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !setting.isEmpty else { continue }

            // TOML table header 之后的裸 key 都属于该 table；TOML 没有
            // “返回文档根部”的 header，因此一旦进入 section 就保持 false。
            if setting.hasPrefix("[") {
                isTopLevel = false
                continue
            }

            guard isTopLevel else { continue }
            guard let equals = setting.firstIndex(of: "=") else { continue }
            let key = String(setting[..<equals]).trimmingCharacters(in: .whitespaces)
            guard key == "service_tier" else { continue }
            let rawValue = String(setting[setting.index(after: equals)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if rawValue == "fast" || rawValue == "priority" {
                return .fast
            }
        }
        return .standard
    }

    /// 读取 Codex 根目录中的 `config.toml` 并解析计价速度。
    /// - Parameter codexRoot: 包含 `config.toml` 的 `.codex` 目录。
    /// - Returns: 配置不存在、不可读或未启用快速层级时返回 `.standard`。
    func pricingSpeed(at codexRoot: URL) -> CodexPricingSpeed {
        let configURL = codexRoot.appendingPathComponent("config.toml")
        guard let contents = try? String(contentsOf: configURL, encoding: .utf8) else {
            return .standard
        }
        return Self.pricingSpeed(in: contents)
    }
}
