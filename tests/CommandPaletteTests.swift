import XCTest
@testable import Mvx

@MainActor
final class CommandPaletteTests: XCTestCase {
    func testPaletteFuzzyMatchesAndExecutesRegisteredActions() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let handler = WorkspaceCommandHandler(workspace: workspace)

        let matches = handler.searchCommands(matching: "attention")
        let attention = matches.first { $0.command == .nextAttention }

        XCTAssertEqual(attention?.title, "Next Session Needing Attention")
        XCTAssertEqual(attention?.isEnabled, false)

        _ = handler.perform(.commandPalette)
        XCTAssertTrue(handler.isCommandPalettePresented)

        _ = handler.perform(.newTab)
        handler.dismissCommandPalette()

        XCTAssertEqual(workspace.sessions.count, 2)
        XCTAssertFalse(handler.isCommandPalettePresented)
    }

    func testPaletteSearchReturnsEnabledActionsWhenWorkspaceStateChanges() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let handler = WorkspaceCommandHandler(workspace: workspace)
        let activeID = try! XCTUnwrap(workspace.activeSessionID)

        XCTAssertTrue(workspace.updateAgentStatus(id: activeID, status: .waiting))

        let matches = handler.searchCommands(matching: "waiting")
        let attention = matches.first { $0.command == .nextAttention }

        XCTAssertEqual(attention?.isEnabled, true)
    }
}
