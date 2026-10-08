import Foundation
import Testing
@testable import TokenWatch

@Suite("DemoStatsFixture tests")
struct DemoStatsFixtureTests {

    @Test("Demo states contain all three providers with active stats and entries")
    func demoStatesContainAllThreeProviders() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let states = DemoStatsFixture.makeDemoStates(now: now, calendar: calendar)

        #expect(states.count == 3)
        #expect(states[.claude]?.directoryState == .selected)
        #expect(states[.codex]?.directoryState == .selected)
        #expect(states[.opencode]?.directoryState == .selected)

        #expect(states[.claude]?.needsAuthorization == false)
        #expect(states[.codex]?.needsAuthorization == false)
        #expect(states[.opencode]?.needsAuthorization == false)

        let totalTokens = states.values.compactMap { $0.stats?.overall.totalTokens }.reduce(0, +)
        #expect(totalTokens > 40_000_000)

        let totalCost = states.values.compactMap { $0.stats?.overall.cost }.reduce(0, +)
        #expect(totalCost > 50.0)

        let claudeEntries = try #require(states[.claude]?.entries)
        #expect(!claudeEntries.isEmpty)

        let codexEntries = try #require(states[.codex]?.entries)
        #expect(!codexEntries.isEmpty)

        let opencodeEntries = try #require(states[.opencode]?.entries)
        #expect(!opencodeEntries.isEmpty)
    }

    @Test("Demo states build valid calendar heatmap and hourly chart")
    func demoStatesBuildValidCharts() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let states = DemoStatsFixture.makeDemoStates(now: now, calendar: calendar)

        let heatmap = CalendarHeatmapBuilder.build(
            states: states,
            month: now,
            now: now,
            calendar: calendar,
            language: .zhHans
        )
        #expect(heatmap.cells.count == 154)
        #expect(heatmap.monthTotalTokens > 0)

        let widgetSnapshot = WidgetSnapshotBuilder.build(
            states: states,
            now: now,
            calendar: calendar,
            language: .zhHans
        )
        let snapshot = try #require(widgetSnapshot)
        #expect(WidgetUsageSnapshotValidator.isValid(snapshot))
    }
}
