import AppKit
import StoreKit

/// Store-facing product data that the AppKit purchase UI can render without retaining StoreKit types.
struct WidgetPurchaseProduct: Equatable, Sendable {
    let id: String
    let displayName: String
    let description: String
    let displayPrice: String
}

/// Verified transaction identity retained until the controller finishes content delivery.
struct WidgetPurchaseTransaction: Equatable, Sendable {
    let id: UInt64
    let productID: String
}

/// Domain result of one purchase request after StoreKit signature verification.
enum WidgetPurchaseResult: Equatable, Sendable {
    case verified(WidgetPurchaseTransaction)
    case unverified(productID: String)
    case pending
    case userCancelled
}

/// One StoreKit transaction update with verification preserved for fail-closed handling.
enum WidgetTransactionUpdate: Equatable, Sendable {
    case verified(WidgetPurchaseTransaction)
    case unverified(productID: String)
}

/// Minimal StoreKit seam used by `WidgetPurchaseController` and deterministic tests.
@MainActor
protocol WidgetPurchaseClient: AnyObject {
    /// Loads the exact product requested by the controller.
    /// - Parameter productID: The immutable App Store Connect product identifier.
    /// - Returns: Localized product metadata, or `nil` when the product is unavailable.
    func loadProduct(productID: String) async throws -> WidgetPurchaseProduct?

    /// Presents the App Store purchase sheet in the supplied AppKit window.
    /// - Parameters:
    ///   - productID: The product to purchase. The client may load it on demand.
    ///   - window: The window that owns the StoreKit confirmation sheet.
    /// - Returns: A verification-preserving purchase result.
    func purchase(productID: String, in window: NSWindow) async throws -> WidgetPurchaseResult

    /// Explicitly synchronizes the local transaction history with the App Store.
    func sync() async throws

    /// Returns whether StoreKit currently exposes a verified entitlement for the product.
    /// - Parameter productID: The product whose non-consumable entitlement is queried.
    func hasVerifiedCurrentEntitlement(productID: String) async -> Bool

    /// Creates a stream that forwards verified and unverified StoreKit transaction updates.
    func transactionUpdates() -> AsyncStream<WidgetTransactionUpdate>

    /// Finishes a transaction only after the controller has delivered the entitlement.
    /// - Parameter transactionID: The StoreKit transaction retained by the client.
    func finish(transactionID: UInt64) async
}

enum StoreKitWidgetPurchaseClientError: Error, Equatable {
    case productUnavailable(String)
}

/// StoreKit 2 implementation for the one-time desktop-widget unlock.
@MainActor
final class StoreKitWidgetPurchaseClient: WidgetPurchaseClient {
    private var productsByID: [String: Product] = [:]
    private var unfinishedTransactionsByID: [UInt64: Transaction] = [:]

    func loadProduct(productID: String) async throws -> WidgetPurchaseProduct? {
        let products = try await Product.products(for: [productID])
        guard let product = products.first(where: { $0.id == productID }) else {
            return nil
        }

        productsByID[productID] = product
        return WidgetPurchaseProduct(
            id: product.id,
            displayName: product.displayName,
            description: product.description,
            displayPrice: product.displayPrice
        )
    }

    func purchase(productID: String, in window: NSWindow) async throws -> WidgetPurchaseResult {
        let product: Product
        if let loadedProduct = productsByID[productID] {
            product = loadedProduct
        } else {
            guard let loadedProduct = try await loadStoreKitProduct(productID: productID) else {
                throw StoreKitWidgetPurchaseClientError.productUnavailable(productID)
            }
            product = loadedProduct
        }

        let result: Product.PurchaseResult
        if #available(macOS 15.2, *) {
            result = try await product.purchase(confirmIn: window)
        } else {
            // The project still deploys to macOS 15.0; StoreKit owns presentation on older 15.x.
            result = try await product.purchase()
        }

        switch result {
        case .success(.verified(let transaction)):
            unfinishedTransactionsByID[transaction.id] = transaction
            return .verified(Self.domainTransaction(transaction))
        case .success(.unverified(let transaction, _)):
            return .unverified(productID: transaction.productID)
        case .pending:
            return .pending
        case .userCancelled:
            return .userCancelled
        @unknown default:
            return .pending
        }
    }

    func sync() async throws {
        try await AppStore.sync()
    }

    func hasVerifiedCurrentEntitlement(productID: String) async -> Bool {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == productID {
                return true
            }
        }
        return false
    }

    func transactionUpdates() -> AsyncStream<WidgetTransactionUpdate> {
        // StoreKit may deliver an unfinished transaction only once during this launch. Keep an
        // unbounded stream so a temporary main-actor stall cannot silently drop access delivery.
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let task = Task { @MainActor [weak self] in
                for await result in Transaction.updates {
                    guard !Task.isCancelled else { break }

                    switch result {
                    case .verified(let transaction)
                        where transaction.productID == WidgetSharedConfiguration.widgetLifetimeProductID:
                        self?.unfinishedTransactionsByID[transaction.id] = transaction
                        continuation.yield(.verified(Self.domainTransaction(transaction)))
                    case .unverified(let transaction, _)
                        where transaction.productID == WidgetSharedConfiguration.widgetLifetimeProductID:
                        continuation.yield(.unverified(productID: transaction.productID))
                    default:
                        // Other products remain owned by their future purchase subsystem.
                        continue
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    func finish(transactionID: UInt64) async {
        guard let transaction = unfinishedTransactionsByID.removeValue(forKey: transactionID) else {
            return
        }
        await transaction.finish()
    }

    private func loadStoreKitProduct(productID: String) async throws -> Product? {
        let products = try await Product.products(for: [productID])
        guard let product = products.first(where: { $0.id == productID }) else {
            return nil
        }
        productsByID[productID] = product
        return product
    }

    private static func domainTransaction(_ transaction: Transaction) -> WidgetPurchaseTransaction {
        WidgetPurchaseTransaction(id: transaction.id, productID: transaction.productID)
    }
}
