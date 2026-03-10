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
        XCTAssertFalse(payload.contains("sessionStartedAt"))
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

    func testRestorePassesSavedWorkingDirectoryToFactory() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let sessionID = try XCTUnwrap(workspace.activeSessionID)
        XCTAssertTrue(workspace.updateSessionContext(
            id: sessionID,
            workingDirectoryPath: "/tmp/demo-project",
            foregroundProcessName: "zsh"
        ))

        let snapshot = workspace.snapshot()
        var capturedStartupDirectory: URL?
        let restored = makeTestWorkspace(
            autoStartSessions: false,
            startsWithSession: false,
            sessionFactoryWithStartupDirectory: { startupDirectory in
                capturedStartupDirectory = startupDirectory
                return makeTestSession()
            }
        )

        XCTAssertTrue(restored.restore(from: snapshot))
        XCTAssertEqual(capturedStartupDirectory?.path, "/tmp/demo-project")
    }

    func testRestoreNormalizesBlankWorkingDirectoryBeforeCallingFactory() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let sessionID = try XCTUnwrap(workspace.activeSessionID)
        XCTAssertTrue(workspace.updateSessionContext(
            id: sessionID,
            workingDirectoryPath: "   \n",
            foregroundProcessName: "zsh"
        ))

        let snapshot = workspace.snapshot()
        var didCallFactory = false
        var capturedStartupDirectory: URL? = URL(fileURLWithPath: "/tmp/placeholder")
        let restored = makeTestWorkspace(
            autoStartSessions: false,
            startsWithSession: false,
            sessionFactoryWithStartupDirectory: { startupDirectory in
                didCallFactory = true
                capturedStartupDirectory = startupDirectory
                return makeTestSession()
            }
        )

        XCTAssertTrue(restored.restore(from: snapshot))
        XCTAssertTrue(didCallFactory)
        XCTAssertNil(capturedStartupDirectory)
    }

    func testWorkspaceSnapshotRoundTripsGroupedAndUngroupedNotes() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let group = workspace.createGroup(name: "Frontend", colorTag: nil)
        XCTAssertTrue(workspace.updateWorkspaceNote(body: "Review output\nShip follow-up"))
        XCTAssertTrue(workspace.updateNote(body: "Frontend todo", forGroup: group.id))

        let snapshot = workspace.snapshot()
        let encoded = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WorkspaceSnapshot.self, from: encoded)
        let restored = makeTestWorkspace(autoStartSessions: false, startsWithSession: false)

        XCTAssertEqual(snapshot.workspaceNote?.body, "Review output\nShip follow-up")
        XCTAssertEqual(snapshot.sessionGroups.first?.note?.body, "Frontend todo")
        XCTAssertEqual(decoded.workspaceNote, snapshot.workspaceNote)
        XCTAssertEqual(decoded.sessionGroups.first?.note, snapshot.sessionGroups.first?.note)
        XCTAssertTrue(restored.restore(from: snapshot))
        XCTAssertEqual(restored.workspaceNote, snapshot.workspaceNote)
        XCTAssertEqual(restored.sessionGroups.first?.note, snapshot.sessionGroups.first?.note)
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
        XCTAssertNil(loaded.workspaceNote)
    }

    func testRegistryPersistenceRestoresWorkspaceOrderAndSelection() throws {
        let persistence = WorkspacePersistence(fileURL: temporaryWorkspaceURL())
        let registry = WorkspaceRegistry(workspaceFactory: { _ in
            makeTestWorkspace(autoStartSessions: false)
        })

        let first = registry.createWorkspace(name: "Alpha")
        let second = registry.createWorkspace(name: "Beta")
        XCTAssertTrue(registry.workspace(for: first.id)?.updateWorkspaceNote(body: "Alpha follow-up") ?? false)
        XCTAssertTrue(registry.activateWorkspace(id: second.id))

        try persistence.saveRegistry(registry.registrySnapshot())

        let restoredRegistry = WorkspaceRegistry(workspaceFactory: { _ in
            makeTestWorkspace(autoStartSessions: false)
        })
        XCTAssertTrue(restoredRegistry.restore(from: try XCTUnwrap(persistence.loadRegistry())))

        XCTAssertEqual(restoredRegistry.entries.map(\.name), ["Alpha", "Beta"])
        XCTAssertEqual(restoredRegistry.activeWorkspaceID, second.id)
        XCTAssertEqual(restoredRegistry.workspace(for: first.id)?.sessions.count, 1)
        XCTAssertEqual(restoredRegistry.workspace(for: first.id)?.workspaceNote?.body, "Alpha follow-up")
    }

    private func temporaryWorkspaceURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("mvx-workspace-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("workspace.json")
    }
}
