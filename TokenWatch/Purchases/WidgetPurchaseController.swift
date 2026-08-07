import AppKit
import os.log

enum WidgetPurchaseFailure: Equatable, Sendable {
    case productUnavailable
    case productLoadFailed
    case purchaseFailed
    case purchaseVerificationFailed
    case restoreFailed
    case entitlementPersistenceFailed
}

enum WidgetPurchaseOperationState: Equatable, Sendable {
    case idle
    case loading
    case purchasing
    case purchasePending
    case purchaseCompleted
    case restoring
    case restoreCompleted
    case noPurchasesToRestore
    case failed(WidgetPurchaseFailure)
}

struct WidgetPurchaseState: Equatable, Sendable {
    var product: WidgetPurchaseProduct?
    var isUnlocked: Bool
    var operation: WidgetPurchaseOperationState

    static let initial = WidgetPurchaseState(
        product: nil,
        isUnlocked: false,
        operation: .idle
    )
}

/// Coordinates StoreKit state, purchase actions, restore, and UI observation on the main actor.
@MainActor
final class WidgetPurchaseController {
    struct ObservationToken: Hashable, Sendable {
        let id: UUID
    }

    static let productID = WidgetSharedConfiguration.widgetLifetimeProductID

    private(set) var state = WidgetPurchaseState.initial

    private let client: any WidgetPurchaseClient
    private let entitlementStore: any WidgetEntitlementStoring
    private let timelineReloader: any WidgetTimelineReloading
    private let logger = Logger(
        subsystem: "com.xiaoao.TokenWatch",
        category: "WidgetPurchaseController"
    )
    private var observers: [ObservationToken: @MainActor (WidgetPurchaseState) -> Void] = [:]
    private var transactionUpdatesTask: Task<Void, Never>?
    private var initialRefreshTask: Task<Void, Never>?
    private var operationGeneration: UInt64 = 0

    init(
        client: any WidgetPurchaseClient = StoreKitWidgetPurchaseClient(),
        entitlementStore: any WidgetEntitlementStoring,
        timelineReloader: any WidgetTimelineReloading = WidgetKitTimelineReloader()
    ) {
        self.client = client
        self.entitlementStore = entitlementStore
        self.timelineReloader = timelineReloader
    }

    /// Creates the production controller with StoreKit and the shared App Group entitlement cache.
    /// - Returns: A controller ready for `start()`.
    /// - Throws: `WidgetEntitlementStoreError` when the App Group container cannot be resolved.
    static func makeLive() throws -> WidgetPurchaseController {
        WidgetPurchaseController(
            client: StoreKitWidgetPurchaseClient(),
            entitlementStore: try AppGroupWidgetEntitlementStore.appGroupStore()
        )
    }

