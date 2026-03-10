import XCTest
@testable import Mvx

@MainActor
final class SessionGroupPersistenceTests: XCTestCase {
    func testWorkspaceSnapshotV8RoundTripsSessionGroups() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let firstID = try XCTUnwrap(workspace.activeSessionID)
        let second = workspace.createSession(selectNewSession: false)
        let frontend = workspace.createGroup(name: "Frontend", colorTag: .blue)
        let backend = workspace.createGroup(name: "Backend", colorTag: nil)

        XCTAssertTrue(workspace.setGroupCollapsed(id: frontend.id, isCollapsed: true))
        XCTAssertTrue(workspace.assignSession(id: firstID, toGroup: frontend.id))
        XCTAssertTrue(workspace.assignSession(id: second.id, toGroup: backend.id))
        XCTAssertTrue(workspace.updateNote(body: "Frontend follow-up", forGroup: frontend.id))
        XCTAssertTrue(workspace.selectGroup(id: frontend.id))

        let snapshot = workspace.snapshot()
        let encoded = try JSONEncoder().encode(snapshot)
        let payload = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        let restored = makeTestWorkspace(autoStartSessions: false, startsWithSession: false)

        XCTAssertEqual(snapshot.schemaVersion, 8)
        XCTAssertTrue(payload.contains("\"sessionGroups\""))
        XCTAssertTrue(payload.contains("\"sessionGroupAssignments\""))
        XCTAssertEqual(snapshot.activeGroupID, frontend.id)
        XCTAssertEqual(snapshot.sessionGroups.first?.note?.body, "Frontend follow-up")
        XCTAssertTrue(restored.restore(from: snapshot))
        XCTAssertEqual(restored.sessionGroups.map(\.name), ["Frontend", "Backend"])
        XCTAssertEqual(restored.sessionGroups.first?.colorTag, .blue)
        XCTAssertEqual(restored.sessionGroups.first?.isCollapsed, true)
        XCTAssertEqual(restored.sessionGroups.first?.note?.body, "Frontend follow-up")
        XCTAssertEqual(restored.sessionGroupAssignments[firstID], frontend.id)
        XCTAssertEqual(restored.sessionGroupAssignments[second.id], backend.id)
        XCTAssertEqual(restored.activeGroupID, frontend.id)
    }

    func testWorkspaceSnapshotPersistsUpdatedAndClearedGroupColorTags() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let frontend = workspace.createGroup(name: "Frontend", colorTag: nil)
        let backend = workspace.createGroup(name: "Backend", colorTag: .green)

        XCTAssertTrue(workspace.setGroupColorTag(id: frontend.id, colorTag: .blue))
        XCTAssertTrue(workspace.setGroupColorTag(id: backend.id, colorTag: nil))

        let snapshot = workspace.snapshot()
        let restored = makeTestWorkspace(autoStartSessions: false, startsWithSession: false)

        XCTAssertEqual(snapshot.sessionGroups.map(\.colorTag), [.blue, nil])
        XCTAssertTrue(restored.restore(from: snapshot))
        XCTAssertEqual(restored.sessionGroups.map(\.colorTag), [.blue, nil])
    }

    func testV4SnapshotDecodeDefaultsGroupsToEmptyCollections() throws {
        let sessionID = UUID()
        let legacyJSON = """
        {
          "schemaVersion": 4,
          "sessions": [
            {
              "descriptor": {
                "id": "\(sessionID.uuidString)",
                "ordinal": 1,
                "customTitle": null,
                "workingDirectoryPath": "/tmp/demo",
                "foregroundProcessName": null,
                "agentStatus": "none"
              }
            }
          ],
          "activeSessionID": "\(sessionID.uuidString)",
          "nextOrdinal": 2,
          "workspaceGraph": null
        }
        """

        let data = try XCTUnwrap(legacyJSON.data(using: .utf8))
        let snapshot = try JSONDecoder().decode(WorkspaceSnapshot.self, from: data)
        let restored = makeTestWorkspace(autoStartSessions: false, startsWithSession: false)

        XCTAssertEqual(snapshot.schemaVersion, 4)
        XCTAssertEqual(snapshot.sessionGroups, [])
        XCTAssertEqual(snapshot.sessionGroupAssignments, [:])
        XCTAssertTrue(restored.restore(from: snapshot))
        XCTAssertEqual(restored.sessionGroups, [])
        XCTAssertEqual(restored.sessionGroupAssignments, [:])
    }

    func testRestoreDropsDanglingAndMalformedAssignments() {
        let firstDescriptor = SessionDescriptor(ordinal: 1)
        let secondDescriptor = SessionDescriptor(ordinal: 2)
        let validGroup = WorkspaceSnapshot.PersistedSessionGroup(
            id: UUID(),
            name: "Frontend",
            colorTag: .teal,
            isCollapsed: false
        )
        let snapshot = WorkspaceSnapshot(
            schemaVersion: 5,
            sessions: [
                WorkspaceSnapshot.PersistedSession(descriptor: firstDescriptor),
                WorkspaceSnapshot.PersistedSession(descriptor: secondDescriptor),
            ],
            activeSessionID: firstDescriptor.id,
            nextOrdinal: 3,
            workspaceGraph: nil,
            sessionGroups: [validGroup],
            sessionGroupAssignments: [
                firstDescriptor.id.uuidString: validGroup.id.uuidString,
                secondDescriptor.id.uuidString: UUID().uuidString,
                UUID().uuidString: validGroup.id.uuidString,
                "bad-session": "bad-group",
            ]
        )
        let restored = makeTestWorkspace(autoStartSessions: false, startsWithSession: false)

        XCTAssertTrue(restored.restore(from: snapshot))
        XCTAssertEqual(restored.sessionGroups.map(\.id), [validGroup.id])
        XCTAssertNil(restored.sessionGroups.first?.note)
        XCTAssertEqual(restored.sessionGroupAssignments, [firstDescriptor.id: validGroup.id])
    }
}
