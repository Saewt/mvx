import XCTest
@testable import Mvx

@MainActor
final class WorkflowChromeTests: XCTestCase {
    func testActiveWorkPaneShowsSelectedSessionContext() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let handler = WorkspaceCommandHandler(workspace: workspace)
        let activeID = try! XCTUnwrap(workspace.activeSessionID)

        XCTAssertTrue(workspace.updateSessionContext(
            id: activeID,
            workingDirectoryPath: "/Users/emirekici/Desktop/mvx",
            foregroundProcessName: "claude"
        ))
        XCTAssertTrue(workspace.updateAgentStatus(id: activeID, status: .waiting))

        let state = ActiveWorkContextState.resolve(workspace: workspace, commandHandler: handler)

        XCTAssertEqual(state.title, "mvx")
        XCTAssertEqual(state.statusLabel, "Waiting for Input")
        XCTAssertEqual(state.statusAccentName, "orange")
        XCTAssertTrue(state.contextLine.contains("mvx"))
        XCTAssertTrue(state.contextLine.contains("claude"))
        XCTAssertTrue(state.promptHint.contains("waiting"))
        XCTAssertTrue(state.contextDetails.contains("Directory: /Users/emirekici/Desktop/mvx"))
        XCTAssertTrue(state.contextDetails.contains("Process: claude"))
        XCTAssertFalse(state.paneActions.isEmpty)
        XCTAssertTrue(state.workspaceSummary.contains("pane"))
    }

    func testVisibleQuickActionsRouteThroughSharedCommandHandler() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let handler = WorkspaceCommandHandler(workspace: workspace)

        let commands = handler.chromeCommands()

        XCTAssertEqual(commands.map(\.command), [.commandPalette, .newTab, .nextAttention, .closeCurrentSession])
        XCTAssertEqual(commands.first?.isEnabled, true)

        _ = handler.perform(.newTab)
        XCTAssertEqual(workspace.sessions.count, 2)

        _ = handler.perform(.commandPalette)
        XCTAssertTrue(handler.isCommandPalettePresented)
    }
}
