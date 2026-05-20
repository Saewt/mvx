import Foundation

public struct ReleasePublicationDescriptor: Equatable {
    public var artifact: ReleaseArtifactDescriptor
    public var sha256: String
    public var homepageURLString: String

    public init(
        artifact: ReleaseArtifactDescriptor,
        sha256: String,
        homepageURLString: String = "https://github.com/Saewt/mvx"
    ) {
        self.artifact = artifact
        self.sha256 = sha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.homepageURLString = homepageURLString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isValidSHA256: Bool {
        Self.isValidSHA256(sha256)
    }

    public func latestJSON() -> String {
        let minimumMacOS = DistributionDefaults.defaultMinimumMacOS
        return """
        {
          "version": "\(artifact.version)",
          "build": "\(artifact.build)",
          "minimum_macos": "\(minimumMacOS)",
          "platforms": {
            "darwin-aarch64": {
              "url": "\(artifact.downloadURLString)",
              "sha256": "\(sha256)"
            }
          }
        }
        """
    }

    public static func isValidSHA256(_ value: String) -> Bool {
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard candidate.count == 64 else {
            return false
        }

        return candidate.unicodeScalars.allSatisfy { scalar in
            CharacterSet(charactersIn: "0123456789abcdef").contains(scalar)
        }
    }
}

public struct AppUpdateConfiguration: Equatable {
    public var latestReleaseURL: URL?

    public init(latestReleaseURL: URL?) {
        self.latestReleaseURL = latestReleaseURL
    }

    public var canCheckForUpdates: Bool {
        latestReleaseURL != nil
    }

    public static func resolve(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AppUpdateConfiguration {
        let latestReleaseURLString = environment["MVX_LATEST_RELEASE_URL"]
            ?? (bundle.object(forInfoDictionaryKey: "MVXLatestReleaseURL") as? String)
            ?? DistributionDefaults.defaultLatestReleaseURL

        return AppUpdateConfiguration(
            latestReleaseURL: URL(string: latestReleaseURLString)
        )
    }
}