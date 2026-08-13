import AppKit
import Foundation
import Testing
@testable import TokenWatch

@MainActor
@Suite("Widget purchase controller")
struct WidgetPurchaseControllerTests {
    @Test("购买卡片文案覆盖全部支持语言并保留 StoreKit 价格")
    func purchaseCopyCoversEverySupportedLanguage() {
        let displayPrice = "¤2.99"

        for language in AppLanguage.allCases {
            let copy = WidgetPurchaseCopy.make(language: language)
            let values = [
                copy.lockedTitle,
                copy.lockedDescription,
                copy.unlockedTitle,
                copy.unlockedDescription,
                copy.lockedStatus,
                copy.unlockedStatus,
                copy.loadingMessage,
                copy.purchasingMessage,
                copy.restoringMessage,
                copy.pendingMessage,
                copy.noPurchaseMessage,
                copy.unavailableMessage,
                copy.failedMessage,
                copy.entitlementPersistenceFailedMessage,
                copy.verificationFailedMessage,
                copy.purchaseUnavailableTitle,
                copy.restoreTitle,
            ]

            #expect(values.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            #expect(copy.purchaseTitle(displayPrice: displayPrice).contains(displayPrice))
        }

        #expect(
            WidgetPurchaseCopy.make(language: .ja).lockedTitle
                != WidgetPurchaseCopy.make(language: .en).lockedTitle
        )
    }

    @Test("产品配置、verified entitlement 与 timeline reload 顺序保持一致")
    func refreshLoadsProductAndPublishesVerifiedEntitlement() async {
        let events = LockedPurchaseEventRecorder()
        let client = FakeWidgetPurchaseClient(product: product, currentEntitlement: true)
        let store = RecordingWidgetEntitlementStore(state: .locked, events: events)
        let reloader = RecordingWidgetPurchaseTimelineReloader(events: events)
        let controller = makeController(client: client, store: store, reloader: reloader)
        var observedStates: [WidgetPurchaseState] = []
        let token = controller.observe { observedStates.append($0) }

        await controller.refresh()

        #expect(WidgetPurchaseController.productID == "com.xiaoao.tokenwatch.widgets.lifetime")
        #expect(WidgetPurchaseController.productID == WidgetSharedConfiguration.widgetLifetimeProductID)
        #expect(client.loadedProductIDs == [WidgetPurchaseController.productID])
        #expect(client.entitlementProductIDs == [WidgetPurchaseController.productID])
        #expect(controller.state == WidgetPurchaseState(
            product: product,
            isUnlocked: true,
            operation: .idle
        ))
        #expect(store.savedStates == [.unlocked])
        #expect(reloader.kinds == widgetKinds)
        #expect(events.values == ["save:unlocked"] + widgetKinds.map { "reload:\($0)" })
        #expect(observedStates.first?.operation == .loading)
        #expect(observedStates.last == controller.state)

        controller.removeObserver(token)
        let observedCount = observedStates.count
        await controller.refresh()
        #expect(store.savedStates == [.unlocked, .unlocked])
        #expect(reloader.kinds == widgetKinds + widgetKinds)
        let refreshEvents: [String] = ["save:unlocked"]
            + widgetKinds.map { "reload:\($0)" }
        let expectedEvents = refreshEvents + refreshEvents
        #expect(events.values == expectedEvents)
        #expect(observedStates.count == observedCount)
    }

    @Test("产品缺失与加载错误保留明确失败状态")
    func refreshReportsProductFailures() async {
        let missingClient = FakeWidgetPurchaseClient(product: nil, currentEntitlement: false)
        let missingController = makeController(client: missingClient)

        await missingController.refresh()

        #expect(missingController.state.product == nil)
        #expect(missingController.state.operation == .failed(.productUnavailable))

        let failingClient = FakeWidgetPurchaseClient(product: product, currentEntitlement: false)
        failingClient.loadError = .load
        let failingController = makeController(client: failingClient)

        await failingController.refresh()

        #expect(failingController.state.product == nil)
        #expect(failingController.state.operation == .failed(.productLoadFailed))
    }

    @Test("refresh 权限写入失败时保留上次已交付状态")
    func refreshPersistenceFailureKeepsDeliveredState() async {
        let client = FakeWidgetPurchaseClient(product: product, currentEntitlement: true)
        let store = RecordingWidgetEntitlementStore(
            state: .locked,
            saveError: .save
        )
        let controller = makeController(client: client, store: store)

        await controller.refresh()

        #expect(controller.state.product == product)
        #expect(!controller.state.isUnlocked)
        #expect(controller.state.operation == .failed(.entitlementPersistenceFailed))
    }

    @Test("verified 购买先保存并刷新小组件，再 finish transaction")
    func verifiedPurchaseUnlocksBeforeFinishing() async {
        let events = LockedPurchaseEventRecorder()
        let transaction = WidgetPurchaseTransaction(
            id: 42,
            productID: WidgetPurchaseController.productID
        )
        let client = FakeWidgetPurchaseClient(
            product: product,
            currentEntitlement: false,
            purchaseResult: .verified(transaction),
            events: events
        )
        let store = RecordingWidgetEntitlementStore(state: .locked, events: events)
        let reloader = RecordingWidgetPurchaseTimelineReloader(events: events)
        let controller = makeController(client: client, store: store, reloader: reloader)
        let window = NSWindow()

        await controller.purchase(in: window)

        #expect(client.purchasedProductIDs == [WidgetPurchaseController.productID])
        #expect(client.purchaseWindow === window)
        #expect(client.finishedTransactionIDs == [42])
        #expect(controller.state.product == product)
        #expect(controller.state.isUnlocked)
        #expect(controller.state.operation == .purchaseCompleted)
        #expect(store.savedStates == [.unlocked])
        #expect(events.values == ["save:unlocked"]
            + widgetKinds.map { "reload:\($0)" }
            + ["finish:42"])
    }

    @Test("pending、取消及未验证交易均不会解锁或 finish")
    func nonVerifiedPurchaseResultsFailClosed() async {
        let cases: [(WidgetPurchaseResult, WidgetPurchaseOperationState)] = [
            (.pending, .purchasePending),
            (.userCancelled, .idle),
            (
                .unverified(productID: WidgetPurchaseController.productID),
                .failed(.purchaseVerificationFailed)
            ),
            (
                .verified(.init(id: 9, productID: "foreign.product")),
                .failed(.purchaseVerificationFailed)
            ),
        ]

        for (result, expectedOperation) in cases {
            let client = FakeWidgetPurchaseClient(
                product: product,
                currentEntitlement: false,
                purchaseResult: result
            )
            let store = RecordingWidgetEntitlementStore(state: .locked)
            let reloader = RecordingWidgetPurchaseTimelineReloader()
            let controller = makeController(client: client, store: store, reloader: reloader)

            await controller.purchase(in: NSWindow())

            #expect(!controller.state.isUnlocked)
            #expect(controller.state.operation == expectedOperation)
            #expect(client.finishedTransactionIDs.isEmpty)
            #expect(store.savedStates.isEmpty)
            #expect(reloader.kinds.isEmpty)
        }
    }

    @Test("购买错误与 entitlement 持久化错误不会误交付内容")
    func purchaseAndPersistenceFailuresDoNotUnlock() async {
        let purchaseClient = FakeWidgetPurchaseClient(product: product, currentEntitlement: false)
        purchaseClient.purchaseError = .purchase
        let purchaseController = makeController(client: purchaseClient)

        await purchaseController.purchase(in: NSWindow())

        #expect(purchaseController.state.operation == .failed(.purchaseFailed))
        #expect(!purchaseController.state.isUnlocked)

        let transaction = WidgetPurchaseTransaction(
            id: 88,
            productID: WidgetPurchaseController.productID
        )
        let persistenceClient = FakeWidgetPurchaseClient(
            product: product,
            currentEntitlement: false,
            purchaseResult: .verified(transaction)
        )
        let failingStore = RecordingWidgetEntitlementStore(
            state: .locked,
            saveError: .save
        )
        let reloader = RecordingWidgetPurchaseTimelineReloader()
        let persistenceController = makeController(
            client: persistenceClient,
            store: failingStore,
            reloader: reloader
        )

        await persistenceController.purchase(in: NSWindow())

        #expect(persistenceController.state.operation == .failed(.entitlementPersistenceFailed))
        #expect(!persistenceController.state.isUnlocked)
        #expect(persistenceClient.finishedTransactionIDs.isEmpty)
        #expect(reloader.kinds.isEmpty)
    }

    @Test("恢复购买只在显式调用 sync 后重查 verified entitlement")
    func restoreSynchronizesThenReconcilesEntitlement() async {
        let events = LockedPurchaseEventRecorder()
        let client = FakeWidgetPurchaseClient(product: product, currentEntitlement: false)
        client.entitlementAfterSync = true
        let store = RecordingWidgetEntitlementStore(state: .locked, events: events)
        let reloader = RecordingWidgetPurchaseTimelineReloader(events: events)
        let controller = makeController(client: client, store: store, reloader: reloader)

        #expect(client.syncCallCount == 0)
        await controller.restorePurchases()

        #expect(client.syncCallCount == 1)
        #expect(client.entitlementProductIDs == [WidgetPurchaseController.productID])
        #expect(controller.state.isUnlocked)
        #expect(controller.state.operation == .restoreCompleted)
        #expect(store.savedStates == [.unlocked])
        #expect(events.values == ["save:unlocked"] + widgetKinds.map { "reload:\($0)" })
    }

    @Test("无历史购买与 sync 错误分别保留可区分状态")
    func restoreReportsNoPurchaseAndSyncFailure() async {
        let emptyClient = FakeWidgetPurchaseClient(product: product, currentEntitlement: false)
        let emptyController = makeController(client: emptyClient)

        await emptyController.restorePurchases()

        #expect(emptyController.state.operation == .noPurchasesToRestore)
        #expect(!emptyController.state.isUnlocked)

        let failingClient = FakeWidgetPurchaseClient(product: product, currentEntitlement: true)
        failingClient.syncError = .sync
        let failingController = makeController(client: failingClient)

        await failingController.restorePurchases()

        #expect(failingController.state.operation == .failed(.restoreFailed))
        #expect(failingClient.entitlementProductIDs.isEmpty)
    }

    @Test("transaction updates 重算撤销状态并仅 finish verified 目标产品")
    func transactionUpdatesReconcileEntitlementAndFilterProducts() async {
        let client = FakeWidgetPurchaseClient(product: product, currentEntitlement: false)
        let store = RecordingWidgetEntitlementStore(state: .locked)
        let reloader = RecordingWidgetPurchaseTimelineReloader()
        let controller = makeController(client: client, store: store, reloader: reloader)

        controller.start()
        let didStart = await eventually {
            client.transactionUpdatesCallCount == 1
                && client.loadedProductIDs.count == 1
                && controller.state.operation == .idle
        }
        #expect(didStart)

        client.currentEntitlement = true
        client.send(.verified(.init(
            id: 100,
            productID: WidgetPurchaseController.productID
        )))
        let didUnlock = await eventually {
            controller.state.isUnlocked && client.finishedTransactionIDs == [100]
        }
        #expect(didUnlock)
        #expect(store.savedStates == [.locked, .unlocked])

        client.currentEntitlement = false
        client.send(.verified(.init(
            id: 101,
            productID: WidgetPurchaseController.productID
        )))
        let didLock = await eventually {
            !controller.state.isUnlocked && client.finishedTransactionIDs == [100, 101]
        }
        #expect(didLock)
        #expect(store.savedStates == [.locked, .unlocked, .locked])
        #expect(reloader.kinds == widgetKinds + widgetKinds + widgetKinds)

        client.send(.verified(.init(id: 102, productID: "foreign.product")))
        await Task.yield()
        #expect(client.finishedTransactionIDs == [100, 101])

        client.send(.unverified(productID: WidgetPurchaseController.productID))
        let didReject = await eventually {
            controller.state.operation == .failed(.purchaseVerificationFailed)
        }
        #expect(didReject)
        #expect(client.finishedTransactionIDs == [100, 101])
        controller.stop()
    }

    @Test("同一生命周期重复 start 不会重复刷新，stop 后可以重新启动")
    func startIsIdempotentUntilStopped() async {
        let client = FakeWidgetPurchaseClient(product: product, currentEntitlement: true)
        let controller = makeController(client: client)

        controller.start()
        let didStart = await eventually {
            client.transactionUpdatesCallCount == 1
                && client.loadedProductIDs.count == 1
                && client.entitlementProductIDs.count == 1
                && controller.state.operation == .idle
        }
        #expect(didStart)

        controller.start()
        await Task.yield()
        #expect(client.transactionUpdatesCallCount == 1)
        #expect(client.loadedProductIDs.count == 1)
        #expect(client.entitlementProductIDs.count == 1)

        controller.stop()
        controller.start()
        let didRestart = await eventually {
            client.transactionUpdatesCallCount == 2
                && client.loadedProductIDs.count == 2
                && client.entitlementProductIDs.count == 2
                && controller.state.operation == .idle
        }
        #expect(didRestart)
        controller.stop()
    }

    @Test("较早 refresh 的结果不会覆盖较新的 verified 购买")
    func staleRefreshCannotOverwriteVerifiedPurchase() async {
        let transaction = WidgetPurchaseTransaction(
            id: 300,
            productID: WidgetPurchaseController.productID
        )
        let client = FakeWidgetPurchaseClient(
            product: product,
            currentEntitlement: false,
            purchaseResult: .verified(transaction)
        )
        let store = RecordingWidgetEntitlementStore(state: .locked)
        let controller = makeController(client: client, store: store)
        client.suspendNextEntitlementCheck = true

        let staleRefresh = Task { @MainActor in
            await controller.refresh()
        }
        let didSuspend = await eventually {
            client.hasSuspendedEntitlementCheck
        }
        #expect(didSuspend)

        await controller.purchase(in: NSWindow())
        #expect(controller.state.isUnlocked)
        #expect(controller.state.operation == .purchaseCompleted)

        client.resumeSuspendedEntitlementCheck(with: .notEntitled)
        await staleRefresh.value

        #expect(controller.state.isUnlocked)
        #expect(controller.state.operation == .purchaseCompleted)
        #expect(store.savedStates == [.unlocked])
        #expect(client.finishedTransactionIDs == [300])
    }

    @Test("DEBUG 审核夹具稳定提供 locked/unlocked 与 $2.99 产品信息")
    func reviewFixturesAreDeterministic() async {
        let locked = WidgetPurchaseReviewFixtures.makeLockedController()
        await locked.refresh()
        #expect(locked.state.product?.displayName == "Unlock All Widgets")
        #expect(locked.state.product?.displayPrice == "$2.99")
        #expect(!locked.state.isUnlocked)

        let unlocked = WidgetPurchaseReviewFixtures.makeUnlockedController()
        await unlocked.refresh()
        #expect(unlocked.state.product == WidgetPurchaseReviewFixtures.product)
        #expect(unlocked.state.isUnlocked)
    }

    @Test("indeterminate 权益查询保留现状不 finish，延迟重查收敛后交付")
    func indeterminateEntitlementRetainsStateAndRechecks() async {
        let client = FakeWidgetPurchaseClient(product: product, currentEntitlement: false)
        let store = RecordingWidgetEntitlementStore(state: .locked)
        let reloader = RecordingWidgetPurchaseTimelineReloader()
        let controller = makeController(
            client: client,
            store: store,
            reloader: reloader,
            entitlementRecheckDelay: .milliseconds(10)
        )

        controller.start()
        let didStart = await eventually {
            client.transactionUpdatesCallCount == 1
                && client.loadedProductIDs.count == 1
                && controller.state.operation == .idle
        }
        #expect(didStart)
        // start 的 refresh 查询到 notEntitled，写入一次 locked
        #expect(store.savedStates == [.locked])

        client.indeterminateEntitlement = true
        client.send(.verified(.init(
            id: 200,
            productID: WidgetPurchaseController.productID
        )))
        let didHandle = await eventually {
            client.entitlementProductIDs.count >= 2
        }
        #expect(didHandle)
        // 目标交易无法验证：保留交易不 finish、不覆盖 entitlement 缓存、不改变解锁状态
        #expect(client.finishedTransactionIDs == [])
        #expect(store.savedStates == [.locked])
        #expect(!controller.state.isUnlocked)

        // StoreKit 恢复可验证后，延迟重查收敛并完成交付
        client.indeterminateEntitlement = false
        client.currentEntitlement = true
        let didConverge = await eventually {
            controller.state.isUnlocked && client.finishedTransactionIDs == [200]
        }
        #expect(didConverge)
        #expect(store.savedStates == [.locked, .unlocked])
        controller.stop()
    }

    private var product: WidgetPurchaseProduct {
        WidgetPurchaseProduct(
            id: WidgetPurchaseController.productID,
            displayName: "Unlock All Widgets",
            description: "Unlock all 7 desktop widgets permanently.",
            displayPrice: "$2.99"
        )
    }

    private var widgetKinds: [String] {
        [
            WidgetSharedConfiguration.heatmapKind,
            WidgetSharedConfiguration.hourlyLineKind,
            WidgetSharedConfiguration.weeklySummaryKind,
            WidgetSharedConfiguration.monthlyBudgetKind,
            WidgetSharedConfiguration.todayAnomalyKind,
            WidgetSharedConfiguration.projectFocusKind,
            WidgetSharedConfiguration.modelFocusKind,
        ]
    }

    private func makeController(
        client: FakeWidgetPurchaseClient,
        store: RecordingWidgetEntitlementStore? = nil,
        reloader: RecordingWidgetPurchaseTimelineReloader? = nil,
        entitlementRecheckDelay: Duration = .seconds(3)
    ) -> WidgetPurchaseController {
        WidgetPurchaseController(
            client: client,
            entitlementStore: store ?? RecordingWidgetEntitlementStore(state: .locked),
            timelineReloader: reloader ?? RecordingWidgetPurchaseTimelineReloader(),
            entitlementRecheckDelay: entitlementRecheckDelay
        )
    }

    private func eventually(
        _ condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0..<200 {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return condition()
    }
}