    /// Starts one long-lived transaction listener and refreshes product and entitlement state.
    func start() {
        if transactionUpdatesTask == nil {
            let updates = client.transactionUpdates()
            transactionUpdatesTask = Task { @MainActor [weak self] in
                for await update in updates {
                    guard let self, !Task.isCancelled else { break }
                    await self.handle(update)
                }
            }
        }

        guard initialRefreshTask == nil else { return }
        initialRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.refresh()
        }
    }

    /// Stops background observation without changing the last user-visible purchase state.
    func stop() {
        invalidatePendingOperations()
        transactionUpdatesTask?.cancel()
        transactionUpdatesTask = nil
        initialRefreshTask?.cancel()
        initialRefreshTask = nil
    }

    /// Loads localized product metadata and reconciles the verified current entitlement.
    func refresh() async {
        let generation = beginOperation()
        setOperation(.loading)
        var product = state.product
        var failure: WidgetPurchaseFailure?

        do {
            let loadedProduct = try await client.loadProduct(productID: Self.productID)
            if loadedProduct?.id == Self.productID {
                product = loadedProduct
                logger.info("Widget unlock product loaded")
            } else {
                product = nil
                failure = .productUnavailable
                logger.error("Widget unlock product is unavailable")
            }
        } catch {
            failure = .productLoadFailed
            logger.error("Widget unlock product load failed: \(String(describing: error), privacy: .private)")
        }
        guard isCurrentOperation(generation) else { return }

        let isUnlocked = await client.hasVerifiedCurrentEntitlement(productID: Self.productID)
        guard isCurrentOperation(generation) else { return }
        do {
            try persistEntitlement(isUnlocked)
            logger.info("Widget entitlement refresh completed; unlocked=\(isUnlocked)")
        } catch {
            logger.error("Widget entitlement persistence failed during refresh")
            updateState { next in
                next.product = product
                // Keep the last delivered state when the extension cache could not be updated.
                next.operation = .failed(.entitlementPersistenceFailed)
            }
            return
        }

        updateState { next in
            next.product = product
            next.isUnlocked = isUnlocked
            next.operation = failure.map(WidgetPurchaseOperationState.failed) ?? .idle
        }
    }

    /// Purchases the lifetime unlock and finishes only a verified matching transaction.
    /// - Parameter window: The AppKit window that owns the StoreKit purchase sheet.
    func purchase(in window: NSWindow) async {
        let generation = beginOperation()
        guard await ensureProductIsLoaded(operationGeneration: generation),
              isCurrentOperation(generation) else { return }
        setOperation(.purchasing)
        logger.info("Widget unlock purchase started")

        do {
            switch try await client.purchase(productID: Self.productID, in: window) {
            case .verified(let transaction) where transaction.productID == Self.productID:
                // A verified purchase result is a newer entitlement event even if a refresh or
                // Transaction.updates callback ran while the App Store sheet was presented.
                _ = beginOperation()
                do {
                    try persistEntitlement(true)
                } catch {
                    setOperation(.failed(.entitlementPersistenceFailed))
                    logger.error("Verified widget purchase could not persist entitlement")
                    return
                }

                updateState { next in
                    next.isUnlocked = true
                    next.operation = .purchaseCompleted
                }
                // Content access and its cross-process flag are established before finishing.
                await client.finish(transactionID: transaction.id)
                logger.info("Verified widget unlock purchase completed")
            case .verified:
                guard isCurrentOperation(generation) else { return }
                setOperation(.failed(.purchaseVerificationFailed))
                logger.error("Widget purchase returned a verified transaction for another product")
            case .unverified:
                guard isCurrentOperation(generation) else { return }
                setOperation(.failed(.purchaseVerificationFailed))
                logger.error("Widget purchase transaction verification failed")
            case .pending:
                guard isCurrentOperation(generation) else { return }
                setOperation(.purchasePending)
                logger.info("Widget unlock purchase is pending")
            case .userCancelled:
                guard isCurrentOperation(generation) else { return }
                setOperation(.idle)
                logger.info("Widget unlock purchase was cancelled")
            }
        } catch {
            guard isCurrentOperation(generation) else { return }
            setOperation(.failed(.purchaseFailed))
            logger.error("Widget unlock purchase failed: \(String(describing: error), privacy: .private)")
        }
    }

    /// Restores purchases only after an explicit UI action, then rechecks verified entitlements.
    func restorePurchases() async {
        let generation = beginOperation()
        setOperation(.restoring)
        logger.info("Widget purchase restore started")

        do {
            try await client.sync()
            guard isCurrentOperation(generation) else { return }
            let isUnlocked = await client.hasVerifiedCurrentEntitlement(productID: Self.productID)
            guard isCurrentOperation(generation) else { return }
            do {
                try persistEntitlement(isUnlocked)
            } catch {
                setOperation(.failed(.entitlementPersistenceFailed))
                logger.error("Restored widget entitlement could not be persisted")
                return
            }

            updateState { next in
                next.isUnlocked = isUnlocked
                next.operation = isUnlocked ? .restoreCompleted : .noPurchasesToRestore
            }
            logger.info("Widget purchase restore completed; unlocked=\(isUnlocked)")
        } catch {
            guard isCurrentOperation(generation) else { return }
            setOperation(.failed(.restoreFailed))
            logger.error("Widget purchase restore failed: \(String(describing: error), privacy: .private)")
        }
    }

    /// Registers a synchronous main-actor state observer.
    /// - Parameter handler: Called after a semantically different state is committed.
    /// - Returns: A token that can later remove the observer.
    @discardableResult
    func observe(
        _ handler: @escaping @MainActor (WidgetPurchaseState) -> Void
    ) -> ObservationToken {
        let token = ObservationToken(id: UUID())
        observers[token] = handler
        return token
    }

    /// Removes a previously registered state observer.
    /// - Parameter token: The token returned by `observe(_:)`.
    func removeObserver(_ token: ObservationToken) {
        observers.removeValue(forKey: token)
    }

    private func ensureProductIsLoaded(operationGeneration generation: UInt64) async -> Bool {
        if state.product?.id == Self.productID {
            return true
        }

        setOperation(.loading)
        do {
            guard let product = try await client.loadProduct(productID: Self.productID),
                  product.id == Self.productID else {
                guard isCurrentOperation(generation) else { return false }
                setOperation(.failed(.productUnavailable))
                logger.error("Widget unlock product is unavailable before purchase")
                return false
            }
            guard isCurrentOperation(generation) else { return false }
            updateState { next in
                next.product = product
                next.operation = .idle
            }
            return true
        } catch {
            guard isCurrentOperation(generation) else { return false }
            setOperation(.failed(.productLoadFailed))
            logger.error("Widget unlock product load failed before purchase")
            return false
        }
    }

    private func handle(_ update: WidgetTransactionUpdate) async {
        switch update {
        case .verified(let transaction) where transaction.productID == Self.productID:
            let generation = beginOperation()
            let isUnlocked = await client.hasVerifiedCurrentEntitlement(productID: Self.productID)
            guard isCurrentOperation(generation) else { return }
            do {
                try persistEntitlement(isUnlocked)
            } catch {
                setOperation(.failed(.entitlementPersistenceFailed))
                logger.error("Widget transaction update could not persist entitlement")
                return
            }

            updateState { next in
                next.isUnlocked = isUnlocked
                next.operation = isUnlocked ? .purchaseCompleted : .idle
            }
            await client.finish(transactionID: transaction.id)
            logger.info("Verified widget transaction update applied; unlocked=\(isUnlocked)")
        case .verified:
            return
        case .unverified(let productID) where productID == Self.productID:
            _ = beginOperation()
            setOperation(.failed(.purchaseVerificationFailed))
            logger.error("Widget transaction update verification failed")
        case .unverified:
            return
        }
    }

    private func beginOperation() -> UInt64 {
        operationGeneration &+= 1
        return operationGeneration
    }

    private func invalidatePendingOperations() {
        operationGeneration &+= 1
    }

    private func isCurrentOperation(_ generation: UInt64) -> Bool {
        generation == operationGeneration
    }

    private func setOperation(_ operation: WidgetPurchaseOperationState) {
        updateState { $0.operation = operation }
    }

    /// Persists before reloading timelines so the extension never observes the old gate state.
    private func persistEntitlement(_ isUnlocked: Bool) throws {
        let next: WidgetEntitlementState = isUnlocked ? .unlocked : .locked
        // StoreKit is authoritative. Always replace the fail-closed cache because `load()` cannot
        // distinguish a confirmed locked record from a temporarily unreadable unlocked record.
        try entitlementStore.save(next)
        for kind in Self.widgetKinds {
            timelineReloader.reloadTimelines(ofKind: kind)
        }
    }

    private static let widgetKinds = [
        WidgetSharedConfiguration.heatmapKind,
        WidgetSharedConfiguration.hourlyLineKind,
        WidgetSharedConfiguration.weeklySummaryKind,
        WidgetSharedConfiguration.monthlyBudgetKind,
        WidgetSharedConfiguration.todayAnomalyKind,
        WidgetSharedConfiguration.projectFocusKind,
        WidgetSharedConfiguration.modelFocusKind,
    ]

    private func updateState(_ update: (inout WidgetPurchaseState) -> Void) {
        var next = state
        update(&next)
        guard next != state else { return }
        state = next
        for observer in Array(observers.values) {
            observer(next)
        }
    }

    deinit {
        transactionUpdatesTask?.cancel()
        initialRefreshTask?.cancel()
    }
}

