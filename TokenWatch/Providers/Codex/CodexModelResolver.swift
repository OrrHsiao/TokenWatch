import Foundation

enum CodexModelSource: Sendable, Equatable {
    case explicit
    case fallback
}

struct CodexModelState: Sendable, Equatable {
    let rawModel: String
    let source: CodexModelSource
}

enum CodexModelResolver {
    private static let autoReviewModel = "codex-auto-review"
    private static let fallbackModels: [(releasedOn: String, model: String)] = [
        ("2026-04-23", "gpt-5.5"),
        ("2026-03-05", "gpt-5.4"),
        ("2026-02-05", "gpt-5.3-codex"),
        ("2025-12-11", "gpt-5.2-codex"),
        ("2025-11-13", "gpt-5.1-codex"),
        ("2025-09-15", "gpt-5-codex"),
        ("2025-08-07", "gpt-5"),
    ]

    /// 结合新解析到的模型与当前状态，解析本条 Codex 事件的计价模型。
    /// - Parameters:
    ///   - parsedModel: 当前记录显式携带的模型；为空时沿用现有状态。
    ///   - eventDate: `codex-auto-review` 按固定发布日期映射时使用的 UTC 时间。
    ///   - current: 跨记录保留的模型状态；无模型时写入 `gpt-5` fallback。
    /// - Returns: 本条事件应使用的模型名称。
    static func resolve(
        parsedModel: String?,
        eventDate: Date?,
        current: inout CodexModelState?
    ) -> String {
        if let parsedModel, !parsedModel.isEmpty {
            current = CodexModelState(
                rawModel: parsedModel,
                source: parsedModel == autoReviewModel ? .fallback : .explicit
            )
        }
        if current == nil {
            current = CodexModelState(rawModel: "gpt-5", source: .fallback)
        }
        let state = current!
        guard state.rawModel == autoReviewModel else { return state.rawModel }
        guard let eventDate else { return "gpt-5" }
        let key = dateKey(eventDate)
        return fallbackModels.first { key >= $0.releasedOn }?.model ?? "gpt-5"
    }

    /// 按生产匹配顺序序列化 `codex-auto-review` 固定日期映射。
    static var canonicalAutoReviewFallbacks: Data {
        Data(fallbackModels
            .map { "\($0.releasedOn)\t\($0.model)" }
            .joined(separator: "\n")
            .utf8)
    }

    private static func dateKey(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0
        )
    }
}
