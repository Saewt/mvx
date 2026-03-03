import XCTest
@testable import Mvx

@MainActor
final class SessionSidebarBehaviorTests: XCTestCase {
    func testAutoNamePreservesUserOverride() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let firstID = try! XCTUnwrap(workspace.activeSessionID)

        XCTAssertTrue(workspace.updateSessionContext(
            id: firstID,
            workingDirectoryPath: "/Users/emirekici/Desktop/mvx",
            foregroundProcessName: "zsh"
        ))
        XCTAssertEqual(workspace.activeDescriptor?.displayTitle, "mvx")

        XCTAssertTrue(workspace.renameSession(id: firstID, title: "Pinned"))
        XCTAssertTrue(workspace.updateSessionContext(
            id: firstID,
            workingDirectoryPath: "/tmp",
            foregroundProcessName: "vim"
        ))

        XCTAssertEqual(workspace.activeDescriptor?.displayTitle, "Pinned")

        XCTAssertTrue(workspace.renameSession(id: firstID, title: "   "))
        XCTAssertEqual(workspace.activeDescriptor?.displayTitle, "tmp")
    }

    func testRenameCommitsAndCancelsCleanly() {
        var controller = SessionTabRenameController()

        controller.beginRename(currentTitle: "Session 1")
        controller.updateDraft("Renamed")

        let committed = controller.commit()

        XCTAssertEqual(committed, "Renamed")
        XCTAssertFalse(controller.isRenaming)
        XCTAssertEqual(controller.draftTitle, "")

        controller.beginRename(currentTitle: "Renamed")
        controller.updateDraft("Ignored")
        controller.cancel()

        XCTAssertFalse(controller.isRenaming)
        XCTAssertEqual(controller.draftTitle, "")
    }

    func testReorderPreservesActiveSession() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let first = try! XCTUnwrap(workspace.activeSessionID)
        let second = workspace.createSession()
        let third = workspace.createSession()

        XCTAssertTrue(workspace.selectSession(id: second.id))
        XCTAssertTrue(workspace.moveSession(id: third.id, toIndex: 0))

        XCTAssertEqual(workspace.sessionIDs(), [third.id, first, second.id])
        XCTAssertEqual(workspace.activeSessionID, second.id)

        XCTAssertTrue(workspace.moveSession(id: second.id, before: third.id))
        XCTAssertEqual(workspace.sessionIDs(), [second.id, third.id, first])
        XCTAssertEqual(workspace.activeSessionID, second.id)
    }

    func testBadgeRenderingKeepsSelectionAndAgentStateSeparate() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let activeID = try! XCTUnwrap(workspace.activeSessionID)

        XCTAssertTrue(workspace.updateAgentStatus(id: activeID, status: .waiting))
        let descriptor = try! XCTUnwrap(workspace.activeDescriptor)

        let selectedState = SessionTabRowVisualState.resolve(
            descriptor: descriptor,
            activeSessionID: activeID
        )
        let inactiveState = SessionTabRowVisualState.resolve(
            descriptor: descriptor,
            activeSessionID: UUID()
        )

        XCTAssertTrue(selectedState.isSelected)
        XCTAssertEqual(selectedState.selectionIndicatorStyleName, "bar")
        XCTAssertEqual(selectedState.selectionIndicatorColorName, "accent")
        XCTAssertTrue(selectedState.showsAgentBadge)
        XCTAssertEqual(selectedState.agentBadgeShapeName, "dot")
        XCTAssertEqual(selectedState.agentBadgeColorName, "orange")
        XCTAssertEqual(selectedState.agentBadgeLabel, "Waiting for Input")
        XCTAssertFalse(inactiveState.isSelected)
        XCTAssertEqual(inactiveState.selectionIndicatorStyleName, "dot")
        XCTAssertTrue(inactiveState.showsAgentBadge)
    }

    func testSessionTabRowCanBeSelectedAndFocusedIndependently() {
        let descriptor = SessionDescriptor(ordinal: 1, agentStatus: .none)
        let visualState = SessionTabRowVisualState.resolve(
            descriptor: descriptor,
            activeSessionID: UUID(),
            isFocusedInTiling: true
        )

        XCTAssertFalse(visualState.isSelected)
        XCTAssertTrue(visualState.isFocusedInTiling)
        XCTAssertTrue(visualState.focusBorderOpacity > 0)
        XCTAssertTrue(visualState.focusGlowOpacity > 0)
    }

    func testSessionTabRowShowsGitBadgeForKnownSummary() {
        let descriptor = SessionDescriptor(ordinal: 1, agentStatus: .none)
        let visualState = SessionTabRowVisualState.resolve(
            descriptor: descriptor,
            activeSessionID: descriptor.id,
            gitChangeSummary: WorkspaceGitChangeSummary(addedCount: 4, removedCount: 2)
        )

        XCTAssertTrue(visualState.showsGitBadge)
        XCTAssertEqual(visualState.gitAddedCount, 4)
        XCTAssertEqual(visualState.gitRemovedCount, 2)
    }

    func testSplitMenuStateDisablesWithoutFocusedPane() {
        let workspace = makeTestWorkspace(autoStartSessions: false, startsWithSession: false)

        let state = SessionTabSplitMenuState.resolve(workspace: workspace)

        XCTAssertFalse(state.isEnabled)
        XCTAssertNil(state.sourceSessionID)
        XCTAssertTrue(state.candidates.isEmpty)
    }

    func testSplitMenuStateExcludesFocusedSessionFromCandidates() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let firstID = try! XCTUnwrap(workspace.activeSessionID)

        XCTAssertTrue(workspace.splitActivePane(.vertical))

        let focusedID = try! XCTUnwrap(workspace.activeSessionID)
        let state = SessionTabSplitMenuState.resolve(workspace: workspace)

        XCTAssertTrue(state.isEnabled)
        XCTAssertEqual(state.sourceSessionID, focusedID)
        XCTAssertFalse(state.candidates.contains(where: { $0.id == focusedID }))
        XCTAssertTrue(state.candidates.contains(where: { $0.id == firstID }))
    }

    func testSplitMenuStatePreservesSidebarOrderForAttachedTargets() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let firstID = try! XCTUnwrap(workspace.activeSessionID)

        XCTAssertTrue(workspace.splitActivePane(.vertical))
        let secondID = try! XCTUnwrap(workspace.activeSessionID)

        XCTAssertTrue(workspace.splitActivePane(.vertical))
        let focusedID = try! XCTUnwrap(workspace.activeSessionID)

        _ = workspace.createSession(selectNewSession: false)
        XCTAssertTrue(workspace.moveSession(id: secondID, toIndex: 0))

        let state = SessionTabSplitMenuState.resolve(workspace: workspace)

        XCTAssertEqual(state.sourceSessionID, focusedID)
        XCTAssertEqual(state.candidates.map(\.id), [secondID, firstID])
    }

    func testSplitMenuStateIncludesOnlyAttachedSessions() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let attachedID = try! XCTUnwrap(workspace.activeSessionID)

        XCTAssertTrue(workspace.splitActivePane(.vertical))

        let focusedID = try! XCTUnwrap(workspace.activeSessionID)
        let detached = workspace.createSession(selectNewSession: false)

        let state = SessionTabSplitMenuState.resolve(workspace: workspace)

        XCTAssertEqual(state.sourceSessionID, focusedID)
        XCTAssertTrue(state.candidates.contains(where: { $0.id == attachedID }))
        XCTAssertFalse(state.candidates.contains(where: { $0.id == focusedID }))
        XCTAssertFalse(state.candidates.contains(where: { $0.id == detached.id }))
    }

    func testDuplicateSplitMenuTitlesAppendOrdinalSuffix() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let firstID = try! XCTUnwrap(workspace.activeSessionID)

        XCTAssertTrue(workspace.splitActivePane(.vertical))
        let secondID = try! XCTUnwrap(workspace.activeSessionID)

        XCTAssertTrue(workspace.splitActivePane(.vertical))

        let focusedID = try! XCTUnwrap(workspace.activeSessionID)

        XCTAssertTrue(workspace.renameSession(id: firstID, title: "Pinned"))
        XCTAssertTrue(workspace.renameSession(id: secondID, title: "Pinned"))

        let state = SessionTabSplitMenuState.resolve(workspace: workspace)

        XCTAssertEqual(state.sourceSessionID, focusedID)
        XCTAssertEqual(
            state.candidates.first(where: { $0.id == firstID })?.title,
            "Pinned (#\(workspace.descriptor(for: firstID)?.ordinal ?? 0))"
        )
        XCTAssertEqual(
            state.candidates.first(where: { $0.id == secondID })?.title,
            "Pinned (#\(workspace.descriptor(for: secondID)?.ordinal ?? 0))"
        )
    }

    func testRenameControllerDefaultsToSelectAll() {
        var controller = SessionTabRenameController()

        controller.beginRename(currentTitle: "Session 1")

        XCTAssertEqual(controller.selectionBehavior, .selectAll)
        XCTAssertTrue(controller.activationID > 0)
    }

    func testRenameControllerCanRequestCaretAtEnd() {
        var controller = SessionTabRenameController()

        controller.beginRename(
            currentTitle: "Session 1",
            selectionBehavior: .placeCaretAtEnd
        )

        XCTAssertEqual(controller.selectionBehavior, .placeCaretAtEnd)

        _ = controller.commit()
        XCTAssertEqual(controller.selectionBehavior, .selectAll)
    }

    func testNoBadgeForUnsetStatus() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let descriptor = try! XCTUnwrap(workspace.activeDescriptor)

        let visualState = SessionTabRowVisualState.resolve(
            descriptor: descriptor,
            activeSessionID: workspace.activeSessionID
        )

        XCTAssertFalse(visualState.showsAgentBadge)
        XCTAssertNil(visualState.agentBadgeShapeName)
        XCTAssertNil(visualState.agentBadgeColorName)
        XCTAssertNil(visualState.agentBadgeLabel)
    }

    func testSelectedDoneStateUsesDistinctBadgeColorAndIndicatorShape() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let activeID = try! XCTUnwrap(workspace.activeSessionID)

        XCTAssertTrue(workspace.updateAgentStatus(id: activeID, status: .done))
        let descriptor = try! XCTUnwrap(workspace.activeDescriptor)
        let visualState = SessionTabRowVisualState.resolve(
            descriptor: descriptor,
            activeSessionID: activeID
        )

        XCTAssertTrue(visualState.isSelected)
        XCTAssertEqual(visualState.selectionIndicatorStyleName, "bar")
        XCTAssertEqual(visualState.agentBadgeShapeName, "dot")
        XCTAssertEqual(visualState.agentBadgeColorName, "teal")
        XCTAssertNotEqual(visualState.selectionIndicatorStyleName, visualState.agentBadgeShapeName)
    }

    func testSelectedErrorStateKeepsBadgeSeparateFromSelectionIndicator() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let activeID = try! XCTUnwrap(workspace.activeSessionID)

        XCTAssertTrue(workspace.updateAgentStatus(id: activeID, status: .error))
        let descriptor = try! XCTUnwrap(workspace.activeDescriptor)
        let visualState = SessionTabRowVisualState.resolve(
            descriptor: descriptor,
            activeSessionID: activeID
        )

        XCTAssertTrue(visualState.isSelected)
        XCTAssertEqual(visualState.selectionIndicatorStyleName, "bar")
        XCTAssertEqual(visualState.agentBadgeShapeName, "dot")
        XCTAssertEqual(visualState.agentBadgeColorName, "red")
    }

    func testWorkspaceCardMetadataUsesFocusedPaneContext() {
        let registry = WorkspaceRegistry(workspaceFactory: { _ in
            makeTestWorkspace(autoStartSessions: false)
        })
        let entry = registry.createWorkspace(name: "Alpha")
        let workspace = try! XCTUnwrap(registry.workspace(for: entry.id))
        let activeID = try! XCTUnwrap(workspace.activeSessionID)
        let featurePath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("feature", isDirectory: true)
            .appendingPathComponent("sidebar-card", isDirectory: true)

        XCTAssertTrue(workspace.updateSessionContext(
            id: activeID,
            workingDirectoryPath: featurePath.path,
            foregroundProcessName: "zsh"
        ))
        XCTAssertTrue(workspace.updateAgentStatus(id: activeID, status: .waiting))

        let metadata = try! XCTUnwrap(registry.cardMetadata(for: entry.id))

        XCTAssertEqual(metadata.name, "Alpha")
        XCTAssertEqual(metadata.branchName, "feature/sidebar-card")
        XCTAssertEqual(metadata.paneCount, 1)
        XCTAssertEqual(metadata.notificationCount, 1)
        XCTAssertEqual(metadata.waitingCount, 1)
        XCTAssertEqual(metadata.errorCount, 0)
        XCTAssertNil(metadata.gitAddedCount)
        XCTAssertNil(metadata.gitRemovedCount)
        XCTAssertFalse(metadata.hasGitStatus)
    }

    func testWorkspaceCardVisualStateHighlightsOnlyActiveWorkspace() {
        let metadata = WorkspaceCardMetadata(
            workspaceID: UUID(),
            name: "Alpha",
            branchName: "feature/sidebar-card",
            paneCount: 2,
            notificationCount: 1,
            waitingCount: 1,
            errorCount: 0,
            gitAddedCount: nil,
            gitRemovedCount: nil
        )

        let activeState = WorkspaceCardVisualState.resolve(isActive: true, metadata: metadata)
        let inactiveState = WorkspaceCardVisualState.resolve(isActive: false, metadata: metadata)

        XCTAssertTrue(activeState.isActive)
        XCTAssertTrue(activeState.glowOpacity > inactiveState.glowOpacity)
        XCTAssertTrue(activeState.borderOpacity > inactiveState.borderOpacity)
        XCTAssertFalse(activeState.showsGitStatus)
        XCTAssertTrue(activeState.showsAttention)
        XCTAssertEqual(activeState.glowColorName, "orange")
        XCTAssertFalse(inactiveState.isActive)
    }

    func testWorkspaceCardVisualStateUsesRedGlowWhenErrorsPresent() {
        let metadata = WorkspaceCardMetadata(
            workspaceID: UUID(),
            name: "Alpha",
            branchName: "feature/sidebar-card",
            paneCount: 2,
            notificationCount: 2,
            waitingCount: 1,
            errorCount: 1,
            gitAddedCount: nil,
            gitRemovedCount: nil
        )

        let visualState = WorkspaceCardVisualState.resolve(isActive: true, metadata: metadata)

        XCTAssertTrue(visualState.showsAttention)
        XCTAssertEqual(visualState.glowColorName, "red")
    }
}
