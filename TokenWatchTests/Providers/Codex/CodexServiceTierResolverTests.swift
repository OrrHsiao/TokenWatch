import Testing
@testable import TokenWatch

@Suite("CodexServiceTierResolver")
struct CodexServiceTierResolverTests {
    @Test("只识别顶层 service_tier fast 或 priority")
    func detectsFastAndPriority() {
        #expect(CodexServiceTierResolver.pricingSpeed(
            in: #"service_tier = "fast""#
        ) == .fast)
        #expect(CodexServiceTierResolver.pricingSpeed(
            in: "service_tier = 'priority' # higher tier"
        ) == .fast)
        #expect(CodexServiceTierResolver.pricingSpeed(
            in: #"service_tier = "standard""#
        ) == .standard)
        #expect(CodexServiceTierResolver.pricingSpeed(
            in: #"service_tier_override = "fast""#
        ) == .standard)
        #expect(CodexServiceTierResolver.pricingSpeed(
            in: #"service_tier = "breakfast""#
        ) == .standard)
    }

    @Test("TOML table 内同名 service_tier 不得冒充顶层设置")
    func rejectsServiceTierInsideTables() {
        let nestedConfigurations = [
            """
            [model_providers.openai]
            service_tier = "fast"
            """,
            """
            [profiles.fast]
            model = "gpt-5.4"
            service_tier = "priority"
            """,
            """
            [[profiles]]
            name = "fast"
            service_tier = "fast"
            """,
        ]

        for contents in nestedConfigurations {
            #expect(
                CodexServiceTierResolver.pricingSpeed(in: contents) == .standard,
                Comment(rawValue: contents)
            )
        }

        #expect(CodexServiceTierResolver.pricingSpeed(in: """
        service_tier = "priority"
        [profiles.default]
        service_tier = "standard"
        """) == .fast)
    }
}
