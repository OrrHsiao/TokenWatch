# Recent Session Details Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a recent session details section that always lists recent `provider + sessionID` rows, while the selected time period only controls which usage entries are included in each row.

**Architecture:** Preserve the existing provider/parser boundary: providers still produce `[ParsedUsageEntry]`, ViewModel stores the latest entries next to aggregated stats, and a new pure builder converts filtered entries into `RecentSessionDetailsSnapshot`. UI renders the builder snapshot in the existing time-window page without changing parser formats or introducing a separate raw session model.

**Tech Stack:** Swift 6, AppKit, Swift Testing, Xcode file-system-synchronized groups, existing `UsageStatsPeriod`, `PricingEngine`, `UsageAggregator`, `MonthlyStatsViewController`.

---

## File Structure

- Modify `TokenWatch/ViewModels/TokenStatsViewModel.swift`: keep the latest provider entries in `ProviderState`, return entries from the background load result, and preserve entries on unchanged or failed refreshes.
- Create `TokenWatch/Analytics/UsageCostResolver.swift`: share entry cost resolution between `UsageAggregator` and the new recent-session builder.
- Modify `TokenWatch/Analytics/UsageAggregator.swift`: replace private cost fallback logic with `UsageCostResolver`.
- Modify `TokenWatch/ViewControllers/MonthlyTokenChartBuilder.swift`: expose a reusable period date interval and add `.recent7Days`.
- Create `TokenWatch/ViewControllers/RecentSessionDetailsBuilder.swift`: define `RecentSessionDetailsSnapshot`, `RecentSessionRow`, and pure build logic.
- Create `TokenWatch/ViewControllers/RecentSessionDetailsView.swift`: AppKit rendering for the recent details table-like section.
- Modify `TokenWatch/ViewControllers/MonthlyStatsViewController.swift`: render the recent details section under the existing charts.
- Modify `TokenWatch/Localization/AppStrings.swift`: add recent-details labels and English coverage for all new keys.
- Add `TokenWatchTests/ViewControllers/RecentSessionDetailsBuilderTests.swift`.
- Add `TokenWatchTests/ViewControllers/RecentSessionDetailsViewTests.swift`.
- Modify `TokenWatchTests/ViewModels/TokenStatsViewModelObserverTests.swift`.
- Modify `TokenWatchTests/ViewControllers/MonthlyStatsViewControllerTests.swift`.

Xcode project note: this repo uses `PBXFileSystemSynchronizedRootGroup`, so new Swift files under `TokenWatch/` and `TokenWatchTests/` should be picked up without manual `project.pbxproj` references.

---

### Task 1: Store Latest Entries In Provider State

**Files:**
- Modify: `TokenWatch/ViewModels/TokenStatsViewModel.swift`
- Modify: `TokenWatchTests/ViewModels/TokenStatsViewModelObserverTests.swift`

- [ ] **Step 1: Write failing ViewModel tests**

Append these tests inside `TokenStatsViewModelObserverTests`:

```swift
@Test func successfulLoadStoresLatestEntries() async throws {
    let provider = StubUsageProvider(id: .claude)
    let bookmarkManager = StubBookmarkManager(rootURL: URL(fileURLWithPath: NSTemporaryDirectory()))
    let aggregator = CountingUsageAggregator()
    let vm = TokenStatsViewModel(
        providers: [provider],
        bookmarkManager: bookmarkManager,
        aggregator: aggregator
    )

    await vm.loadStats(for: .claude)

    #expect(vm.states[.claude]?.entries?.count == 1)
    #expect(vm.states[.claude]?.entries?.first?.sessionID == "session-1")
    #expect(vm.states[.claude]?.stats != nil)
}

@Test func unchangedRefreshKeepsExistingEntries() async throws {
    let provider = StubUsageProvider(id: .claude)
    let bookmarkManager = StubBookmarkManager(rootURL: URL(fileURLWithPath: NSTemporaryDirectory()))
    let aggregator = CountingUsageAggregator()
    let vm = TokenStatsViewModel(
        providers: [provider],
        bookmarkManager: bookmarkManager,
        aggregator: aggregator
    )

    await vm.loadStats(for: .claude, mode: .silentIfUnchanged)
    let firstEntries = vm.states[.claude]?.entries

    await vm.loadStats(for: .claude, mode: .silentIfUnchanged)

    #expect(vm.states[.claude]?.entries == firstEntries)
    #expect(aggregator.aggregateCallCount == 1)
}

@Test func failedRefreshKeepsExistingEntries() async throws {
    let provider = FailingAfterFirstLoadProvider(id: .claude)
    let bookmarkManager = StubBookmarkManager(rootURL: URL(fileURLWithPath: NSTemporaryDirectory()))
    let aggregator = CountingUsageAggregator()
    let vm = TokenStatsViewModel(
        providers: [provider],
        bookmarkManager: bookmarkManager,
        aggregator: aggregator
    )

    await vm.loadStats(for: .claude)
    let firstEntries = vm.states[.claude]?.entries

    provider.failNextLoad()
    await vm.loadStats(for: .claude)

    #expect(vm.states[.claude]?.entries == firstEntries)
    #expect(vm.states[.claude]?.errorMessage != nil)
}
```

Add this helper near the other stub providers in the same test file:

```swift
private final class FailingAfterFirstLoadProvider: UsageProvider, @unchecked Sendable {
    let id: ProviderID
    let displayName = "Failing Provider"
    let bookmarkKey = "FailingBookmark"
    let defaultDirectoryPath = NSTemporaryDirectory()
    let openPanelMessage = "Select a folder"
    let hasCacheWriteDimension = true
    let hasReasoningDimension = false

    private let lock = NSLock()
    private var shouldFail = false

    init(id: ProviderID) {
        self.id = id
    }

    func failNextLoad() {
        lock.lock()
        shouldFail = true
        lock.unlock()
    }

    func loadEntries(from rootURL: URL) throws -> [ParsedUsageEntry] {
        lock.lock()
        let fail = shouldFail
        shouldFail = false
        lock.unlock()

        if fail {
            throw StubLoadError()
        }
        return [makeEntry(id: id, usage: makeUsage(cacheCreation5m: 0, cacheCreation1h: 0))]
    }
}

private struct StubLoadError: LocalizedError {
    var errorDescription: String? { "stub load failed" }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/TokenStatsViewModelObserverTests test
```

Expected: compile failure mentioning `ProviderState` has no member `entries`.

- [ ] **Step 3: Implement entry retention**

In `TokenWatch/ViewModels/TokenStatsViewModel.swift`, change `ProviderState` to:

```swift
struct ProviderState: Sendable {
    var stats: AggregatedStats?
    var entries: [ParsedUsageEntry]?
    var isLoading = false
    var errorMessage: String?
    var needsAuthorization = true
}
```

