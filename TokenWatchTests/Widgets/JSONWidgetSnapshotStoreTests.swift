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
        let source = makeValidSnapshot(totalTokens: 42)
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
        try Data(#"{"schemaVersion":2}"#.utf8).write(to: fileURL)

        #expect(JSONWidgetSnapshotStore(fileURL: fileURL).load() == .invalid(.unsupportedSchema(2)))
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
        hourlyDayKey: String = "2026-07-15"
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
                notReadyMessage: "打开 TokenWatch 刷新数据"
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
            )
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
