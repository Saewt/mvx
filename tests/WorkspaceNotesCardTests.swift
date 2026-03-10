import XCTest
@testable import Mvx

final class WorkspaceNotesCardTests: XCTestCase {
    @MainActor
    func testResolveUsesCompactEmptyStateWithoutPreview() {
        let state = WorkspaceNotesCardState.resolve(
            note: nil,
            metadata: WorkspaceMetadataSnapshot(reviewState: .active)
        )

        XCTAssertFalse(state.isHighlighted)
        XCTAssertEqual(state.highlightColorName, "none")
        XCTAssertFalse(state.showsTriggerBadge)
        XCTAssertFalse(state.showsClearAction)
    }

    @MainActor
    func testResolveHighlightsReadyAndReviewRequestedStates() {
        let readyState = WorkspaceNotesCardState.resolve(
            note: nil,
            metadata: WorkspaceMetadataSnapshot(reviewState: .ready)
        )
        let reviewState = WorkspaceNotesCardState.resolve(
            note: nil,
            metadata: WorkspaceMetadataSnapshot(reviewState: .reviewRequested)
        )

        XCTAssertTrue(readyState.isHighlighted)
        XCTAssertEqual(readyState.highlightColorName, "teal")
        XCTAssertTrue(reviewState.isHighlighted)
        XCTAssertEqual(reviewState.highlightColorName, "orange")
    }

    @MainActor
    func testResolveShowsClearActionWhenNoteExists() {
        let note = WorkspaceNoteSnapshot(
            body: "Ship migrations tomorrow\nDouble-check snapshots",
            updatedAt: Date(timeIntervalSinceReferenceDate: 42)
        )
        let state = WorkspaceNotesCardState.resolve(
            note: note,
            metadata: WorkspaceMetadataSnapshot(reviewState: .none)
        )

        XCTAssertTrue(state.showsTriggerBadge)
        XCTAssertTrue(state.showsClearAction)
    }

    @MainActor
    func testResolveScopeLabelUsesNamedGroupOrUngrouped() {
        let group = SessionGroup(name: "Frontend")

        XCTAssertEqual(
            WorkspaceNotesCardState.resolveScopeLabel(
                activeGroupID: nil,
                sessionGroups: [group]
            ),
            "Ungrouped"
        )
        XCTAssertEqual(
            WorkspaceNotesCardState.resolveScopeLabel(
                activeGroupID: group.id,
                sessionGroups: [group]
            ),
            "Frontend"
        )
    }

    @MainActor
    func testEditorControllerDoesNotPersistOnFirstKeystroke() async throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let controller = WorkspaceNotesEditorController(
            workspace: workspace,
            debounceNanoseconds: 30_000_000
        )

        controller.updateDraft("a")

        XCTAssertNil(workspace.workspaceNote)

        try await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertEqual(workspace.workspaceNote?.body, "a")
    }

    @MainActor
    func testEditorControllerFlushSavesImmediately() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let controller = WorkspaceNotesEditorController(
            workspace: workspace,
            debounceNanoseconds: 60_000_000_000
        )

        controller.updateDraft("x")

        XCTAssertNil(workspace.workspaceNote)

        controller.flush()

        XCTAssertEqual(workspace.workspaceNote?.body, "x")
    }

    @MainActor
    func testEditorControllerUsesActiveGroupScope() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let group = workspace.createGroup(name: "Frontend", colorTag: nil)

        XCTAssertTrue(workspace.updateNote(body: "group note", forGroup: group.id))
        XCTAssertTrue(workspace.selectGroup(id: group.id))

        let controller = WorkspaceNotesEditorController(workspace: workspace)

        XCTAssertEqual(controller.draftBody, "group note")
    }

    @MainActor
    func testEditorControllerSwitchScopeFlushesPendingDraftAndLoadsNextScope() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let source = workspace.createGroup(name: "Source", colorTag: nil)
        let destination = workspace.createGroup(name: "Destination", colorTag: nil)

        XCTAssertTrue(workspace.updateNote(body: "destination note", forGroup: destination.id))
        XCTAssertTrue(workspace.selectGroup(id: source.id))

        let controller = WorkspaceNotesEditorController(
            workspace: workspace,
            debounceNanoseconds: 60_000_000_000
        )

        controller.updateDraft("source draft")
        XCTAssertTrue(workspace.selectGroup(id: destination.id))
        controller.switchScope(to: workspace.activeGroupID)

        XCTAssertEqual(workspace.note(forGroup: source.id)?.body, "source draft")
        XCTAssertEqual(controller.draftBody, "destination note")
    }

    @MainActor
    func testEditorControllerSyncSkippedWhenCommitPending() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let group = workspace.createGroup(name: "Frontend", colorTag: nil)
        XCTAssertTrue(workspace.updateNote(body: "older value", forGroup: group.id))
        XCTAssertTrue(workspace.selectGroup(id: group.id))

        let controller = WorkspaceNotesEditorController(
            workspace: workspace,
            debounceNanoseconds: 60_000_000_000
        )

        controller.updateDraft("draft")
        controller.syncFromWorkspace()

        XCTAssertEqual(controller.draftBody, "draft")

        controller.flush()
    }
}