Change `ProviderLoadResult` to:

```swift
private enum ProviderLoadResult: Sendable {
    case loaded(stats: AggregatedStats, entries: [ParsedUsageEntry], fingerprint: UsageEntriesFingerprint, entryCount: Int)
    case unchanged(entryCount: Int)
}
```

In the detached load task, return entries with the loaded result:

```swift
let stats = aggregator.aggregate(entries)
return .success(.loaded(stats: stats, entries: entries, fingerprint: fingerprint, entryCount: entries.count))
```

In the success switch, set `entries` only for the loaded case:

```swift
case .success(.loaded(let stats, let entries, let fingerprint, _)):
    entryFingerprints[id] = fingerprint
    states[id]?.stats = stats
    states[id]?.entries = entries
    states[id]?.needsAuthorization = false
    states[id]?.errorMessage = nil
    states[id]?.isLoading = false
    notifyStateChange(id)
case .success(.unchanged):
    if sendsLoadingNotifications {
        states[id]?.isLoading = false
        notifyStateChange(id)
    }
```

Leave failure and authorization branches preserving existing `stats` and `entries`, matching current `stats` behavior.

- [ ] **Step 4: Run tests to verify pass**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/TokenStatsViewModelObserverTests test
```

Expected: `TokenStatsViewModelObserverTests` passes.

- [ ] **Step 5: Commit**

```bash
git add TokenWatch/ViewModels/TokenStatsViewModel.swift TokenWatchTests/ViewModels/TokenStatsViewModelObserverTests.swift
git commit -m "feat(stats): 保留数据源明细条目"
```

---

### Task 2: Share Entry Cost Resolution

**Files:**
- Create: `TokenWatch/Analytics/UsageCostResolver.swift`
- Modify: `TokenWatch/Analytics/UsageAggregator.swift`
- Test: `TokenWatchTests/Analytics/UsageAggregatorTests.swift`

- [ ] **Step 1: Run existing pricing fallback test before refactor**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/UsageAggregatorTests test
```

Expected: pass before refactor. This gives a baseline for the upstream cost fallback behavior.

- [ ] **Step 2: Create shared resolver**

Create `TokenWatch/Analytics/UsageCostResolver.swift`:

```swift
import Foundation

/// Resolves a ParsedUsageEntry cost using the local pricing table, with provider-supplied
/// cost as fallback when a model is unknown.
struct UsageCostResolver: Sendable {
    private let pricingEngine = PricingEngine()

    /// Returns the USD cost for one parsed usage entry.
    /// - Parameter entry: A parsed assistant usage entry from any provider.
    /// - Returns: Local pricing cost, or positive upstream cost when local pricing is missing.
    func resolvedCost(for entry: ParsedUsageEntry) -> Double {
        let (engineCost, pricing) = pricingEngine.calculateCost(
            usage: entry.usage,
            model: entry.model
        )
        if pricing == nil, let upstream = entry.upstreamCost, upstream > 0 {
            return upstream
        }
        return engineCost
    }
}
```

- [ ] **Step 3: Replace aggregator private cost logic**

In `UsageAggregator`, replace:

```swift
private let pricingEngine = PricingEngine()
```

with:

```swift
private let costResolver = UsageCostResolver()
```

Replace:

```swift
let cost = resolvedCost(for: entry)
```

with:

```swift
let cost = costResolver.resolvedCost(for: entry)
```

Delete the private `resolvedCost(for:)` method from `UsageAggregator`.

- [ ] **Step 4: Run aggregation tests**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/UsageAggregatorTests test
```

Expected: pass, including the existing upstream-cost fallback test.

- [ ] **Step 5: Commit**

```bash
git add TokenWatch/Analytics/UsageCostResolver.swift TokenWatch/Analytics/UsageAggregator.swift
git commit -m "refactor(stats): 复用用量成本解析"
```

---

### Task 3: Expose Time Window Filtering

**Files:**
- Modify: `TokenWatch/ViewControllers/MonthlyTokenChartBuilder.swift`
- Modify: `TokenWatch/Localization/AppStrings.swift`
- Modify: `TokenWatchTests/ViewControllers/MonthlyTokenChartBuilderTests.swift`

- [ ] **Step 1: Write failing period interval tests**

Append to `MonthlyTokenChartBuilderTests`:

```swift
@Test("最近七天窗口包含今天并向前回溯六天")
func recentSevenDaysWindowIncludesTodayAndSixPreviousDays() {
    let calendar = utcCalendar()
    let now = dateTime(2026, 6, 20, hour: 14, minute: 30, calendar: calendar)
    let interval = UsageStatsPeriod.recent7Days.entryDateInterval(now: now, calendar: calendar)

    #expect(interval.start == date(2026, 6, 14, calendar: calendar))
    #expect(interval.end == date(2026, 6, 21, calendar: calendar))
}

@Test("本日窗口使用自然日半开区间")
func todayEntryWindowUsesLocalDayHalfOpenInterval() {
    let calendar = utcCalendar()
    let now = dateTime(2026, 6, 20, hour: 14, minute: 30, calendar: calendar)
    let interval = UsageStatsPeriod.today.entryDateInterval(now: now, calendar: calendar)

    #expect(interval.start == date(2026, 6, 20, calendar: calendar))
    #expect(interval.end == date(2026, 6, 21, calendar: calendar))
}

