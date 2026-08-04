import Foundation

/// Stores the optional monthly spending limit used by the budget widget.
///
/// Costs in TokenWatch are estimated in USD, so the persisted value is also USD.
/// Missing, non-finite, and non-positive values all mean that no budget is configured.
@MainActor
final class MonthlyBudgetSettings {
    struct ObservationToken: Hashable, Sendable {
        let id: UUID
    }

    static let shared = MonthlyBudgetSettings(defaults: .standard)
    static let storageKey = "TokenWatch.monthlyBudgetUSD"

    private let defaults: UserDefaults
    private var observers: [ObservationToken: @MainActor () -> Void] = [:]

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The configured monthly USD limit, or `nil` when budget tracking is disabled.
    var monthlyBudgetUSD: Double? {
        get {
            Self.validated(defaults.object(forKey: Self.storageKey) as? NSNumber)
        }
        set {
            let normalized = Self.validated(newValue)
            guard monthlyBudgetUSD != normalized else { return }

            if let normalized {
                defaults.set(normalized, forKey: Self.storageKey)
            } else {
                defaults.removeObject(forKey: Self.storageKey)
            }
            notifyChange()
        }
    }

    /// Registers a callback invoked only after the normalized budget value changes.
    /// - Parameter handler: Main-actor callback for updating dependent UI or widget snapshots.
    /// - Returns: A token that can later remove the callback.
    @discardableResult
    func observe(
        _ handler: @escaping @MainActor () -> Void
    ) -> ObservationToken {
        let token = ObservationToken(id: UUID())
        observers[token] = handler
        return token
    }

    /// Removes a callback previously returned by `observe(_:)`.
    /// - Parameter token: The callback token to remove.
    func removeObserver(_ token: ObservationToken) {
        observers.removeValue(forKey: token)
    }

    private func notifyChange() {
        for observer in Array(observers.values) {
            observer()
        }
    }

    private static func validated(_ value: NSNumber?) -> Double? {
        guard let value else { return nil }
        return validated(value.doubleValue)
    }

    private static func validated(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }
}
