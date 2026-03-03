import Foundation

public final class WorkspacePersistence {
    public let fileURL: URL

    public init(fileURL: URL = WorkspacePersistence.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public func load() -> WorkspaceSnapshot? {
        guard
            let snapshot = try? loadRequired(),
            snapshot.isSupported
        else {
            return nil
        }

        return snapshot
    }

    public func loadRequired() throws -> WorkspaceSnapshot {
        try AppDirectories.migrateLegacyContentsIfNeeded(
            homeDirectory: fileURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
        )

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(WorkspaceSnapshot.self, from: data)
    }

    public func save(_ snapshot: WorkspaceSnapshot) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder.prettyPrinted.encode(snapshot)
        try data.write(to: fileURL, options: Data.WritingOptions.atomic)
    }

    // MARK: - Registry Persistence

    public var registryFileURL: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("registry.json")
    }

    public func loadRegistry() -> RegistrySnapshot? {
        guard
            let data = try? Data(contentsOf: registryFileURL),
            let snapshot = try? JSONDecoder().decode(RegistrySnapshot.self, from: data),
            snapshot.isSupported
        else {
            return nil
        }

        return snapshot
    }

    public func saveRegistry(_ snapshot: RegistrySnapshot) throws {
        let directory = registryFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder.prettyPrinted.encode(snapshot)
        try data.write(to: registryFileURL, options: Data.WritingOptions.atomic)
    }

    public static func defaultFileURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        AppDirectories
            .appDirectory(homeDirectory: homeDirectory)
            .appendingPathComponent("workspace.json")
    }
}
