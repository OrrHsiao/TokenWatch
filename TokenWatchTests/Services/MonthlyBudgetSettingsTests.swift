import Foundation
import Testing
@testable import TokenWatch

@Suite("Monthly budget settings")
@MainActor
struct MonthlyBudgetSettingsTests {
    @Test("a positive finite budget persists and notifies observers once")
    func validBudgetPersists() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        var notificationCount = 0
        _ = fixture.settings.observe { notificationCount += 1 }

        fixture.settings.monthlyBudgetUSD = 120.5

        #expect(fixture.settings.monthlyBudgetUSD == 120.5)
        #expect(fixture.defaults.double(forKey: MonthlyBudgetSettings.storageKey) == 120.5)
        #expect(notificationCount == 1)

        fixture.settings.monthlyBudgetUSD = 120.5
        #expect(notificationCount == 1)
    }

    @Test("missing, zero, negative, and non-finite budgets disable budget tracking")
    func invalidBudgetsClearStoredValue() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        fixture.settings.monthlyBudgetUSD = 100
        for value: Double? in [nil, 0, -1, .infinity, .nan] {
            fixture.settings.monthlyBudgetUSD = value
            #expect(fixture.settings.monthlyBudgetUSD == nil)
            #expect(fixture.defaults.object(forKey: MonthlyBudgetSettings.storageKey) == nil)
        }
    }

    private func makeFixture() -> (
        settings: MonthlyBudgetSettings,
        defaults: UserDefaults,
        suiteName: String
    ) {
        let suiteName = "MonthlyBudgetSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (
            MonthlyBudgetSettings(defaults: defaults),
            defaults,
            suiteName
        )
    }
}