#if DEBUG
/// Deterministic review/UI-test clients selected by dependency injection outside production code.
@MainActor
enum WidgetPurchaseReviewFixtures {
    static let product = WidgetPurchaseProduct(
        id: WidgetPurchaseController.productID,
        displayName: "Unlock All Widgets",
        description: "Unlock all 7 desktop widgets permanently.",
        displayPrice: "$2.99"
    )

    static func makeLockedClient() -> any WidgetPurchaseClient {
        StaticWidgetPurchaseClient(isUnlocked: false)
    }

    static func makeUnlockedClient() -> any WidgetPurchaseClient {
        StaticWidgetPurchaseClient(isUnlocked: true)
    }

    static func makeLockedController(
        entitlementStore: any WidgetEntitlementStoring = DiscardingWidgetEntitlementStore(),
        timelineReloader: any WidgetTimelineReloading = DiscardingWidgetTimelineReloader()
    ) -> WidgetPurchaseController {
        WidgetPurchaseController(
            client: makeLockedClient(),
            entitlementStore: entitlementStore,
            timelineReloader: timelineReloader
        )
    }

    static func makeUnlockedController(
        entitlementStore: any WidgetEntitlementStoring = DiscardingWidgetEntitlementStore(),
        timelineReloader: any WidgetTimelineReloading = DiscardingWidgetTimelineReloader()
    ) -> WidgetPurchaseController {
        WidgetPurchaseController(
            client: makeUnlockedClient(),
            entitlementStore: entitlementStore,
            timelineReloader: timelineReloader
        )
    }
}