@MainActor
private final class FakeWidgetPurchaseClient: WidgetPurchaseClient {
    private let updates: AsyncStream<WidgetTransactionUpdate>
    private let continuation: AsyncStream<WidgetTransactionUpdate>.Continuation
    private let events: LockedPurchaseEventRecorder?

    var product: WidgetPurchaseProduct?
    var currentEntitlement: Bool
    var purchaseResult: WidgetPurchaseResult
    var entitlementAfterSync: Bool?
    var loadError: InjectedWidgetPurchaseError?
    var purchaseError: InjectedWidgetPurchaseError?
    var syncError: InjectedWidgetPurchaseError?
    var suspendNextEntitlementCheck = false
    var indeterminateEntitlement = false
    private(set) var loadedProductIDs: [String] = []
    private(set) var purchasedProductIDs: [String] = []
    private(set) weak var purchaseWindow: NSWindow?
    private(set) var entitlementProductIDs: [String] = []
    private(set) var syncCallCount = 0
    private(set) var transactionUpdatesCallCount = 0
    private(set) var finishedTransactionIDs: [UInt64] = []
    private var suspendedEntitlementContinuation: CheckedContinuation<WidgetEntitlementQueryResult, Never>?

    init(
        product: WidgetPurchaseProduct?,
        currentEntitlement: Bool,
        purchaseResult: WidgetPurchaseResult = .userCancelled,
        events: LockedPurchaseEventRecorder? = nil
    ) {
        let pair = AsyncStream<WidgetTransactionUpdate>.makeStream()
        self.updates = pair.stream
        self.continuation = pair.continuation
        self.product = product
        self.currentEntitlement = currentEntitlement
        self.purchaseResult = purchaseResult
        self.events = events
    }

