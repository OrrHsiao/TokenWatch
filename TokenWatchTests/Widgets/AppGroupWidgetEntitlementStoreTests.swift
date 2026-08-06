import Foundation
import Testing
@testable import TokenWatch

@Suite("App Group widget entitlement store")
struct AppGroupWidgetEntitlementStoreTests {
    @Test("missing and non-data values fail closed")
    func missingAndWrongTypeFailClosed() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        #expect(fixture.store.load() == .locked)

        fixture.defaults.set(
            "unlocked",
            forKey: WidgetSharedConfiguration.widgetEntitlementKey
        )
        #expect(fixture.store.load() == .locked)
    }

    @Test("verified state round-trips through the shared preference")
    func stateRoundTrips() throws {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        try fixture.store.save(.unlocked)
        #expect(fixture.store.load() == .unlocked)

        try fixture.store.save(.locked)
        #expect(fixture.store.load() == .locked)
    }

    @Test("a separately opened suite observes the flushed entitlement")
    func separateSuiteInstanceObservesSavedState() throws {
        let suiteName = "AppGroupWidgetEntitlementStoreTests.\(UUID().uuidString)"
        let writerDefaults = UserDefaults(suiteName: suiteName)!
        let readerDefaults = UserDefaults(suiteName: suiteName)!
        writerDefaults.removePersistentDomain(forName: suiteName)
        defer { writerDefaults.removePersistentDomain(forName: suiteName) }
        let writer = AppGroupWidgetEntitlementStore(defaults: writerDefaults)
        let reader = AppGroupWidgetEntitlementStore(defaults: readerDefaults)

        try writer.save(.unlocked)

        #expect(reader.load() == .unlocked)
    }

    @Test("corrupt stale and foreign-product records fail closed")
    func invalidRecordsFailClosed() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let invalidRecords = [
            Data("not-json".utf8),
            Data(#"{"schemaVersion":2,"productID":"com.xiaoao.tokenwatch.widgets.lifetime","state":"unlocked"}"#.utf8),
            Data(#"{"schemaVersion":1,"productID":"com.example.foreign","state":"unlocked"}"#.utf8),
            Data(#"{"schemaVersion":1,"productID":"com.xiaoao.tokenwatch.widgets.lifetime","state":"unknown"}"#.utf8),
        ]

        for record in invalidRecords {
            fixture.defaults.set(
                record,
                forKey: WidgetSharedConfiguration.widgetEntitlementKey
            )
            #expect(fixture.store.load() == .locked)
        }
    }

    @Test("App Group resolver is injectable and rejects unavailable suites")
    func appGroupResolutionIsInjectable() throws {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        var resolvedIdentifier: String?

        let store = try AppGroupWidgetEntitlementStore.appGroupStore { identifier in
            resolvedIdentifier = identifier
            return fixture.defaults
        }

        #expect(resolvedIdentifier == WidgetSharedConfiguration.appGroupIdentifier)
        #expect(store.load() == .locked)
        #expect(throws: WidgetEntitlementStoreError.appGroupDefaultsUnavailable) {
            try AppGroupWidgetEntitlementStore.appGroupStore { _ in nil }
        }
    }

    private func makeFixture() -> (
        suiteName: String,
        defaults: UserDefaults,
        store: AppGroupWidgetEntitlementStore
    ) {
        let suiteName = "AppGroupWidgetEntitlementStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (
            suiteName,
            defaults,
            AppGroupWidgetEntitlementStore(defaults: defaults)
        )
    }
}
