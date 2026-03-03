import XCTest
@testable import Mvx

@MainActor
final class SessionGroupTests: XCTestCase {
    func testCreateGroupUsesDefaultNamesAndStartsExpanded() {
        let workspace = makeTestWorkspace(autoStartSessions: false)

        let first = workspace.createGroup(name: "   ", colorTag: nil)
        let second = workspace.createGroup(name: "", colorTag: .blue)

        XCTAssertEqual(first.name, "New Group")
        XCTAssertNil(first.colorTag)
        XCTAssertFalse(first.isCollapsed)
        XCTAssertNil(first.paneGraph.rootPane)
        XCTAssertNil(first.paneGraph.focusedPaneID)
        XCTAssertEqual(second.name, "New Group 2")
        XCTAssertEqual(second.colorTag, .blue)
        XCTAssertNil(second.paneGraph.rootPane)
        XCTAssertNil(second.paneGraph.focusedPaneID)
        XCTAssertEqual(workspace.sessionGroups.map(\.id), [first.id, second.id])
    }

    func testRenameDeleteAndMoveGroupRespectValidation() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let first = workspace.createGroup(name: "Frontend", colorTag: nil)
        let second = workspace.createGroup(name: "Backend", colorTag: nil)
        let third = workspace.createGroup(name: "Tests", colorTag: nil)
        let sessionID = try! XCTUnwrap(workspace.activeSessionID)

        XCTAssertTrue(workspace.assignSession(id: sessionID, toGroup: second.id))
        XCTAssertTrue(workspace.renameGroup(id: second.id, name: "API"))
        XCTAssertFalse(workspace.renameGroup(id: second.id, name: "   "))
        XCTAssertFalse(workspace.renameGroup(id: UUID(), name: "Missing"))

        XCTAssertTrue(workspace.moveGroup(id: third.id, toIndex: 0))
        XCTAssertEqual(workspace.sessionGroups.map(\.id), [third.id, first.id, second.id])
        XCTAssertFalse(workspace.moveGroup(id: third.id, toIndex: 0))
        XCTAssertFalse(workspace.moveGroup(id: UUID(), toIndex: 1))

        XCTAssertTrue(workspace.deleteGroup(id: second.id))
        XCTAssertEqual(workspace.sessionGroups.map(\.id), [third.id, first.id])
        XCTAssertNil(workspace.sessionGroupAssignments[sessionID])
        XCTAssertFalse(workspace.deleteGroup(id: second.id))
    }

    func testAssignAndUnassignSessionsValidateIDsAndFilterByGroup() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let firstID = try! XCTUnwrap(workspace.activeSessionID)
        let second = workspace.createSession(selectNewSession: false)
        let group = workspace.createGroup(name: "Frontend", colorTag: nil)

        XCTAssertTrue(workspace.assignSession(id: firstID, toGroup: group.id))
        XCTAssertEqual(workspace.sessions(inGroup: group.id).map(\.id), [firstID])
        XCTAssertEqual(workspace.sessions(inGroup: nil).map(\.id), [second.id])

        XCTAssertFalse(workspace.assignSession(id: UUID(), toGroup: group.id))
        XCTAssertFalse(workspace.assignSession(id: firstID, toGroup: UUID()))

        XCTAssertTrue(workspace.assignSession(id: firstID, toGroup: nil))
        XCTAssertEqual(workspace.sessions(inGroup: group.id).map(\.id), [])
        XCTAssertEqual(workspace.sessions(inGroup: nil).map(\.id), [second.id, firstID])
    }

    func testAggregatedAgentStatusUsesPriorityOrder() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let firstID = try! XCTUnwrap(workspace.activeSessionID)
        let second = workspace.createSession(selectNewSession: false)
        let third = workspace.createSession(selectNewSession: false)
        let fourth = workspace.createSession(selectNewSession: false)
        let group = workspace.createGroup(name: "Priority", colorTag: nil)

        XCTAssertEqual(workspace.aggregatedAgentStatus(forGroup: group.id), .none)

        XCTAssertTrue(workspace.assignSession(id: firstID, toGroup: group.id))
        XCTAssertTrue(workspace.updateAgentStatus(id: firstID, status: .done))
        XCTAssertEqual(workspace.aggregatedAgentStatus(forGroup: group.id), .done)

        XCTAssertTrue(workspace.assignSession(id: second.id, toGroup: group.id))
        XCTAssertTrue(workspace.updateAgentStatus(id: second.id, status: .running))
        XCTAssertEqual(workspace.aggregatedAgentStatus(forGroup: group.id), .running)

        XCTAssertTrue(workspace.assignSession(id: third.id, toGroup: group.id))
        XCTAssertTrue(workspace.updateAgentStatus(id: third.id, status: .waiting))
        XCTAssertEqual(workspace.aggregatedAgentStatus(forGroup: group.id), .waiting)

        XCTAssertTrue(workspace.assignSession(id: fourth.id, toGroup: group.id))
        XCTAssertTrue(workspace.updateAgentStatus(id: fourth.id, status: .error))
        XCTAssertEqual(workspace.aggregatedAgentStatus(forGroup: group.id), .error)
    }

    func testCloseSessionRemovesGroupAssignment() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let sessionID = try! XCTUnwrap(workspace.activeSessionID)
        let group = workspace.createGroup(name: "Frontend", colorTag: nil)

        XCTAssertTrue(workspace.assignSession(id: sessionID, toGroup: group.id))
        XCTAssertTrue(workspace.closeSession(id: sessionID))
        XCTAssertNil(workspace.sessionGroupAssignments[sessionID])
    }

    func testHandleDroppedSessionBeforeInheritsTargetGroup() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let firstID = try! XCTUnwrap(workspace.activeSessionID)
        let second = workspace.createSession(selectNewSession: false)
        let third = workspace.createSession(selectNewSession: false)
        let group = workspace.createGroup(name: "Frontend", colorTag: nil)

        XCTAssertTrue(workspace.assignSession(id: second.id, toGroup: group.id))
        let payload = WorkspaceDragPayload(kind: .session, id: third.id).serializedValue

        XCTAssertTrue(workspace.handleDroppedSession(identifier: payload, before: second.id))
        XCTAssertEqual(workspace.sessionGroupAssignments[third.id], group.id)
        XCTAssertEqual(workspace.sessions(inGroup: group.id).map(\.id), [third.id, second.id])
        XCTAssertNil(workspace.sessionGroupAssignments[firstID])
    }

    func testHandleDroppedSessionToGroupAssignsAndMovesToEndOfGroup() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let firstID = try! XCTUnwrap(workspace.activeSessionID)
        let second = workspace.createSession(selectNewSession: false)
        let third = workspace.createSession(selectNewSession: false)
        let group = workspace.createGroup(name: "Frontend", colorTag: nil)

        XCTAssertTrue(workspace.assignSession(id: firstID, toGroup: group.id))
        XCTAssertTrue(workspace.assignSession(id: second.id, toGroup: group.id))
        XCTAssertTrue(workspace.moveSession(id: third.id, toIndex: 0))

        let payload = WorkspaceDragPayload(kind: .session, id: third.id).serializedValue

        XCTAssertTrue(workspace.handleDroppedSession(identifier: payload, toGroup: group.id))
        XCTAssertEqual(workspace.sessions(inGroup: group.id).map(\.id), [firstID, second.id, third.id])
    }
}