    func loadProduct(productID: String) async throws -> WidgetPurchaseProduct? {
        loadedProductIDs.append(productID)
        if let loadError { throw loadError }
        return product
    }

    func purchase(productID: String, in window: NSWindow) async throws -> WidgetPurchaseResult {
        purchasedProductIDs.append(productID)
        purchaseWindow = window
        if let purchaseError { throw purchaseError }
        return purchaseResult
    }

    func sync() async throws {
        syncCallCount += 1
        if let syncError { throw syncError }
        if let entitlementAfterSync {
            currentEntitlement = entitlementAfterSync
        }
    }

    func currentEntitlementStatus(for productID: String) async -> WidgetEntitlementQueryResult {
        entitlementProductIDs.append(productID)
        if suspendNextEntitlementCheck {
            suspendNextEntitlementCheck = false
            return await withCheckedContinuation { continuation in
                suspendedEntitlementContinuation = continuation
            }
        }
        if indeterminateEntitlement {
            return .indeterminate
        }
        return currentEntitlement ? .entitled : .notEntitled
    }

    var hasSuspendedEntitlementCheck: Bool {
        suspendedEntitlementContinuation != nil
    }

    func resumeSuspendedEntitlementCheck(with result: WidgetEntitlementQueryResult) {
        let continuation = suspendedEntitlementContinuation
        suspendedEntitlementContinuation = nil
        continuation?.resume(returning: result)
    }

