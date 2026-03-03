import CoreGraphics
import XCTest
@testable import Mvx

@MainActor
final class WorkspaceModelTests: XCTestCase {
    func testWorkspaceGraphStartsWithSingleLeafPane() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let activeID = try! XCTUnwrap(workspace.activeSessionID)

        XCTAssertEqual(workspace.workspaceGraph.paneCount, 1)
        XCTAssertEqual(workspace.workspaceGraph.leafSessionIDs, [activeID])
        XCTAssertEqual(workspace.workspaceGraph.focusedSessionID, activeID)
        XCTAssertNotNil(workspace.focusedPaneID)
    }

    func testWorkspaceMetadataSnapshotResolvesFromActiveContext() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let activeID = try! XCTUnwrap(workspace.activeSessionID)
        let featurePath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("mvx", isDirectory: true)
            .appendingPathComponent("feature-phase-6", isDirectory: true)

        XCTAssertTrue(workspace.updateSessionContext(
            id: activeID,
            workingDirectoryPath: featurePath.path,
            foregroundProcessName: "claude"
        ))
        XCTAssertTrue(workspace.updateAgentStatus(id: activeID, status: .waiting))

        let metadata = workspace.workspaceMetadata

        XCTAssertEqual(metadata.branchName, "mvx/feature-phase-6")
        XCTAssertEqual(metadata.reviewState, .reviewRequested)
        XCTAssertEqual(metadata.notificationCount, 1)
        XCTAssertEqual(metadata.waitingCount, 1)
        XCTAssertEqual(metadata.paneCount, 1)
    }

    func testSwapPaneContentsExchangesLeafSessionsAndMovesFocusToDropTarget() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let firstSessionID = try! XCTUnwrap(workspace.activeSessionID)

        XCTAssertTrue(workspace.splitActivePane(.vertical))

        let secondSessionID = try! XCTUnwrap(workspace.activeSessionID)
        let leafPanes = workspace.workspaceGraph.leafPanes
        let firstPaneID = try! XCTUnwrap(leafPanes.first?.id)
        let secondPaneID = try! XCTUnwrap(leafPanes.last?.id)

        XCTAssertTrue(workspace.swapPaneContents(sourcePaneID: firstPaneID, targetPaneID: secondPaneID))
        XCTAssertEqual(workspace.sessionID(forPane: firstPaneID), secondSessionID)
        XCTAssertEqual(workspace.sessionID(forPane: secondPaneID), firstSessionID)
        XCTAssertEqual(workspace.focusedPaneID, secondPaneID)
        XCTAssertEqual(workspace.activeSessionID, firstSessionID)
    }

    func testSwapPaneContentsRejectsUnknownPaneIDs() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let sourcePaneID = try! XCTUnwrap(workspace.focusedPaneID)

        XCTAssertFalse(
            workspace.swapPaneContents(
                sourcePaneID: sourcePaneID,
                targetPaneID: UUID()
            )
        )
    }

    func testSplitPaneBeforeInsertsNewLeafAheadOfTarget() {
        let sessionA = UUID()
        let sessionB = UUID()
        var graph = WorkspaceGraph.single(sessionID: sessionA)
        let targetPaneID = try! XCTUnwrap(graph.focusedPaneID)

        let insertedPaneID = graph.splitPane(
            targetPaneID,
            axis: .vertical,
            newSessionID: sessionB,
            insertion: .before
        )

        XCTAssertNotNil(insertedPaneID)
        XCTAssertEqual(graph.leafSessionIDs, [sessionB, sessionA])
        XCTAssertEqual(graph.focusedPaneID, insertedPaneID)
    }

    func testSplitPaneAfterInsertsNewLeafAfterTarget() {
        let sessionA = UUID()
        let sessionB = UUID()
        var graph = WorkspaceGraph.single(sessionID: sessionA)
        let targetPaneID = try! XCTUnwrap(graph.focusedPaneID)

        let insertedPaneID = graph.splitPane(
            targetPaneID,
            axis: .horizontal,
            newSessionID: sessionB,
            insertion: .after
        )

        XCTAssertNotNil(insertedPaneID)
        XCTAssertEqual(graph.leafSessionIDs, [sessionA, sessionB])
        XCTAssertEqual(graph.focusedPaneID, insertedPaneID)
    }

    func testMoveLeafPaneAllowsSiblingReorder() {
        let sessionA = UUID()
        let sessionB = UUID()
        var graph = WorkspaceGraph.single(sessionID: sessionA)
        let firstPaneID = try! XCTUnwrap(graph.focusedPaneID)
        let secondPaneID = try! XCTUnwrap(
            graph.splitPane(firstPaneID, axis: .vertical, newSessionID: sessionB, insertion: .after)
        )
        let leafPanes = graph.leafPanes

        XCTAssertTrue(
            graph.moveLeafPane(
                try! XCTUnwrap(leafPanes.first?.id),
                beside: secondPaneID,
                axis: .horizontal,
                insertion: .before
            )
        )

        XCTAssertEqual(graph.paneCount, 2)
        XCTAssertEqual(graph.leafSessionIDs, [sessionA, sessionB])
        XCTAssertEqual(graph.focusedSessionID, sessionA)
    }

    func testPaneDropZoneResolvesEdgesBeforeCenter() {
        let size = CGSize(width: 160, height: 120)
        let compactSize = CGSize(width: 80, height: 80)

        XCTAssertEqual(PaneDropZone.resolve(location: CGPoint(x: 80, y: 4), in: size), .splitTop)
        XCTAssertEqual(PaneDropZone.resolve(location: CGPoint(x: 80, y: 118), in: size), .splitBottom)
        XCTAssertEqual(PaneDropZone.resolve(location: CGPoint(x: 4, y: 60), in: size), .splitLeft)
        XCTAssertEqual(PaneDropZone.resolve(location: CGPoint(x: 158, y: 60), in: size), .splitRight)
        XCTAssertEqual(PaneDropZone.resolve(location: CGPoint(x: 80, y: 60), in: size), .swap)
        XCTAssertEqual(PaneDropZone.resolve(location: CGPoint(x: 20, y: 20), in: compactSize), .swap)
    }

    func testPerformPaneDropDetachedSessionEdgeDropCreatesSplit() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let visibleSessionID = try! XCTUnwrap(workspace.activeSessionID)
        let detachedSession = workspace.createSession(selectNewSession: false)
        let targetPaneID = try! XCTUnwrap(workspace.paneID(for: visibleSessionID))

        XCTAssertTrue(
            workspace.performPaneDrop(
                payload: WorkspaceDragPayload(kind: .session, id: detachedSession.id),
                targetPaneID: targetPaneID,
                zone: .splitRight
            )
        )

        XCTAssertEqual(workspace.workspaceGraph.paneCount, 2)
        XCTAssertEqual(workspace.activeSessionID, detachedSession.id)
        XCTAssertNotNil(workspace.paneID(for: detachedSession.id))
    }

    func testPerformPaneDropAttachedSessionEdgeDropCreatesSplitMove() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let firstSessionID = try! XCTUnwrap(workspace.activeSessionID)
        XCTAssertTrue(workspace.splitActivePane(.vertical))
        let secondSessionID = try! XCTUnwrap(workspace.activeSessionID)
        let leafPanes = workspace.workspaceGraph.leafPanes
        let firstPaneID = try! XCTUnwrap(leafPanes.first?.id)
        let secondPaneID = try! XCTUnwrap(leafPanes.last?.id)

        XCTAssertTrue(
            workspace.performPaneDrop(
                payload: WorkspaceDragPayload(kind: .session, id: firstSessionID),
                targetPaneID: secondPaneID,
                zone: .splitLeft
            )
        )

        XCTAssertEqual(workspace.workspaceGraph.paneCount, 2)
        XCTAssertNil(workspace.sessionID(forPane: firstPaneID))
        XCTAssertEqual(workspace.sessionID(forPane: secondPaneID), secondSessionID)
        XCTAssertEqual(workspace.activeSessionID, firstSessionID)
        XCTAssertNotNil(workspace.paneID(for: firstSessionID))
        XCTAssertNotEqual(workspace.paneID(for: firstSessionID), firstPaneID)
    }

    func testWorkspaceGitStatusParserTracksAddedRemovedAndModifiedEntries() {
        let summary = WorkspaceMetadataSnapshot.parseGitStatusPorcelain(
            """
            ?? new-file.swift
             M edited-file.swift
            D  removed-file.swift
            R  old-name.swift -> new-name.swift
            """
        )

        XCTAssertEqual(summary.addedCount, 3)
        XCTAssertEqual(summary.removedCount, 3)
    }

    func testWorkspaceGitStatusParserIgnoresIgnoredFiles() {
        let summary = WorkspaceMetadataSnapshot.parseGitStatusPorcelain(
            """
            !! .build/
            ?? notes.txt
            """
        )

        XCTAssertEqual(summary.addedCount, 1)
        XCTAssertEqual(summary.removedCount, 0)
    }

    func testWorkspaceGitRootResolvesNestedPathToRepositoryRoot() throws {
        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repositoryRoot = tempDirectory.appendingPathComponent("repo", isDirectory: true)
        let gitDirectory = repositoryRoot.appendingPathComponent(".git", isDirectory: true)
        let nestedDirectory = repositoryRoot.appendingPathComponent("Sources/App", isDirectory: true)

        defer {
            try? fileManager.removeItem(at: tempDirectory)
        }

        try fileManager.createDirectory(at: gitDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)

        XCTAssertEqual(
            WorkspaceMetadataSnapshot.gitRoot(for: nestedDirectory.path),
            repositoryRoot.standardizedFileURL.path
        )
    }

    func testWorkspaceMetadataRespectsActiveGroupScope() throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let ungroupedID = try XCTUnwrap(workspace.activeSessionID)
        let grouped = workspace.createSession(selectNewSession: false)
        let group = workspace.createGroup(name: "Frontend", colorTag: nil)

        XCTAssertTrue(workspace.updateAgentStatus(id: ungroupedID, status: .waiting))
        XCTAssertTrue(workspace.assignSession(id: grouped.id, toGroup: group.id))
        XCTAssertTrue(workspace.updateAgentStatus(id: grouped.id, status: .error))
        XCTAssertTrue(workspace.selectGroup(id: group.id))

        let metadata = workspace.workspaceMetadata

        XCTAssertEqual(metadata.reviewState, .blocked)
        XCTAssertEqual(metadata.notificationCount, 1)
        XCTAssertEqual(metadata.errorCount, 1)
        XCTAssertEqual(metadata.waitingCount, 0)
    }

    func testWorkspaceMetadataReturnsEmptyStateForEmptyActiveGroup() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let sessionID = try! XCTUnwrap(workspace.activeSessionID)
        let group = workspace.createGroup(name: "Frontend", colorTag: nil)

        XCTAssertTrue(workspace.assignSession(id: sessionID, toGroup: group.id))
        XCTAssertTrue(workspace.selectGroup(id: group.id))
        XCTAssertTrue(workspace.selectGroup(id: nil))

        let metadata = workspace.workspaceMetadata

        XCTAssertEqual(metadata.branchName, "No Branch")
        XCTAssertEqual(metadata.reviewState, .none)
        XCTAssertEqual(metadata.notificationCount, 0)
        XCTAssertEqual(metadata.paneCount, 0)
        XCTAssertNil(workspace.activeSessionID)
    }
}
