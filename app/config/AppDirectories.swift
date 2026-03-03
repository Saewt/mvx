import Foundation

public enum AppDirectories {
    public static let currentDirectoryName = ".mvx"
    public static let legacyDirectoryName = ".codop"

    public static func appDirectory(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory.appendingPathComponent(currentDirectoryName, isDirectory: true)
    }

    public static func legacyAppDirectory(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory.appendingPathComponent(legacyDirectoryName, isDirectory: true)
    }

    public static func migrateLegacyContentsIfNeeded(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) throws {
        let currentDirectory = appDirectory(homeDirectory: homeDirectory)
        let legacyDirectory = legacyAppDirectory(homeDirectory: homeDirectory)

        guard !fileManager.fileExists(atPath: currentDirectory.path) else {
            return
        }

        var isLegacyDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: legacyDirectory.path, isDirectory: &isLegacyDirectory),
              isLegacyDirectory.boolValue else {
            return
        }

        try fileManager.createDirectory(at: currentDirectory, withIntermediateDirectories: true)

        let contents = try fileManager.contentsOfDirectory(
            at: legacyDirectory,
            includingPropertiesForKeys: nil
        )

        for sourceURL in contents {
            let destinationURL = currentDirectory.appendingPathComponent(sourceURL.lastPathComponent)
            guard !fileManager.fileExists(atPath: destinationURL.path) else {
                continue
            }

            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }
    }
}
