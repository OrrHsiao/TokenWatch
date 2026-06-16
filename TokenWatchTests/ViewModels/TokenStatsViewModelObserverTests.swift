import Testing
@testable import TokenWatch

@MainActor
struct TokenStatsViewModelObserverTests {

    /// 多个 observer 都能收到通知
    @Test func multipleObserversAllReceiveNotification() async throws {
        let vm = TokenStatsViewModel()

        var firstReceived: [ProviderID] = []
        var secondReceived: [ProviderID] = []

        _ = vm.observe { id in firstReceived.append(id) }
        _ = vm.observe { id in secondReceived.append(id) }

        // 触发未授权路径,会同步 notify 一次
        await vm.loadStats(for: .claude)

        #expect(firstReceived.contains(.claude))
        #expect(secondReceived.contains(.claude))
    }

    /// removeObserver 之后该 observer 不再收到
    @Test func removedObserverStopsReceiving() async throws {
        let vm = TokenStatsViewModel()

        var received: [ProviderID] = []
        let token = vm.observe { id in received.append(id) }

        vm.removeObserver(token)

        await vm.loadStats(for: .claude)

        #expect(received.isEmpty)
    }

    /// 不同 observer 拿到的 token 不同(可独立移除)
    @Test func observeReturnsDistinctTokens() {
        let vm = TokenStatsViewModel()
        let t1 = vm.observe { _ in }
        let t2 = vm.observe { _ in }
        #expect(t1 != t2)
    }

    /// 用户目录授权是共享的:任一 provider 授权成功后,同 key 的其它 provider 也应退出未授权态
    @Test func sharedBookmarkAuthorizationUpdatesAllProviders() {
        let vm = TokenStatsViewModel()
        var received: [ProviderID] = []
        _ = vm.observe { id in received.append(id) }

        vm.markProvidersAuthorized(sharingBookmarkWith: ClaudeProvider())

        #expect(ProviderRegistry.allProviders.allSatisfy {
            vm.states[$0.id]?.needsAuthorization == false
        })
        #expect(Set(received) == Set(ProviderRegistry.allProviders.map(\.id)))
    }
}
