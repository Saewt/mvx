import XCTest
@testable import Mvx

@MainActor
final class SessionAgentStatusTests: XCTestCase {
    func testParsesValidStatusPayloads() {
        let rawUpdate = SessionAgentStatusUpdate.parse("7777;state=running")
        let belUpdate = SessionAgentStatusUpdate.parse("\u{001B}]7777;state=waiting\u{0007}")
        let stUpdate = SessionAgentStatusUpdate.parse("\u{001B}]7777;state=error\u{001B}\\")

        XCTAssertEqual(rawUpdate?.status, .running)
        XCTAssertEqual(belUpdate?.status, .waiting)
        XCTAssertEqual(stUpdate?.status, .error)
    }

    func testRejectsMalformedStatusPayloads() {
        XCTAssertNil(SessionAgentStatusUpdate.parse(""))
        XCTAssertNil(SessionAgentStatusUpdate.parse("9999;state=running"))
        XCTAssertNil(SessionAgentStatusUpdate.parse("7777"))
        XCTAssertNil(SessionAgentStatusUpdate.parse("7777;state=paused"))
        XCTAssertNil(SessionAgentStatusUpdate.parse("7777;state"))
    }

    func testWorkspaceAppliesStatusUpdateToMatchingSession() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let firstID = try! XCTUnwrap(workspace.activeSessionID)
        let second = workspace.createSession()

        XCTAssertTrue(workspace.applyAgentStatusEscapeSequence(
            id: second.id,
            sequence: "\u{001B}]7777;state=running\u{0007}"
        ))

        XCTAssertEqual(workspace.sessions.first(where: { $0.id == firstID })?.agentStatus, SessionAgentStatus.none)
        XCTAssertEqual(workspace.sessions.first(where: { $0.id == second.id })?.agentStatus, .running)
    }

    func testLatestValidStatusWins() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let activeID = try! XCTUnwrap(workspace.activeSessionID)

        XCTAssertTrue(workspace.applyAgentStatusEscapeSequence(id: activeID, sequence: "7777;state=running"))
        XCTAssertTrue(workspace.applyAgentStatusEscapeSequence(id: activeID, sequence: "7777;state=done"))
        XCTAssertFalse(workspace.applyAgentStatusEscapeSequence(id: activeID, sequence: "7777;state=paused"))

        XCTAssertEqual(workspace.activeDescriptor?.agentStatus, .done)
    }

    func testDocumentedWrapperPayloadParses() {
        let wrapperPayload = "\u{001B}]7777;state=running\u{0007}"
        let session = makeTestSession()

        XCTAssertEqual(session.processAgentStatusEscapeSequence(wrapperPayload)?.status, .running)
    }

    func testHelperCommandUpdatesStatus() {
        let session = makeTestSession()

        session.start()
        _ = session.sendUserInput("./scripts/mvx-agent-status waiting\n")

        XCTAssertEqual(session.latestAgentStatus, .waiting)
        XCTAssertTrue(session.currentPromptVisible())
    }

    func testWrapperCommandTransitionsToDone() {
        let session = makeTestSession()
        let driver = session.backendObject as? InMemoryTestTerminalDriver

        session.start()
        _ = session.sendUserInput("./scripts/mvx-wrap-agent /bin/sh -lc 'sleep 1'\n")
        driver?.emitAgentStatus(.done)

        XCTAssertEqual(session.latestAgentStatus, .done)
    }
}
