import XCTest
@testable import Mvx

@MainActor
final class ActiveWorkspaceProxyTests: XCTestCase {
    func testProxyTracksActiveWorkspaceAndRecreatesCommandHandler() throws {
        let registry = WorkspaceRegistry(workspaceFactory: { _ in
            makeTestWorkspace(autoStartSessions: false)
        })
        let first = registry.createWorkspace(name: "Alpha")
        let second = registry.createWorkspace(name: "Beta", activate: false)
        let controller = ReleaseUpdateController()
        let proxy = ActiveWorkspaceProxy(updateController: controller)

        proxy.bind(to: registry)
        let firstHandler = try XCTUnwrap(proxy.commandHandler)

        XCTAssertEqual(proxy.activeWorkspaceID, first.id)
        XCTAssertTrue(proxy.workspace === registry.workspace(for: first.id))
        XCTAssertTrue(firstHandler.workspace === registry.workspace(for: first.id))
        XCTAssertTrue(firstHandler.updateController === controller)

        XCTAssertTrue(registry.activateWorkspace(id: second.id))

        let secondHandler = try XCTUnwrap(proxy.commandHandler)
        XCTAssertEqual(proxy.activeWorkspaceID, second.id)
        XCTAssertTrue(proxy.workspace === registry.workspace(for: second.id))
        XCTAssertTrue(secondHandler.workspace === registry.workspace(for: second.id))
        XCTAssertFalse(firstHandler === secondHandler)
        XCTAssertTrue(secondHandler.updateController === controller)
    }
}
