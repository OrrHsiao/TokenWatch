import Foundation
import Testing
@testable import TokenWatch

@Suite("App Group widget entitlement store")
struct AppGroupWidgetEntitlementStoreTests {
    @Test("missing and non-record files fail closed")
    func missingAndWrongTypeFailClosed() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        #expect(fixture.store.load() == .locked)

        try Data(#""unlocked""#.utf8).write(to: fixture.store.fileURL)
        #expect(fixture.store.load() == .locked)
    }

    @Test("verified state round-trips through the shared file")
    func stateRoundTrips() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        try fixture.store.save(.unlocked)
        #expect(fixture.store.load() == .unlocked)

        try fixture.store.save(.locked)
        #expect(fixture.store.load() == .locked)
    }

    @Test("a separately opened store observes the atomic entitlement file")
    func separateStoreInstanceObservesSavedState() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let reader = AppGroupWidgetEntitlementStore(fileURL: fixture.store.fileURL)

        try fixture.store.save(.unlocked)

        #expect(reader.load() == .unlocked)
    }

    @Test("corrupt stale and foreign-product records fail closed")
    func invalidRecordsFailClosed() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let invalidRecords = [
            Data("not-json".utf8),
            Data(#"{"schemaVersion":2,"productID":"com.xiaoao.tokenwatch.widgets.lifetime","state":"unlocked"}"#.utf8),
            Data(#"{"schemaVersion":1,"productID":"com.example.foreign","state":"unlocked"}"#.utf8),
            Data(#"{"schemaVersion":1,"productID":"com.xiaoao.tokenwatch.widgets.lifetime","state":"unknown"}"#.utf8),
        ]

        for record in invalidRecords {
            try record.write(to: fixture.store.fileURL, options: .atomic)
            #expect(fixture.store.load() == .locked)
        }
    }

    @Test("App Group resolver uses the configured container and rejects an unavailable one")
    func appGroupResolutionIsInjectable() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        var resolvedIdentifier: String?

        let store = try AppGroupWidgetEntitlementStore.appGroupStore { identifier in
            resolvedIdentifier = identifier
            return fixture.directory
        }

        #expect(resolvedIdentifier == WidgetSharedConfiguration.appGroupIdentifier)
        #expect(store.fileURL.lastPathComponent == WidgetSharedConfiguration.widgetEntitlementFilename)
        #expect(store.load() == .locked)
        #expect(throws: WidgetEntitlementStoreError.appGroupContainerUnavailable) {
            try AppGroupWidgetEntitlementStore.appGroupStore { _ in nil }
        }
    }

    @Test("atomic write failure leaves the old entitlement readable")
    func failedAtomicWritePreservesExistingEntitlement() throws {
        struct InjectedWriteError: Error {}

        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try fixture.store.save(.unlocked)
        let failingStore = AppGroupWidgetEntitlementStore(
            fileURL: fixture.store.fileURL,
            atomicWrite: { _, _ in throw InjectedWriteError() }
        )

        #expect(throws: InjectedWriteError.self) {
            try failingStore.save(.locked)
        }
        #expect(fixture.store.load() == .unlocked)
    }

    private func makeFixture() throws -> (
        directory: URL,
        store: AppGroupWidgetEntitlementStore
    ) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "AppGroupWidgetEntitlementStoreTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return (
            directory,
            AppGroupWidgetEntitlementStore(
                fileURL: directory.appendingPathComponent(
                    WidgetSharedConfiguration.widgetEntitlementFilename,
                    isDirectory: false
                )
            )
        )
    }
}
