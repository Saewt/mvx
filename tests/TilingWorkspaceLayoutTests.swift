import XCTest
@testable import Mvx

@MainActor
final class TilingWorkspaceLayoutTests: XCTestCase {
    func testTilingWorkspaceRendersBothSplitAxes() {
        let workspace = makeTestWorkspace(autoStartSessions: false)

        XCTAssertTrue(workspace.splitActivePane(.vertical))
        XCTAssertTrue(workspace.splitActivePane(.horizontal))

        let state = TilingWorkspaceLayoutState.resolve(workspace: workspace)

        XCTAssertEqual(state.paneCount, 3)
        XCTAssertTrue(state.visibleAxes.contains(.vertical))
        XCTAssertTrue(state.visibleAxes.contains(.horizontal))
        XCTAssertEqual(state.paneTitles.count, 3)
    }

    func testFocusedPaneRoutesSplitAndCloseCommands() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let handler = WorkspaceCommandHandler(workspace: workspace)
        let originalFocusedPaneID = workspace.focusedPaneID

        _ = handler.perform(.splitVertical)
        let splitFocusedPaneID = workspace.focusedPaneID

        XCTAssertEqual(workspace.workspaceGraph.paneCount, 2)
        XCTAssertNotEqual(originalFocusedPaneID, splitFocusedPaneID)

        _ = handler.perform(.closePane)

        XCTAssertEqual(workspace.workspaceGraph.paneCount, 1)
        XCTAssertEqual(workspace.sessions.count, 1)
        XCTAssertNotNil(workspace.focusedPaneID)
    }

    func testTitleChangeDoesNotAlterGeometryState() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let before = TilingWorkspaceGeometryState.resolve(workspace: workspace)

        _ = workspace.renameSession(id: workspace.activeSessionID!, title: "Renamed")

        let after = TilingWorkspaceGeometryState.resolve(workspace: workspace)
        XCTAssertEqual(before, after)
    }

    func testSplitChangeDoesAlterGeometryState() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let before = TilingWorkspaceGeometryState.resolve(workspace: workspace)

        XCTAssertTrue(workspace.splitActivePane(.vertical))

        let after = TilingWorkspaceGeometryState.resolve(workspace: workspace)
        XCTAssertNotEqual(before, after)
        XCTAssertEqual(after.paneCount, 2)
    }

    func testFocusChangeDoesAlterGeometryState() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let firstID = try! XCTUnwrap(workspace.activeSessionID)
        let second = workspace.createSession()
        XCTAssertTrue(workspace.splitActivePane(.vertical))
        XCTAssertTrue(workspace.selectSession(id: firstID))

        let before = TilingWorkspaceGeometryState.resolve(workspace: workspace)
        XCTAssertTrue(workspace.selectSession(id: second.id))

        let after = TilingWorkspaceGeometryState.resolve(workspace: workspace)
        XCTAssertNotEqual(before, after)
    }
}
