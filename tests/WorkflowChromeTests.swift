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

    func testPaneActionsUseSharedCommandSymbolsWithCorrectSplitIcons() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let handler = WorkspaceCommandHandler(workspace: workspace)

        let state = ActiveWorkContextState.resolve(workspace: workspace, commandHandler: handler)

        XCTAssertEqual(
            state.paneActions.map(\.command),
            [.splitVertical, .splitHorizontal, .nextPane, .closePane]
        )
        XCTAssertEqual(state.paneActions[0].symbolName, "rectangle.split.2x1")
        XCTAssertEqual(state.paneActions[1].symbolName, "rectangle.split.1x2")
        XCTAssertEqual(WorkspaceCommand.splitVertical.symbolName, "rectangle.split.2x1")
        XCTAssertEqual(WorkspaceCommand.splitHorizontal.symbolName, "rectangle.split.1x2")
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

    func testSessionRailChromeStateUsesExpectedOrderAndTooltips() {
        let workspace = makeTestWorkspace(autoStartSessions: false)

        let chrome = SessionRailChromeState.resolve(workspace: workspace)

        XCTAssertEqual(chrome.topActions.map(\.command), [.commandPalette, .nextAttention, .newTab])
        XCTAssertEqual(
            chrome.topActions.map(\.tooltip),
            [
                WorkspaceCommand.commandPalette.title,
                WorkspaceCommand.nextAttention.title,
                WorkspaceCommand.newTab.title,
            ]
        )
        XCTAssertTrue(chrome.topActions[0].isEnabled)
        XCTAssertFalse(chrome.topActions[1].isEnabled)
        XCTAssertTrue(chrome.topActions[2].isEnabled)
    }

    func testDisabledTopActionStillResolvesTooltipTitle() {
        let workspace = makeTestWorkspace(autoStartSessions: false)

        let chrome = SessionRailChromeState.resolve(workspace: workspace)
        let action = try! XCTUnwrap(chrome.topActions.first(where: { !$0.isEnabled }))

        XCTAssertEqual(action.command, .nextAttention)
        XCTAssertEqual(action.tooltip, WorkspaceCommand.nextAttention.title)
        XCTAssertFalse(action.tooltip.isEmpty)
    }
}