    func transactionUpdates() -> AsyncStream<WidgetTransactionUpdate> {
        transactionUpdatesCallCount += 1
        return updates
    }

    func finish(transactionID: UInt64) async {
        finishedTransactionIDs.append(transactionID)
        events?.append("finish:\(transactionID)")
    }

    func send(_ update: WidgetTransactionUpdate) {
        continuation.yield(update)
    }
}

private enum InjectedWidgetPurchaseError: Error {
    case load
    case purchase
    case sync
    case save
}

private final class RecordingWidgetEntitlementStore: WidgetEntitlementStoring, @unchecked Sendable {
    private let lock = NSLock()
    private let saveError: InjectedWidgetPurchaseError?
    private let events: LockedPurchaseEventRecorder?
    private var storedState: WidgetEntitlementState
    private var storedSavedStates: [WidgetEntitlementState] = []

    init(
        state: WidgetEntitlementState,
        saveError: InjectedWidgetPurchaseError? = nil,
        events: LockedPurchaseEventRecorder? = nil
    ) {
        self.storedState = state
        self.saveError = saveError
        self.events = events
    }

    var savedStates: [WidgetEntitlementState] {
        withLock { storedSavedStates }
    }

    func load() -> WidgetEntitlementState {
        withLock { storedState }
    }

    func save(_ state: WidgetEntitlementState) throws {
        events?.append("save:\(state.rawValue)")
        if let saveError { throw saveError }
        withLock {
            storedState = state
            storedSavedStates.append(state)
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private final class RecordingWidgetPurchaseTimelineReloader: WidgetTimelineReloading, @unchecked Sendable {
    private let lock = NSLock()
    private let events: LockedPurchaseEventRecorder?
    private var storedKinds: [String] = []

    init(events: LockedPurchaseEventRecorder? = nil) {
        self.events = events
    }

    var kinds: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storedKinds
    }

    func reloadTimelines(ofKind kind: String) {
        lock.lock()
        storedKinds.append(kind)
        lock.unlock()
        events?.append("reload:\(kind)")
    }
}

private final class LockedPurchaseEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [String] = []

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storedValues
    }

    func append(_ value: String) {
        lock.lock()
        storedValues.append(value)
        lock.unlock()
    }
}
