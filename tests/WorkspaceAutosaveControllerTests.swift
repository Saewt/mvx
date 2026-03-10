import XCTest
@testable import Mvx

@MainActor
final class WorkspaceAutosaveControllerTests: XCTestCase {
    func testAutosaveDebouncesRapidWorkspaceNoteChanges() async throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        var snapshots: [WorkspaceSnapshot] = []
        let controller = WorkspaceAutosaveController(
            workspace: workspace,
            debounceInterval: .milliseconds(25),
            persistSnapshot: { snapshot in
                snapshots.append(snapshot)
            }
        )

        XCTAssertTrue(workspace.updateWorkspaceNote(body: "First"))
        XCTAssertTrue(workspace.updateWorkspaceNote(body: "Second"))
        XCTAssertTrue(workspace.updateWorkspaceNote(body: "Third"))

        try await waitUntil { snapshots.count == 1 }
        withExtendedLifetime(controller) {
            XCTAssertEqual(snapshots.count, 1)
            XCTAssertEqual(snapshots.first?.workspaceNote?.body, "Third")
        }
    }

    func testPersistNowFlushesLatestWorkspaceNoteImmediately() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        var snapshots: [WorkspaceSnapshot] = []
        let controller = WorkspaceAutosaveController(
            workspace: workspace,
            debounceInterval: .seconds(60),
            persistSnapshot: { snapshot in
                snapshots.append(snapshot)
            }
        )

        XCTAssertTrue(workspace.updateWorkspaceNote(body: "Ship it tomorrow"))
        XCTAssertTrue(snapshots.isEmpty)

        try controller.persistNow()

        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.workspaceNote?.body, "Ship it tomorrow")
    }

    func testAutosaveDebouncesRapidGroupNoteChanges() async throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let group = workspace.createGroup(name: "Frontend", colorTag: nil)
        var snapshots: [WorkspaceSnapshot] = []
        let controller = WorkspaceAutosaveController(
            workspace: workspace,
            debounceInterval: .milliseconds(25),
            persistSnapshot: { snapshot in
                snapshots.append(snapshot)
            }
        )

        XCTAssertTrue(workspace.updateNote(body: "First", forGroup: group.id))
        XCTAssertTrue(workspace.updateNote(body: "Second", forGroup: group.id))
        XCTAssertTrue(workspace.updateNote(body: "Third", forGroup: group.id))

        try await waitUntil { snapshots.count == 1 }
        withExtendedLifetime(controller) {
            XCTAssertEqual(snapshots.count, 1)
            XCTAssertEqual(snapshots.first?.sessionGroups.first?.note?.body, "Third")
        }
    }

    func testRenamingGroupWithoutNoteChangeDoesNotTriggerAutosave() async throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let group = workspace.createGroup(name: "Frontend", colorTag: nil)
        var snapshots: [WorkspaceSnapshot] = []
        let controller = WorkspaceAutosaveController(
            workspace: workspace,
            debounceInterval: .milliseconds(25),
            persistSnapshot: { snapshot in
                snapshots.append(snapshot)
            }
        )

        XCTAssertTrue(workspace.renameGroup(id: group.id, name: "API"))

        try await Task.sleep(nanoseconds: 80_000_000)
        withExtendedLifetime(controller) {
            XCTAssertTrue(snapshots.isEmpty)
        }
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        pollIntervalNanoseconds: UInt64 = 10_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

        while !condition() {
            if DispatchTime.now().uptimeNanoseconds >= deadline {
                XCTFail("Timed out waiting for condition")
                return
            }

            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }
    }
}