private struct DiscardingWidgetEntitlementStore: WidgetEntitlementStoring {
    func load() -> WidgetEntitlementState { .locked }
    func save(_ state: WidgetEntitlementState) throws {}
}

private struct DiscardingWidgetTimelineReloader: WidgetTimelineReloading {
    func reloadTimelines(ofKind kind: String) {}
}

@MainActor
private final class StaticWidgetPurchaseClient: WidgetPurchaseClient {
    private var isUnlocked: Bool
    private var nextTransactionID: UInt64 = 1

    init(isUnlocked: Bool) {
        self.isUnlocked = isUnlocked
    }

    func loadProduct(productID: String) async throws -> WidgetPurchaseProduct? {
        productID == WidgetPurchaseReviewFixtures.product.id
            ? WidgetPurchaseReviewFixtures.product
            : nil
    }

    func purchase(productID: String, in window: NSWindow) async throws -> WidgetPurchaseResult {
        guard productID == WidgetPurchaseReviewFixtures.product.id else {
            throw StoreKitWidgetPurchaseClientError.productUnavailable(productID)
        }
        isUnlocked = true
        defer { nextTransactionID += 1 }
        return .verified(WidgetPurchaseTransaction(
            id: nextTransactionID,
            productID: productID
        ))
    }

    func sync() async throws {}

    func hasVerifiedCurrentEntitlement(productID: String) async -> Bool {
        productID == WidgetPurchaseReviewFixtures.product.id && isUnlocked
    }

    func transactionUpdates() -> AsyncStream<WidgetTransactionUpdate> {
        AsyncStream { _ in }
    }

    func finish(transactionID: UInt64) async {}
}
#endif
