import XCTest
@testable import Mvx

final class TerminalSessionSmokeTests: XCTestCase {
    func testSessionUsesNativeBackendAndExposesUnderlyingDriver() {
        let session = makeTestSession()

        XCTAssertEqual(session.backendKind, .nativeGhostty)
        XCTAssertTrue(session.backendObject is InMemoryTestTerminalDriver)
    }

    func testLaunchesAndEchoesSentInput() {
        let session = makeTestSession()

        session.start()
        let output = session.sendUserInput("printf 'hello from mvx\\n'\n")

        XCTAssertEqual(output, "printf 'hello from mvx\\n'\n")
        XCTAssertEqual((session.backendObject as? InMemoryTestTerminalDriver)?.sentInput.last, output)
        XCTAssertTrue(session.isActive)
    }

    func testRuntimeEventsReportStartupDirectoryAndExit() {
        let session = makeTestSession()
        let driver = session.backendObject as? InMemoryTestTerminalDriver
        var events: [SessionRuntimeEvent] = []

        _ = session.addRuntimeEventObserver { events.append($0) }
        driver?.emitRuntimeEvent(.contextChanged(workingDirectoryPath: "/tmp/mvx", foregroundProcessName: "zsh"))
        driver?.emitRuntimeEvent(.childExited(exitCode: 0))

        XCTAssertEqual(
            events,
            [
                .contextChanged(workingDirectoryPath: "/tmp/mvx", foregroundProcessName: "zsh"),
                .childExited(exitCode: 0),
            ]
        )
    }
}
