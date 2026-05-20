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
        XCTAssertNil(first.note)
        XCTAssertEqual(second.name, "New Group 2")
        XCTAssertEqual(second.colorTag, .blue)
        XCTAssertNil(second.paneGraph.rootPane)
        XCTAssertNil(second.paneGraph.focusedPaneID)
        XCTAssertNil(second.note)
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
        XCTAssertNotNil(workspace.descriptor(for: sessionID))
        XCTAssertTrue(workspace.sessions(inGroup: nil).map(\.id).contains(sessionID))
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

    func testSetGroupColorTag() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let group = workspace.createGroup(name: "Frontend", colorTag: nil)
        XCTAssertNil(group.colorTag)

        XCTAssertTrue(workspace.setGroupColorTag(id: group.id, colorTag: .blue))
        XCTAssertEqual(workspace.sessionGroups.first?.colorTag, .blue)

        XCTAssertTrue(workspace.setGroupColorTag(id: group.id, colorTag: .red))
        XCTAssertEqual(workspace.sessionGroups.first?.colorTag, .red)

        // Same color → no-op
        XCTAssertFalse(workspace.setGroupColorTag(id: group.id, colorTag: .red))

        // Clear
        XCTAssertTrue(workspace.setGroupColorTag(id: group.id, colorTag: nil))
        XCTAssertNil(workspace.sessionGroups.first?.colorTag)
    }

    func testCloseDoneSessionsOnlyRemovesDoneSessionsInRequestedGroup() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let firstID = try XCTUnwrap(workspace.activeSessionID)
        let doneInGroup = workspace.createSession(selectNewSession: false)
        let runningInGroup = workspace.createSession(selectNewSession: false)
        let doneOutsideGroup = workspace.createSession(selectNewSession: false)
        let group = workspace.createGroup(name: "Frontend", colorTag: nil)

        XCTAssertTrue(workspace.assignSession(id: firstID, toGroup: group.id))
        XCTAssertTrue(workspace.assignSession(id: doneInGroup.id, toGroup: group.id))
        XCTAssertTrue(workspace.assignSession(id: runningInGroup.id, toGroup: group.id))
        XCTAssertTrue(workspace.updateAgentStatus(id: firstID, status: .done))
        XCTAssertTrue(workspace.updateAgentStatus(id: doneInGroup.id, status: .done))
        XCTAssertTrue(workspace.updateAgentStatus(id: runningInGroup.id, status: .running))
        XCTAssertTrue(workspace.updateAgentStatus(id: doneOutsideGroup.id, status: .done))

        let closedCount = workspace.closeDoneSessions(inGroup: group.id)

        XCTAssertEqual(closedCount, 2)
        XCTAssertEqual(workspace.sessions(inGroup: group.id).map(\.id), [runningInGroup.id])
        XCTAssertNotNil(workspace.descriptor(for: doneOutsideGroup.id))
    }

    func testCloseAllSessionsInActiveGroupCreatesReplacementInSameGroup() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let firstID = try XCTUnwrap(workspace.activeSessionID)
        let second = workspace.createSession(selectNewSession: false)
        let outside = workspace.createSession(selectNewSession: false)
        let group = workspace.createGroup(name: "Frontend", colorTag: nil)

        XCTAssertTrue(workspace.assignSession(id: firstID, toGroup: group.id))
        XCTAssertTrue(workspace.assignSession(id: second.id, toGroup: group.id))
        XCTAssertTrue(workspace.selectGroup(id: group.id))

        let closedCount = workspace.closeAllSessions(inGroup: group.id)
        let remainingInGroup = workspace.sessions(inGroup: group.id)

        XCTAssertEqual(closedCount, 2)
        XCTAssertEqual(remainingInGroup.count, 1)
        XCTAssertNotEqual(remainingInGroup.first?.id, firstID)
        XCTAssertNotEqual(remainingInGroup.first?.id, second.id)
        XCTAssertNotNil(workspace.descriptor(for: outside.id))
        XCTAssertEqual(workspace.activeGroupID, group.id)
    }

    func testCloseAllSessionsInInactiveGroupLeavesGroupEmpty() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let firstID = try XCTUnwrap(workspace.activeSessionID)
        let grouped = workspace.createSession(selectNewSession: false)
        let group = workspace.createGroup(name: "Backend", colorTag: nil)

        XCTAssertTrue(workspace.assignSession(id: grouped.id, toGroup: group.id))
        XCTAssertNil(workspace.activeGroupID)

        let closedCount = workspace.closeAllSessions(inGroup: group.id)

        XCTAssertEqual(closedCount, 1)
        XCTAssertEqual(workspace.sessions(inGroup: group.id), [])
        XCTAssertEqual(workspace.sessions(inGroup: nil).map(\.id), [firstID])
    }

    func testMoveAllSessionsAndCollapseOtherGroupsComposeExistingPrimitives() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let firstID = try XCTUnwrap(workspace.activeSessionID)
        let second = workspace.createSession(selectNewSession: false)
        let third = workspace.createSession(selectNewSession: false)
        let preserved = workspace.createGroup(name: "Preserved", colorTag: nil)
        let collapsed = workspace.createGroup(name: "Already Collapsed", colorTag: nil)
        let target = workspace.createGroup(name: "Target", colorTag: nil)

        XCTAssertTrue(workspace.assignSession(id: firstID, toGroup: preserved.id))
        XCTAssertTrue(workspace.assignSession(id: second.id, toGroup: preserved.id))
        XCTAssertTrue(workspace.assignSession(id: third.id, toGroup: target.id))
        XCTAssertTrue(workspace.setGroupCollapsed(id: collapsed.id, isCollapsed: true))

        XCTAssertEqual(workspace.moveAllSessions(fromGroup: preserved.id, toGroup: nil), 2)
        XCTAssertEqual(workspace.sessions(inGroup: nil).map(\.id), [firstID, second.id])

        XCTAssertEqual(workspace.collapseOtherGroups(excluding: preserved.id), 1)
        XCTAssertFalse(try XCTUnwrap(workspace.sessionGroups.first { $0.id == preserved.id }).isCollapsed)
        XCTAssertTrue(try XCTUnwrap(workspace.sessionGroups.first { $0.id == collapsed.id }).isCollapsed)
        XCTAssertTrue(try XCTUnwrap(workspace.sessionGroups.first { $0.id == target.id }).isCollapsed)
    }
}
