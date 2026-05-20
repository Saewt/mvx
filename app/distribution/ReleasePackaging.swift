import Foundation

public enum DistributionDefaults {
    public static let bundleIdentifier = "dev.mvx.app"
    public static let appName = "mvx"
    public static let appBundleName = "mvx.app"
    public static let defaultMinimumMacOS = "13.0"
    public static let defaultVersion = "0.1.4"
    public static let defaultBuild = "4"
    public static let defaultDownloadBaseURL = "https://github.com/Saewt/mvx/releases/latest/download"
    public static let defaultLatestReleaseURL = "https://github.com/Saewt/mvx/releases/latest/download/latest.json"
}

public struct ReleasePackagingManifest: Codable, Equatable {
    public var version: String
    public var build: String
    public var bundleIdentifier: String
    public var appBundleName: String
    public var tarballFileName: String
    public var downloadURL: String
    public var requiresNotarization: Bool
    public var hardenedRuntimeEnabled: Bool

    public init(
        version: String,
        build: String,
        bundleIdentifier: String,
        appBundleName: String,
        tarballFileName: String,
        downloadURL: String,
        requiresNotarization: Bool,
        hardenedRuntimeEnabled: Bool
    ) {
        self.version = version
        self.build = build
        self.bundleIdentifier = bundleIdentifier
        self.appBundleName = appBundleName
        self.tarballFileName = tarballFileName
        self.downloadURL = downloadURL
        self.requiresNotarization = requiresNotarization
        self.hardenedRuntimeEnabled = hardenedRuntimeEnabled
    }
}

public struct ReleaseArtifactDescriptor: Codable, Equatable {
    public var version: String
    public var build: String
    public var downloadBaseURL: String

    public init(
        version: String = DistributionDefaults.defaultVersion,
        build: String = DistributionDefaults.defaultBuild,
        downloadBaseURL: String = DistributionDefaults.defaultDownloadBaseURL
    ) {
        let trimmedVersion = version.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBuild = build.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBaseURL = Self.normalizeBaseURL(downloadBaseURL)

        self.version = trimmedVersion.isEmpty ? DistributionDefaults.defaultVersion : trimmedVersion
        self.build = trimmedBuild.isEmpty ? DistributionDefaults.defaultBuild : trimmedBuild
        self.downloadBaseURL = normalizedBaseURL.isEmpty ? DistributionDefaults.defaultDownloadBaseURL : normalizedBaseURL
    }

    public var archiveFileName: String {
        "mvx-\(sanitizedVersion)-\(sanitizedBuild).xcarchive"
    }

    public var exportDirectoryName: String {
        "mvx-\(sanitizedVersion)-export"
    }

    public var releaseDirectoryName: String {
        "mvx-\(sanitizedVersion)-release"
    }

    public var tarballFileName: String {
        "mvx-\(sanitizedVersion)-\(sanitizedBuild)-darwin-aarch64.app.tar.gz"
    }

    public var downloadURLString: String {
        "\(downloadBaseURL)/\(tarballFileName)"
    }

    public func packagingManifest(
        bundleIdentifier: String = DistributionDefaults.bundleIdentifier
    ) -> ReleasePackagingManifest {
        ReleasePackagingManifest(
            version: version,
            build: build,
            bundleIdentifier: bundleIdentifier,
            appBundleName: DistributionDefaults.appBundleName,
            tarballFileName: tarballFileName,
            downloadURL: downloadURLString,
            requiresNotarization: false,
            hardenedRuntimeEnabled: true
        )
    }

    public static func missingEnvironmentKeys(
        in environment: [String: String],
        required keys: [String]
    ) -> [String] {
        keys.filter { key in
            guard let value = environment[key] else {
                return true
            }

            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var sanitizedVersion: String {
        Self.sanitize(version)
    }

    private var sanitizedBuild: String {
        Self.sanitize(build)
    }

    private static func sanitize(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
        let scalarView = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let rendered = String(scalarView)

        while rendered.contains("--") {
            return sanitize(rendered.replacingOccurrences(of: "--", with: "-"))
        }

        return rendered.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func normalizeBaseURL(_ value: String) -> String {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized
    }
}
