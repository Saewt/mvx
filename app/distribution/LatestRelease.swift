import Foundation

public struct LatestRelease: Codable, Equatable, Sendable {
    public var version: String
    public var build: String
    public var minimumMacOS: String
    public var platforms: Platforms

    private enum CodingKeys: String, CodingKey {
        case version, build, platforms
        case minimumMacOS = "minimum_macos"
    }

    public struct Platforms: Codable, Equatable {
        public var darwinAarch64: PlatformAsset

        public init(darwinAarch64: PlatformAsset) {
            self.darwinAarch64 = darwinAarch64
        }

        private enum CodingKeys: String, CodingKey {
            case darwinAarch64 = "darwin-aarch64"
        }
    }

    public struct PlatformAsset: Codable, Equatable {
        public var url: String
        public var sha256: String

        public init(url: String, sha256: String) {
            self.url = url
            self.sha256 = sha256
        }
    }

    public init(
        version: String,
        build: String,
        minimumMacOS: String,
        platforms: Platforms
    ) {
        self.version = version
        self.build = build
        self.minimumMacOS = minimumMacOS
        self.platforms = platforms
    }

    public var tarballURL: URL? {
        URL(string: platforms.darwinAarch64.url)
    }

    public var expectedSHA256: String {
        platforms.darwinAarch64.sha256
    }

    public static func fromJSON(_ data: Data) -> LatestRelease? {
        let decoder = JSONDecoder()
        return try? decoder.decode(LatestRelease.self, from: data)
    }

    public static func fromJSON(_ string: String) -> LatestRelease? {
        guard let data = string.data(using: .utf8) else { return nil }
        return fromJSON(data)
    }
}

public enum SemanticVersion: Comparable {
    case stable(major: Int, minor: Int, patch: Int, build: Int)
    case invalid(String)

    public init(_ string: String) {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3,
              let major = Int(parts[0]),
              let minor = Int(parts[1]),
              let patchStr = parts[2].split(separator: "-", omittingEmptySubsequences: false).first,
              let patch = Int(patchStr)
        else {
            self = .invalid(string)
            return
        }

        let build = Int(parts.count > 3 ? String(parts[3]) : "0") ?? 0
        self = .stable(major: major, minor: minor, patch: patch, build: build)
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        switch (lhs, rhs) {
        case (.invalid, .invalid):
            return false
        case (.invalid, .stable):
            return false
        case (.stable, .invalid):
            return true
        case let (.stable(lMaj, lMin, lPat, lBld), .stable(rMaj, rMin, rPat, rBld)):
            if lMaj != rMaj { return lMaj < rMaj }
            if lMin != rMin { return lMin < rMin }
            if lPat != rPat { return lPat < rPat }
            return lBld < rBld
        }
    }

    public static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        switch (lhs, rhs) {
        case let (.stable(lMaj, lMin, lPat, lBld), .stable(rMaj, rMin, rPat, rBld)):
            return lMaj == rMaj && lMin == rMin && lPat == rPat && lBld == rBld
        case let (.invalid(lStr), .invalid(rStr)):
            return lStr == rStr
        default:
            return false
        }
    }
}