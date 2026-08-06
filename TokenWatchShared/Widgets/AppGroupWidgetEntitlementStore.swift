import Foundation

/// Cached access state shared from the host app to the widget extension.
enum WidgetEntitlementState: String, Codable, Equatable, Sendable {
    case locked
    case unlocked
}

/// Errors raised while resolving the App Group entitlement file.
enum WidgetEntitlementStoreError: Error, Equatable, Sendable {
    case appGroupContainerUnavailable
}

/// Cross-process entitlement cache used by the host app and widget extension.
protocol WidgetEntitlementStoring: Sendable {
    /// Loads the cached widget access state, failing closed for missing or invalid data.
    /// - Returns: `.unlocked` only for a valid record for the current lifetime product.
    func load() -> WidgetEntitlementState

    /// Persists the latest StoreKit-derived access state in the shared App Group container.
    /// - Parameter state: The verified lifetime widget entitlement state.
    /// - Throws: An encoding or atomic file replacement error.
    func save(_ state: WidgetEntitlementState) throws
}

/// App Group JSON storage whose envelope rejects stale or malformed values.
///
/// A versioned atomic file avoids cross-process `CFPreferences` cache divergence between the
/// host app and an already-running WidgetKit extension. Failed replacement preserves old bytes.
struct AppGroupWidgetEntitlementStore: WidgetEntitlementStoring, Sendable {
    typealias AtomicWrite = @Sendable (Data, URL) throws -> Void

    private static let schemaVersion = 1

    private struct Record: Codable {
        let schemaVersion: Int
        let productID: String
        let state: WidgetEntitlementState
    }

    let fileURL: URL
    private let atomicWrite: AtomicWrite

    /// Creates a store at an explicit URL with an injectable atomic replacement seam.
    /// - Parameters:
    ///   - fileURL: The shared entitlement record URL.
    ///   - atomicWrite: The replacement operation; defaults to Foundation's atomic write.
    init(
        fileURL: URL,
        atomicWrite: @escaping AtomicWrite = { data, url in
            try data.write(to: url, options: .atomic)
        }
    ) {
        self.fileURL = fileURL
        self.atomicWrite = atomicWrite
    }

    /// Resolves the entitlement file inside the App Group container used by both processes.
    /// - Parameter containerURLProvider: Injectable container resolver for deterministic tests.
    /// - Returns: A store targeting the configured entitlement filename.
    /// - Throws: `WidgetEntitlementStoreError.appGroupContainerUnavailable` when resolution fails.
    static func appGroupStore(
        containerURLProvider: (String) -> URL? = {
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0)
        }
    ) throws -> AppGroupWidgetEntitlementStore {
        guard let containerURL = containerURLProvider(
            WidgetSharedConfiguration.appGroupIdentifier
        ) else {
            throw WidgetEntitlementStoreError.appGroupContainerUnavailable
        }
        return AppGroupWidgetEntitlementStore(
            fileURL: containerURL.appendingPathComponent(
                WidgetSharedConfiguration.widgetEntitlementFilename,
                isDirectory: false
            )
        )
    }

    /// Loads only an exact-schema record for the configured lifetime product.
    /// - Returns: `.locked` for missing, unreadable, malformed, stale, or foreign-product data.
    func load() -> WidgetEntitlementState {
        guard let data = try? Data(contentsOf: fileURL),
              let record = try? JSONDecoder().decode(Record.self, from: data),
              record.schemaVersion == Self.schemaVersion,
              record.productID == WidgetSharedConfiguration.widgetLifetimeProductID else {
            return .locked
        }
        return record.state
    }

    /// Encodes and atomically replaces the versioned record before timelines are reloaded.
    /// - Parameter state: The verified widget access state to cache.
    /// - Throws: The underlying encoder or atomic replacement error.
    func save(_ state: WidgetEntitlementState) throws {
        let record = Record(
            schemaVersion: Self.schemaVersion,
            productID: WidgetSharedConfiguration.widgetLifetimeProductID,
            state: state
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try atomicWrite(try encoder.encode(record), fileURL)
    }
}
