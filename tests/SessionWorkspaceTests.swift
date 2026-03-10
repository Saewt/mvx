import Combine
import XCTest
@testable import Mvx

@MainActor
final class SessionWorkspaceTests: XCTestCase {
    func testCreateSessionStartsIndependentRuntime() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let firstID = try XCTUnwrap(workspace.activeSessionID)
        let second = workspace.createSession()

        let firstSession = try XCTUnwrap(workspace.session(for: firstID))
        let secondSession = try XCTUnwrap(workspace.session(for: second.id))

        _ = firstSession.sendUserInput("first session output")
        _ = secondSession.sendUserInput("second session output")

        let firstDriver = try XCTUnwrap(firstSession.backendObject as? InMemoryTestTerminalDriver)
        let secondDriver = try XCTUnwrap(secondSession.backendObject as? InMemoryTestTerminalDriver)

        XCTAssertEqual(workspace.sessions.count, 2)
        XCTAssertEqual(firstDriver.sentInput.last, "first session output")
        XCTAssertEqual(secondDriver.sentInput.last, "second session output")
        XCTAssertEqual(workspace.activeSessionID, second.id)
    }

    func testCloseCurrentSelectsNearestRemainingSession() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let firstID = try XCTUnwrap(workspace.activeSessionID)
        let second = workspace.createSession()

        XCTAssertTrue(workspace.selectSession(id: firstID))
        XCTAssertTrue(workspace.closeCurrentSession())

        XCTAssertEqual(workspace.activeSessionID, second.id)
        XCTAssertNil(workspace.session(for: firstID))
    }

    func testCreateSessionTracksStartedAtDate() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let firstID = try XCTUnwrap(workspace.activeSessionID)
        let second = workspace.createSession(selectNewSession: false)

        XCTAssertNotNil(workspace.sessionStartedAt(for: firstID))
        XCTAssertNotNil(workspace.sessionStartedAt(for: second.id))
    }

    func testCloseSessionRemovesTrackedStartedAtDate() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let second = workspace.createSession(selectNewSession: false)

        XCTAssertNotNil(workspace.sessionStartedAt(for: second.id))
        XCTAssertTrue(workspace.closeSession(id: second.id))
        XCTAssertNil(workspace.sessionStartedAt(for: second.id))
    }

    func testClosingLastSessionCreatesReplacement() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let firstID = try XCTUnwrap(workspace.activeSessionID)

        XCTAssertTrue(workspace.closeCurrentSession())

        let replacementID = try XCTUnwrap(workspace.activeSessionID)
        XCTAssertNotEqual(replacementID, firstID)
        XCTAssertEqual(workspace.sessions.count, 1)
    }

    func testRuntimeEventsUpdateSessionContext() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let sessionID = try XCTUnwrap(workspace.activeSessionID)
        let driver = try XCTUnwrap(workspace.activeSession?.backendObject as? InMemoryTestTerminalDriver)

        driver.emitRuntimeEvent(.titleChanged("Build"))
        driver.emitRuntimeEvent(.contextChanged(workingDirectoryPath: "/tmp/mvx", foregroundProcessName: "zsh"))
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))

        XCTAssertEqual(workspace.descriptor(for: sessionID)?.displayTitle, "Build")
        XCTAssertNil(workspace.descriptor(for: sessionID)?.customTitle)
        XCTAssertFalse(workspace.descriptor(for: sessionID)?.hasCustomTitle ?? true)
        XCTAssertEqual(workspace.descriptor(for: sessionID)?.workingDirectoryPath, "/tmp/mvx")
        XCTAssertEqual(workspace.descriptor(for: sessionID)?.foregroundProcessName, "zsh")
    }

    func testCustomTitlePersistsWhenTerminalSendsTitle() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let sessionID = try XCTUnwrap(workspace.activeSessionID)
        let driver = try XCTUnwrap(workspace.activeSession?.backendObject as? InMemoryTestTerminalDriver)

        _ = workspace.renameSession(id: sessionID, title: "My Terminal")

        driver.emitRuntimeEvent(.titleChanged("opencode"))
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))

        XCTAssertEqual(workspace.descriptor(for: sessionID)?.displayTitle, "My Terminal")
        XCTAssertEqual(workspace.descriptor(for: sessionID)?.customTitle, "My Terminal")
    }

    func testPlaceSessionReturnsFalseForUnknownSession() {
        let workspace = makeTestWorkspace(autoStartSessions: false, startsWithSession: false)

        XCTAssertFalse(workspace.placeSession(id: UUID(), inFocusedPaneUsing: .splitLeft))
    }

    func testPlaceSessionInPaneReturnsFalseForUnknownTargetPane() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let detached = workspace.createSession(selectNewSession: false)

        XCTAssertFalse(workspace.placeSession(id: detached.id, inPane: UUID(), using: .splitLeft))
    }

    func testPlaceSessionInPaneReturnsFalseWhenSourceMatchesTargetSession() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let activeID = try XCTUnwrap(workspace.activeSessionID)
        let targetPaneID = try XCTUnwrap(workspace.focusedPaneID)

        XCTAssertFalse(workspace.placeSession(id: activeID, inPane: targetPaneID, using: .splitLeft))
    }

    func testPlaceSessionInPaneSplitLeftUsesExplicitTargetPane() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let firstID = try XCTUnwrap(workspace.activeSessionID)

        XCTAssertTrue(workspace.splitActivePane(.vertical))

        let secondID = try XCTUnwrap(workspace.activeSessionID)
        let targetPaneID = try XCTUnwrap(workspace.paneID(for: firstID))
        let nonTargetPaneID = try XCTUnwrap(workspace.paneID(for: secondID))
        let detached = workspace.createSession(selectNewSession: false)

        XCTAssertTrue(workspace.focusPane(id: nonTargetPaneID))
        XCTAssertTrue(workspace.placeSession(id: detached.id, inPane: targetPaneID, using: .splitLeft))

        XCTAssertEqual(workspace.workspaceGraph.paneCount, 3)
        XCTAssertEqual(workspace.sessionID(forPane: targetPaneID), firstID)
        XCTAssertEqual(workspace.activeSessionID, detached.id)
        XCTAssertEqual(workspace.workspaceGraph.leafSessionIDs.filter { $0 == detached.id }.count, 1)
    }

    func testPlaceSessionInPaneMovesFocusedSourceAndPreservesTargetSession() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let firstID = try XCTUnwrap(workspace.activeSessionID)

        XCTAssertTrue(workspace.splitActivePane(.vertical))

        let secondID = try XCTUnwrap(workspace.activeSessionID)
        let firstPaneID = try XCTUnwrap(workspace.paneID(for: firstID))
        let secondPaneID = try XCTUnwrap(workspace.paneID(for: secondID))

        XCTAssertTrue(workspace.focusPane(id: firstPaneID))
        XCTAssertTrue(workspace.placeSession(id: firstID, inPane: secondPaneID, using: .splitRight))

        XCTAssertEqual(workspace.workspaceGraph.leafSessionIDs, [secondID, firstID])
        XCTAssertEqual(workspace.sessionID(forPane: secondPaneID), secondID)
        XCTAssertEqual(workspace.activeSessionID, firstID)
        XCTAssertEqual(workspace.workspaceGraph.leafSessionIDs.filter { $0 == firstID }.count, 1)
        XCTAssertEqual(workspace.workspaceGraph.leafSessionIDs.filter { $0 == secondID }.count, 1)
    }

    func testPlaceSessionSplitLeftUsesFocusedPane() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let focusedID = try XCTUnwrap(workspace.activeSessionID)
        let focusedPaneID = try XCTUnwrap(workspace.focusedPaneID)
        let detached = workspace.createSession(selectNewSession: false)

        XCTAssertTrue(workspace.placeSession(id: detached.id, inFocusedPaneUsing: .splitLeft))

        let insertedPaneID = try XCTUnwrap(workspace.paneID(for: detached.id))
        XCTAssertNotEqual(insertedPaneID, focusedPaneID)
        XCTAssertEqual(workspace.workspaceGraph.paneCount, 2)
        XCTAssertEqual(workspace.activeSessionID, detached.id)
        XCTAssertEqual(workspace.sessionID(forPane: focusedPaneID), focusedID)
        XCTAssertEqual(workspace.workspaceGraph.leafSessionIDs.filter { $0 == detached.id }.count, 1)
    }

    func testPlaceSessionSwapUsesFocusedPaneForAttachedSession() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let firstID = try XCTUnwrap(workspace.activeSessionID)

        XCTAssertTrue(workspace.splitActivePane(.vertical))

        let secondID = try XCTUnwrap(workspace.activeSessionID)
        let firstPaneID = try XCTUnwrap(workspace.paneID(for: firstID))
        let secondPaneID = try XCTUnwrap(workspace.paneID(for: secondID))

        XCTAssertTrue(workspace.focusPane(id: firstPaneID))
        XCTAssertTrue(workspace.placeSession(id: secondID, inFocusedPaneUsing: .swap))

        XCTAssertEqual(workspace.sessionID(forPane: firstPaneID), secondID)
        XCTAssertEqual(workspace.sessionID(forPane: secondPaneID), firstID)
        XCTAssertEqual(workspace.activeSessionID, secondID)
    }

    func testPlaceSessionReplaceUsesFocusedPaneForDetachedSession() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let firstID = try XCTUnwrap(workspace.activeSessionID)
        let detached = workspace.createSession(selectNewSession: false)
        let focusedPaneID = try XCTUnwrap(workspace.focusedPaneID)

        XCTAssertTrue(workspace.placeSession(id: detached.id, inFocusedPaneUsing: .replace))

        XCTAssertEqual(workspace.sessionID(forPane: focusedPaneID), detached.id)
        XCTAssertEqual(workspace.activeSessionID, detached.id)
        XCTAssertNil(workspace.paneID(for: firstID))
    }

    func testPlaceSessionReplaceReturnsFalseForAttachedSession() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let firstID = try XCTUnwrap(workspace.activeSessionID)

        XCTAssertTrue(workspace.splitActivePane(.vertical))

        let secondID = try XCTUnwrap(workspace.activeSessionID)
        let firstPaneID = try XCTUnwrap(workspace.paneID(for: firstID))

        XCTAssertTrue(workspace.focusPane(id: firstPaneID))
        XCTAssertFalse(workspace.placeSession(id: secondID, inFocusedPaneUsing: .replace))
        XCTAssertEqual(workspace.sessionID(forPane: firstPaneID), firstID)
    }

    func testSessionCommandAdaptiveVerticalSplitBuildsTopTwoBottomOneLayout() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)

        XCTAssertTrue(workspace.perform(.splitHorizontal))
        XCTAssertTrue(workspace.perform(.splitVertical))

        let rootPane = try XCTUnwrap(workspace.workspaceGraph.rootPane)

        XCTAssertEqual(workspace.workspaceGraph.paneCount, 3)
        XCTAssertEqual(rootPane.axis, .horizontal)
        XCTAssertEqual(rootPane.children.count, 2)
        XCTAssertEqual(rootPane.children[0].axis, .vertical)
        XCTAssertEqual(rootPane.children[0].children.count, 2)
        XCTAssertTrue(rootPane.children[0].children.allSatisfy(\.isLeaf))
        XCTAssertTrue(rootPane.children[1].isLeaf)
    }

    func testSplitActivePaneStillUsesFocusedPaneAfterHorizontalSplit() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)

        XCTAssertTrue(workspace.perform(.splitHorizontal))
        let focusedBottomPaneID = try XCTUnwrap(workspace.focusedPaneID)

        XCTAssertTrue(workspace.splitActivePane(.vertical))

        let rootPane = try XCTUnwrap(workspace.workspaceGraph.rootPane)

        XCTAssertEqual(workspace.workspaceGraph.paneCount, 3)
        XCTAssertEqual(rootPane.axis, .horizontal)
        XCTAssertTrue(rootPane.children[0].isLeaf)
        XCTAssertEqual(rootPane.children[1].axis, .vertical)
        XCTAssertEqual(rootPane.children[1].children.count, 2)
        XCTAssertEqual(rootPane.children[1].children[0].id, focusedBottomPaneID)
        XCTAssertTrue(rootPane.children[1].children.allSatisfy(\.isLeaf))
    }

    func testSessionCommandAdaptiveVerticalSplitFallsBackAfterTwoByTwoLayout() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)

        XCTAssertTrue(workspace.perform(.splitHorizontal))
        XCTAssertTrue(workspace.perform(.splitVertical))
        XCTAssertTrue(workspace.perform(.splitVertical))
        let focusedPaneID = try XCTUnwrap(workspace.focusedPaneID)

        XCTAssertTrue(workspace.perform(.splitVertical))

        let rootPane = try XCTUnwrap(workspace.workspaceGraph.rootPane)
        let bottomBranch = rootPane.children[1]
        let nestedBranch = bottomBranch.children[1]

        XCTAssertEqual(workspace.workspaceGraph.paneCount, 5)
        XCTAssertEqual(rootPane.axis, .horizontal)
        XCTAssertEqual(rootPane.children.count, 2)
        XCTAssertEqual(rootPane.children[0].axis, .vertical)
        XCTAssertEqual(bottomBranch.axis, .vertical)
        XCTAssertEqual(bottomBranch.children.count, 2)
        XCTAssertEqual(nestedBranch.axis, .vertical)
        XCTAssertEqual(nestedBranch.children.count, 2)
        XCTAssertEqual(nestedBranch.children[0].id, focusedPaneID)
        XCTAssertTrue(nestedBranch.children.allSatisfy(\.isLeaf))
    }

    func testUpdateSessionContextPublishesSingleChange() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let sessionID = try XCTUnwrap(workspace.activeSessionID)
        var publishCount = 0
        let cancellable = workspace.objectWillChange.sink { _ in
            publishCount += 1
        }

        XCTAssertTrue(
            workspace.updateSessionContext(
                id: sessionID,
                workingDirectoryPath: "/tmp/mvx",
                foregroundProcessName: "zsh"
            )
        )

        XCTAssertEqual(publishCount, 1)
        _ = cancellable
    }

    func testUpdateAgentStatusPublishesSingleChange() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let sessionID = try XCTUnwrap(workspace.activeSessionID)
        var publishCount = 0
        let cancellable = workspace.objectWillChange.sink { _ in
            publishCount += 1
        }

        XCTAssertTrue(workspace.updateAgentStatus(id: sessionID, status: .waiting))

        XCTAssertEqual(publishCount, 1)
        _ = cancellable
    }

    func testRestoreResetsTrackedStartedAtDates() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let sessionID = try XCTUnwrap(workspace.activeSessionID)
        let initialStartedAt = try XCTUnwrap(workspace.sessionStartedAt(for: sessionID))
        let snapshot = workspace.snapshot()

        Thread.sleep(forTimeInterval: 0.01)

        XCTAssertTrue(workspace.restore(from: snapshot))

        let restoredStartedAt = try XCTUnwrap(workspace.sessionStartedAt(for: sessionID))
        XCTAssertGreaterThan(restoredStartedAt, initialStartedAt)
    }

    func testRefreshVisibleStateCoalescesMultipleRequestsPerRunLoop() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        var publishCount = 0
        let cancellable = workspace.objectWillChange.sink { _ in
            publishCount += 1
        }

        workspace.refreshVisibleState()
        workspace.refreshVisibleState()

        XCTAssertEqual(publishCount, 0)

        RunLoop.current.run(until: Date().addingTimeInterval(0.01))

        XCTAssertEqual(publishCount, 1)
        _ = cancellable
    }

    func testSendInputToActiveSessionCoalescesActivityAndVisibleRefresh() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        var publishCount = 0
        let cancellable = workspace.objectWillChange.sink { _ in
            publishCount += 1
        }

        XCTAssertEqual(
            workspace.sendInputToActiveSession("echo hi", appendNewline: false),
            "echo hi"
        )

        XCTAssertEqual(publishCount, 0)

        RunLoop.current.run(until: Date().addingTimeInterval(0.01))

        XCTAssertEqual(publishCount, 1)
        _ = cancellable
    }

    // MARK: - Adaptive Drop Placement

    func testAdaptivelyPlaceSessionCreatesHorizontalSplitFromSinglePane() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let firstID = try XCTUnwrap(workspace.activeSessionID)
        let detached = workspace.createSession(selectNewSession: false)
        let targetPaneID = try XCTUnwrap(workspace.paneID(for: firstID))

        XCTAssertTrue(
            workspace.performPaneDrop(
                payload: WorkspaceDragPayload(kind: .session, id: detached.id),
                targetPaneID: targetPaneID,
                zone: .splitRight
            )
        )

        XCTAssertEqual(workspace.workspaceGraph.paneCount, 2)
        let root = try XCTUnwrap(workspace.workspaceGraph.rootPane)
        XCTAssertEqual(root.axis, .horizontal)
    }

    func testAdaptivelyPlaceSessionSplitsTopPaneAtTwoPanes() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let firstID = try XCTUnwrap(workspace.activeSessionID)
        XCTAssertTrue(workspace.splitActivePane(.horizontal))
        XCTAssertEqual(workspace.workspaceGraph.paneCount, 2)

        let detached = workspace.createSession(selectNewSession: false)
        let targetPaneID = try XCTUnwrap(workspace.paneID(for: firstID))

        XCTAssertTrue(
            workspace.performPaneDrop(
                payload: WorkspaceDragPayload(kind: .session, id: detached.id),
                targetPaneID: targetPaneID,
                zone: .splitRight
            )
        )

        XCTAssertEqual(workspace.workspaceGraph.paneCount, 3)
        let root = try XCTUnwrap(workspace.workspaceGraph.rootPane)
        XCTAssertEqual(root.axis, .horizontal)
        XCTAssertEqual(root.children[0].axis, .vertical)
        XCTAssertTrue(root.children[1].isLeaf)
    }

    func testAdaptivelyPlaceSessionCreates2x2AtThreePanes() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let firstID = try XCTUnwrap(workspace.activeSessionID)
        XCTAssertTrue(workspace.splitActivePane(.horizontal))
        // Focus back to first session (top pane) and split vertically
        XCTAssertTrue(workspace.selectSession(id: firstID))
        XCTAssertTrue(workspace.splitActivePane(.vertical))
        XCTAssertEqual(workspace.workspaceGraph.paneCount, 3)

        let detached = workspace.createSession(selectNewSession: false)
        let bottomPaneID = try XCTUnwrap(workspace.workspaceGraph.rootPane?.children[1].id)

        XCTAssertTrue(
            workspace.performPaneDrop(
                payload: WorkspaceDragPayload(kind: .session, id: detached.id),
                targetPaneID: bottomPaneID,
                zone: .splitRight
            )
        )

        XCTAssertEqual(workspace.workspaceGraph.paneCount, 4)
        let root = try XCTUnwrap(workspace.workspaceGraph.rootPane)
        XCTAssertEqual(root.axis, .horizontal)
        XCTAssertEqual(root.children[0].axis, .vertical)
        XCTAssertEqual(root.children[1].axis, .vertical)
    }

    func testAdaptivelyPlaceSessionReturnsFalseAtFourPlusPanes() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        XCTAssertTrue(workspace.performAdaptiveSplit(.horizontal))
        XCTAssertTrue(workspace.performAdaptiveSplit(.vertical))
        XCTAssertTrue(workspace.performAdaptiveSplit(.vertical))
        XCTAssertEqual(workspace.workspaceGraph.paneCount, 4)

        let detached = workspace.createSession(selectNewSession: false)
        let leafPanes = workspace.workspaceGraph.leafPanes
        let targetPaneID = try XCTUnwrap(leafPanes.first?.id)

        // Adaptive placement should not apply — falls back to explicit drop zone
        XCTAssertTrue(
            workspace.performPaneDrop(
                payload: WorkspaceDragPayload(kind: .session, id: detached.id),
                targetPaneID: targetPaneID,
                zone: .splitBottom
            )
        )

        XCTAssertEqual(workspace.workspaceGraph.paneCount, 5)
    }
}
