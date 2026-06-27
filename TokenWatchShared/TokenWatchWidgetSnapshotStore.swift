import Foundation

enum TokenWatchWidgetSnapshotStoreError: Error, Equatable {
    case appGroupContainerUnavailable
}

struct TokenWatchWidgetSnapshotStore {
    static let appGroupIdentifier = "group.com.xiaoao.TokenWatch"
    private static let snapshotsDirectoryName = "WidgetSnapshots"
    private static let latestSnapshotFileName = "latest.json"

    private let fileManager: FileManager
    private let containerURLProvider: () -> URL?

    init(
        fileManager: FileManager = .default,
        containerURLProvider: (() -> URL?)? = nil
    ) {
        self.fileManager = fileManager
        self.containerURLProvider = containerURLProvider ?? {
            fileManager.containerURL(
                forSecurityApplicationGroupIdentifier: TokenWatchWidgetSnapshotStore.appGroupIdentifier
            )
        }
    }

    func read() -> TokenWatchWidgetSnapshot? {
        guard let fileURL = try? snapshotFileURL(),
              fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(TokenWatchWidgetSnapshot.self, from: data)
    }

    func write(_ snapshot: TokenWatchWidgetSnapshot) throws {
        let fileURL = try snapshotFileURL()
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        let temporaryURL = directoryURL.appendingPathComponent("latest-\(UUID().uuidString).json")

        var didCommitTemporaryFile = false
        defer {
            if !didCommitTemporaryFile && fileManager.fileExists(atPath: temporaryURL.path) {
                try? fileManager.removeItem(at: temporaryURL)
            }
        }

        try data.write(to: temporaryURL, options: .atomic)
        try commitTemporarySnapshot(at: temporaryURL, to: fileURL)
        didCommitTemporaryFile = true
    }

    func snapshotFileURL() throws -> URL {
        guard let containerURL = containerURLProvider() else {
            throw TokenWatchWidgetSnapshotStoreError.appGroupContainerUnavailable
        }

        return containerURL
            .appendingPathComponent(Self.snapshotsDirectoryName, isDirectory: true)
            .appendingPathComponent(Self.latestSnapshotFileName)
    }

    private func commitTemporarySnapshot(at temporaryURL: URL, to fileURL: URL) throws {
        do {
            _ = try fileManager.replaceItemAt(fileURL, withItemAt: temporaryURL)
        } catch {
            do {
                try fileManager.moveItem(at: temporaryURL, to: fileURL)
            } catch {
                _ = try fileManager.replaceItemAt(fileURL, withItemAt: temporaryURL)
            }
        }
    }
}
