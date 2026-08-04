import Foundation

/// Stable read failures shared by the host app and widget extension.
///
/// Missing data is represented separately by `WidgetSnapshotReadResult.missing`.
/// Existing bytes are unreadable when the file cannot be read, corrupt when JSON or
/// render invariants are invalid, and unsupported when the envelope schema is unknown.
enum WidgetSnapshotReadFailure: Equatable, Sendable {
    case unreadable
    case corrupt
    case unsupportedSchema(Int)
}

/// The complete, nonthrowing result of reading a cross-process widget snapshot.
enum WidgetSnapshotReadResult: Equatable, Sendable {
    case available(WidgetUsageSnapshot)
    case missing
    case invalid(WidgetSnapshotReadFailure)
}

/// Errors produced before a snapshot can be persisted in the shared container.
enum WidgetSnapshotStoreError: Error, Equatable, Sendable {
    case appGroupContainerUnavailable
    case invalidSnapshot
}

/// Cross-process persistence contract used by the host app and widget extension.
protocol WidgetSnapshotStoring: Sendable {
    /// Loads the latest snapshot while preserving missing and invalid failure semantics.
    func load() -> WidgetSnapshotReadResult

    /// Validates and atomically replaces the stored snapshot.
    /// - Parameter snapshot: The render-ready payload to persist.
    func save(_ snapshot: WidgetUsageSnapshot) throws
}

/// Validates every storage and rendering invariant before bytes cross process boundaries.
enum WidgetUsageSnapshotValidator {
    /// Returns whether a snapshot matches the current schema and fixed chart shapes.
    /// - Parameter snapshot: The candidate payload to validate.
    /// - Returns: `true` only when every cross-process invariant is satisfied.
    static func isValid(_ snapshot: WidgetUsageSnapshot) -> Bool {
        guard snapshot.schemaVersion == WidgetSharedConfiguration.schemaVersion,
              snapshot.localDayKey == snapshot.hourlyLine.dayKey,
              snapshot.heatmap.totalTokens >= 0,
              snapshot.heatmap.maxDailyTokens >= 0,
              snapshot.hourlyLine.totalTokens >= 0,
              snapshot.hourlyLine.maxHourlyTokens >= 0,
              !snapshot.localizedText.weeklySummaryTitle
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty,
              snapshot.heatmap.cells.count
                == WidgetChartVisualStyle.heatmapColumns * WidgetChartVisualStyle.heatmapRows,
              snapshot.hourlyLine.points.count == 24 else {
            return false
        }

        let cellsAreValid = snapshot.heatmap.cells.allSatisfy { cell in
            cell.totalTokens >= 0
                && (0...WidgetChartVisualStyle.heatmapMaximumIntensity).contains(cell.intensity)
                && cell.isPlaceholder == (cell.dateKey == nil)
                && (!cell.isPlaceholder || (cell.totalTokens == 0 && cell.intensity == 0))
        }
        let hours = snapshot.hourlyLine.points.map(\.hour)
        let pointsAreValid = hours == Array(0...23)
            && Set(snapshot.hourlyLine.points.map(\.hourKey)).count == 24
            && snapshot.hourlyLine.points.filter(\.isCurrentHour).count == 1
            && snapshot.hourlyLine.points.allSatisfy {
                $0.totalTokens >= 0 && !$0.hourKey.isEmpty && !$0.hourLabel.isEmpty
            }
        let monthlyBudgetIsValid = snapshot.monthlyBudget.map(isValidMonthlyBudget) ?? true
        return cellsAreValid && pointsAreValid && monthlyBudgetIsValid
    }

    private static func isValidMonthlyBudget(
        _ snapshot: WidgetMonthlyBudgetSnapshot
    ) -> Bool {
        guard isValidMonthKey(snapshot.monthKey),
              snapshot.spentUSD.isFinite,
              snapshot.spentUSD >= 0,
              snapshot.forecastUSD.isFinite,
              snapshot.forecastUSD >= 0,
              !snapshot.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !snapshot.forecastTitle
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty,
              !snapshot.unconfiguredMessage
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty,
              !snapshot.forecastOverBudgetMessage
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty else {
            return false
        }
        return snapshot.budgetUSD.map { $0.isFinite && $0 > 0 } ?? true
    }

