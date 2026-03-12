import Foundation

public struct ReleasePublicationDescriptor: Equatable {
    public var artifact: ReleaseArtifactDescriptor
    public var sha256: String
    public var appcastURLString: String
    public var homepageURLString: String

    public init(
        artifact: ReleaseArtifactDescriptor,
        sha256: String,
        appcastURLString: String = DistributionDefaults.defaultAppcastURL,
        homepageURLString: String = "https://github.com/Saewt/mvx"
    ) {
        self.artifact = artifact
        self.sha256 = sha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.appcastURLString = appcastURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        self.homepageURLString = homepageURLString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isValidSHA256: Bool {
        Self.isValidSHA256(sha256)
    }

    public func appcastXML() -> String {
        let releaseDate = ISO8601DateFormatter().string(from: Date())

        return """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel>
            <title>mvx Updates</title>
            <link>\(appcastURLString)</link>
            <description>Release feed for mvx direct distribution builds.</description>
            <item>
              <title>mvx \(artifact.version)</title>
              <pubDate>\(releaseDate)</pubDate>
              <sparkle:version>\(artifact.build)</sparkle:version>
              <sparkle:shortVersionString>\(artifact.version)</sparkle:shortVersionString>
              <enclosure
                url="\(artifact.downloadURLString)"
                sparkle:version="\(artifact.build)"
                sparkle:shortVersionString="\(artifact.version)"
                sparkle:edSignature=""
                length="0"
                type="application/octet-stream" />
            </item>
          </channel>
        </rss>
        """
    }

    public func homebrewCask(
        minimumMacOS: String = DistributionDefaults.defaultMinimumMacOS
    ) -> String {
        """
        cask "mvx" do
          version "\(artifact.version)"
          sha256 "\(sha256)"

          url "\(artifact.downloadURLString)"
          name "mvx"
          desc "AI-agent-aware terminal workspace for macOS"
          homepage "\(homepageURLString)"

          auto_updates true
          depends_on macos: ">= :ventura"

          app "\(DistributionDefaults.appBundleName)"
        end
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
    public var appcastURL: URL?
    public var fallbackDownloadURL: URL?

    public init(appcastURL: URL?, fallbackDownloadURL: URL?) {
        self.appcastURL = appcastURL
        self.fallbackDownloadURL = fallbackDownloadURL
    }

    public var canCheckForUpdates: Bool {
        appcastURL != nil || fallbackDownloadURL != nil
    }

    public static func resolve(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AppUpdateConfiguration {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = bundle.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String
        let downloadBaseURL = environment["MVX_DOWNLOAD_BASE_URL"]
            ?? (bundle.object(forInfoDictionaryKey: "MVXDownloadBaseURL") as? String)
            ?? DistributionDefaults.defaultDownloadBaseURL
        let appcastURLString = environment["MVX_APPCAST_URL"]
            ?? (bundle.object(forInfoDictionaryKey: "MVXAppcastURL") as? String)
            ?? DistributionDefaults.defaultAppcastURL

        let artifact = ReleaseArtifactDescriptor(
            version: version ?? DistributionDefaults.defaultVersion,
            build: build ?? DistributionDefaults.defaultBuild,
            downloadBaseURL: downloadBaseURL
        )

        return AppUpdateConfiguration(
            appcastURL: URL(string: appcastURLString),
            fallbackDownloadURL: URL(string: artifact.downloadURLString)
        )
    }
}
