import Foundation

/// Cached access state shared from the host app to the widget extension.
enum WidgetEntitlementState: String, Codable, Equatable, Sendable {
    case locked
    case unlocked
}

/// Errors raised while resolving the App Group preference suite.
enum WidgetEntitlementStoreError: Error, Equatable, Sendable {
    case appGroupDefaultsUnavailable
    case synchronizationFailed
}

/// Cross-process entitlement cache used by the host app and widget extension.
protocol WidgetEntitlementStoring: Sendable {
    /// Loads the cached widget access state, failing closed for missing or invalid data.
    /// - Returns: `.unlocked` only for a valid record for the current lifetime product.
    func load() -> WidgetEntitlementState

    /// Persists the latest StoreKit-derived access state in the shared App Group suite.
    /// - Parameter state: The verified lifetime widget entitlement state.
    /// - Throws: An encoding or App Group preference synchronization error.
    func save(_ state: WidgetEntitlementState) throws
}

/// App Group `UserDefaults` storage whose JSON envelope rejects stale or malformed values.
///
/// `UserDefaults` is documented as thread-safe. The unchecked conformance only bridges
/// Foundation's missing `Sendable` annotation while each operation remains synchronous.
struct AppGroupWidgetEntitlementStore: WidgetEntitlementStoring, @unchecked Sendable {
    private static let schemaVersion = 1

    private struct Record: Codable {
        let schemaVersion: Int
        let productID: String
        let state: WidgetEntitlementState
    }

    private let defaults: UserDefaults

    /// Creates a store backed by an explicitly supplied defaults suite.
    /// - Parameter defaults: The App Group suite in production or an isolated suite in tests.
    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Resolves the shared App Group preference suite used by both processes.
    /// - Parameter defaultsProvider: Injectable suite resolver for deterministic tests.
    /// - Returns: A store backed by the configured App Group suite.
    /// - Throws: `WidgetEntitlementStoreError.appGroupDefaultsUnavailable` when resolution fails.
    static func appGroupStore(
        defaultsProvider: (String) -> UserDefaults? = { UserDefaults(suiteName: $0) }
    ) throws -> AppGroupWidgetEntitlementStore {
        guard let defaults = defaultsProvider(WidgetSharedConfiguration.appGroupIdentifier) else {
            throw WidgetEntitlementStoreError.appGroupDefaultsUnavailable
        }
        return AppGroupWidgetEntitlementStore(defaults: defaults)
    }

    /// Refreshes the shared preference domain, then loads only an exact-schema record.
    /// - Returns: `.locked` for synchronization failure, missing, malformed, stale, or
    ///   foreign-product data.
    func load() -> WidgetEntitlementState {
        guard defaults.synchronize(),
              let data = defaults.data(forKey: WidgetSharedConfiguration.widgetEntitlementKey),
              let record = try? JSONDecoder().decode(Record.self, from: data),
              record.schemaVersion == Self.schemaVersion,
              record.productID == WidgetSharedConfiguration.widgetLifetimeProductID else {
            return .locked
        }
        return record.state
    }

    /// Encodes a versioned record and flushes it before widget timelines are reloaded.
    /// - Parameter state: The verified widget access state to cache.
    /// - Throws: An encoding error, or `WidgetEntitlementStoreError.synchronizationFailed`
    ///   when the App Group preference domain cannot be flushed for the widget process.
    func save(_ state: WidgetEntitlementState) throws {
        let record = Record(
            schemaVersion: Self.schemaVersion,
            productID: WidgetSharedConfiguration.widgetLifetimeProductID,
            state: state
        )
        let data = try JSONEncoder().encode(record)
        defaults.set(data, forKey: WidgetSharedConfiguration.widgetEntitlementKey)
        guard defaults.synchronize() else {
            throw WidgetEntitlementStoreError.synchronizationFailed
        }
    }
}
