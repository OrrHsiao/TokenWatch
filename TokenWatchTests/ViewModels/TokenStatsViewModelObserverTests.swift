import Foundation
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

    /// 同一 provider 已在刷新时,后续刷新请求应被挡掉;不同 provider 不互相影响
    @Test func providerLoadGateRejectsDuplicateInFlightLoads() {
        var gate = ProviderLoadGate()

        let firstClaudeEnter = gate.enter(.claude)
        let secondClaudeEnter = gate.enter(.claude)
        let codexEnter = gate.enter(.codex)

        #expect(firstClaudeEnter)
        #expect(!secondClaudeEnter)
        #expect(codexEnter)

        gate.leave(.claude)
        let thirdClaudeEnter = gate.enter(.claude)
        #expect(thirdClaudeEnter)
    }

    /// 用户可见错误信息应按当前语言生成,同时保留底层错误描述。
    @Test func localizedErrorMessagesUseAppStrings() {
        let error = StubLocalizedError(description: "disk read failed")

        #expect(TokenStatsViewModel.cannotAccessHomeMessage(language: .zhHans) == "无法访问用户目录,请重新授权")
        #expect(TokenStatsViewModel.cannotAccessHomeMessage(language: .en) == "Cannot access home folder. Please authorize again")
        #expect(TokenStatsViewModel.loadFailedMessage(error: error, language: .zhHans) == "数据加载失败: disk read failed")
        #expect(TokenStatsViewModel.loadFailedMessage(error: error, language: .en) == "Data load failed: disk read failed")
    }
}

private struct StubLocalizedError: LocalizedError {
    let description: String
    var errorDescription: String? { description }
}
