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
}
