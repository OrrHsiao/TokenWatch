import Foundation
import Testing
@testable import TokenWatch

@Suite("ProviderRegistry")
struct ProviderRegistryTests {
    @Test("allProviders 至少含 .claude")
    func containsClaude() {
        let ids = ProviderRegistry.allProviders.map(\.id)
        #expect(ids.contains(.claude))
    }

    @Test("每个 provider 的 bookmarkKey 唯一")
    func bookmarkKeysUnique() {
        let keys = ProviderRegistry.allProviders.map(\.bookmarkKey)
        #expect(Set(keys).count == keys.count)
    }

    @Test("provider(for:) 能按 id 查到对应实例")
    func lookupById() {
        let claude = ProviderRegistry.provider(for: .claude)
        #expect(claude?.id == .claude)
    }

    @Test("allProviders 含 .opencode")
    func containsOpenCode() {
        let ids = ProviderRegistry.allProviders.map(\.id)
        #expect(ids.contains(.opencode))
    }

    @Test("opencode provider 默认目录指向 ~/.local/share/opencode")
    func openCodeDefaultDirectory() {
        let provider = ProviderRegistry.provider(for: .opencode)
        let expected = NSString("~/.local/share/opencode").expandingTildeInPath
        #expect(provider?.defaultDirectoryPath == expected)
    }

    @Test("hasReasoningDimension:仅 opencode=true,Claude/Codex=false")
    func reasoningDimensionFlags() {
        #expect(ProviderRegistry.provider(for: .claude)?.hasReasoningDimension == false)
        #expect(ProviderRegistry.provider(for: .codex)?.hasReasoningDimension == false)
        #expect(ProviderRegistry.provider(for: .opencode)?.hasReasoningDimension == true)
    }
}
