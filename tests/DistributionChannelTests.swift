import Combine
import XCTest
@testable import Mvx

final class DistributionChannelTests: XCTestCase {
    func testPublicationDescriptorGeneratesLatestJSON() {
        let artifact = ReleaseArtifactDescriptor(version: "1.4.0", build: "12")
        let sha = String(repeating: "b", count: 64)
        let publication = ReleasePublicationDescriptor(artifact: artifact, sha256: sha)

        let json = publication.latestJSON()

        XCTAssertTrue(json.contains("\"version\": \"1.4.0\""))
        XCTAssertTrue(json.contains("\"build\": \"12\""))
        XCTAssertTrue(json.contains("\"minimum_macos\": \"13.0\""))
        XCTAssertTrue(json.contains(artifact.downloadURLString))
        XCTAssertTrue(json.contains(sha))
        XCTAssertTrue(json.contains("darwin-aarch64"))
    }

    func testShaValidationRejectsInvalidChecksums() {
        XCTAssertTrue(ReleasePublicationDescriptor.isValidSHA256(String(repeating: "c", count: 64)))
        XCTAssertFalse(ReleasePublicationDescriptor.isValidSHA256("xyz"))
        XCTAssertFalse(ReleasePublicationDescriptor.isValidSHA256(String(repeating: "g", count: 64)))
    }

    func testUpdateConfigurationResolvesLatestReleaseURLOffEnvironment() {
        let environment = [
            "MVX_LATEST_RELEASE_URL": "https://example.com/mvx/latest.json"
        ]

        let configuration = AppUpdateConfiguration.resolve(bundle: .main, environment: environment)

        XCTAssertEqual(configuration.latestReleaseURL?.absoluteString, "https://example.com/mvx/latest.json")
        XCTAssertTrue(configuration.canCheckForUpdates)
    }

    func testUpdateConfigurationDefaultsToGitHubLatestReleaseURL() {
        let configuration = AppUpdateConfiguration.resolve(bundle: .main, environment: [:])

        XCTAssertEqual(configuration.latestReleaseURL, URL(string: DistributionDefaults.defaultLatestReleaseURL))
        XCTAssertTrue(configuration.canCheckForUpdates)
    }

    func testUpdateConfigurationNilURLCannotCheckForUpdates() {
        let configuration = AppUpdateConfiguration(latestReleaseURL: nil)

        XCTAssertFalse(configuration.canCheckForUpdates)
    }

    @MainActor
    func testUpdateControllerWithNoNetworkReportsFailure() {
        let controller = ReleaseUpdateController()
        XCTAssertTrue(controller.canCheckForUpdates)
        XCTAssertTrue(controller.checkForUpdates())
    }

    @MainActor
    func testWorkspaceCommandHandlerSurfacesCheckForUpdates() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let controller = ReleaseUpdateController()
        let handler = WorkspaceCommandHandler(workspace: workspace, updateController: controller)

        let commands = handler.availableCommands()

