import Foundation

enum OpenCodePricingCandidateResolver {
    /// 按 ccusage OpenCode adapter 的稳定顺序生成本地定价候选。
    /// - Parameters:
    ///   - modelID: OpenCode 返回的真实 model ID；缺失时不可用 provider fallback 计价。
    ///   - providerID: OpenCode 上游 provider 标识。
    /// - Returns: 去重后依次供本地定价查询的 model ID。
    static func candidates(modelID: String?, providerID: String?) -> [String] {
        guard let rawModel = modelID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawModel.isEmpty else { return [] }
        let resolved: String
        switch rawModel {
        case "gemini-3-pro-high": resolved = "gemini-3-pro-preview"
        case "k2p6": resolved = "kimi-k2.6"
        default: resolved = rawModel
        }

        let normalized = normalizeClaudeModel(resolved)
        var base = [resolved]
        if normalized != resolved { base.append(normalized) }
        var result = base
        if let providerID,
           !providerID.isEmpty,
           providerID != "unknown" {
            let provider = providerID.replacingOccurrences(of: "-", with: "_")
            result.append(contentsOf: base.map { "\(provider)/\($0)" })
        }

        var seen: Set<String> = []
        return result.filter { seen.insert($0).inserted }
    }

    private static func normalizeClaudeModel(_ model: String) -> String {
        for family in ["claude-haiku-", "claude-opus-", "claude-sonnet-"] {
            guard model.hasPrefix(family) else { continue }
            let rest = String(model.dropFirst(family.count))
            if let dot = rest.firstIndex(of: ".") {
                let major = rest[..<dot]
                let minorAndSuffix = rest[rest.index(after: dot)...]
                if !major.isEmpty,
                   major.allSatisfy(\.isNumber),
                   minorAndSuffix.first?.isNumber == true {
                    return "\(family)\(major)-\(minorAndSuffix)"
                }
            }
            let chars = Array(rest)
            if chars.count >= 2,
               chars[0].isNumber,
               chars[1].isNumber {
                return "\(family)\(chars[0])-\(String(chars.dropFirst(1)))"
            }
        }
        return model
    }
}
