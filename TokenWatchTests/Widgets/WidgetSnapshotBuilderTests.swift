import Foundation
import Testing
@testable import TokenWatch

@Suite("Widget snapshot builder")
struct WidgetSnapshotBuilderTests {
    @Test("no provider stats preserves the previous shared snapshot")
    func noValidStatsReturnsNil() {
        let states: [ProviderID: TokenStatsViewModel.ProviderState] = [
            .claude: .init(
                stats: nil,
                isLoading: false,
                errorMessage: nil,
                needsAuthorization: true
            ),
        ]

        #expect(WidgetSnapshotBuilder.build(
            states: states,
            now: fixedNow,
            calendar: shanghaiCalendar,
            language: .zhHans
        ) == nil)
    }

    @Test("valid zero stats still produce fixed render shapes")
    func validZeroStatsBuilds154CellsAnd24Points() throws {
        let snapshot = try #require(WidgetSnapshotBuilder.build(
            states: [.claude: loadedState(stats: makeStats())],
            now: fixedNow,
            calendar: shanghaiCalendar,
            language: .zhHans
        ))

        #expect(snapshot.heatmap.cells.count == 154)
        #expect(snapshot.hourlyLine.points.map(\.hour) == Array(0...23))
        #expect(snapshot.heatmap.totalTokens == 0)
        #expect(snapshot.hourlyLine.totalTokens == 0)
        #expect(WidgetUsageSnapshotValidator.isValid(snapshot))
    }

    @Test("provider totals use saturated addition for the same day and hour")
    func providerTotalsUseSaturatedAddition() throws {
        let almostMaximum = makeSummary(total: Int.max - 10)
        let overflow = makeSummary(total: 50)
        let states: [ProviderID: TokenStatsViewModel.ProviderState] = [
            .claude: loadedState(stats: makeStats(
                byHour: ["2026-07-15T13": almostMaximum],
                byDay: ["2026-07-15": almostMaximum]
            )),
            .codex: loadedState(stats: makeStats(
                byHour: ["2026-07-15T13": overflow],
                byDay: ["2026-07-15": overflow]
            )),
        ]

        let snapshot = try #require(WidgetSnapshotBuilder.build(
            states: states,
            now: fixedNow,
            calendar: shanghaiCalendar,
            language: .zhHans
        ))

        #expect(snapshot.heatmap.cells.first {
            $0.dateKey == "2026-07-15"
        }?.totalTokens == Int.max)
        #expect(snapshot.hourlyLine.points.first {
            $0.hour == 13
        }?.totalTokens == Int.max)
        #expect(snapshot.heatmap.totalTokens == Int.max)
        #expect(snapshot.hourlyLine.totalTokens == Int.max)
    }

    @Test("heatmap preserves padding, real zero days, and builder intensities")
    func heatmapMappingMatchesExistingBuilder() throws {
        let states: [ProviderID: TokenStatsViewModel.ProviderState] = [
            .claude: loadedState(stats: makeStats(byDay: [
                "2026-07-14": makeSummary(total: 100),
                "2026-07-15": makeSummary(total: 0),
            ])),
        ]
        let expected = CalendarHeatmapBuilder.build(
            states: states,
            month: fixedNow,
            now: fixedNow,
            calendar: shanghaiCalendar,
            language: .zhHans
        )
        let actual = try #require(WidgetSnapshotBuilder.build(
            states: states,
            now: fixedNow,
            calendar: shanghaiCalendar,
            language: .zhHans
        ))

        #expect(actual.heatmap.cells.count == expected.cells.count)
        for (source, mapped) in zip(expected.cells, actual.heatmap.cells) {
            switch source {
            case .placeholder:
                #expect(mapped.dateKey == nil)
                #expect(mapped.totalTokens == 0)
                #expect(mapped.intensity == 0)
                #expect(mapped.isPlaceholder)
            case .day(let day):
                #expect(mapped.dateKey == day.dateKey)
                #expect(mapped.totalTokens == day.totalTokens)
                #expect(mapped.intensity == day.intensity)
                #expect(!mapped.isPlaceholder)
            }
        }
        let realZeroDay = try #require(actual.heatmap.cells.first {
            $0.dateKey == "2026-07-15"
        })
        #expect(realZeroDay.totalTokens == 0)
        #expect(!realZeroDay.isPlaceholder)
        #expect(actual.heatmap.cells.contains { $0.isPlaceholder })
    }

    @Test("only the matching wall-clock hour is current")
    func currentHourMarkerUsesHourKey() throws {
        let snapshot = try #require(WidgetSnapshotBuilder.build(
            states: [.claude: loadedState(stats: makeStats())],
            now: fixedNow,
            calendar: shanghaiCalendar,
            language: .zhHans
        ))

        let current = snapshot.hourlyLine.points.filter(\.isCurrentHour)
        #expect(current.count == 1)
        #expect(current.first?.hour == 13)
        #expect(current.first?.hourKey == "2026-07-15T13")
    }

    @Test("spring-forward day remains twenty-four wall-clock buckets")
    func springForwardKeepsTwentyFourWallClockHours() throws {
        try assertTwentyFourWallClockHours(year: 2026, month: 3, day: 8)
    }

    @Test("fall-back day remains twenty-four wall-clock buckets")
    func fallBackKeepsTwentyFourWallClockHours() throws {
        try assertTwentyFourWallClockHours(year: 2026, month: 11, day: 1)
    }

    @Test("English render copy uses the fixed local date")
    func englishRenderCopyIsExact() throws {
        let snapshot = try #require(WidgetSnapshotBuilder.build(
            states: [.claude: loadedState(stats: makeStats())],
            now: fixedNow,
            calendar: shanghaiCalendar,
            language: .en
        ))

        #expect(snapshot.localizedText.heatmapTitle == "Heatmap")
        #expect(snapshot.localizedText.todayUsageTitle == "Today's Usage")
        #expect(snapshot.localizedText.datedUsageTitle == "7/15 Usage")
        #expect(snapshot.localizedText.updatedThroughTitle == "Updated through 7/15")
        #expect(snapshot.localizedText.notReadyMessage == "Open TokenWatch to refresh data")
        #expect(snapshot.localizedText.monthlyBudgetTitle == "Monthly Budget")
        #expect(
            snapshot.localizedText.monthlyBudgetUnconfiguredMessage
                == "Set a monthly budget in TokenWatch"
        )
        #expect(snapshot.localizedText.weeklySummaryTitle == "Last 7 Days")
        #expect(snapshot.localizedText.projectFocusTitle == "Project Usage")
        #expect(snapshot.localizedText.projectFocusNoDataMessage == "No project data")
        #expect(snapshot.localizedText.modelFocusTitle == "Primary Model")
        #expect(snapshot.localizedText.modelFocusNoDataMessage == "No model data")
        #expect(snapshot.monthlyBudget?.title == "Monthly Budget")
    }

    @Test("monthly budget combines current-month costs and projects the calendar month")
    func monthlyBudgetUsesCurrentMonthCostAndPacing() throws {
        let states: [ProviderID: TokenStatsViewModel.ProviderState] = [
            .claude: loadedState(stats: makeStats(byMonth: [
                "2026-06": makeSummary(total: 0, cost: 999),
                "2026-07": makeSummary(total: 0, cost: 12.5),
            ])),
            .codex: loadedState(stats: makeStats(byMonth: [
                "2026-07": makeSummary(total: 0, cost: 7.5),
                "2026-08": makeSummary(total: 0, cost: 999),
            ])),
        ]

        let configured = try #require(WidgetSnapshotBuilder.build(
            states: states,
            now: fixedNow,
            calendar: shanghaiCalendar,
            language: .zhHans,
            monthlyBudgetUSD: 100
        ))
        let unconfigured = try #require(WidgetSnapshotBuilder.build(
            states: states,
            now: fixedNow,
            calendar: shanghaiCalendar,
            language: .zhHans
        ))
        let budget = try #require(configured.monthlyBudget)

        #expect(budget.monthKey == "2026-07")
        #expect(budget.spentUSD == 20)
        #expect(abs(budget.forecastUSD - (20.0 / 15.0 * 31.0)) < 0.000_001)
        #expect(budget.budgetUSD == 100)
        #expect(budget.title == "本月预算")
        #expect(configured.localizedText.weeklySummaryTitle == "最近 7 天")
        #expect(unconfigured.monthlyBudget?.budgetUSD == nil)
        #expect(MonthlyBudgetCopy.make(language: .zhHant).title == "本月預算")
    }

    @Test("monthly budget copy resolves all fields in every supported language")
    func monthlyBudgetCopyUsesLocalizedResources() {
        for language in AppLanguage.allCases {
            let copy = MonthlyBudgetCopy.make(language: language)

            #expect(
                copy.title == AppStrings.text(.widgetMonthlyBudgetTitle, language: language)
            )
            #expect(
                copy.settingsTitle
                    == AppStrings.text(.widgetMonthlyBudgetSettingsTitle, language: language)
            )
            #expect(
                copy.forecastTitle
                    == AppStrings.text(.widgetMonthlyBudgetForecastTitle, language: language)
            )
            #expect(
                copy.unconfiguredMessage
                    == AppStrings.text(.widgetMonthlyBudgetUnconfiguredMessage, language: language)
            )
            #expect(
                copy.forecastOverBudgetMessage
                    == AppStrings.text(
                        .widgetMonthlyBudgetForecastOverBudgetMessage,
                        language: language
                    )
            )
        }
    }

    @Test("seven-day project and model focus preserve provider identity")
    func sevenDayFocusUsesCleanProjectsAndProviderScopedModels() throws {
        let claudeDay = makeSummary(
            total: 130,
            modelBreakdown: ["gpt": makeSummary(total: 130)],
            projectBreakdown: [
                "/Users/example/TokenWatch/.claude/worktrees/feature": makeSummary(total: 130),
            ]
        )
        let codexSameModelDay = makeSummary(
            total: 120,
            modelBreakdown: ["gpt": makeSummary(total: 120)],
            projectBreakdown: ["/Users/example/Other": makeSummary(total: 120)]
        )
        let codexProjectDay = makeSummary(
            total: 100,
            modelBreakdown: ["codex-large": makeSummary(total: 100)],
            projectBreakdown: ["/Users/example/TokenWatch": makeSummary(total: 100)]
        )
        let states: [ProviderID: TokenStatsViewModel.ProviderState] = [
            .claude: loadedState(stats: makeStats(byDay: [
                "2026-07-09": claudeDay,
            ])),
            .codex: loadedState(stats: makeStats(byDay: [
                "2026-07-10": codexSameModelDay,
                "2026-07-11": codexProjectDay,
            ])),
        ]

        let snapshot = try #require(WidgetSnapshotBuilder.build(
            states: states,
            now: fixedNow,
            calendar: shanghaiCalendar,
            language: .zhHans
        ))

        #expect(snapshot.projectFocus.windowStartDayKey == "2026-07-09")
        #expect(snapshot.projectFocus.windowEndDayKey == "2026-07-15")
        #expect(snapshot.projectFocus.windowTotalTokens == 350)
        #expect(snapshot.projectFocus.topProjectName == "TokenWatch")
        #expect(snapshot.projectFocus.topProjectTokens == 230)
        #expect(snapshot.modelFocus.windowTotalTokens == 350)
        #expect(snapshot.modelFocus.providerName == "Claude Code")
        #expect(snapshot.modelFocus.modelName == "gpt")
        #expect(snapshot.modelFocus.modelTokens == 130)
        #expect(snapshot.localizedText.projectFocusTitle == "项目消耗")
        #expect(snapshot.localizedText.modelFocusTitle == "主模型")
        let payload = String(data: try JSONEncoder().encode(snapshot), encoding: .utf8) ?? ""
        #expect(!payload.contains("/Users/example"))
        #expect(WidgetUsageSnapshotValidator.isValid(snapshot))
    }

    @Test("all supported languages resolve all five widget strings")
    func everyLanguageHasExactWidgetStrings() throws {
        let expected: [AppLanguage: [AppStringKey: String]] = [
            .zhHans: [
                .widgetHeatmapTitle: "热力图",
                .widgetTodayUsageTitle: "今日用量",
                .widgetDatedUsageTitleFormat: "%@ 用量",
                .widgetUpdatedThroughTitleFormat: "更新至 %@",
                .widgetNotReadyMessage: "打开 TokenWatch 刷新数据",
            ],
            .zhHant: [
                .widgetHeatmapTitle: "熱力圖",
                .widgetTodayUsageTitle: "今日用量",
                .widgetDatedUsageTitleFormat: "%@ 用量",
                .widgetUpdatedThroughTitleFormat: "更新至 %@",
                .widgetNotReadyMessage: "開啟 TokenWatch 重新整理資料",
            ],
            .ja: [
                .widgetHeatmapTitle: "ヒートマップ",
                .widgetTodayUsageTitle: "今日の使用量",
                .widgetDatedUsageTitleFormat: "%@の使用量",
                .widgetUpdatedThroughTitleFormat: "%@ まで更新",
                .widgetNotReadyMessage: "TokenWatchを開いてデータを更新",
            ],
            .ko: [
                .widgetHeatmapTitle: "히트맵",
                .widgetTodayUsageTitle: "오늘 사용량",
                .widgetDatedUsageTitleFormat: "%@ 사용량",
                .widgetUpdatedThroughTitleFormat: "%@까지 업데이트",
                .widgetNotReadyMessage: "TokenWatch를 열어 데이터를 새로고침",
            ],
            .es: [
                .widgetHeatmapTitle: "Mapa de calor",
                .widgetTodayUsageTitle: "Uso de hoy",
                .widgetDatedUsageTitleFormat: "Uso del %@",
                .widgetUpdatedThroughTitleFormat: "Actualizado hasta %@",
                .widgetNotReadyMessage: "Abre TokenWatch para actualizar los datos",
            ],
            .de: [
                .widgetHeatmapTitle: "Heatmap",
                .widgetTodayUsageTitle: "Heutige Nutzung",
                .widgetDatedUsageTitleFormat: "Nutzung am %@",
                .widgetUpdatedThroughTitleFormat: "Aktualisiert bis %@",
                .widgetNotReadyMessage: "TokenWatch öffnen, um Daten zu aktualisieren",
            ],
            .fr: [
                .widgetHeatmapTitle: "Carte thermique",
                .widgetTodayUsageTitle: "Utilisation aujourd’hui",
                .widgetDatedUsageTitleFormat: "Utilisation du %@",
                .widgetUpdatedThroughTitleFormat: "Mis à jour jusqu’au %@",
                .widgetNotReadyMessage: "Ouvrez TokenWatch pour actualiser les données",
            ],
            .ptBR: [
                .widgetHeatmapTitle: "Mapa de calor",
                .widgetTodayUsageTitle: "Uso de hoje",
                .widgetDatedUsageTitleFormat: "Uso em %@",
                .widgetUpdatedThroughTitleFormat: "Atualizado até %@",
                .widgetNotReadyMessage: "Abra o TokenWatch para atualizar os dados",
            ],
            .it: [
                .widgetHeatmapTitle: "Mappa di calore",
                .widgetTodayUsageTitle: "Utilizzo di oggi",
                .widgetDatedUsageTitleFormat: "Utilizzo del %@",
                .widgetUpdatedThroughTitleFormat: "Aggiornato al %@",
                .widgetNotReadyMessage: "Apri TokenWatch per aggiornare i dati",
            ],
            .nl: [
                .widgetHeatmapTitle: "Warmtekaart",
                .widgetTodayUsageTitle: "Gebruik vandaag",
                .widgetDatedUsageTitleFormat: "Gebruik op %@",
                .widgetUpdatedThroughTitleFormat: "Bijgewerkt tot %@",
                .widgetNotReadyMessage: "Open TokenWatch om gegevens te verversen",
            ],
            .pl: [
                .widgetHeatmapTitle: "Mapa cieplna",
                .widgetTodayUsageTitle: "Dzisiejsze użycie",
                .widgetDatedUsageTitleFormat: "Użycie: %@",
                .widgetUpdatedThroughTitleFormat: "Zaktualizowano do %@",
                .widgetNotReadyMessage: "Otwórz TokenWatch, aby odświeżyć dane",
            ],
            .en: [
                .widgetHeatmapTitle: "Heatmap",
                .widgetTodayUsageTitle: "Today's Usage",
                .widgetDatedUsageTitleFormat: "%@ Usage",
                .widgetUpdatedThroughTitleFormat: "Updated through %@",
                .widgetNotReadyMessage: "Open TokenWatch to refresh data",
            ],
        ]
        let keys: [AppStringKey] = [
            .widgetHeatmapTitle,
            .widgetTodayUsageTitle,
            .widgetDatedUsageTitleFormat,
            .widgetUpdatedThroughTitleFormat,
            .widgetNotReadyMessage,
        ]

        #expect(expected.count == 12)
        for (language, table) in expected {
            #expect(table.count == keys.count)
            for key in keys {
                let expectedValue = try #require(table[key])
                #expect(AppStrings.text(key, language: language) == expectedValue)
            }
        }

        for language in AppLanguage.allCases {
            for key in keys {
                #expect(
                    AppStrings.text(key, language: language) != key.rawValue,
                    "Expected direct widget translation for \(language.rawValue)/\(key.rawValue)"
                )
            }
        }
    }

    private var shanghaiCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.firstWeekday = 2
        return calendar
    }

    private var fixedNow: Date {
        shanghaiCalendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 15,
            hour: 13,
            minute: 30
        ))!
    }

    private func assertTwentyFourWallClockHours(
        year: Int,
        month: Int,
        day: Int
    ) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        calendar.firstWeekday = 2
        let now = try #require(calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: 13
        )))
        let snapshot = try #require(WidgetSnapshotBuilder.build(
            states: [.claude: loadedState(stats: makeStats())],
            now: now,
            calendar: calendar,
            language: .en
        ))

        #expect(snapshot.hourlyLine.points.map(\.hour) == Array(0...23))
        #expect(Set(snapshot.hourlyLine.points.map(\.hourKey)).count == 24)
        #expect(snapshot.hourlyLine.points.filter(\.isCurrentHour).map(\.hour) == [13])
        #expect(WidgetUsageSnapshotValidator.isValid(snapshot))
    }

    private func loadedState(
        stats: AggregatedStats
    ) -> TokenStatsViewModel.ProviderState {
        .init(
            stats: stats,
            isLoading: false,
            errorMessage: nil,
            needsAuthorization: false
        )
    }

    private func makeSummary(
        total: Int,
        cost: Double = 0,
        modelBreakdown: [String: UsageSummary] = [:],
        projectBreakdown: [String: UsageSummary] = [:]
    ) -> UsageSummary {
        UsageSummary(
            inputTokens: total,
            outputTokens: 0,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            reasoningTokens: 0,
            totalTokens: total,
            cost: cost,
            entryCount: total == 0 ? 0 : 1,
            modelBreakdown: modelBreakdown,
            projectBreakdown: projectBreakdown
        )
    }

    private func makeStats(
        byHour: [String: UsageSummary] = [:],
        byDay: [String: UsageSummary] = [:],
        byMonth: [String: UsageSummary] = [:]
    ) -> AggregatedStats {
        AggregatedStats(
            overall: .zero,
            byHour: byHour,
            byDay: byDay,
            byWeek: [:],
            byMonth: byMonth,
            bySession: [:],
            byModel: [:],
            byProject: [:],
            dataSourceCount: 1
        )
    }
}
