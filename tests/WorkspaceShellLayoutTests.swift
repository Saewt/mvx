import XCTest
@testable import Mvx

@MainActor
final class WorkspaceShellLayoutTests: XCTestCase {
    func testShellScaffoldDefinesTwoPrimaryRegions() {
        let layout = WorkspaceShellLayoutSpec.wantedUI

        XCTAssertEqual(layout.primaryRegionCount, 2)
        XCTAssertGreaterThan(layout.leftRailWidth, 180)
        XCTAssertGreaterThan(layout.collapsedRailWidth, 0)
        XCTAssertLessThan(layout.collapsedRailWidth, layout.leftRailWidth)
        XCTAssertGreaterThan(layout.centerMinimumWidth, layout.leftRailWidth)
    }

    func testSidebarVisibilityStateUsesFullRailWhenExpanded() {
        let layout = WorkspaceShellLayoutSpec.wantedUI

        let state = WorkspaceSidebarVisibilityState(layout: layout, isCollapsed: false)

        XCTAssertEqual(state.visibleLeftWidth, layout.leftRailWidth)
        XCTAssertTrue(state.showsExpandedSidebar)
        XCTAssertTrue(state.showsStandaloneDivider)
    }

    func testSidebarVisibilityStateUsesRevealStripWhenCollapsed() {
        let layout = WorkspaceShellLayoutSpec.wantedUI

        let state = WorkspaceSidebarVisibilityState(layout: layout, isCollapsed: true)

        XCTAssertEqual(state.visibleLeftWidth, layout.collapsedRailWidth)
        XCTAssertFalse(state.showsExpandedSidebar)
        XCTAssertFalse(state.showsStandaloneDivider)
    }

    func testCompactRailKeepsSessionScanability() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let second = workspace.createSession()
        let third = workspace.createSession()

        XCTAssertTrue(workspace.updateAgentStatus(id: second.id, status: .waiting))
        XCTAssertTrue(workspace.updateAgentStatus(id: third.id, status: .error))

        let chrome = SessionRailChromeState.resolve(workspace: workspace)

        XCTAssertEqual(chrome.topActionSymbols, ["square.grid.2x2", "bell", "plus"])
        XCTAssertEqual(chrome.sessionCount, 3)
        XCTAssertEqual(chrome.attentionCount, 2)
        XCTAssertEqual(chrome.activeSessionTitle, third.displayTitle)
    }
}
