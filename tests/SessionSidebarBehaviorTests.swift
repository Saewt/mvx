import XCTest
@testable import Mvx

@MainActor
final class SessionSidebarBehaviorTests: XCTestCase {
    func testPathLikeTerminalTitleUsesLeafName() {
        XCTAssertEqual(
            SessionNaming.automaticTitle(
                terminalTitle: "~/desktop/codop",
                workingDirectoryPath: "/tmp/ignored",
                foregroundProcessName: "zsh",
                fallbackOrdinal: 83
            ),
            "codop"
        )
        XCTAssertEqual(
            SessionNaming.automaticTitle(
                terminalTitle: "/",
                workingDirectoryPath: "/tmp/ignored",
                foregroundProcessName: "zsh",
                fallbackOrdinal: 83
            ),
            "/"
        )
    }

    func testNonPathTerminalTitleStaysVerbatim() {
        XCTAssertEqual(
            SessionNaming.automaticTitle(
                terminalTitle: "Running tests",
                workingDirectoryPath: "/Users/test/codop",
                foregroundProcessName: "zsh",
                fallbackOrdinal: 1
            ),
            "Running tests"
        )
    }

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
        XCTAssertEqual(workspace.activeDescriptor?.displayTitle, "vim")
    }

    func testDisplayIdentityDisambiguatesDuplicateTitlesByProcessThenLocalRank() {
        let first = SessionDescriptor(
            ordinal: 1,
            workingDirectoryPath: "/Users/test/codop",
            foregroundProcessName: "claude"
        )
        let second = SessionDescriptor(
            ordinal: 2,
            workingDirectoryPath: "/Users/test/codop",
            foregroundProcessName: "node"
        )
        let third = SessionDescriptor(
            ordinal: 3,
            workingDirectoryPath: "/Users/test/codop",
            foregroundProcessName: "node"
        )

        let titles = SessionDisplayIdentityResolver.resolvedTitles(for: [first, second, third])

        XCTAssertEqual(titles[first.id], "claude")
        XCTAssertEqual(titles[second.id], "node")
        XCTAssertEqual(titles[third.id], "node 2")
    }

    func testDisplayIdentityDisambiguatesDuplicateTitlesByLocalRank() {
        let first = SessionDescriptor(
            ordinal: 83,
            workingDirectoryPath: "/Users/test/codop",
            foregroundProcessName: "zsh"
        )
        let second = SessionDescriptor(
            ordinal: 144,
            workingDirectoryPath: "/Users/test/codop",
            foregroundProcessName: "zsh"
        )
        let third = SessionDescriptor(
            ordinal: 165,
            workingDirectoryPath: "/Users/test/codop",
            foregroundProcessName: "zsh"
        )

        let titles = SessionDisplayIdentityResolver.resolvedTitles(for: [third, first, second])

        XCTAssertEqual(titles[first.id], "codop")
        XCTAssertEqual(titles[second.id], "codop 2")
        XCTAssertEqual(titles[third.id], "codop 3")
    }

    func testDisplayIdentityDoesNotMutateCustomTitleAndBuildsContextLine() {
        let descriptor = SessionDescriptor(
            ordinal: 1,
            customTitle: "Pinned",
            workingDirectoryPath: "/Users/test/codop",
            foregroundProcessName: "claude"
        )

        let identity = SessionDisplayIdentityResolver.resolve(
            descriptor: descriptor,
            visibleDescriptors: [descriptor],
            branchName: "main",
            gitChangeSummary: WorkspaceGitChangeSummary(addedCount: 3, removedCount: 1)
        )

        XCTAssertEqual(identity.title, "Pinned")
        XCTAssertEqual(descriptor.customTitle, "Pinned")
        XCTAssertEqual(identity.contextLine, "codop  ·  main  ·  +3 -1  ·  claude")
    }

    func testDisplayIdentityDropsRepoFromContextWhenItMatchesBaseTitle() {
        let first = SessionDescriptor(
            ordinal: 83,
            workingDirectoryPath: "/Users/test/codop",
            foregroundProcessName: "zsh"
        )
        let second = SessionDescriptor(
            ordinal: 144,
            workingDirectoryPath: "/Users/test/codop",
            foregroundProcessName: "zsh"
        )

        let identity = SessionDisplayIdentityResolver.resolve(
            descriptor: second,
            visibleDescriptors: [first, second],
            branchName: "main",
            gitChangeSummary: WorkspaceGitChangeSummary(addedCount: 30, removedCount: 2)
        )

        XCTAssertEqual(identity.title, "codop 2")
        XCTAssertEqual(identity.contextLine, "main  ·  +30 -2")
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

    func testDurationStateFormatsCompactElapsedTime() {
        let startedAt = Date(timeIntervalSinceReferenceDate: 100)

        XCTAssertEqual(
            SessionTabDurationState.resolve(
                startedAt: startedAt,
                isRenaming: false,
                referenceDate: startedAt.addingTimeInterval(30)
            ).label,
            "0m"
        )
        XCTAssertEqual(
            SessionTabDurationState.resolve(
                startedAt: startedAt,
                isRenaming: false,
                referenceDate: startedAt.addingTimeInterval(59 * 60)
            ).label,
            "59m"
        )
        XCTAssertEqual(
            SessionTabDurationState.resolve(
                startedAt: startedAt,
                isRenaming: false,
                referenceDate: startedAt.addingTimeInterval(60 * 60)
            ).label,
            "1h"
        )
        XCTAssertEqual(
            SessionTabDurationState.resolve(
                startedAt: startedAt,
                isRenaming: false,
                referenceDate: startedAt.addingTimeInterval(24 * 60 * 60)
            ).label,
            "1d"
        )
    }

    func testDurationStateHidesLabelWhenMissingOrRenaming() {
        let startedAt = Date(timeIntervalSinceReferenceDate: 200)

        XCTAssertNil(
            SessionTabDurationState.resolve(
                startedAt: nil,
                isRenaming: false,
                referenceDate: startedAt
            ).label
        )
        XCTAssertNil(
            SessionTabDurationState.resolve(
                startedAt: startedAt,
                isRenaming: true,
                referenceDate: startedAt.addingTimeInterval(120)
            ).label
        )
    }

    func testDurationStateUsesInjectedReferenceDate() {
        let startedAt = Date(timeIntervalSinceReferenceDate: 500)
        let referenceDate = startedAt.addingTimeInterval(125)

        let state = SessionTabDurationState.resolve(
            startedAt: startedAt,
            isRenaming: false,
            referenceDate: referenceDate
        )

        XCTAssertEqual(state.label, "2m")
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

    func testDuplicateSplitMenuTitlesUseLocalRankSuffix() {
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
            "Pinned"
        )
        XCTAssertEqual(
            state.candidates.first(where: { $0.id == secondID })?.title,
            "Pinned 2"
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
        _ = workspace.createSession(selectNewSession: false)
        _ = workspace.createGroup(name: "Frontend", colorTag: nil)

        let metadata = try! XCTUnwrap(registry.cardMetadata(for: entry.id))

        XCTAssertEqual(metadata.name, "Alpha")
        XCTAssertEqual(metadata.branchName, "feature/sidebar-card")
        XCTAssertEqual(metadata.sessionCount, 2)
        XCTAssertEqual(metadata.groupCount, 1)
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
        XCTAssertTrue(activeState.backgroundOpacity > inactiveState.backgroundOpacity)
        XCTAssertEqual(activeState.glowOpacity, 0)
        XCTAssertEqual(activeState.borderOpacity, 0)
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

    func testSidebarSectionStateHidesUngroupedWhenAllSessionsAreGrouped() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let sessionID = try! XCTUnwrap(workspace.activeSessionID)
        let group = workspace.createGroup(name: "Backend", colorTag: nil)

        XCTAssertTrue(workspace.assignSession(id: sessionID, toGroup: group.id))

        let state = SessionSidebarSectionState.resolve(workspace: workspace)

        XCTAssertFalse(state.showsUngroupedSection)
    }

    func testSidebarSectionStateShowsUngroupedWhenUngroupedSessionsRemain() {
        let workspace = makeTestWorkspace(autoStartSessions: false)

        _ = workspace.createGroup(name: "Backend", colorTag: nil)

        let state = SessionSidebarSectionState.resolve(workspace: workspace)

        XCTAssertTrue(state.showsUngroupedSection)
    }

    func testSidebarSectionStateDoesNotForceActiveGroupWhenUngroupedIsHidden() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let sessionID = try! XCTUnwrap(workspace.activeSessionID)
        let group = workspace.createGroup(name: "Backend", colorTag: nil)

        XCTAssertTrue(workspace.assignSession(id: sessionID, toGroup: group.id))
        XCTAssertNil(workspace.activeGroupID)

        _ = SessionSidebarSectionState.resolve(workspace: workspace)

        XCTAssertNil(workspace.activeGroupID)
    }

    func testGroupCollapseActionLabelReflectsCollapsedState() {
        XCTAssertEqual(
            SessionGroupHeaderView.collapseActionLabel(isCollapsed: true),
            "Expand Group"
        )
        XCTAssertEqual(
            SessionGroupHeaderView.collapseActionLabel(isCollapsed: false),
            "Collapse Group"
        )
    }

    func testWaitingStatusSetsNeedsAttentionAndIsNotRunning() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let activeID = try! XCTUnwrap(workspace.activeSessionID)

        XCTAssertTrue(workspace.updateAgentStatus(id: activeID, status: .waiting))
        let descriptor = try! XCTUnwrap(workspace.activeDescriptor)

        let otherID = UUID()
        let visualState = SessionTabRowVisualState.resolve(
            descriptor: descriptor,
            activeSessionID: otherID
        )

        XCTAssertTrue(visualState.needsAttention)
        XCTAssertEqual(visualState.attentionColorName, "orange")
        XCTAssertEqual(visualState.attentionLabel, "Waiting")
        XCTAssertFalse(visualState.isRunning)
        XCTAssertEqual(visualState.statusSymbolName, "hourglass")
    }

    func testErrorStatusSetsNeedsAttentionAndIsNotRunning() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let activeID = try! XCTUnwrap(workspace.activeSessionID)

        XCTAssertTrue(workspace.updateAgentStatus(id: activeID, status: .error))
        let descriptor = try! XCTUnwrap(workspace.activeDescriptor)

        let otherID = UUID()
        let visualState = SessionTabRowVisualState.resolve(
            descriptor: descriptor,
            activeSessionID: otherID
        )

        XCTAssertTrue(visualState.needsAttention)
        XCTAssertEqual(visualState.attentionColorName, "red")
        XCTAssertEqual(visualState.attentionLabel, "Error")
        XCTAssertFalse(visualState.isRunning)
        XCTAssertEqual(visualState.statusSymbolName, "exclamationmark.triangle.fill")
    }

    func testRunningStatusSetsIsRunningWithoutAttention() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let activeID = try! XCTUnwrap(workspace.activeSessionID)

        XCTAssertTrue(workspace.updateAgentStatus(id: activeID, status: .running))
        let descriptor = try! XCTUnwrap(workspace.activeDescriptor)

        let otherID = UUID()
        let visualState = SessionTabRowVisualState.resolve(
            descriptor: descriptor,
            activeSessionID: otherID
        )

        XCTAssertTrue(visualState.isRunning)
        XCTAssertFalse(visualState.needsAttention)
        XCTAssertNil(visualState.attentionColorName)
        XCTAssertNil(visualState.attentionLabel)
        XCTAssertEqual(visualState.statusSymbolName, "circle.fill")
    }

    func testDoneStatusHasNoAttentionAndIsNotRunning() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let activeID = try! XCTUnwrap(workspace.activeSessionID)

        XCTAssertTrue(workspace.updateAgentStatus(id: activeID, status: .done))
        let descriptor = try! XCTUnwrap(workspace.activeDescriptor)

        let otherID = UUID()
        let visualState = SessionTabRowVisualState.resolve(
            descriptor: descriptor,
            activeSessionID: otherID
        )

        XCTAssertFalse(visualState.needsAttention)
        XCTAssertFalse(visualState.isRunning)
        XCTAssertNil(visualState.attentionColorName)
        XCTAssertNil(visualState.attentionLabel)
        XCTAssertTrue(visualState.showsAgentBadge)
        XCTAssertEqual(visualState.agentBadgeColorName, "teal")
        XCTAssertEqual(visualState.statusSymbolName, "checkmark")
    }

    func testNoneStatusHasNoAttentionAndIsNotRunning() {
        let workspace = makeTestWorkspace(autoStartSessions: false)

        let descriptor = try! XCTUnwrap(workspace.activeDescriptor)

        let otherID = UUID()
        let visualState = SessionTabRowVisualState.resolve(
            descriptor: descriptor,
            activeSessionID: otherID
        )

        XCTAssertFalse(visualState.needsAttention)
        XCTAssertFalse(visualState.isRunning)
        XCTAssertNil(visualState.attentionColorName)
        XCTAssertNil(visualState.attentionLabel)
        XCTAssertNil(visualState.statusSymbolName)
    }

    func testStatusSymbolNameMapsAgentStatus() {
        XCTAssertNil(MvxStatusStyle.symbolName(for: .none))
        XCTAssertEqual(MvxStatusStyle.symbolName(for: .running), "circle.fill")
        XCTAssertEqual(MvxStatusStyle.symbolName(for: .waiting), "hourglass")
        XCTAssertEqual(MvxStatusStyle.symbolName(for: .done), "checkmark")
        XCTAssertEqual(MvxStatusStyle.symbolName(for: .error), "exclamationmark.triangle.fill")
    }

    func testSelectedErrorStatePreservesExistingAgentBadgeFields() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let activeID = try! XCTUnwrap(workspace.activeSessionID)

        XCTAssertTrue(workspace.updateAgentStatus(id: activeID, status: .error))
        let descriptor = try! XCTUnwrap(workspace.activeDescriptor)
        let visualState = SessionTabRowVisualState.resolve(
            descriptor: descriptor,
            activeSessionID: activeID
        )

        XCTAssertTrue(visualState.isSelected)
        XCTAssertTrue(visualState.needsAttention)
        XCTAssertEqual(visualState.selectionIndicatorStyleName, "bar")
        XCTAssertEqual(visualState.selectionIndicatorColorName, "accent")
        XCTAssertEqual(visualState.agentBadgeShapeName, "dot")
        XCTAssertEqual(visualState.agentBadgeColorName, "red")
        XCTAssertEqual(visualState.agentBadgeLabel, "Error")
        XCTAssertFalse(visualState.isRunning)
    }

    func testStatusRailColorTracksStatusAndSelectionWins() {
        let waiting = SessionDescriptor(ordinal: 1, agentStatus: .waiting)
        let inactiveWaiting = SessionTabRowVisualState.resolve(
            descriptor: waiting,
            activeSessionID: UUID()
        )

        XCTAssertEqual(inactiveWaiting.statusRailColorName, "orange")
        XCTAssertEqual(inactiveWaiting.railColorName, "orange")

        let selectedWaiting = SessionTabRowVisualState.resolve(
            descriptor: waiting,
            activeSessionID: waiting.id
        )

        XCTAssertEqual(selectedWaiting.statusRailColorName, "orange")
        XCTAssertEqual(selectedWaiting.railColorName, "accent")

        let done = SessionDescriptor(ordinal: 2, agentStatus: .done)
        let inactiveDone = SessionTabRowVisualState.resolve(
            descriptor: done,
            activeSessionID: UUID()
        )

        XCTAssertEqual(inactiveDone.statusRailColorName, "teal")
        XCTAssertEqual(inactiveDone.railColorName, "teal")
    }
}
