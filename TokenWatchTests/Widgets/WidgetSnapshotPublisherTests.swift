import Foundation
import Testing
@testable import TokenWatch

@MainActor
@Suite("WidgetSnapshotPublisher")
struct WidgetSnapshotPublisherTests {

    @Test("发布成功时写入快照并 reload timelines")
    func publishWritesSnapshotAndReloadsTimelines() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TokenWatchWidgetSnapshotStore(containerURLProvider: { directory })
        let reloader = RecordingWidgetTimelineReloader()
        let now = Date(timeIntervalSince1970: 1_779_811_200)
        let languageSettings = makeEnglishLanguageSettings()
        let publisher = WidgetSnapshotPublisher(
            store: store,
            timelineReloader: reloader,
            dateProvider: { now },
            calendar: utcCalendar(),
            languageSettings: languageSettings
        )

        publisher.publish(states: allProvidersNeedAuthorizationStates())

        let snapshot = try #require(store.read())
        #expect(snapshot.generatedAt == now)
        #expect(snapshot.languageIdentifier == "en")
        #expect(snapshot.status == .needsAuthorization)
        #expect(reloader.reloadCallCount == 1)
    }

    @Test("写入失败时不 reload timelines")
    func publishFailureDoesNotReloadTimelines() {
        let store = TokenWatchWidgetSnapshotStore(containerURLProvider: { nil })
        let reloader = RecordingWidgetTimelineReloader()
        let publisher = WidgetSnapshotPublisher(
            store: store,
            timelineReloader: reloader,
            dateProvider: { Date(timeIntervalSince1970: 1_779_811_200) },
            calendar: utcCalendar(),
            languageSettings: makeEnglishLanguageSettings()
        )

        publisher.publish(states: allProvidersNeedAuthorizationStates())

        #expect(reloader.reloadCallCount == 0)
    }

    private func allProvidersNeedAuthorizationStates() -> [ProviderID: TokenStatsViewModel.ProviderState] {
        Dictionary(uniqueKeysWithValues: ProviderRegistry.allProviders.map {
            (
                $0.id,
                TokenStatsViewModel.ProviderState(
                    stats: nil,
                    isLoading: false,
                    errorMessage: nil,
                    needsAuthorization: true
                )
            )
        })
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetSnapshotPublisherTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeEnglishLanguageSettings() -> AppLanguageSettings {
        let suiteName = "WidgetSnapshotPublisherTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppLanguageSettings(defaults: defaults, preferredLanguagesProvider: { ["en-US"] })
        settings.selectedPreference = .en
        return settings
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }
}

@MainActor
private final class RecordingWidgetTimelineReloader: WidgetTimelineReloading {
    private(set) var reloadCallCount = 0

    func reloadAllTimelines() {
        reloadCallCount += 1
    }
}