@Test("最近十二个月窗口结束于下一自然月")
func recentTwelveMonthEntryWindowEndsAtNextMonth() {
    let calendar = utcCalendar()
    let now = dateTime(2026, 6, 20, hour: 14, minute: 30, calendar: calendar)
    let interval = UsageStatsPeriod.recent12Months.entryDateInterval(now: now, calendar: calendar)

    #expect(interval.start == date(2025, 7, 1, calendar: calendar))
    #expect(interval.end == date(2026, 7, 1, calendar: calendar))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/MonthlyTokenChartBuilderTests test
```

Expected: compile failure because `.recent7Days` and `entryDateInterval` do not exist.

- [ ] **Step 3: Add period case and reusable interval**

In `UsageStatsPeriod`, add:

```swift
case recent7Days
```

Update `title(language:)`:

```swift
case .recent7Days:
    return AppStrings.text(.sidebarRecent7Days, language: language)
```

Update `bucketCount`:

```swift
case .recent7Days:
    return 7
```

Update `calendarComponent`:

```swift
case .recent7Days:
    return .day
```

Update `currentBucketStart(now:calendar:)`, `windowStart(currentBucketStart:now:calendar:)`, `bucketKey(for:calendar:)`, `bucketLabel(for:calendar:language:)`, and `summary(in:for:)` so `.recent7Days` uses the same behavior as `.recent30Days`, except `bucketCount == 7`.

Add this internal method to `UsageStatsPeriod`:

```swift
func entryDateInterval(now: Date, calendar: Calendar) -> DateInterval {
    let currentStart = currentBucketStart(now: now, calendar: calendar)
    let start = windowStart(currentBucketStart: currentStart, now: now, calendar: calendar)
    let end: Date
    switch self {
    case .recent12Months:
        end = calendar.date(byAdding: .month, value: 1, to: currentStart) ?? now
    case .recent7Days, .recent30Days, .today:
        let dayStart = calendar.startOfDay(for: now)
        end = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? now
    }
    return DateInterval(start: start, end: end)
}
```

- [ ] **Step 4: Add localized title key**

In `AppStringKey`, add:

```swift
case sidebarRecent7Days
```

Add at least these English and Simplified Chinese strings:

```swift
.sidebarRecent7Days: "最近 7 天",
```

```swift
.sidebarRecent7Days: "Last 7 Days",
```

Add matching values to the other language tables to preserve current localization completeness:

```swift
.sidebarRecent7Days: "最近 7 天",
.sidebarRecent7Days: "過去7日",
.sidebarRecent7Days: "최근 7일",
.sidebarRecent7Days: "Últimos 7 días",
.sidebarRecent7Days: "Letzte 7 Tage",
.sidebarRecent7Days: "7 derniers jours",
.sidebarRecent7Days: "Últimos 7 dias",
.sidebarRecent7Days: "Ultimi 7 giorni",
.sidebarRecent7Days: "Afgelopen 7 dagen",
.sidebarRecent7Days: "Ostatnie 7 dni",
```

Use the first value for `zhHant`, the second for `ja`, the third for `ko`, then `es`, `de`, `fr`, `ptBR`, `it`, `nl`, `pl`.

Update the exhaustive `makeStats(for:)` helper in `TokenWatchTests/ViewControllers/MonthlyStatsViewControllerTests.swift` so the test target still compiles after adding `.recent7Days`:

```swift
case .recent7Days:
    return makeStats(
        byDay: [
            "2026-06-20": makeSummary(total: 500_000, cost: 2.5, modelBreakdown: ["claude-sonnet": 500_000])
        ],
        byMonth: [:]
    )
```

- [ ] **Step 5: Run period and localization tests**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/MonthlyTokenChartBuilderTests -only-testing:TokenWatchTests/AppLanguageSettingsTests test
```

Expected: both suites pass.

- [ ] **Step 6: Commit**

```bash
git add TokenWatch/ViewControllers/MonthlyTokenChartBuilder.swift TokenWatch/Localization/AppStrings.swift TokenWatchTests/ViewControllers/MonthlyTokenChartBuilderTests.swift
git commit -m "feat(stats): 增加最近七天时间窗口"
```

---

### Task 4: Build Recent Session Rows

**Files:**
- Create: `TokenWatch/ViewControllers/RecentSessionDetailsBuilder.swift`
- Create: `TokenWatchTests/ViewControllers/RecentSessionDetailsBuilderTests.swift`

- [ ] **Step 1: Write builder tests**

Create `TokenWatchTests/ViewControllers/RecentSessionDetailsBuilderTests.swift`:

```swift
import Foundation
import Testing
@testable import TokenWatch

@Suite("RecentSessionDetailsBuilder")
struct RecentSessionDetailsBuilderTests {

    @Test("按 provider + sessionID 聚合且不同 provider 不混并")
    func groupsByProviderAndSessionID() {
        let calendar = utcCalendar()
        let now = dateTime(2026, 6, 20, hour: 12, minute: 0, calendar: calendar)
        let states: [ProviderID: TokenStatsViewModel.ProviderState] = [
            .claude: .init(
                stats: makeStats(),
                entries: [makeEntry(provider: .claude, sessionID: "same", timestamp: dateTime(2026, 6, 20, hour: 9, minute: 0, calendar: calendar), model: "m1", input: 100, output: 20)],
                isLoading: false,
                errorMessage: nil,
                needsAuthorization: false
            ),
            .codex: .init(
                stats: makeStats(),
                entries: [makeEntry(provider: .codex, sessionID: "same", timestamp: dateTime(2026, 6, 20, hour: 10, minute: 0, calendar: calendar), model: "m2", input: 200, output: 40)],
                isLoading: false,
                errorMessage: nil,
                needsAuthorization: false
            ),
        ]

        let snapshot = RecentSessionDetailsBuilder.build(
            states: states,
            period: .today,
            now: now,
            calendar: calendar
        )

        #expect(snapshot.rows.map(\.id) == ["codex:same", "claude:same"])
        #expect(snapshot.rows.map(\.totalTokens) == [240, 120])
        #expect(snapshot.totalSessionCount == 2)
        #expect(snapshot.loadedProviderCount == 2)
    }

    @Test("筛选窗口只统计窗口内 entry")
    func filtersEntriesByPeriodWindow() {
        let calendar = utcCalendar()
        let now = dateTime(2026, 6, 20, hour: 12, minute: 0, calendar: calendar)
        let states: [ProviderID: TokenStatsViewModel.ProviderState] = [
            .claude: .init(
                stats: makeStats(),
                entries: [
                    makeEntry(provider: .claude, sessionID: "s1", timestamp: dateTime(2026, 6, 13, hour: 23, minute: 59, calendar: calendar), model: "m1", input: 900, output: 0),
                    makeEntry(provider: .claude, sessionID: "s1", timestamp: dateTime(2026, 6, 14, hour: 0, minute: 0, calendar: calendar), model: "m1", input: 100, output: 10),
                    makeEntry(provider: .claude, sessionID: "s1", timestamp: dateTime(2026, 6, 20, hour: 23, minute: 59, calendar: calendar), model: "m1", input: 200, output: 20),
                    makeEntry(provider: .claude, sessionID: "s1", timestamp: dateTime(2026, 6, 21, hour: 0, minute: 0, calendar: calendar), model: "m1", input: 800, output: 0),
                ],
                isLoading: false,
                errorMessage: nil,
                needsAuthorization: false
            ),
        ]

        let snapshot = RecentSessionDetailsBuilder.build(
            states: states,
            period: .recent7Days,
            now: now,
            calendar: calendar
        )

        #expect(snapshot.rows.count == 1)
        #expect(snapshot.rows[0].totalTokens == 330)
        #expect(snapshot.rows[0].firstActiveAt == dateTime(2026, 6, 14, hour: 0, minute: 0, calendar: calendar))
        #expect(snapshot.rows[0].lastActiveAt == dateTime(2026, 6, 20, hour: 23, minute: 59, calendar: calendar))
    }

    @Test("排序按最近时间、token、provider、sessionID 稳定排序")
    func sortsRowsByRecentActivityAndStableTieBreakers() {
        let calendar = utcCalendar()
        let t = dateTime(2026, 6, 20, hour: 10, minute: 0, calendar: calendar)
        let states: [ProviderID: TokenStatsViewModel.ProviderState] = [
            .claude: .init(
                stats: makeStats(),
                entries: [
                    makeEntry(provider: .claude, sessionID: "b", timestamp: t, model: "m1", input: 100, output: 0),
                    makeEntry(provider: .claude, sessionID: "a", timestamp: t, model: "m1", input: 200, output: 0),
                    makeEntry(provider: .codex, sessionID: "a", timestamp: dateTime(2026, 6, 20, hour: 11, minute: 0, calendar: calendar), model: "m1", input: 50, output: 0),
                ],
                isLoading: false,
                errorMessage: nil,
                needsAuthorization: false
            ),
        ]

        let snapshot = RecentSessionDetailsBuilder.build(
            states: states,
            period: .today,
            now: dateTime(2026, 6, 20, hour: 12, minute: 0, calendar: calendar),
            calendar: calendar
        )

        #expect(snapshot.rows.map(\.id) == ["codex:a", "claude:a", "claude:b"])
    }

    @Test("主模型取 token 最大模型并记录额外模型数量")
    func primaryModelUsesLargestTokenModel() {
        let calendar = utcCalendar()
        let now = dateTime(2026, 6, 20, hour: 12, minute: 0, calendar: calendar)
        let states: [ProviderID: TokenStatsViewModel.ProviderState] = [
            .opencode: .init(
                stats: makeStats(),
                entries: [
                    makeEntry(provider: .opencode, sessionID: "s", timestamp: now, model: "b-model", input: 100, output: 0, upstreamProviderID: "openai"),
                    makeEntry(provider: .opencode, sessionID: "s", timestamp: now, model: "a-model", input: 100, output: 0, upstreamProviderID: "anthropic"),
                    makeEntry(provider: .opencode, sessionID: "s", timestamp: now, model: "z-model", input: 50, output: 0, upstreamProviderID: "openai"),
                ],
                isLoading: false,
                errorMessage: nil,
                needsAuthorization: false
            ),
        ]

        let row = RecentSessionDetailsBuilder.build(
            states: states,
            period: .today,
            now: now,
            calendar: calendar
        ).rows[0]

        #expect(row.primaryModel == "a-model")
        #expect(row.additionalModelCount == 2)
        #expect(row.upstreamProviderIDs == ["anthropic", "openai"])
    }

    @Test("项目路径取最近非空 cwd 且 subagent 标记会聚合")
    func projectPathUsesLatestNonEmptyCwdAndSubagentFlagAggregates() {
        let calendar = utcCalendar()
        let now = dateTime(2026, 6, 20, hour: 12, minute: 0, calendar: calendar)
        let states: [ProviderID: TokenStatsViewModel.ProviderState] = [
            .claude: .init(
                stats: makeStats(),
                entries: [
                    makeEntry(provider: .claude, sessionID: "s", timestamp: dateTime(2026, 6, 20, hour: 9, minute: 0, calendar: calendar), model: "m1", input: 50, output: 0, cwd: "/old", isSubagent: false),
                    makeEntry(provider: .claude, sessionID: "s", timestamp: dateTime(2026, 6, 20, hour: 10, minute: 0, calendar: calendar), model: "m1", input: 50, output: 0, cwd: nil, isSubagent: true),
                    makeEntry(provider: .claude, sessionID: "s", timestamp: dateTime(2026, 6, 20, hour: 11, minute: 0, calendar: calendar), model: "m1", input: 50, output: 0, cwd: "/new", isSubagent: false),
                ],
                isLoading: false,
                errorMessage: nil,
                needsAuthorization: false
            ),
        ]

        let row = RecentSessionDetailsBuilder.build(
            states: states,
            period: .today,
            now: now,
            calendar: calendar
        ).rows[0]

        #expect(row.projectPath == "/new")
        #expect(row.isSubagentIncluded)
    }

    @Test("统计 provider 状态和错误")
    func countsProviderStatesAndErrors() {
        let calendar = utcCalendar()
        let snapshot = RecentSessionDetailsBuilder.build(
            states: [
                .claude: .init(stats: makeStats(), entries: [], isLoading: false, errorMessage: nil, needsAuthorization: false),
                .codex: .init(stats: nil, entries: nil, isLoading: true, errorMessage: nil, needsAuthorization: false),
                .opencode: .init(stats: nil, entries: nil, isLoading: false, errorMessage: "opencode failed", needsAuthorization: true),
            ],
            period: .today,
            now: dateTime(2026, 6, 20, hour: 12, minute: 0, calendar: calendar),
            calendar: calendar
        )

        #expect(snapshot.loadedProviderCount == 1)
        #expect(snapshot.loadingProviderCount == 1)
        #expect(snapshot.unauthorizedProviderCount == 1)
        #expect(snapshot.errorMessages == ["opencode failed"])
    }

    private func makeEntry(
        provider: ProviderID,
        sessionID: String,
        timestamp: Date?,
        model: String,
        input: Int,
        output: Int,
        cwd: String? = "/project",
        isSubagent: Bool = false,
        upstreamProviderID: String? = nil
    ) -> ParsedUsageEntry {
        ParsedUsageEntry(
            recordUUID: "\(provider.rawValue)-\(sessionID)-\(UUID().uuidString)",
            messageId: "\(provider.rawValue)-\(sessionID)-\(UUID().uuidString)",
            requestId: nil,
            sessionID: sessionID,
            timestamp: timestamp,
            model: model,
            cwd: cwd,
            agentId: nil,
            usage: TokenUsage(
                inputTokens: input,
                cacheCreationInputTokens: 0,
                cacheReadInputTokens: 0,
                outputTokens: output,
                serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
                serviceTier: "",
                cacheCreation: CacheCreation(ephemeral1hInputTokens: 0, ephemeral5mInputTokens: 0),
                inferenceGeo: "",
                iterations: [],
                speed: ""
            ),
            isSubagent: isSubagent,
            provider: provider,
            upstreamProviderID: upstreamProviderID,
            upstreamCost: nil
        )
    }

    private func makeStats() -> AggregatedStats {
        .zero
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: year, month: month, day: day))!
    }

    private func dateTime(_ year: Int, _ month: Int, _ day: Int, hour: Int, minute: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/RecentSessionDetailsBuilderTests test
```

Expected: compile failure because `RecentSessionDetailsBuilder` and related snapshot types do not exist.

- [ ] **Step 3: Implement builder**

Create `TokenWatch/ViewControllers/RecentSessionDetailsBuilder.swift`:

```swift
import Foundation

struct RecentSessionDetailsSnapshot: Sendable, Equatable {
    let rows: [RecentSessionRow]
    let totalSessionCount: Int
    let totalTokens: Int
    let totalCost: Double
    let loadedProviderCount: Int
    let loadingProviderCount: Int
    let unauthorizedProviderCount: Int
    let errorMessages: [String]
}

struct RecentSessionRow: Sendable, Equatable, Identifiable {
    let id: String
    let provider: ProviderID
    let sessionID: String
    let projectPath: String?
    let primaryModel: String
    let additionalModelCount: Int
    let firstActiveAt: Date?
    let lastActiveAt: Date?
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheCreationTokens: Int
    let reasoningTokens: Int
    let totalTokens: Int
    let cost: Double
    let entryCount: Int
    let modelBreakdown: [String: UsageSummary]
    let upstreamProviderIDs: [String]
    let isSubagentIncluded: Bool
}

enum RecentSessionDetailsBuilder {
    private struct SessionKey: Hashable {
        let provider: ProviderID
        let sessionID: String
    }

    static func build(
        states: [ProviderID: TokenStatsViewModel.ProviderState],
        period: UsageStatsPeriod,
        now: Date,
        calendar: Calendar
    ) -> RecentSessionDetailsSnapshot {
        let costResolver = UsageCostResolver()
        var loadedProviderCount = 0
        var loadingProviderCount = 0
        var unauthorizedProviderCount = 0
        var errorMessages: [String] = []
        var groups: [SessionKey: RecentSessionAccumulator] = [:]

        for (providerID, state) in states {
            if state.isLoading {
                loadingProviderCount += 1
            }
            if state.needsAuthorization {
                unauthorizedProviderCount += 1
            }
            if let errorMessage = state.errorMessage {
                errorMessages.append(errorMessage)
            }
            guard state.stats != nil || state.entries != nil else { continue }
            loadedProviderCount += 1

            for entry in state.entries ?? [] {
                guard let timestamp = entry.timestamp else { continue }
                guard period.containsEntryDate(timestamp, now: now, calendar: calendar) else { continue }

                let key = SessionKey(provider: providerID, sessionID: entry.sessionID)
                let cost = costResolver.resolvedCost(for: entry)
                groups[key, default: RecentSessionAccumulator(provider: providerID, sessionID: entry.sessionID)]
                    .add(entry, cost: cost)
            }
        }

        let rows = groups.values
            .map { $0.makeRow() }
            .sorted { lhs, rhs in
                switch RecentSessionDetailsBuilder.compare(lhs, rhs) {
                case .orderedAscending:
                    return true
                case .orderedDescending, .orderedSame:
                    return false
                }
            }

        return RecentSessionDetailsSnapshot(
            rows: rows,
            totalSessionCount: rows.count,
            totalTokens: rows.reduce(0) { $0 + $1.totalTokens },
            totalCost: rows.reduce(0) { $0 + $1.cost },
            loadedProviderCount: loadedProviderCount,
            loadingProviderCount: loadingProviderCount,
            unauthorizedProviderCount: unauthorizedProviderCount,
            errorMessages: errorMessages
        )
    }

    private static func compare(_ lhs: RecentSessionRow, _ rhs: RecentSessionRow) -> ComparisonResult {
        if lhs.lastActiveAt != rhs.lastActiveAt {
            return (lhs.lastActiveAt ?? .distantPast) > (rhs.lastActiveAt ?? .distantPast)
                ? .orderedAscending
                : .orderedDescending
        }
        if lhs.totalTokens != rhs.totalTokens {
            return lhs.totalTokens > rhs.totalTokens ? .orderedAscending : .orderedDescending
        }
        if lhs.provider.rawValue != rhs.provider.rawValue {
            return lhs.provider.rawValue < rhs.provider.rawValue ? .orderedAscending : .orderedDescending
        }
        if lhs.sessionID != rhs.sessionID {
            return lhs.sessionID < rhs.sessionID ? .orderedAscending : .orderedDescending
        }
        return .orderedSame
    }
}
```

In the same file, add the private accumulator:

```swift
private struct RecentSessionAccumulator {
    let provider: ProviderID
    let sessionID: String
    private(set) var projectPath: String?
    private(set) var projectPathTimestamp: Date?
    private(set) var firstActiveAt: Date?
    private(set) var lastActiveAt: Date?
    private(set) var inputTokens = 0
    private(set) var outputTokens = 0
    private(set) var cacheReadTokens = 0
    private(set) var cacheCreationTokens = 0
    private(set) var reasoningTokens = 0
    private(set) var cost = 0.0
    private(set) var entryCount = 0
    private(set) var modelTotals: [String: UsageSummaryAccumulatorForRecentSessions] = [:]
    private(set) var upstreamProviderIDs = Set<String>()
    private(set) var isSubagentIncluded = false

    mutating func add(_ entry: ParsedUsageEntry, cost entryCost: Double) {
        if let timestamp = entry.timestamp {
            firstActiveAt = min(firstActiveAt ?? timestamp, timestamp)
            lastActiveAt = max(lastActiveAt ?? timestamp, timestamp)
            if let cwd = entry.cwd, !cwd.isEmpty,
               projectPathTimestamp == nil || timestamp >= (projectPathTimestamp ?? .distantPast) {
                projectPath = cwd
                projectPathTimestamp = timestamp
            }
        }

        inputTokens += entry.usage.inputTokens
        outputTokens += entry.usage.outputTokens
        cacheReadTokens += entry.usage.cacheReadInputTokens
        cacheCreationTokens += entry.usage.totalCacheCreationTokens
        reasoningTokens += entry.usage.reasoningTokens
        cost += entryCost
        entryCount += 1
        modelTotals[entry.model, default: UsageSummaryAccumulatorForRecentSessions()].add(entry, cost: entryCost)
        if let upstream = entry.upstreamProviderID, !upstream.isEmpty {
            upstreamProviderIDs.insert(upstream)
        }
        isSubagentIncluded = isSubagentIncluded || entry.isSubagent
    }

    func makeRow() -> RecentSessionRow {
        let modelBreakdown = modelTotals.mapValues { $0.makeSummary() }
        let primaryModel = modelBreakdown
            .sorted { lhs, rhs in
                if lhs.value.totalTokens != rhs.value.totalTokens {
                    return lhs.value.totalTokens > rhs.value.totalTokens
                }
                return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
            }
            .first?.key ?? "unknown"

        return RecentSessionRow(
            id: "\(provider.rawValue):\(sessionID)",
            provider: provider,
            sessionID: sessionID,
            projectPath: projectPath,
            primaryModel: primaryModel,
            additionalModelCount: max(0, modelBreakdown.count - 1),
            firstActiveAt: firstActiveAt,
            lastActiveAt: lastActiveAt,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheReadTokens,
            cacheCreationTokens: cacheCreationTokens,
            reasoningTokens: reasoningTokens,
            totalTokens: inputTokens + outputTokens + cacheReadTokens + cacheCreationTokens + reasoningTokens,
            cost: cost,
            entryCount: entryCount,
            modelBreakdown: modelBreakdown,
            upstreamProviderIDs: upstreamProviderIDs.sorted(),
            isSubagentIncluded: isSubagentIncluded
        )
    }
}

private struct UsageSummaryAccumulatorForRecentSessions {
    private(set) var inputTokens = 0
    private(set) var outputTokens = 0
    private(set) var cacheReadTokens = 0
    private(set) var cacheCreationTokens = 0
    private(set) var reasoningTokens = 0
    private(set) var cost = 0.0
    private(set) var entryCount = 0

    mutating func add(_ entry: ParsedUsageEntry, cost entryCost: Double) {
        inputTokens += entry.usage.inputTokens
        outputTokens += entry.usage.outputTokens
        cacheReadTokens += entry.usage.cacheReadInputTokens
        cacheCreationTokens += entry.usage.totalCacheCreationTokens
        reasoningTokens += entry.usage.reasoningTokens
        cost += entryCost
        entryCount += 1
    }

    func makeSummary() -> UsageSummary {
        UsageSummary(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheReadTokens,
            cacheCreationTokens: cacheCreationTokens,
            reasoningTokens: reasoningTokens,
            totalTokens: inputTokens + outputTokens + cacheReadTokens + cacheCreationTokens + reasoningTokens,
            cost: cost,
            entryCount: entryCount,
            modelBreakdown: [:]
        )
    }
}
```

- [ ] **Step 4: Run builder tests**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/RecentSessionDetailsBuilderTests test
```

Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add TokenWatch/ViewControllers/RecentSessionDetailsBuilder.swift TokenWatchTests/ViewControllers/RecentSessionDetailsBuilderTests.swift
git commit -m "feat(stats): 构建最近会话明细数据"
```

---

### Task 5: Render Recent Session Details View

**Files:**
- Create: `TokenWatch/ViewControllers/RecentSessionDetailsView.swift`
- Modify: `TokenWatch/Localization/AppStrings.swift`
- Create: `TokenWatchTests/ViewControllers/RecentSessionDetailsViewTests.swift`

- [ ] **Step 1: Add localization keys and tests**

In `AppStringKey`, add:

```swift
case recentDetailsTitle
case recentDetailsEmpty
case recentDetailsTime
case recentDetailsSession
case recentDetailsTool
case recentDetailsProject
case recentDetailsModel
case recentDetailsTokens
case recentDetailsCost
case recentDetailsRecords
```

Add English strings so `englishStringTableCoversAllKeys` passes:

```swift
.recentDetailsTitle: "Recent Details",
.recentDetailsEmpty: "No recent session details",
.recentDetailsTime: "Time",
.recentDetailsSession: "Session",
.recentDetailsTool: "Tool",
.recentDetailsProject: "Project",
.recentDetailsModel: "Model",
.recentDetailsTokens: "Tokens",
.recentDetailsCost: "Cost",
.recentDetailsRecords: "Records",
```

Add Simplified Chinese strings:

```swift
.recentDetailsTitle: "最近明细",
.recentDetailsEmpty: "当前筛选暂无会话明细",
.recentDetailsTime: "时间",
.recentDetailsSession: "会话",
.recentDetailsTool: "工具",
.recentDetailsProject: "项目",
.recentDetailsModel: "模型",
.recentDetailsTokens: "Token",
.recentDetailsCost: "成本",
.recentDetailsRecords: "记录",
```

For the other language tables, add either localized strings or the English strings above. The existing fallback allows English, but adding every table keeps the file's current style consistent.

- [ ] **Step 2: Write view tests**

Create `TokenWatchTests/ViewControllers/RecentSessionDetailsViewTests.swift`:

```swift
import AppKit
import Foundation
import Testing
@testable import TokenWatch

@MainActor
@Suite("RecentSessionDetailsView")
struct RecentSessionDetailsViewTests {

    @Test("展示最近会话明细行")
    func rendersRows() {
        let view = RecentSessionDetailsView()
        let snapshot = RecentSessionDetailsSnapshot(
            rows: [
                RecentSessionRow(
                    id: "claude:s1",
                    provider: .claude,
                    sessionID: "s1",
                    projectPath: "/Users/me/project",
                    primaryModel: "claude-sonnet-4-5",
                    additionalModelCount: 1,
                    firstActiveAt: Date(timeIntervalSince1970: 1_800_000_000),
                    lastActiveAt: Date(timeIntervalSince1970: 1_800_000_060),
                    inputTokens: 100,
                    outputTokens: 50,
                    cacheReadTokens: 20,
                    cacheCreationTokens: 0,
                    reasoningTokens: 0,
                    totalTokens: 170,
                    cost: 0.1234,
                    entryCount: 2,
                    modelBreakdown: [:],
                    upstreamProviderIDs: [],
                    isSubagentIncluded: false
                )
            ],
            totalSessionCount: 1,
            totalTokens: 170,
            totalCost: 0.1234,
            loadedProviderCount: 1,
            loadingProviderCount: 0,
            unauthorizedProviderCount: 0,
            errorMessages: []
        )

        view.configure(with: snapshot, language: .zhHans)

        #expect(view.debugTitleText == "最近明细")
        #expect(view.debugRowTexts.count == 1)
        #expect(view.debugRowTexts[0].contains("s1"))
        #expect(view.debugRowTexts[0].contains("Claude"))
        #expect(view.debugRowTexts[0].contains("claude-sonnet-4-5 +1"))
        #expect(view.debugRowTexts[0].contains("170"))
        #expect(view.debugEmptyText == "")
    }

    @Test("无行时展示空状态")
    func rendersEmptyState() {
        let view = RecentSessionDetailsView()
        let snapshot = RecentSessionDetailsSnapshot(
            rows: [],
            totalSessionCount: 0,
            totalTokens: 0,
            totalCost: 0,
            loadedProviderCount: 1,
            loadingProviderCount: 0,
            unauthorizedProviderCount: 0,
            errorMessages: []
        )

        view.configure(with: snapshot, language: .zhHans)

        #expect(view.debugRowTexts.isEmpty)
        #expect(view.debugEmptyText == "当前筛选暂无会话明细")
    }
}
```

- [ ] **Step 3: Run view tests to verify they fail**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/RecentSessionDetailsViewTests test
```

Expected: compile failure because `RecentSessionDetailsView` does not exist.

- [ ] **Step 4: Implement AppKit view**

Create `TokenWatch/ViewControllers/RecentSessionDetailsView.swift`:

```swift
import AppKit

@MainActor
final class RecentSessionDetailsView: NSView {
    private static let rowHeight: CGFloat = 28
    private static let timeWidth: CGFloat = 96
    private static let sessionWidth: CGFloat = 110
    private static let toolWidth: CGFloat = 68
    private static let projectWidth: CGFloat = 145
    private static let modelWidth: CGFloat = 130
    private static let tokensWidth: CGFloat = 76
    private static let costWidth: CGFloat = 68
    private static let recordsWidth: CGFloat = 52

    private let titleLabel = NSTextField(labelWithString: "")
    private let headerStack = NSStackView()
    private let rowsStack = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private let dateFormatter = DateFormatter()
    private(set) var debugRowTexts: [String] = []

    var debugTitleText: String { titleLabel.stringValue }
    var debugEmptyText: String { emptyLabel.isHidden ? "" : emptyLabel.stringValue }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(with snapshot: RecentSessionDetailsSnapshot, language: AppLanguage) {
        titleLabel.stringValue = AppStrings.text(.recentDetailsTitle, language: language)
        emptyLabel.stringValue = AppStrings.text(.recentDetailsEmpty, language: language)
        configureHeader(language: language)
        renderRows(snapshot.rows, language: language)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = .secondaryLabelColor

        headerStack.orientation = .horizontal
        headerStack.spacing = 8
        headerStack.alignment = .centerY
        rowsStack.orientation = .vertical
        rowsStack.spacing = 2
        rowsStack.alignment = .leading

        let stack = NSStackView(views: [titleLabel, headerStack, rowsStack, emptyLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        addSubview(stack)

        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func configureHeader(language: AppLanguage) {
        headerStack.setViews([
            makeHeader(AppStrings.text(.recentDetailsTime, language: language), width: Self.timeWidth),
            makeHeader(AppStrings.text(.recentDetailsSession, language: language), width: Self.sessionWidth),
            makeHeader(AppStrings.text(.recentDetailsTool, language: language), width: Self.toolWidth),
            makeHeader(AppStrings.text(.recentDetailsProject, language: language), width: Self.projectWidth),
            makeHeader(AppStrings.text(.recentDetailsModel, language: language), width: Self.modelWidth),
            makeHeader(AppStrings.text(.recentDetailsTokens, language: language), width: Self.tokensWidth, alignment: .right),
            makeHeader(AppStrings.text(.recentDetailsCost, language: language), width: Self.costWidth, alignment: .right),
            makeHeader(AppStrings.text(.recentDetailsRecords, language: language), width: Self.recordsWidth, alignment: .right),
        ], in: .leading)
    }

    private func renderRows(_ rows: [RecentSessionRow], language: AppLanguage) {
        rowsStack.setViews([], in: .top)
        debugRowTexts = []
        emptyLabel.isHidden = !rows.isEmpty

        for row in rows {
            let labels = [
                makeCell(row.lastActiveAt.map { dateFormatter.string(from: $0) } ?? "-", width: Self.timeWidth),
                makeCell(row.sessionID, width: Self.sessionWidth),
                makeCell(providerName(row.provider), width: Self.toolWidth),
                makeCell(row.projectPath ?? "unknown", width: Self.projectWidth),
                makeCell(modelText(row), width: Self.modelWidth),
                makeCell(Self.formatInt(row.totalTokens), width: Self.tokensWidth, alignment: .right, monospaced: true),
                makeCell(String(format: "$%.4f", row.cost), width: Self.costWidth, alignment: .right, monospaced: true),
                makeCell(Self.formatInt(row.entryCount), width: Self.recordsWidth, alignment: .right, monospaced: true),
            ]
            let rowStack = NSStackView(views: labels)
            rowStack.orientation = .horizontal
            rowStack.spacing = 8
            rowStack.alignment = .centerY
            rowStack.heightAnchor.constraint(equalToConstant: Self.rowHeight).isActive = true
            rowsStack.addArrangedSubview(rowStack)
            debugRowTexts.append(labels.map(\.stringValue).joined(separator: " "))
        }
    }

    private func makeHeader(_ text: String, width: CGFloat, alignment: NSTextAlignment = .left) -> NSTextField {
        let label = makeCell(text, width: width, alignment: alignment)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func makeCell(
        _ text: String,
        width: CGFloat,
        alignment: NSTextAlignment = .left,
        monospaced: Bool = false
    ) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = monospaced
            ? .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            : .systemFont(ofSize: 12)
        label.alignment = alignment
        label.lineBreakMode = .byTruncatingMiddle
        label.toolTip = text
        label.widthAnchor.constraint(equalToConstant: width).isActive = true
        return label
    }

    private func modelText(_ row: RecentSessionRow) -> String {
        row.additionalModelCount > 0
            ? "\(row.primaryModel) +\(row.additionalModelCount)"
            : row.primaryModel
    }

    private func providerName(_ provider: ProviderID) -> String {
        switch provider {
        case .claude:
            return "Claude"
        case .codex:
            return "Codex"
        case .opencode:
            return "opencode"
        }
    }

    private static func formatInt(_ value: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }
}
```

- [ ] **Step 5: Run view and localization tests**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/RecentSessionDetailsViewTests -only-testing:TokenWatchTests/AppLanguageSettingsTests test
```

Expected: pass.

- [ ] **Step 6: Commit**

```bash
git add TokenWatch/ViewControllers/RecentSessionDetailsView.swift TokenWatch/Localization/AppStrings.swift TokenWatchTests/ViewControllers/RecentSessionDetailsViewTests.swift
git commit -m "feat(stats): 展示最近会话明细视图"
```

---

### Task 6: Integrate Details Into Time Window Page

**Files:**
- Modify: `TokenWatch/ViewControllers/MonthlyStatsViewController.swift`
- Modify: `TokenWatchTests/ViewControllers/MonthlyStatsViewControllerTests.swift`

- [ ] **Step 1: Write failing controller tests**

Append these tests inside `MonthlyStatsViewControllerTests`:

```swift
@MainActor
@Test("时间窗口页展示最近会话明细")
func rendersRecentSessionDetailsRows() {
    let calendar = utcCalendar()
    let viewController = MonthlyStatsViewController(
        period: .today,
        stateProvider: {
            [.claude: .init(
                stats: makeStats(
                    byHour: ["2026-06-20T10": makeSummary(total: 150)],
                    byMonth: [:]
                ),
                entries: [
                    makeEntry(
                        provider: .claude,
                        sessionID: "session-1",
                        timestamp: dateTime(2026, 6, 20, hour: 10, minute: 0, calendar: calendar),
                        model: "claude-sonnet-4-5",
                        input: 100,
                        output: 50
                    )
                ],
                isLoading: false,
                errorMessage: nil,
                needsAuthorization: false
            )]
        },
        nowProvider: { dateTime(2026, 6, 20, hour: 12, minute: 0, calendar: calendar) },
        calendar: calendar,
        languageSettings: zhHansLanguageSettings()
    )

    viewController.loadViewIfNeeded()

    #expect(viewController.debugRecentSessionRowTexts.count == 1)
    #expect(viewController.debugRecentSessionRowTexts[0].contains("session-1"))
    #expect(viewController.debugRecentSessionRowTexts[0].contains("Claude"))
    #expect(viewController.debugRecentSessionRowTexts[0].contains("claude-sonnet-4-5"))
    #expect(viewController.debugRecentSessionRowTexts[0].contains("150"))
}

@MainActor
@Test("时间窗口页无最近会话时展示明细空状态")
func rendersRecentSessionDetailsEmptyState() {
    let calendar = utcCalendar()
    let viewController = MonthlyStatsViewController(
        period: .today,
        stateProvider: {
            [.claude: .init(
                stats: makeStats(byHour: ["2026-06-20T10": makeSummary(total: 0)], byMonth: [:]),
                entries: [],
                isLoading: false,
                errorMessage: nil,
                needsAuthorization: false
            )]
        },
        nowProvider: { dateTime(2026, 6, 20, hour: 12, minute: 0, calendar: calendar) },
        calendar: calendar,
        languageSettings: zhHansLanguageSettings()
    )

    viewController.loadViewIfNeeded()

    #expect(viewController.debugRecentSessionRowTexts.isEmpty)
    #expect(viewController.debugRecentSessionEmptyText == "当前筛选暂无会话明细")
}
```

Add these helpers near the existing `date` and `makeStats` helpers in `MonthlyStatsViewControllerTests`:

```swift
private func dateTime(_ year: Int, _ month: Int, _ day: Int, hour: Int, minute: Int, calendar: Calendar) -> Date {
    calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: year, month: month, day: day, hour: hour, minute: minute))!
}

private func makeEntry(
    provider: ProviderID,
    sessionID: String,
    timestamp: Date?,
    model: String,
    input: Int,
    output: Int
) -> ParsedUsageEntry {
    ParsedUsageEntry(
        recordUUID: "\(provider.rawValue)-\(sessionID)-record",
        messageId: "\(provider.rawValue)-\(sessionID)-message",
        requestId: nil,
        sessionID: sessionID,
        timestamp: timestamp,
        model: model,
        cwd: "/project",
        agentId: nil,
        usage: TokenUsage(
            inputTokens: input,
            cacheCreationInputTokens: 0,
            cacheReadInputTokens: 0,
            outputTokens: output,
            serverToolUse: ServerToolUse(webSearchRequests: 0, webFetchRequests: 0),
            serviceTier: "",
            cacheCreation: CacheCreation(ephemeral1hInputTokens: 0, ephemeral5mInputTokens: 0),
            inferenceGeo: "",
            iterations: [],
            speed: ""
        ),
        isSubagent: false,
        provider: provider,
        upstreamProviderID: nil,
        upstreamCost: nil
    )
}
```

- [ ] **Step 2: Run controller tests to verify they fail**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/MonthlyStatsViewControllerTests test
```

Expected: compile failure because `debugRecentSessionRowTexts` and `debugRecentSessionEmptyText` do not exist.

- [ ] **Step 3: Add view property and debug accessors**

In `MonthlyStatsViewController`, add:

```swift
private let recentDetailsView = RecentSessionDetailsView()
```

Add debug accessors:

```swift
var debugRecentSessionRowTexts: [String] {
    recentDetailsView.debugRowTexts
}

var debugRecentSessionEmptyText: String {
    recentDetailsView.debugEmptyText
}
```

- [ ] **Step 4: Install the section in the content stack**

In `setupSubviews`, set:

```swift
recentDetailsView.translatesAutoresizingMaskIntoConstraints = false
```

Add `recentDetailsView` to the main `contentStack` after `pieChartsStack` and before `statusLabel`:

```swift
let contentStack = NSStackView(views: [
    headerView,
    tokenChartSection.stack,
    costChartSection.stack,
    pieChartsStack,
    recentDetailsView,
    statusLabel
])
```

Add constraints:

```swift
recentDetailsView.leadingAnchor.constraint(equalTo: contentStack.leadingAnchor),
recentDetailsView.trailingAnchor.constraint(lessThanOrEqualTo: contentStack.trailingAnchor),
```

- [ ] **Step 5: Render recent details snapshot**

In `render()`, after `snapshot` is built, build and configure recent details:

```swift
let recentSnapshot = RecentSessionDetailsBuilder.build(
    states: states,
    period: period,
    now: nowProvider(),
    calendar: calendar
)
recentDetailsView.configure(with: recentSnapshot, language: language)
```

Avoid calling `nowProvider()` twice by assigning it once at the top:

```swift
let now = nowProvider()
let snapshot = MonthlyTokenChartBuilder.build(
    states: states,
    period: period,
    now: now,
    calendar: calendar,
    language: language
)
let recentSnapshot = RecentSessionDetailsBuilder.build(
    states: states,
    period: period,
    now: now,
    calendar: calendar
)
```

- [ ] **Step 6: Run controller tests**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/MonthlyStatsViewControllerTests test
```

Expected: pass.

- [ ] **Step 7: Commit**

```bash
git add TokenWatch/ViewControllers/MonthlyStatsViewController.swift TokenWatchTests/ViewControllers/MonthlyStatsViewControllerTests.swift
git commit -m "feat(stats): 接入最近会话明细"
```

---

### Task 7: Final Verification

**Files:**
- No new files.

- [ ] **Step 1: Run focused suites**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests/RecentSessionDetailsBuilderTests -only-testing:TokenWatchTests/RecentSessionDetailsViewTests -only-testing:TokenWatchTests/MonthlyStatsViewControllerTests -only-testing:TokenWatchTests/TokenStatsViewModelObserverTests -only-testing:TokenWatchTests/UsageAggregatorTests -only-testing:TokenWatchTests/MonthlyTokenChartBuilderTests -only-testing:TokenWatchTests/AppLanguageSettingsTests test
```

Expected: all selected tests pass.

- [ ] **Step 2: Run full unit test target**

Run:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests test
```

Expected: all unit tests pass.

- [ ] **Step 3: Run diff check**

Run:

```bash
git diff --check
```

Expected: no output and exit code 0.

- [ ] **Step 4: Commit any final fixes**

If verification required small fixes, commit them with:

```bash
git add TokenWatch TokenWatchTests
git commit -m "fix(stats): 修正最近会话明细验证问题"
```

Skip this commit if there are no changes after Task 6.

---

## Self-Review Notes

- Spec coverage: The plan stores raw entries, builds rows by `provider + sessionID`, filters by time period before grouping, derives the approved fields, sorts by recent activity, and renders the table-like section.
- Scope: The plan does not parse prompts, assistant text, titles, exports, search, pagination, or raw conversation content.
- Type consistency: `RecentSessionDetailsSnapshot`, `RecentSessionRow`, `UsageCostResolver`, and `ProviderState.entries` names are consistent across tests, implementation, and UI integration.
- Verification: Each implementation task includes a failing-test step, a passing-test step, and a commit step.