    private static func isValidMonthKey(_ key: String) -> Bool {
        guard key.count == 7,
              key.dropFirst(4).first == "-",
              Int(key.prefix(4)) != nil,
              let month = Int(key.suffix(2)) else {
            return false
        }
        return (1...12).contains(month)
    }
}

/// Foundation-only JSON storage safe for use by both the app and widget processes.
///
/// Saving encodes before invoking an atomic replacement, so a failed replacement leaves
/// previously published bytes intact. Loading decodes the schema envelope first to keep
/// future-version payloads distinct from corrupt data.
struct JSONWidgetSnapshotStore: WidgetSnapshotStoring, Sendable {
    typealias AtomicWrite = @Sendable (Data, URL) throws -> Void

    private struct SchemaEnvelope: Decodable {
        let schemaVersion: Int
    }

    let fileURL: URL
    private let atomicWrite: AtomicWrite

    /// Creates storage at an explicit URL with an injectable atomic replacement seam.
    /// - Parameters:
    ///   - fileURL: The shared JSON file URL.
    ///   - atomicWrite: The replacement operation; defaults to Foundation's atomic write.
    init(
        fileURL: URL,
        atomicWrite: @escaping AtomicWrite = { data, url in
            try data.write(to: url, options: .atomic)
        }
    ) {
        self.fileURL = fileURL
        self.atomicWrite = atomicWrite
    }

    /// Resolves the versioned snapshot URL inside the configured App Group container.
    /// - Parameter fileManager: The manager used to resolve the shared container.
    /// - Returns: A store targeting the shared snapshot filename.
    /// - Throws: `WidgetSnapshotStoreError.appGroupContainerUnavailable` when the
    ///   container cannot be resolved for the current process.
    static func appGroupStore(
        fileManager: FileManager = .default
    ) throws -> JSONWidgetSnapshotStore {
        guard let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: WidgetSharedConfiguration.appGroupIdentifier
        ) else {
            throw WidgetSnapshotStoreError.appGroupContainerUnavailable
        }
        return JSONWidgetSnapshotStore(
            fileURL: containerURL.appendingPathComponent(
                WidgetSharedConfiguration.snapshotFilename,
                isDirectory: false
            )
        )
    }

    /// Reads and validates the current bytes without throwing across process boundaries.
    /// - Returns: An available snapshot, a missing result, or a precise invalid category.
    func load() -> WidgetSnapshotReadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .missing
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            return .invalid(.unreadable)
        }

        let decoder = JSONDecoder()
        guard let envelope = try? decoder.decode(SchemaEnvelope.self, from: data) else {
            return .invalid(.corrupt)
        }
        guard envelope.schemaVersion == WidgetSharedConfiguration.schemaVersion else {
            return .invalid(.unsupportedSchema(envelope.schemaVersion))
        }
        guard let snapshot = try? decoder.decode(WidgetUsageSnapshot.self, from: data),
              WidgetUsageSnapshotValidator.isValid(snapshot) else {
            return .invalid(.corrupt)
        }
        return .available(snapshot)
    }

    /// Validates, deterministically encodes, and atomically replaces the shared snapshot.
    /// - Parameter snapshot: The render-ready payload to publish.
    /// - Throws: `WidgetSnapshotStoreError.invalidSnapshot` for an invalid payload, or
    ///   the underlying encoder/replacement error without modifying valid old bytes.
    func save(_ snapshot: WidgetUsageSnapshot) throws {
        guard WidgetUsageSnapshotValidator.isValid(snapshot) else {
            throw WidgetSnapshotStoreError.invalidSnapshot
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try atomicWrite(try encoder.encode(snapshot), fileURL)
    }
}
