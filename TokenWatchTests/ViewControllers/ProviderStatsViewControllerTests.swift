import Testing
@testable import TokenWatch

@Suite("ProviderStatsViewController")
struct ProviderStatsViewControllerTests {
    @Test("未授权提示只展示用户目录")
    func authorizationCopyUsesHomeDirectory() {
        let provider = ClaudeProvider()

        #expect(ProviderStatsViewController.authorizationStatusText(for: provider) == "TokenWatch 想访问用户目录\n以统计 Claude Code Token 用量")
        #expect(ProviderStatsViewController.authorizationButtonTitle == "授权访问用户目录")
    }
}
