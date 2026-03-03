import XCTest
@testable import Mvx

@MainActor
final class SessionGroupPaneGraphTests: XCTestCase {
    func testSelectGroupSwapsWorkspaceGraph() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let ungroupedID = try XCTUnwrap(workspace.activeSessionID)
        let grouped = workspace.createSession(selectNewSession: false)
        let group = workspace.createGroup(name: "Frontend", colorTag: nil)

        XCTAssertTrue(workspace.assignSession(id: grouped.id, toGroup: group.id))
        XCTAssertEqual(workspace.workspaceGraph.leafSessionIDs, [ungroupedID])

        XCTAssertTrue(workspace.selectGroup(id: group.id))
        XCTAssertEqual(workspace.workspaceGraph.leafSessionIDs, [grouped.id])

        XCTAssertTrue(workspace.selectGroup(id: nil))
        XCTAssertEqual(workspace.workspaceGraph.leafSessionIDs, [ungroupedID])
    }

    func testSelectGroupReturnsFalseForUnknownID() {
        let workspace = makeTestWorkspace(autoStartSessions: false)

        XCTAssertFalse(workspace.selectGroup(id: UUID()))
    }

    func testSelectSessionAutoSwitchesToOwningGroup() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        _ = try XCTUnwrap(workspace.activeSessionID)
        let grouped = workspace.createSession(selectNewSession: false)
        let group = workspace.createGroup(name: "Frontend", colorTag: nil)

        XCTAssertTrue(workspace.assignSession(id: grouped.id, toGroup: group.id))
        XCTAssertTrue(workspace.selectSession(id: grouped.id))

        XCTAssertEqual(workspace.activeGroupID, group.id)
        XCTAssertEqual(workspace.activeSessionID, grouped.id)
        XCTAssertEqual(workspace.workspaceGraph.leafSessionIDs, [grouped.id])
    }

    func testCreateSessionAutoAssignsToActiveGroup() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let group = workspace.createGroup(name: "Frontend", colorTag: nil)

        XCTAssertTrue(workspace.selectGroup(id: group.id))

        let created = workspace.createSession()

        XCTAssertEqual(workspace.activeGroupID, group.id)
        XCTAssertEqual(workspace.sessionGroupAssignments[created.id], group.id)
        XCTAssertEqual(workspace.workspaceGraph.leafSessionIDs, [created.id])
    }

    func testSplitActivePaneAutoAssignsNewSession() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let initialID = try XCTUnwrap(workspace.activeSessionID)
        let group = workspace.createGroup(name: "Frontend", colorTag: nil)

        XCTAssertTrue(workspace.assignSession(id: initialID, toGroup: group.id))
        XCTAssertTrue(workspace.selectGroup(id: group.id))
        XCTAssertTrue(workspace.splitActivePane(.vertical))

        let newActiveID = try XCTUnwrap(workspace.activeSessionID)

        XCTAssertEqual(workspace.sessionGroupAssignments[initialID], group.id)
        XCTAssertEqual(workspace.sessionGroupAssignments[newActiveID], group.id)
        XCTAssertEqual(workspace.workspaceGraph.paneCount, 2)
    }

    func testCloseSessionDetachesFromCorrectBackingGraph() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        _ = try XCTUnwrap(workspace.activeSessionID)
        let grouped = workspace.createSession(selectNewSession: false)
        let group = workspace.createGroup(name: "Frontend", colorTag: nil)

        XCTAssertTrue(workspace.assignSession(id: grouped.id, toGroup: group.id))
        XCTAssertTrue(workspace.selectGroup(id: group.id))
        XCTAssertTrue(workspace.selectGroup(id: nil))
        XCTAssertTrue(workspace.closeSession(id: grouped.id))

        XCTAssertNil(groupState(in: workspace, id: group.id)?.paneGraph.rootPane)
        XCTAssertNil(workspace.sessionGroupAssignments[grouped.id])
    }

    func testAssignSessionDetachesFromSourceGraph() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let sessionID = try XCTUnwrap(workspace.activeSessionID)
        let source = workspace.createGroup(name: "Source", colorTag: nil)
        let destination = workspace.createGroup(name: "Destination", colorTag: nil)

        XCTAssertTrue(workspace.assignSession(id: sessionID, toGroup: source.id))
        XCTAssertTrue(workspace.selectGroup(id: source.id))
        XCTAssertNotNil(groupState(in: workspace, id: source.id)?.paneGraph.rootPane)

        XCTAssertTrue(workspace.assignSession(id: sessionID, toGroup: destination.id))

        XCTAssertNil(groupState(in: workspace, id: source.id)?.paneGraph.rootPane)
        XCTAssertEqual(workspace.sessionGroupAssignments[sessionID], destination.id)
    }

    func testDeleteGroupMovesSessionsToUngrouped() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let sessionID = try XCTUnwrap(workspace.activeSessionID)
        let group = workspace.createGroup(name: "Frontend", colorTag: nil)

        XCTAssertTrue(workspace.assignSession(id: sessionID, toGroup: group.id))
        XCTAssertTrue(workspace.selectGroup(id: group.id))
        XCTAssertTrue(workspace.deleteGroup(id: group.id))

        XCTAssertNil(workspace.activeGroupID)
        XCTAssertNil(workspace.sessionGroupAssignments[sessionID])
        XCTAssertEqual(workspace.workspaceGraph.leafSessionIDs, [sessionID])
    }

    func testSnapshotRoundTripsGroupPaneGraphsAndActiveGroup() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let firstID = try XCTUnwrap(workspace.activeSessionID)
        let second = workspace.createSession(selectNewSession: false)
        let group = workspace.createGroup(name: "Frontend", colorTag: .blue)

        XCTAssertTrue(workspace.assignSession(id: firstID, toGroup: group.id))
        XCTAssertTrue(workspace.assignSession(id: second.id, toGroup: group.id))
        XCTAssertTrue(workspace.selectGroup(id: group.id))
        XCTAssertTrue(workspace.placeSession(id: second.id, inFocusedPaneUsing: .splitLeft))
        XCTAssertTrue(workspace.splitActivePane(.horizontal))

        let snapshot = workspace.snapshot()
        let restored = makeTestWorkspace(autoStartSessions: false, startsWithSession: false)

        XCTAssertTrue(restored.restore(from: snapshot))

        let restoredGroup = try XCTUnwrap(groupState(in: restored, id: group.id))
        XCTAssertEqual(restored.activeGroupID, group.id)
        XCTAssertEqual(restored.workspaceGraph.leafSessionIDs.count, 3)
        XCTAssertEqual(restoredGroup.paneGraph.leafSessionIDs.count, 3)
    }

    func testV5SnapshotRestoreDefaultsToEmptyGraphsAndNilActiveGroup() throws {
        let sessionID = UUID()
        let groupID = UUID()
        let legacyJSON = """
        {
          "schemaVersion": 5,
          "sessions": [
            {
              "descriptor": {
                "id": "\(sessionID.uuidString)",
                "ordinal": 1,
                "customTitle": null,
                "workingDirectoryPath": null,
                "foregroundProcessName": null,
                "agentStatus": "none"
              }
            }
          ],
          "activeSessionID": "\(sessionID.uuidString)",
          "nextOrdinal": 2,
          "workspaceGraph": null,
          "sessionGroups": [
            {
              "id": "\(groupID.uuidString)",
              "name": "Frontend",
              "colorTag": null,
              "isCollapsed": false
            }
          ],
          "sessionGroupAssignments": {
            "\(sessionID.uuidString)": "\(groupID.uuidString)"
          }
        }
        """

        let snapshot = try JSONDecoder().decode(
            WorkspaceSnapshot.self,
            from: XCTUnwrap(legacyJSON.data(using: .utf8))
        )
        let restored = makeTestWorkspace(autoStartSessions: false, startsWithSession: false)

        XCTAssertTrue(restored.restore(from: snapshot))

        XCTAssertNil(restored.activeGroupID)
        XCTAssertNil(restored.workspaceGraph.rootPane)
        XCTAssertEqual(restored.sessionGroups.count, 1)
        XCTAssertEqual(restored.sessionGroups[0].paneGraph.leafSessionIDs, [sessionID])
    }

    private func groupState(in workspace: SessionWorkspace, id: UUID) -> SessionGroup? {
        workspace.sessionGroups.first(where: { $0.id == id })
    }
}
