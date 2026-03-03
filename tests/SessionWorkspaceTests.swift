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
}
