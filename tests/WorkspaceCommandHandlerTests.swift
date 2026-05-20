import Combine
import XCTest
@testable import Mvx

@MainActor
final class WorkspaceCommandHandlerTests: XCTestCase {
    func testCopyPasteAndSelectAllUseActiveSession() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let handler = WorkspaceCommandHandler(workspace: workspace)

        _ = handler.perform(.copy, selection: "copied")
        let pasted = handler.perform(.paste)
        let selected = handler.perform(.selectAll)

        XCTAssertEqual(workspace.activeSession?.clipboardContents(), "copied")
        XCTAssertEqual(pasted, "copied")
        XCTAssertNil(selected)
    }

    func testNativeCopyPasteAndSelectAllFallBackToSessionWhenResponderChainDoesNotHandleActions() throws {
        let session = makeTestSession(clipboardBridge: ClipboardBridge())
        let workspace = SessionWorkspace(
            autoStartSessions: false,
            startsWithSession: false,
            sessionFactory: { session }
        )
        _ = workspace.createSession()
        let handler = WorkspaceCommandHandler(workspace: workspace)

        _ = handler.perform(.copy, selection: "native copied")
        let pasted = handler.perform(.paste)
        let selected = handler.perform(.selectAll)

        XCTAssertEqual(session.clipboardContents(), "native copied")
        XCTAssertEqual(pasted, "native copied")
        XCTAssertNil(selected)
    }

    func testNewTabAndCloseRouteThroughWorkspace() {
        let workspace = makeTestWorkspace()
        let handler = WorkspaceCommandHandler(workspace: workspace)
        let firstID = workspace.activeSessionID

        _ = handler.perform(.newTab)
        let secondID = workspace.activeSessionID

        XCTAssertNotEqual(firstID, secondID)
        XCTAssertEqual(workspace.sessions.count, 2)

        _ = handler.perform(.closeCurrentSession)

        XCTAssertEqual(workspace.sessions.count, 1)
        XCTAssertEqual(workspace.activeSessionID, firstID)
    }

    func testNextAttentionSelectsWaitingThenErrorSessions() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let firstID = try XCTUnwrap(workspace.activeSessionID)
        let second = workspace.createSession(selectNewSession: false)
        let third = workspace.createSession(selectNewSession: false)
        let handler = WorkspaceCommandHandler(workspace: workspace)

        _ = workspace.updateAgentStatus(id: second.id, status: .waiting)
        _ = workspace.updateAgentStatus(id: third.id, status: .error)

        XCTAssertTrue(workspace.selectSession(id: firstID))
        _ = handler.perform(.nextAttention)
        XCTAssertEqual(workspace.activeSessionID, second.id)

        _ = workspace.updateAgentStatus(id: second.id, status: .none)
        _ = handler.perform(.nextAttention)
        XCTAssertEqual(workspace.activeSessionID, third.id)
    }

    func testPaneAwareCommandsPreserveFocusedRouting() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let handler = WorkspaceCommandHandler(workspace: workspace)
        let firstPane = try XCTUnwrap(workspace.focusedPaneID)

        _ = handler.perform(.splitVertical)
        let secondPane = try XCTUnwrap(workspace.focusedPaneID)
        XCTAssertNotEqual(firstPane, secondPane)

        _ = handler.perform(.previousPane)
        XCTAssertEqual(workspace.focusedPaneID, firstPane)

        _ = handler.perform(.nextPane)
        XCTAssertEqual(workspace.focusedPaneID, secondPane)
    }

    func testSplitCommandsBuildRequestedThreeAndFourPaneLayouts() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let handler = WorkspaceCommandHandler(workspace: workspace)

        _ = handler.perform(.splitHorizontal)
        _ = handler.perform(.splitVertical)

        var rootPane = try XCTUnwrap(workspace.workspaceGraph.rootPane)
        XCTAssertEqual(rootPane.axis, .horizontal)
        XCTAssertEqual(rootPane.children.count, 2)
        XCTAssertEqual(rootPane.children[0].axis, .vertical)
        XCTAssertTrue(rootPane.children[1].isLeaf)

        _ = handler.perform(.splitVertical)

        rootPane = try XCTUnwrap(workspace.workspaceGraph.rootPane)
        XCTAssertEqual(workspace.workspaceGraph.paneCount, 4)
        XCTAssertEqual(rootPane.axis, .horizontal)
        XCTAssertEqual(rootPane.children.count, 2)
        XCTAssertEqual(rootPane.children[0].axis, .vertical)
        XCTAssertEqual(rootPane.children[1].axis, .vertical)
        XCTAssertEqual(rootPane.children[0].children.count, 2)
        XCTAssertEqual(rootPane.children[1].children.count, 2)
        XCTAssertTrue(rootPane.children[0].children.allSatisfy(\.isLeaf))
        XCTAssertTrue(rootPane.children[1].children.allSatisfy(\.isLeaf))
    }

    func testNextSessionCyclesSelectionAndQuitSetsFlag() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let handler = WorkspaceCommandHandler(workspace: workspace)
        let firstID = try XCTUnwrap(workspace.activeSessionID)
        let second = workspace.createSession(selectNewSession: false)

        XCTAssertTrue(workspace.selectSession(id: firstID))
        _ = handler.perform(.nextSession)
        XCTAssertEqual(workspace.activeSessionID, second.id)

        _ = handler.perform(.quit)
        XCTAssertTrue(workspace.quitRequested)
    }

    func testNextSessionStaysWithinActiveGroup() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let handler = WorkspaceCommandHandler(workspace: workspace)
        let ungroupedID = try XCTUnwrap(workspace.activeSessionID)
        let groupedA = workspace.createSession(selectNewSession: false)
        let groupedB = workspace.createSession(selectNewSession: false)
        let group = workspace.createGroup(name: "Frontend", colorTag: nil)

        XCTAssertTrue(workspace.assignSession(id: groupedA.id, toGroup: group.id))
        XCTAssertTrue(workspace.assignSession(id: groupedB.id, toGroup: group.id))
        XCTAssertTrue(workspace.selectGroup(id: group.id))
        XCTAssertEqual(workspace.activeSessionID, groupedA.id)

        _ = handler.perform(.nextSession)
        XCTAssertEqual(workspace.activeSessionID, groupedB.id)

        _ = handler.perform(.nextSession)
        XCTAssertEqual(workspace.activeSessionID, groupedA.id)
        XCTAssertNotEqual(workspace.activeSessionID, ungroupedID)
    }

    func testBulkGroupCommandsRouteThroughWorkspaceAndExposeAvailability() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let handler = WorkspaceCommandHandler(workspace: workspace)
        let firstID = try XCTUnwrap(workspace.activeSessionID)
        let second = workspace.createSession(selectNewSession: false)
        let outside = workspace.createSession(selectNewSession: false)
        let activeGroup = workspace.createGroup(name: "Frontend", colorTag: nil)
        let otherGroup = workspace.createGroup(name: "Backend", colorTag: nil)

        XCTAssertTrue(workspace.assignSession(id: firstID, toGroup: activeGroup.id))
        XCTAssertTrue(workspace.assignSession(id: second.id, toGroup: activeGroup.id))
        XCTAssertTrue(workspace.assignSession(id: outside.id, toGroup: otherGroup.id))
        XCTAssertTrue(workspace.selectGroup(id: activeGroup.id))
        XCTAssertTrue(workspace.updateAgentStatus(id: firstID, status: .done))

        let descriptors = Dictionary(uniqueKeysWithValues: handler.availableCommands().map { ($0.command, $0) })
        XCTAssertTrue(try XCTUnwrap(descriptors[.closeDoneSessionsInActiveGroup]).isEnabled)
        XCTAssertTrue(try XCTUnwrap(descriptors[.closeAllSessionsInActiveGroup]).isEnabled)
        XCTAssertTrue(try XCTUnwrap(descriptors[.moveActiveGroupToUngrouped]).isEnabled)
        XCTAssertTrue(try XCTUnwrap(descriptors[.collapseOtherGroups]).isEnabled)

        _ = handler.perform(.closeDoneSessionsInActiveGroup)
        XCTAssertNil(workspace.descriptor(for: firstID))
        XCTAssertEqual(workspace.sessions(inGroup: activeGroup.id).map(\.id), [second.id])

        _ = handler.perform(.closeAllSessionsInActiveGroup)
        let replacement = try XCTUnwrap(workspace.sessions(inGroup: activeGroup.id).first)
        XCTAssertNotEqual(replacement.id, second.id)

        _ = handler.perform(.moveActiveGroupToUngrouped)
        XCTAssertEqual(workspace.sessions(inGroup: activeGroup.id), [])
        XCTAssertTrue(workspace.sessions(inGroup: nil).contains { $0.id == replacement.id })

        _ = handler.perform(.collapseOtherGroups)
        XCTAssertTrue(try XCTUnwrap(workspace.sessionGroups.first { $0.id == otherGroup.id }).isCollapsed)
    }

    func testSplitCommandsEnabledWhenPaneExists() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let handler = WorkspaceCommandHandler(workspace: workspace)

        let descriptors = Dictionary(uniqueKeysWithValues: handler.availableCommands().map { ($0.command, $0) })
        XCTAssertTrue(try XCTUnwrap(descriptors[.splitHorizontal]).isEnabled)
        XCTAssertTrue(try XCTUnwrap(descriptors[.splitVertical]).isEnabled)

        _ = handler.perform(.splitVertical)
        XCTAssertEqual(workspace.workspaceGraph.paneCount, 2)
    }

    func testSplitCommandsDisabledWhenNoPaneExists() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false, startsWithSession: false)
        let handler = WorkspaceCommandHandler(workspace: workspace)

        let descriptors = Dictionary(uniqueKeysWithValues: handler.availableCommands().map { ($0.command, $0) })
        XCTAssertFalse(try XCTUnwrap(descriptors[.splitHorizontal]).isEnabled)
        XCTAssertFalse(try XCTUnwrap(descriptors[.splitVertical]).isEnabled)
    }

    func testCheckForUpdatesPresentsUpdateSheet() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let handler = WorkspaceCommandHandler(workspace: workspace, updateController: ReleaseUpdateController())

        XCTAssertFalse(handler.isUpdateSheetPresented)

        _ = handler.perform(.checkForUpdates)

        XCTAssertTrue(handler.isUpdateSheetPresented)
    }

    func testAutoCheckOnlyOpensSheetWhenUpdateAvailable() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let bundle = makeWritableTestBundle()
        let controller = ReleaseUpdateController(bundle: bundle)
        let handler = WorkspaceCommandHandler(workspace: workspace, updateController: controller)

        XCTAssertFalse(handler.isUpdateSheetPresented)

        // Simulate what MvxApp does: observe the controller state and present
        // the sheet only when an update becomes available.
        let expectation = XCTestExpectation(description: "sheet opened")
        var cancellables: Set<AnyCancellable> = []
        controller.$updateState
            .dropFirst()
            .filter { state in
                if case .updateAvailable = state { return true }
                return false
            }
            .sink { _ in
                handler.isUpdateSheetPresented = true
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // Simulate a background check that finds an update.
        let release = LatestRelease(
            version: "999.0.0",
            build: "999",
            minimumMacOS: "13.0",
            platforms: .init(darwinAarch64: .init(
                url: "https://example.com/mvx.tar.gz",
                sha256: String(repeating: "a", count: 64)
            ))
        )
        let publisher = Just(release)
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()

        _ = controller.checkForUpdates(interactive: false, publisher: publisher)

        wait(for: [expectation], timeout: 2.0)
        XCTAssertTrue(handler.isUpdateSheetPresented)

        cancellables.removeAll()
    }

    func testDismissUpdateSheetHidesUpdateSheet() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let handler = WorkspaceCommandHandler(workspace: workspace, updateController: ReleaseUpdateController())

        _ = handler.perform(.checkForUpdates)
        XCTAssertTrue(handler.isUpdateSheetPresented)

        handler.dismissUpdateSheet()

        XCTAssertFalse(handler.isUpdateSheetPresented)
    }

    func testQuitHidesOpenUpdateSheetAndStillRequestsWorkspaceQuit() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let handler = WorkspaceCommandHandler(workspace: workspace, updateController: ReleaseUpdateController())

        _ = handler.perform(.checkForUpdates)
        XCTAssertTrue(handler.isUpdateSheetPresented)

        _ = handler.perform(.quit)

        XCTAssertFalse(handler.isUpdateSheetPresented)
        XCTAssertTrue(workspace.quitRequested)
    }
}