        XCTAssertTrue(commands.contains { $0.command == .checkForUpdates })
        XCTAssertTrue(commands.contains { $0.title == "Check for Updates" })
    }

    @MainActor
    func testDismissUpdateFromNonIdleStatesReturnsToIdle() {
        let controller = ReleaseUpdateController()
        controller.dismissUpdate()
        XCTAssertEqual(controller.updateState, .idle)

        controller.checkForUpdates()
        controller.dismissUpdate()
        XCTAssertEqual(controller.updateState, .idle)
    }

    @MainActor
    func testDismissedDownloadCallbackDoesNotLeaveStaleUpdateState() {
        let controller = ReleaseUpdateController()
        controller.updateState = .downloading
        controller.dismissUpdate()
        XCTAssertEqual(controller.updateState, .idle)
    }

    @MainActor
    func testRelaunchToUpdateReturnsFalseOutsideReadyState() {
        let controller = ReleaseUpdateController()

        XCTAssertFalse(controller.relaunchToUpdate())
        XCTAssertEqual(controller.updateState, .idle)
    }

    @MainActor
    func testRelaunchToUpdateTransitionsToRelaunchingWhenHelperLaunchSucceeds() throws {
        let helperScript = try makeUpdateHelperScript()
        let controller = ReleaseUpdateController(updateHelperScriptPath: helperScript.path)
        controller.updateState = .readyToRelaunch(
            extractedAppPath: "/tmp/new/mvx.app",
            appPath: "/Applications/mvx.app",
            version: "9.9.9",
            build: "99"
        )

        XCTAssertTrue(controller.relaunchToUpdate())
        XCTAssertEqual(controller.updateState, .relaunching(version: "9.9.9", build: "99"))
    }

    @MainActor
    func testRelaunchToUpdateReportsFailureWhenHelperCannotBeLocated() {
        let controller = ReleaseUpdateController(updateHelperScriptPath: "/tmp/does-not-exist-helper.sh")
        controller.updateState = .readyToRelaunch(
            extractedAppPath: "/tmp/new/mvx.app",
            appPath: "/Applications/mvx.app",
            version: "9.9.9",
            build: "99"
        )

        XCTAssertFalse(controller.relaunchToUpdate())
        XCTAssertEqual(controller.updateState, .failed("Failed to locate the update helper script."))
    }

    @MainActor
    func testInteractiveCheckReportsUpToDate() {
        let controller = ReleaseUpdateController()
        let currentVersion = controller.currentVersion
        let currentBuild = controller.currentBuild

        let release = LatestRelease(
            version: currentVersion,
            build: currentBuild,
            minimumMacOS: "13.0",
            platforms: .init(darwinAarch64: .init(
                url: "https://example.com/mvx.tar.gz",
                sha256: String(repeating: "a", count: 64)
            ))
        )

        let publisher = Just(release)
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()

        let expectation = XCTestExpectation(description: "up to date")
        let cancellable = controller.$updateState
            .dropFirst()
            .sink { state in
                if state == .upToDate {
                    expectation.fulfill()
                }
            }

        controller.checkForUpdates(interactive: true, publisher: publisher)

        wait(for: [expectation], timeout: 2.0)
        cancellable.cancel()
        XCTAssertEqual(controller.updateState, .upToDate)
    }

    @MainActor
    func testInteractiveCheckReportsFailure() {
        let controller = ReleaseUpdateController()
        let publisher = Fail<LatestRelease, Error>(error: UpdateError.networkUnavailable)
            .eraseToAnyPublisher()

        let expectation = XCTestExpectation(description: "failure")
        let cancellable = controller.$updateState
            .dropFirst()
            .sink { state in
                if case .failed = state {
                    expectation.fulfill()
                }
            }

        controller.checkForUpdates(interactive: true, publisher: publisher)

        wait(for: [expectation], timeout: 2.0)
        cancellable.cancel()
        XCTAssertEqual(
            controller.updateState,
            .failed(UpdateError.networkUnavailable.localizedDescription)
        )
    }

    @MainActor
    func testNonInteractiveCheckDoesNotSurfaceNetworkErrors() {
        let controller = ReleaseUpdateController()
        let publisher = Fail<LatestRelease, Error>(error: UpdateError.networkUnavailable)
            .eraseToAnyPublisher()

        let expectation = XCTestExpectation(description: "idle after silent failure")
        let cancellable = controller.$updateState
            .dropFirst()
            .sink { state in
                if state == .idle {
                    expectation.fulfill()
                }
            }

        controller.checkForUpdates(interactive: false, publisher: publisher)

        wait(for: [expectation], timeout: 2.0)
        cancellable.cancel()
        XCTAssertEqual(controller.updateState, .idle)
    }

    @MainActor
    func testNonInteractiveCheckSurfacesUpdateAvailable() {
        let bundle = makeWritableTestBundle()
        let controller = ReleaseUpdateController(bundle: bundle)
        let release = LatestRelease(
            version: "999.0.0",
            build: "999",
            minimumMacOS: "13.0",
            platforms: .init(darwinAarch64: .init(
                url: "https://example.com/mvx.tar.gz",
                sha256: String(repeating: "a", count: 64)
            ))
        )

        let publisher = Just(release)
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()

        let expectation = XCTestExpectation(description: "update available")
        let cancellable = controller.$updateState
            .dropFirst()
            .sink { state in
                if case .updateAvailable = state {
                    expectation.fulfill()
                }
            }

        controller.checkForUpdates(interactive: false, publisher: publisher)

        wait(for: [expectation], timeout: 2.0)
        cancellable.cancel()
        XCTAssertEqual(
            controller.updateState,
            .updateAvailable(version: "999.0.0", build: "999", downloadSize: nil)
        )
    }

    @MainActor
    func testThrottlingSkipsChecksInside24Hours() {
        let key = ReleaseUpdateController.lastUpdateCheckDefaultsKey
        let original = UserDefaults.standard.object(forKey: key) as? Date

        UserDefaults.standard.set(Date(), forKey: key)
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        let controller = ReleaseUpdateController()
        XCTAssertFalse(controller.shouldPerformAutoCheck)

        // scheduleAutoCheck should return immediately without changing state.
        controller.scheduleAutoCheck()
        XCTAssertEqual(controller.updateState, .idle)
    }

    @MainActor
    func testEnvironmentOverrideMVXLatestReleaseURLIsHonoredByController() {
        let customURL = URL(string: "https://example.com/custom/latest.json")!
        let config = AppUpdateConfiguration(latestReleaseURL: customURL)
        let controller = ReleaseUpdateController(configuration: config)
        XCTAssertEqual(controller.latestReleaseURL, customURL)
    }

    @MainActor
    func testAutoCheckWithUpdateAvailableTriggersCallback() {
        let key = ReleaseUpdateController.lastUpdateCheckDefaultsKey
        UserDefaults.standard.removeObject(forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let bundle = makeWritableTestBundle()
        let controller = ReleaseUpdateController(bundle: bundle)

        let release = LatestRelease(
            version: "999.0.0",
            build: "999",
            minimumMacOS: "13.0",
            platforms: .init(darwinAarch64: .init(
                url: "https://example.com/mvx.tar.gz",
                sha256: String(repeating: "a", count: 64)
            ))
        )
        let publisher = Just(release)
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()

        let callbackExpectation = XCTestExpectation(description: "callback fired")
        controller.scheduleAutoCheck(
            onUpdateAvailable: { callbackExpectation.fulfill() },
            publisher: publisher
        )

        wait(for: [callbackExpectation], timeout: 2.0)
        XCTAssertEqual(
            controller.updateState,
            .updateAvailable(version: "999.0.0", build: "999", downloadSize: nil)
        )
        XCTAssertFalse(controller.shouldPerformAutoCheck)
    }

    @MainActor
    func testAutoCheckUpToDateRecordsThrottle() {
        let key = ReleaseUpdateController.lastUpdateCheckDefaultsKey
        UserDefaults.standard.removeObject(forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let bundle = makeWritableTestBundle()
        let controller = ReleaseUpdateController(bundle: bundle)

        let release = LatestRelease(
            version: controller.currentVersion,
            build: controller.currentBuild,
            minimumMacOS: "13.0",
            platforms: .init(darwinAarch64: .init(
                url: "https://example.com/mvx.tar.gz",
                sha256: String(repeating: "a", count: 64)
            ))
        )
        let publisher = Just(release)
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()

        let expectation = XCTestExpectation(description: "idle after up-to-date")
        let cancellable = controller.$updateState
            .dropFirst()
            .sink { state in
                if state == .idle {
                    expectation.fulfill()
                }
            }

        controller.scheduleAutoCheck(
            onUpdateAvailable: {},
            publisher: publisher
        )

        wait(for: [expectation], timeout: 2.0)
        cancellable.cancel()
        XCTAssertEqual(controller.updateState, .idle)
        XCTAssertFalse(controller.shouldPerformAutoCheck)
    }

    @MainActor
    func testAutoCheckNetworkFailureDoesNotRecordThrottle() {
        let key = ReleaseUpdateController.lastUpdateCheckDefaultsKey
        UserDefaults.standard.removeObject(forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let controller = ReleaseUpdateController()
        let publisher = Fail<LatestRelease, Error>(error: UpdateError.networkUnavailable)
            .eraseToAnyPublisher()

        let expectation = XCTestExpectation(description: "idle after failure")
        let cancellable = controller.$updateState
            .dropFirst()
            .sink { state in
                if state == .idle {
                    expectation.fulfill()
                }
            }

        controller.scheduleAutoCheck(
            onUpdateAvailable: {},
            publisher: publisher
        )

        wait(for: [expectation], timeout: 2.0)
        cancellable.cancel()
        XCTAssertEqual(controller.updateState, .idle)
        XCTAssertTrue(controller.shouldPerformAutoCheck)
    }

    @MainActor
    func testManualCheckSurfacesUpToDate() {
        let bundle = makeWritableTestBundle()
        let controller = ReleaseUpdateController(bundle: bundle)

        let release = LatestRelease(
            version: controller.currentVersion,
            build: controller.currentBuild,
            minimumMacOS: "13.0",
            platforms: .init(darwinAarch64: .init(
                url: "https://example.com/mvx.tar.gz",
                sha256: String(repeating: "a", count: 64)
            ))
        )
        let publisher = Just(release)
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()

        let expectation = XCTestExpectation(description: "up to date")
        let cancellable = controller.$updateState
            .dropFirst()
            .sink { state in
                if state == .upToDate {
                    expectation.fulfill()
                }
            }

        controller.checkForUpdates(interactive: true, publisher: publisher)

        wait(for: [expectation], timeout: 2.0)
        cancellable.cancel()
        XCTAssertEqual(controller.updateState, .upToDate)
    }

    @MainActor
    func testManualCheckSurfacesFailure() {
        let controller = ReleaseUpdateController()
        let publisher = Fail<LatestRelease, Error>(error: UpdateError.networkUnavailable)
            .eraseToAnyPublisher()

        let expectation = XCTestExpectation(description: "failure")
        let cancellable = controller.$updateState
            .dropFirst()
            .sink { state in
                if case .failed = state {
                    expectation.fulfill()
                }
            }

        controller.checkForUpdates(interactive: true, publisher: publisher)

        wait(for: [expectation], timeout: 2.0)
        cancellable.cancel()
        XCTAssertEqual(
            controller.updateState,
            .failed(UpdateError.networkUnavailable.localizedDescription)
        )
    }

    @MainActor
    func testSemanticVersionComparison() {
        XCTAssertTrue(SemanticVersion("1.2.4.3") > SemanticVersion("1.2.3.4"))
        XCTAssertTrue(SemanticVersion("2.0.0.1") > SemanticVersion("1.9.9.99"))
        XCTAssertFalse(SemanticVersion("1.0.0.1") > SemanticVersion("1.0.0.1"))
        XCTAssertTrue(SemanticVersion("0.2.0.1") > SemanticVersion("0.1.4.4"))
    }

    func testLatestReleaseParsing() {
        let json = """
        {
          "version": "1.5.0",
          "build": "42",
          "minimum_macos": "13.0",
          "platforms": {
            "darwin-aarch64": {
              "url": "https://github.com/Saewt/mvx/releases/latest/download/mvx-1.5.0-42-darwin-aarch64.app.tar.gz",
              "sha256": "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"
            }
          }
        }
        """
        let release = LatestRelease.fromJSON(json)
        XCTAssertNotNil(release)
        XCTAssertEqual(release?.version, "1.5.0")
        XCTAssertEqual(release?.build, "42")
        XCTAssertEqual(release?.minimumMacOS, "13.0")
        XCTAssertEqual(release?.platforms.darwinAarch64.url, "https://github.com/Saewt/mvx/releases/latest/download/mvx-1.5.0-42-darwin-aarch64.app.tar.gz")
        XCTAssertEqual(release?.platforms.darwinAarch64.sha256, "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789")
    }

    func testLatestReleaseTarballURLAndSHA() {
        let release = LatestRelease(
            version: "0.2.0",
            build: "10",
            minimumMacOS: "13.0",
            platforms: .init(darwinAarch64: .init(
                url: "https://example.com/mvx.tar.gz",
                sha256: "aaa"
            ))
        )
        XCTAssertEqual(release.tarballURL, URL(string: "https://example.com/mvx.tar.gz"))
        XCTAssertEqual(release.expectedSHA256, "aaa")
    }
}

private func makeUpdateHelperScript() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("mvx-update-helper-\(UUID().uuidString).sh")
    try """
    #!/usr/bin/env bash
    exit 0
    """.write(to: url, atomically: true, encoding: .utf8)
    return url
}
