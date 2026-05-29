import XCTest
@testable import Mvx

@MainActor
final class WorkspaceShellLayoutTests: XCTestCase {
    func testShellScaffoldDefinesTwoPrimaryRegions() {
        let layout = WorkspaceShellLayoutSpec.wantedUI

        XCTAssertEqual(layout.primaryRegionCount, 2)
        XCTAssertEqual(layout.leftRailWidth, CGFloat(AppPreferences.defaultSidebarWidth))
        XCTAssertGreaterThan(layout.leftRailWidth, 180)
        XCTAssertGreaterThan(layout.collapsedRailWidth, 0)
        XCTAssertLessThan(layout.collapsedRailWidth, layout.leftRailWidth)
        XCTAssertGreaterThan(layout.centerMinimumWidth, layout.leftRailWidth)
    }

    func testSidebarVisibilityStateUsesFullRailWhenExpanded() {
        let layout = WorkspaceShellLayoutSpec.wantedUI.withLeftRailWidth(318)

        let state = WorkspaceSidebarVisibilityState(layout: layout, isCollapsed: false)

        XCTAssertEqual(state.visibleLeftWidth, 318)
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

    func testLeftRailWidthClampsToResizableBounds() {
        XCTAssertEqual(
            WorkspaceShellLayoutSpec.clampedLeftRailWidth(120),
            CGFloat(AppPreferences.minimumSidebarWidth)
        )
        XCTAssertEqual(
            WorkspaceShellLayoutSpec.clampedLeftRailWidth(900),
            CGFloat(AppPreferences.maximumSidebarWidth)
        )
        XCTAssertEqual(WorkspaceShellLayoutSpec.clampedLeftRailWidth(312), 312)
    }

    func testLayoutClampsRuntimeLeftRailWidth() {
        let tooSmall = WorkspaceShellLayoutSpec.wantedUI.withLeftRailWidth(120)
        let tooLarge = WorkspaceShellLayoutSpec.wantedUI.withLeftRailWidth(900)

        XCTAssertEqual(tooSmall.leftRailWidth, CGFloat(AppPreferences.minimumSidebarWidth))
        XCTAssertEqual(tooLarge.leftRailWidth, CGFloat(AppPreferences.maximumSidebarWidth))
    }

    func testCompactRailKeepsSessionScanability() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let second = workspace.createSession()
        let third = workspace.createSession()

        XCTAssertTrue(workspace.updateAgentStatus(id: second.id, status: .waiting))
        XCTAssertTrue(workspace.updateAgentStatus(id: third.id, status: .error))

        let chrome = SessionRailChromeState.resolve(workspace: workspace)

        XCTAssertEqual(chrome.topActions.map(\.symbolName), ["plus"])
        XCTAssertEqual(chrome.sessionCount, 3)
        XCTAssertEqual(chrome.attentionCount, 2)
        XCTAssertTrue(chrome.attentionIsError)
        XCTAssertEqual(chrome.activeSessionTitle, third.displayTitle)
    }

    func testHiddenLayoutHasZeroLeftWidth() {
        let layout = WorkspaceShellLayoutSpec.wantedUI

        let state = WorkspaceSidebarVisibilityState(layout: layout, isCollapsed: false, isHidden: true)

        XCTAssertEqual(state.visibleLeftWidth, 0)
        XCTAssertFalse(state.showsExpandedSidebar)
        XCTAssertFalse(state.showsStandaloneDivider)
    }
}
