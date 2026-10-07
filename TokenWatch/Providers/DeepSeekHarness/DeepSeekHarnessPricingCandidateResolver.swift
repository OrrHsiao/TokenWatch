import Foundation

/// DSH 逐条记录的计价候选键生成。
///
/// DSH 的 route（`source.provider`）与模型名都是**自由配置**，不是受校验的枚举：
/// 例如 `deepseek-v4.1-flash` 只出现在用户自己的 profile 配置里，DSH 自带的
/// pi-ai 定价目录可能尚未收录。因此这里按「越精确越优先」的顺序给出候选键，
/// 由调用方逐个精确匹配，绝不模糊猜到无关模型上。
enum DeepSeekHarnessPricingCandidateResolver {
    /// 生成计价候选键。
    /// - Parameters:
    ///   - modelID: 日志中的模型名（`source.model`）。
    ///   - providerID: 日志中的上游 route（`source.provider`）。
    /// - Returns: 去重后的候选键，顺序即优先级。
    static func candidates(modelID: String?, providerID: String?) -> [String] {
        let model = modelID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !model.isEmpty else { return [] }
        let route = providerID?.trimmingCharacters(in: .whitespacesAndNewlines)

        var candidates: [String] = []
        func append(_ value: String) {
            guard !value.isEmpty, !candidates.contains(value) else { return }
            candidates.append(value)
        }

        if let route, !route.isEmpty {
            append("\(route)/\(model)")
        }
        append(model)

        // 次版本归并：`deepseek-v4.1-flash` → `deepseek-v4-flash`。
        // 只在同一 route 内退化为已知同系列模型，避免跨系列错配。
        if let folded = minorVersionFolded(model), folded != model {
            if let route, !route.isEmpty {
                append("\(route)/\(folded)")
            }
            append(folded)
        }
        return candidates
    }

    /// 去掉模型名中**最后一段** `.<数字>` 次版本片段，得到同系列主版本名。
    ///
    /// 仅当 `.数字` 前一个字符也是数字、且后一个字符不是数字时才折叠，
    /// 因此 `deepseek-v4.1-flash` → `deepseek-v4-flash`、
    /// `deepseek-v4.1.2-flash` → `deepseek-v4.1-flash`（只退一级）。
    /// 折叠结果仍需在定价表中**精确命中**才会生效，不会误配到别的模型。
    /// - Parameter model: 原始模型名。
    /// - Returns: 折叠后的模型名；无可折叠片段时返回 nil。
    static func minorVersionFolded(_ model: String) -> String? {
        let characters = Array(model)
        var index = characters.count - 1
        while index > 0 {
            defer { index -= 1 }
            guard characters[index] == "." else { continue }
            let previousIndex = index - 1
            guard characters[previousIndex].isNumber else { continue }
            var digitEnd = index + 1
            while digitEnd < characters.count, characters[digitEnd].isNumber {
                digitEnd += 1
            }
            guard digitEnd > index + 1 else { continue }

            var folded = String(characters[0..<index])
            folded.append(contentsOf: characters[digitEnd...])
            return folded.isEmpty ? nil : folded
        }
        return nil
    }
}
