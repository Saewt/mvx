import Foundation

public final class ConfigStore {
    public let fileURL: URL

    public init(fileURL: URL = ConfigStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public func load() -> AppPreferences {
        (try? loadValidated()) ?? .default
    }

    public func loadValidated() throws -> AppPreferences {
        try AppDirectories.migrateLegacyContentsIfNeeded(
            homeDirectory: fileURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
        )

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .default
        }

        let data = try Data(contentsOf: fileURL)
        let decoded = try JSONDecoder().decode(AppPreferences.self, from: data)
        return decoded.validated()
    }

    public func save(_ preferences: AppPreferences) throws {
        let normalized = preferences.validated()
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder.prettyPrinted.encode(normalized)
        try data.write(to: fileURL, options: Data.WritingOptions.atomic)
    }

    public static func defaultFileURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        AppDirectories
            .appDirectory(homeDirectory: homeDirectory)
            .appendingPathComponent("config.json")
    }
}

extension JSONEncoder {
    static var prettyPrinted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
