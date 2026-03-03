import XCTest
@testable import Mvx

final class DistributionChannelTests: XCTestCase {
    func testPublicationDescriptorKeepsAppcastAndCaskAlignedToSameArtifact() {
        let artifact = ReleaseArtifactDescriptor(version: "1.4.0", build: "12")
        let sha = String(repeating: "b", count: 64)
        let publication = ReleasePublicationDescriptor(artifact: artifact, sha256: sha)

        let appcast = publication.appcastXML()
        let cask = publication.homebrewCask()

        XCTAssertTrue(appcast.contains(artifact.downloadURLString))
        XCTAssertTrue(appcast.contains("<sparkle:shortVersionString>1.4.0</sparkle:shortVersionString>"))
        XCTAssertTrue(cask.contains("version \"1.4.0\""))
        XCTAssertTrue(cask.contains("sha256 \"\(sha)\""))
        XCTAssertTrue(cask.contains("url \"\(artifact.downloadURLString)\""))
    }

    func testShaValidationRejectsInvalidChecksums() {
        XCTAssertTrue(ReleasePublicationDescriptor.isValidSHA256(String(repeating: "c", count: 64)))
        XCTAssertFalse(ReleasePublicationDescriptor.isValidSHA256("xyz"))
        XCTAssertFalse(ReleasePublicationDescriptor.isValidSHA256(String(repeating: "g", count: 64)))
    }

    func testUpdateConfigurationResolvesFeedAndFallbackFromEnvironment() {
        let environment = [
            "MVX_APPCAST_URL": "https://downloads.example.com/mvx/appcast.xml",
            "MVX_DOWNLOAD_BASE_URL": "https://downloads.example.com/mvx"
        ]

        let configuration = AppUpdateConfiguration.resolve(bundle: .main, environment: environment)

        XCTAssertEqual(configuration.appcastURL?.absoluteString, "https://downloads.example.com/mvx/appcast.xml")
        XCTAssertTrue(configuration.fallbackDownloadURL?.absoluteString.hasPrefix("https://downloads.example.com/mvx/mvx-") == true)
        XCTAssertEqual(configuration.fallbackDownloadURL?.pathExtension, "dmg")
        XCTAssertTrue(configuration.canCheckForUpdates)
    }

    @MainActor
    func testUpdateControllerOpensFallbackDownloadWhenSparkleIsUnavailable() {
        let configuration = AppUpdateConfiguration(
            appcastURL: URL(string: "https://downloads.example.com/mvx/appcast.xml"),
            fallbackDownloadURL: URL(string: "https://downloads.example.com/mvx/mvx-0.1.0.dmg")
        )
        var openedURL: URL?
        let controller = ReleaseUpdateController(configuration: configuration) { url in
            openedURL = url
            return true
        }

        XCTAssertTrue(controller.checkForUpdates())
        XCTAssertEqual(openedURL?.absoluteString, "https://downloads.example.com/mvx/mvx-0.1.0.dmg")
    }

    @MainActor
    func testWorkspaceCommandHandlerDoesNotSurfaceCheckForUpdates() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let controller = ReleaseUpdateController(
            configuration: AppUpdateConfiguration(
                appcastURL: URL(string: "https://downloads.example.com/mvx/appcast.xml"),
                fallbackDownloadURL: URL(string: "https://downloads.example.com/mvx/mvx-0.1.0.dmg")
            )
        )
        let handler = WorkspaceCommandHandler(workspace: workspace, updateController: controller)

        let commands = handler.availableCommands()

        XCTAssertFalse(commands.contains { $0.command == .checkForUpdates })
        XCTAssertFalse(commands.contains { $0.title == "Check for Updates" })
    }
}
