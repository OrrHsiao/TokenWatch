import Foundation
import Testing
@testable import TokenWatch

@Suite("CodexModelResolver")
struct CodexModelResolverTests {
    @Test("无模型回退 gpt-5，真实模型随后覆盖 fallback")
    func missingThenExplicit() {
        var state: CodexModelState?
        let fallback = CodexModelResolver.resolve(
            parsedModel: nil,
            eventDate: date("2026-01-01T00:00:00Z"),
            current: &state
        )
        #expect(fallback == "gpt-5")
        #expect(state?.source == .fallback)

        let explicit = CodexModelResolver.resolve(
            parsedModel: "gpt-real",
            eventDate: date("2026-01-01T00:01:00Z"),
            current: &state
        )
        #expect(explicit == "gpt-real")
        #expect(state == CodexModelState(rawModel: "gpt-real", source: .explicit))
    }

    @Test("codex-auto-review 按 ccusage 固定发布日期映射")
    func autoReviewDateMap() {
        let cases = [
            ("2026-04-23T00:00:00Z", "gpt-5.5"),
            ("2026-03-05T00:00:00Z", "gpt-5.4"),
            ("2026-02-05T00:00:00Z", "gpt-5.3-codex"),
            ("2025-12-11T00:00:00Z", "gpt-5.2-codex"),
            ("2025-11-13T00:00:00Z", "gpt-5.1-codex"),
            ("2025-09-15T00:00:00Z", "gpt-5-codex"),
            ("2025-08-07T00:00:00Z", "gpt-5"),
            ("2025-01-01T00:00:00Z", "gpt-5"),
        ]

        for (timestamp, expected) in cases {
            var state: CodexModelState?
            let resolved = CodexModelResolver.resolve(
                parsedModel: "codex-auto-review",
                eventDate: date(timestamp),
                current: &state
            )
            #expect(resolved == expected, Comment(rawValue: timestamp))
            #expect(state?.source == .fallback)
        }

        var missingDateState: CodexModelState?
        #expect(CodexModelResolver.resolve(
            parsedModel: "codex-auto-review",
            eventDate: nil,
            current: &missingDateState
        ) == "gpt-5")
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
