import XCTest
@testable import Mvx

@MainActor
final class WorkspaceCommandHandlerTests: XCTestCase {
    func testCopyPasteAndSelectAllUseActiveSession() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let handler = WorkspaceCommandHandler(workspace: workspace)

        _ = handler.perform(.copy, selection: "copied")
        let pasted = handler.perform(.paste)
        let selected = handler.perform(.selectAll)

        XCTAssertEqual(workspace.activeSession?.clipboardContents(), "copied")
        XCTAssertEqual(pasted, "copied")
        XCTAssertNil(selected)
    }

    func testNativeCopyPasteAndSelectAllFallBackToSessionWhenResponderChainDoesNotHandleActions() throws {
        let session = makeTestSession(clipboardBridge: ClipboardBridge())
        let workspace = SessionWorkspace(
            autoStartSessions: false,
            startsWithSession: false,
            sessionFactory: { session }
        )
        _ = workspace.createSession()
        let handler = WorkspaceCommandHandler(workspace: workspace)

        _ = handler.perform(.copy, selection: "native copied")
        let pasted = handler.perform(.paste)
        let selected = handler.perform(.selectAll)

        XCTAssertEqual(session.clipboardContents(), "native copied")
        XCTAssertEqual(pasted, "native copied")
        XCTAssertNil(selected)
    }

    func testNewTabAndCloseRouteThroughWorkspace() {
        let workspace = makeTestWorkspace()
        let handler = WorkspaceCommandHandler(workspace: workspace)
        let firstID = workspace.activeSessionID

        _ = handler.perform(.newTab)
        let secondID = workspace.activeSessionID

        XCTAssertNotEqual(firstID, secondID)
        XCTAssertEqual(workspace.sessions.count, 2)

        _ = handler.perform(.closeCurrentSession)

        XCTAssertEqual(workspace.sessions.count, 1)
        XCTAssertEqual(workspace.activeSessionID, firstID)
    }

    func testNextAttentionSelectsWaitingThenErrorSessions() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let firstID = try XCTUnwrap(workspace.activeSessionID)
        let second = workspace.createSession(selectNewSession: false)
        let third = workspace.createSession(selectNewSession: false)
        let handler = WorkspaceCommandHandler(workspace: workspace)

        _ = workspace.updateAgentStatus(id: second.id, status: .waiting)
        _ = workspace.updateAgentStatus(id: third.id, status: .error)

        XCTAssertTrue(workspace.selectSession(id: firstID))
        _ = handler.perform(.nextAttention)
        XCTAssertEqual(workspace.activeSessionID, second.id)

        _ = workspace.updateAgentStatus(id: second.id, status: .none)
        _ = handler.perform(.nextAttention)
        XCTAssertEqual(workspace.activeSessionID, third.id)
    }

    func testPaneAwareCommandsPreserveFocusedRouting() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let handler = WorkspaceCommandHandler(workspace: workspace)
        let firstPane = try XCTUnwrap(workspace.focusedPaneID)

        _ = handler.perform(.splitVertical)
        let secondPane = try XCTUnwrap(workspace.focusedPaneID)
        XCTAssertNotEqual(firstPane, secondPane)

        _ = handler.perform(.previousPane)
        XCTAssertEqual(workspace.focusedPaneID, firstPane)

        _ = handler.perform(.nextPane)
        XCTAssertEqual(workspace.focusedPaneID, secondPane)
    }

    func testNextSessionCyclesSelectionAndQuitSetsFlag() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let handler = WorkspaceCommandHandler(workspace: workspace)
        let firstID = try XCTUnwrap(workspace.activeSessionID)
        let second = workspace.createSession(selectNewSession: false)

        XCTAssertTrue(workspace.selectSession(id: firstID))
        _ = handler.perform(.nextSession)
        XCTAssertEqual(workspace.activeSessionID, second.id)

        _ = handler.perform(.quit)
        XCTAssertTrue(workspace.quitRequested)
    }

    func testNextSessionStaysWithinActiveGroup() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let handler = WorkspaceCommandHandler(workspace: workspace)
        let ungroupedID = try XCTUnwrap(workspace.activeSessionID)
        let groupedA = workspace.createSession(selectNewSession: false)
        let groupedB = workspace.createSession(selectNewSession: false)
        let group = workspace.createGroup(name: "Frontend", colorTag: nil)

        XCTAssertTrue(workspace.assignSession(id: groupedA.id, toGroup: group.id))
        XCTAssertTrue(workspace.assignSession(id: groupedB.id, toGroup: group.id))
        XCTAssertTrue(workspace.selectGroup(id: group.id))
        XCTAssertEqual(workspace.activeSessionID, groupedA.id)

        _ = handler.perform(.nextSession)
        XCTAssertEqual(workspace.activeSessionID, groupedB.id)

        _ = handler.perform(.nextSession)
        XCTAssertEqual(workspace.activeSessionID, groupedA.id)
        XCTAssertNotEqual(workspace.activeSessionID, ungroupedID)
    }
}
