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
}
