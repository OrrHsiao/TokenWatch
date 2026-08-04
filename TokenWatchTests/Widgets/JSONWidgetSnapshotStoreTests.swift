import Foundation
import Testing
@testable import TokenWatch

@Suite("JSON widget snapshot store")
struct JSONWidgetSnapshotStoreTests {
    @Test("valid snapshot saves and loads exactly")
    func validSnapshotRoundTrips() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("snapshot.json", isDirectory: false)
        let source = makeValidSnapshot(
            totalTokens: 42,
            monthlyBudget: validMonthlyBudget()
        )
        let store = JSONWidgetSnapshotStore(fileURL: fileURL)

        try store.save(source)

        #expect(store.load() == .available(source))
    }

    @Test("missing file is distinct from corrupt data")
    func missingFileReturnsMissing() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("snapshot.json", isDirectory: false)

        #expect(JSONWidgetSnapshotStore(fileURL: fileURL).load() == .missing)
    }

    @Test("invalid JSON is reported as corrupt")
    func corruptJSONReturnsCorrupt() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("snapshot.json", isDirectory: false)
        try Data("not-json".utf8).write(to: fileURL)

        #expect(JSONWidgetSnapshotStore(fileURL: fileURL).load() == .invalid(.corrupt))
    }

    @Test("unknown schema is recognized before payload decoding")
    func unknownSchemaIsRejectedBeforePayloadDecode() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("snapshot.json", isDirectory: false)
        let unsupportedSchema = WidgetSharedConfiguration.schemaVersion + 1
        try Data("{\"schemaVersion\":\(unsupportedSchema)}".utf8).write(to: fileURL)

        #expect(JSONWidgetSnapshotStore(fileURL: fileURL).load() == .invalid(
            .unsupportedSchema(unsupportedSchema)
        ))
    }

    @Test("previous schema is rejected before payload decoding")
    func previousSchemaIsRejectedBeforePayloadDecode() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("snapshot.json", isDirectory: false)
        let previousSchema = WidgetSharedConfiguration.schemaVersion - 1
        try Data("{\"schemaVersion\":\(previousSchema)}".utf8).write(to: fileURL)

        #expect(JSONWidgetSnapshotStore(fileURL: fileURL).load() == .invalid(
            .unsupportedSchema(previousSchema)
        ))
    }

    @Test("every invalid render shape is rejected")
    func invalidShapesReturnCorrupt() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("snapshot.json", isDirectory: false)
        let store = JSONWidgetSnapshotStore(fileURL: fileURL)

        for (name, snapshot) in invalidSnapshots() {
            try JSONEncoder().encode(snapshot).write(to: fileURL)
            #expect(
                store.load() == .invalid(.corrupt),
                "mutation must be rejected: \(name)"
            )
            #expect(
                !WidgetUsageSnapshotValidator.isValid(snapshot),
                "validator must reject: \(name)"
            )
        }
    }

    @Test("atomic write failure leaves the old bytes readable")
    func failedAtomicWritePreservesExistingSnapshot() throws {
        struct InjectedWriteError: Error {}

        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("snapshot.json", isDirectory: false)
        let old = makeValidSnapshot(totalTokens: 10)
        let realStore = JSONWidgetSnapshotStore(fileURL: fileURL)
        try realStore.save(old)

        let failingStore = JSONWidgetSnapshotStore(
            fileURL: fileURL,
            atomicWrite: { _, _ in throw InjectedWriteError() }
        )
        #expect(throws: InjectedWriteError.self) {
            try failingStore.save(makeValidSnapshot(totalTokens: 20))
        }
        #expect(realStore.load() == .available(old))
    }

    private func invalidSnapshots() -> [(String, WidgetUsageSnapshot)] {
        let validCells = makeHeatmapCells(totalTokens: 42)
        let validPoints = makeHourlyPoints(totalTokens: 42)

        var duplicateHours = validPoints
        duplicateHours[23] = copyPoint(duplicateHours[23], hour: 22)

        var outOfOrderHours = validPoints
        outOfOrderHours.swapAt(0, 1)

        var duplicateHourKeys = validPoints
        duplicateHourKeys[23] = copyPoint(
            duplicateHourKeys[23],
            hourKey: validPoints[0].hourKey
        )

        let zeroCurrentMarkers = validPoints.map {
            copyPoint($0, isCurrentHour: false)
        }

        var twoCurrentMarkers = validPoints
        twoCurrentMarkers[12] = copyPoint(twoCurrentMarkers[12], isCurrentHour: true)

        var excessiveIntensity = validCells
        excessiveIntensity[0] = copyCell(excessiveIntensity[0], intensity: 5)

        var nonzeroPlaceholder = validCells
        nonzeroPlaceholder[153] = WidgetHeatmapCell(
            dateKey: nil,
            totalTokens: 1,
            intensity: 1,
            isPlaceholder: true
        )

        var negativeCellTotal = validCells
        negativeCellTotal[0] = copyCell(negativeCellTotal[0], totalTokens: -1)

        var negativePointTotal = validPoints
        negativePointTotal[0] = copyPoint(negativePointTotal[0], totalTokens: -1)

        return [
            ("153 heatmap cells", makeValidSnapshot(
                heatmapCells: Array(validCells.dropLast())
            )),
            ("23 hourly points", makeValidSnapshot(
                hourlyPoints: Array(validPoints.dropLast())
            )),
            ("duplicate and missing hour", makeValidSnapshot(
                hourlyPoints: duplicateHours
            )),
            ("out-of-order hours", makeValidSnapshot(
                hourlyPoints: outOfOrderHours
            )),
            ("duplicate hour key", makeValidSnapshot(
                hourlyPoints: duplicateHourKeys
            )),
            ("zero current markers", makeValidSnapshot(
                hourlyPoints: zeroCurrentMarkers
            )),
            ("two current markers", makeValidSnapshot(
                hourlyPoints: twoCurrentMarkers
            )),
            ("intensity above four", makeValidSnapshot(
                heatmapCells: excessiveIntensity
            )),
            ("nonzero placeholder", makeValidSnapshot(
                heatmapCells: nonzeroPlaceholder
            )),
            ("negative heatmap total", makeValidSnapshot(
                heatmapTotalTokens: -1
            )),
            ("negative heatmap maximum", makeValidSnapshot(
                maxDailyTokens: -1
            )),
            ("negative hourly total", makeValidSnapshot(
                hourlyTotalTokens: -1
            )),
            ("negative hourly maximum", makeValidSnapshot(
                maxHourlyTokens: -1
            )),
            ("negative heatmap cell", makeValidSnapshot(
                heatmapCells: negativeCellTotal
            )),
            ("negative hourly point", makeValidSnapshot(
                hourlyPoints: negativePointTotal
            )),
            ("mismatched day keys", makeValidSnapshot(
                hourlyDayKey: "2026-07-14"
            )),
            ("blank monthly budget title fallback", makeValidSnapshot(
                monthlyBudgetTitle: " "
            )),
            ("blank monthly budget setup fallback", makeValidSnapshot(
                monthlyBudgetUnconfiguredMessage: " "
            )),
            ("blank weekly summary title", makeValidSnapshot(
                weeklySummaryTitle: "  "
            )),
            ("invalid budget month", makeValidSnapshot(
                monthlyBudget: validMonthlyBudget(monthKey: "2026-13")
            )),
            ("negative budget spend", makeValidSnapshot(
                monthlyBudget: validMonthlyBudget(spentUSD: -1)
            )),
            ("zero budget limit", makeValidSnapshot(
                monthlyBudget: validMonthlyBudget(budgetUSD: 0)
            )),
            ("blank budget title", makeValidSnapshot(
                monthlyBudget: validMonthlyBudget(title: " ")
            )),
            ("project focus leaks a path", makeValidSnapshot(
                projectFocus: validProjectFocus(topProjectName: "/Users/example/TokenWatch")
            )),
            ("project focus has an impossible day", makeValidSnapshot(
                projectFocus: WidgetProjectFocusSnapshot(
                    windowStartDayKey: "2026-02-31",
                    windowEndDayKey: "2026-07-15",
                    windowTotalTokens: 100,
                    topProjectName: "TokenWatch",
                    topProjectTokens: 60
                )
            )),
            ("project focus exceeds its window", makeValidSnapshot(
                projectFocus: validProjectFocus(
                    windowTotalTokens: 42,
                    topProjectTokens: 43
                )
            )),
            ("model focus is missing a provider", makeValidSnapshot(
                modelFocus: validModelFocus(providerName: nil)
            )),
            ("model focus exceeds its window", makeValidSnapshot(
                modelFocus: validModelFocus(
                    windowTotalTokens: 42,
                    modelTokens: 43
                )
            )),
        ]
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "JSONWidgetSnapshotStoreTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }

    private func makeValidSnapshot(
        totalTokens: Int = 42,
        heatmapCells: [WidgetHeatmapCell]? = nil,
        hourlyPoints: [WidgetHourlyPoint]? = nil,
        heatmapTotalTokens: Int? = nil,
        maxDailyTokens: Int = 42,
        hourlyTotalTokens: Int? = nil,
        maxHourlyTokens: Int = 42,
        hourlyDayKey: String = "2026-07-15",
        monthlyBudgetTitle: String = "本月预算",
        monthlyBudgetUnconfiguredMessage: String = "在 TokenWatch 中设置月度预算",
        weeklySummaryTitle: String = "最近 7 天",
        monthlyBudget: WidgetMonthlyBudgetSnapshot? = nil,
        projectFocus: WidgetProjectFocusSnapshot? = nil,
        modelFocus: WidgetModelFocusSnapshot? = nil
    ) -> WidgetUsageSnapshot {
        WidgetUsageSnapshot(
            schemaVersion: WidgetSharedConfiguration.schemaVersion,
            generatedAt: Date(timeIntervalSince1970: 100),
            localDayKey: "2026-07-15",
            localizedText: WidgetLocalizedText(
                heatmapTitle: "最近 22 周",
                todayUsageTitle: "今日用量",
                datedUsageTitle: "7/15 用量",
                updatedThroughTitle: "更新至 7/15",
                notReadyMessage: "打开 TokenWatch 刷新数据",
                monthlyBudgetTitle: monthlyBudgetTitle,
                monthlyBudgetUnconfiguredMessage: monthlyBudgetUnconfiguredMessage,
                weeklySummaryTitle: weeklySummaryTitle,
                projectFocusTitle: "项目消耗",
                projectFocusNoDataMessage: "暂无项目数据",
                modelFocusTitle: "主模型",
                modelFocusNoDataMessage: "暂无模型数据"
            ),
            heatmap: WidgetHeatmapSnapshot(
                totalTokens: heatmapTotalTokens ?? totalTokens,
                maxDailyTokens: maxDailyTokens,
                cells: heatmapCells ?? makeHeatmapCells(totalTokens: totalTokens)
            ),
            hourlyLine: WidgetHourlyLineSnapshot(
                dayKey: hourlyDayKey,
                totalTokens: hourlyTotalTokens ?? totalTokens,
                maxHourlyTokens: maxHourlyTokens,
                points: hourlyPoints ?? makeHourlyPoints(totalTokens: totalTokens)
            ),
            monthlyBudget: monthlyBudget,
            projectFocus: projectFocus,
            modelFocus: modelFocus
        )
    }

    private func validMonthlyBudget(
        monthKey: String = "2026-07",
        spentUSD: Double = 42,
        budgetUSD: Double? = 100,
        forecastUSD: Double = 80,
        title: String = "本月预算",
        forecastTitle: String = "月底预估",
        unconfiguredMessage: String = "在 TokenWatch 中设置月度预算",
        forecastOverBudgetMessage: String = "预计超出预算"
    ) -> WidgetMonthlyBudgetSnapshot {
        WidgetMonthlyBudgetSnapshot(
            monthKey: monthKey,
            spentUSD: spentUSD,
            budgetUSD: budgetUSD,
            forecastUSD: forecastUSD,
            title: title,
            forecastTitle: forecastTitle,
            unconfiguredMessage: unconfiguredMessage,
            forecastOverBudgetMessage: forecastOverBudgetMessage
        )
    }

    private func validProjectFocus(
        windowTotalTokens: Int = 100,
        topProjectName: String? = "TokenWatch",
        topProjectTokens: Int = 60
    ) -> WidgetProjectFocusSnapshot {
        WidgetProjectFocusSnapshot(
            windowStartDayKey: "2026-07-09",
            windowEndDayKey: "2026-07-15",
            windowTotalTokens: windowTotalTokens,
            topProjectName: topProjectName,
            topProjectTokens: topProjectTokens
        )
    }

    private func validModelFocus(
        windowTotalTokens: Int = 100,
        providerName: String? = "Codex",
        modelName: String? = "gpt-5",
        modelTokens: Int = 60
    ) -> WidgetModelFocusSnapshot {
        WidgetModelFocusSnapshot(
            windowStartDayKey: "2026-07-09",
            windowEndDayKey: "2026-07-15",
            windowTotalTokens: windowTotalTokens,
            providerName: providerName,
            modelName: modelName,
            modelTokens: modelTokens
        )
    }

    private func makeHeatmapCells(totalTokens: Int) -> [WidgetHeatmapCell] {
        (0..<154).map { index in
            let isPlaceholder = index >= 152
            let cellTotal = index == 0 ? totalTokens : 0
            return WidgetHeatmapCell(
                dateKey: isPlaceholder ? nil : "heatmap-day-\(index)",
                totalTokens: isPlaceholder ? 0 : cellTotal,
                intensity: !isPlaceholder && cellTotal > 0 ? 4 : 0,
                isPlaceholder: isPlaceholder
            )
        }
    }

    private func makeHourlyPoints(totalTokens: Int) -> [WidgetHourlyPoint] {
        (0...23).map { hour in
            WidgetHourlyPoint(
                hour: hour,
                hourKey: String(format: "2026-07-15T%02d", hour),
                hourLabel: "\(hour)时",
                totalTokens: hour == 13 ? totalTokens : 0,
                isCurrentHour: hour == 13
            )
        }
    }

    private func copyCell(
        _ cell: WidgetHeatmapCell,
        totalTokens: Int? = nil,
        intensity: Int? = nil
    ) -> WidgetHeatmapCell {
        WidgetHeatmapCell(
            dateKey: cell.dateKey,
            totalTokens: totalTokens ?? cell.totalTokens,
            intensity: intensity ?? cell.intensity,
            isPlaceholder: cell.isPlaceholder
        )
    }

    private func copyPoint(
        _ point: WidgetHourlyPoint,
        hour: Int? = nil,
        hourKey: String? = nil,
        totalTokens: Int? = nil,
        isCurrentHour: Bool? = nil
    ) -> WidgetHourlyPoint {
        WidgetHourlyPoint(
            hour: hour ?? point.hour,
            hourKey: hourKey ?? point.hourKey,
            hourLabel: point.hourLabel,
            totalTokens: totalTokens ?? point.totalTokens,
            isCurrentHour: isCurrentHour ?? point.isCurrentHour
        )
    }
}
