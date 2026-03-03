import XCTest
@testable import Mvx

@MainActor
final class SessionWorkspacePersistenceTests: XCTestCase {
    func testWorkspaceSnapshotOmitsTranscriptButKeepsDescriptorsAndGraph() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let firstID = try XCTUnwrap(workspace.activeSessionID)
        _ = workspace.createSession()

        _ = workspace.renameSession(id: firstID, title: "Pinned")
        let snapshot = workspace.snapshot()

        XCTAssertEqual(snapshot.schemaVersion, WorkspaceSnapshot.currentSchemaVersion)
        XCTAssertEqual(snapshot.sessions.count, 2)
        XCTAssertEqual(snapshot.sessions.first?.descriptor.displayTitle, "Pinned")
        XCTAssertNotNil(snapshot.workspaceGraph)

        let encoded = try JSONEncoder().encode(snapshot)
        let payload = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertFalse(payload.contains("\"transcript\""))
    }

    func testRestoreRebuildsSessionsFromSnapshotWithoutTranscriptState() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let firstID = try XCTUnwrap(workspace.activeSessionID)
        let second = workspace.createSession(selectNewSession: false)
        XCTAssertTrue(workspace.selectSession(id: firstID))

        let snapshot = workspace.snapshot()
        let firstRuntime = try XCTUnwrap(workspace.session(for: firstID))

        XCTAssertTrue(workspace.restore(from: snapshot))

        XCTAssertFalse(firstRuntime === workspace.session(for: firstID))
        XCTAssertEqual(workspace.sessionIDs(), [firstID, second.id])
        XCTAssertEqual(workspace.activeSessionID, firstID)
        XCTAssertNotNil(workspace.workspaceGraph.rootPane)
    }

    func testWorkspacePersistenceLoadsLegacySnapshotWithoutTranscriptFieldAccess() throws {
        let persistence = WorkspacePersistence(fileURL: temporaryWorkspaceURL())

        let legacyJSON = """
        {
          "schemaVersion": 3,
          "sessions": [
            {
              "descriptor": {
                "id": "\(UUID().uuidString)",
                "ordinal": 1,
                "customTitle": null,
                "workingDirectoryPath": "/tmp/demo",
                "foregroundProcessName": null,
                "agentStatus": "none"
              },
              "transcript": "legacy text"
            }
          ],
          "activeSessionID": null,
          "nextOrdinal": 2,
          "workspaceGraph": null
        }
        """

        let legacyData = try XCTUnwrap(legacyJSON.data(using: .utf8))
        try FileManager.default.createDirectory(
            at: persistence.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try legacyData.write(to: persistence.fileURL, options: .atomic)

        let loaded = try XCTUnwrap(persistence.load())
        XCTAssertEqual(loaded.schemaVersion, 3)
        XCTAssertEqual(loaded.sessions.count, 1)
        XCTAssertEqual(loaded.sessions.first?.descriptor.workingDirectoryPath, "/tmp/demo")
    }

    func testRegistryPersistenceRestoresWorkspaceOrderAndSelection() throws {
        let persistence = WorkspacePersistence(fileURL: temporaryWorkspaceURL())
        let registry = WorkspaceRegistry(workspaceFactory: { _ in
            makeTestWorkspace(autoStartSessions: false)
        })

        let first = registry.createWorkspace(name: "Alpha")
        let second = registry.createWorkspace(name: "Beta")
        XCTAssertTrue(registry.activateWorkspace(id: second.id))

        try persistence.saveRegistry(registry.registrySnapshot())

        let restoredRegistry = WorkspaceRegistry(workspaceFactory: { _ in
            makeTestWorkspace(autoStartSessions: false)
        })
        XCTAssertTrue(restoredRegistry.restore(from: try XCTUnwrap(persistence.loadRegistry())))

        XCTAssertEqual(restoredRegistry.entries.map(\.name), ["Alpha", "Beta"])
        XCTAssertEqual(restoredRegistry.activeWorkspaceID, second.id)
        XCTAssertEqual(restoredRegistry.workspace(for: first.id)?.sessions.count, 1)
    }

    private func temporaryWorkspaceURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("mvx-workspace-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("workspace.json")
    }
}
