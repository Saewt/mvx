import XCTest
@testable import Mvx

final class ReleasePackagingTests: XCTestCase {
    func testArtifactDescriptorUsesStableArchiveAndTarballNames() {
        let descriptor = ReleaseArtifactDescriptor(
            version: "1.2.3",
            build: "45",
            downloadBaseURL: "https://github.com/Saewt/mvx/releases/latest/download/"
        )

        XCTAssertEqual(descriptor.archiveFileName, "mvx-1.2.3-45.xcarchive")
        XCTAssertEqual(descriptor.exportDirectoryName, "mvx-1.2.3-export")
        XCTAssertEqual(descriptor.releaseDirectoryName, "mvx-1.2.3-release")
        XCTAssertEqual(descriptor.tarballFileName, "mvx-1.2.3-45-darwin-aarch64.app.tar.gz")
        XCTAssertEqual(descriptor.downloadURLString, "https://github.com/Saewt/mvx/releases/latest/download/mvx-1.2.3-45-darwin-aarch64.app.tar.gz")
    }

    func testPackagingManifestCapturesDirectDistributionContract() {
        let descriptor = ReleaseArtifactDescriptor(version: "2.0.0", build: "9")

        let manifest = descriptor.packagingManifest()

        XCTAssertEqual(manifest.version, "2.0.0")
        XCTAssertEqual(manifest.build, "9")
        XCTAssertEqual(manifest.bundleIdentifier, DistributionDefaults.bundleIdentifier)
        XCTAssertEqual(manifest.appBundleName, DistributionDefaults.appBundleName)
        XCTAssertEqual(manifest.tarballFileName, "mvx-2.0.0-9-darwin-aarch64.app.tar.gz")
        XCTAssertFalse(manifest.requiresNotarization)
        XCTAssertTrue(manifest.hardenedRuntimeEnabled)
    }

    func testMissingEnvironmentKeysFlagsBlankOrAbsentValues() {
        let environment = [
            "MVX_TEAM_ID": "TEAMID1234",
            "MVX_NOTARY_PROFILE": "   "
        ]

        let missing = ReleaseArtifactDescriptor.missingEnvironmentKeys(
            in: environment,
            required: ["MVX_TEAM_ID", "MVX_NOTARY_PROFILE", "MVX_SIGNING_IDENTITY"]
        )

        XCTAssertEqual(missing, ["MVX_NOTARY_PROFILE", "MVX_SIGNING_IDENTITY"])
    }

    func testDistributionDefaultsUseGitHubReleaseURL() {
        XCTAssertTrue(DistributionDefaults.defaultLatestReleaseURL.contains("github.com"))
        XCTAssertTrue(DistributionDefaults.defaultLatestReleaseURL.hasSuffix("latest.json"))
        XCTAssertTrue(DistributionDefaults.defaultDownloadBaseURL.contains("github.com"))
    }
}