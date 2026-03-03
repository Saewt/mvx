import XCTest
@testable import Mvx

@MainActor
final class WorkspacePanePersistenceTests: XCTestCase {
    func testPaneLayoutRoundTripsThroughSnapshot() {
        let workspace = makeTestWorkspace(autoStartSessions: false)

        XCTAssertTrue(workspace.splitActivePane(.vertical))
        XCTAssertTrue(workspace.splitActivePane(.horizontal))

        let snapshot = workspace.snapshot()
        let restored = makeTestWorkspace(autoStartSessions: false, startsWithSession: false)

        XCTAssertTrue(restored.restore(from: snapshot))
        XCTAssertEqual(restored.workspaceGraph.paneCount, 3)
        XCTAssertEqual(restored.workspaceGraph.leafSessionIDs.count, 3)
        XCTAssertEqual(restored.workspaceGraph.focusedSessionID, snapshot.workspaceGraph?.focusedSessionID)
    }
}
