import XCTest
@testable import Mvx

@MainActor
final class TilingWorkspaceLayoutTests: XCTestCase {
    func testTilingWorkspaceRendersBothSplitAxes() {
        let workspace = makeTestWorkspace(autoStartSessions: false)

        XCTAssertTrue(workspace.splitActivePane(.vertical))
        XCTAssertTrue(workspace.splitActivePane(.horizontal))

        let state = TilingWorkspaceLayoutState.resolve(workspace: workspace)

        XCTAssertEqual(state.paneCount, 3)
        XCTAssertTrue(state.visibleAxes.contains(.vertical))
        XCTAssertTrue(state.visibleAxes.contains(.horizontal))
        XCTAssertEqual(state.paneTitles.count, 3)
    }

    func testFocusedPaneRoutesSplitAndCloseCommands() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let handler = WorkspaceCommandHandler(workspace: workspace)
        let originalFocusedPaneID = workspace.focusedPaneID

        _ = handler.perform(.splitVertical)
        let splitFocusedPaneID = workspace.focusedPaneID

        XCTAssertEqual(workspace.workspaceGraph.paneCount, 2)
        XCTAssertNotEqual(originalFocusedPaneID, splitFocusedPaneID)

        _ = handler.perform(.closePane)

        XCTAssertEqual(workspace.workspaceGraph.paneCount, 1)
        XCTAssertEqual(workspace.sessions.count, 1)
        XCTAssertNotNil(workspace.focusedPaneID)
    }

    func testTitleChangeDoesNotAlterGeometryState() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let before = TilingWorkspaceGeometryState.resolve(workspace: workspace)

        _ = workspace.renameSession(id: workspace.activeSessionID!, title: "Renamed")

        let after = TilingWorkspaceGeometryState.resolve(workspace: workspace)
        XCTAssertEqual(before, after)
    }

    func testSplitChangeDoesAlterGeometryState() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let before = TilingWorkspaceGeometryState.resolve(workspace: workspace)

        XCTAssertTrue(workspace.splitActivePane(.vertical))

        let after = TilingWorkspaceGeometryState.resolve(workspace: workspace)
        XCTAssertNotEqual(before, after)
        XCTAssertEqual(after.paneCount, 2)
    }

    func testFocusChangeDoesAlterGeometryState() {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let firstID = try! XCTUnwrap(workspace.activeSessionID)
        let second = workspace.createSession()
        XCTAssertTrue(workspace.splitActivePane(.vertical))
        XCTAssertTrue(workspace.selectSession(id: firstID))

        let before = TilingWorkspaceGeometryState.resolve(workspace: workspace)
        XCTAssertTrue(workspace.selectSession(id: second.id))

        let after = TilingWorkspaceGeometryState.resolve(workspace: workspace)
        XCTAssertNotEqual(before, after)
    }
}

final class ZoomAwareSplitSizingTests: XCTestCase {
    func testBinarySplitNormalVerticalSizing() {
        let result = TilingWorkspaceView.zoomAwareBinarySplitSizes(
            availableSize: CGSize(width: 1000, height: 800),
            axis: .vertical,
            ratio: 0.5,
            dividerThickness: 4,
            zoomTargetChildIndex: nil
        )

        XCTAssertEqual(result.effectiveDividerThickness, 4)
        XCTAssertGreaterThan(result.first, 0)
        XCTAssertGreaterThan(result.second, 0)
        XCTAssertEqual(result.first + result.second + result.effectiveDividerThickness, 1000, accuracy: 2)
    }

    func testBinarySplitNormalHorizontalSizing() {
        let result = TilingWorkspaceView.zoomAwareBinarySplitSizes(
            availableSize: CGSize(width: 1000, height: 800),
            axis: .horizontal,
            ratio: 0.5,
            dividerThickness: 4,
            zoomTargetChildIndex: nil
        )

        XCTAssertEqual(result.effectiveDividerThickness, 4)
        XCTAssertGreaterThan(result.first, 0)
        XCTAssertGreaterThan(result.second, 0)
        XCTAssertEqual(result.first + result.second + result.effectiveDividerThickness, 800, accuracy: 2)
    }

    func testBinarySplitZoomOnFirstChildGetsFullSizeVertical() {
        let result = TilingWorkspaceView.zoomAwareBinarySplitSizes(
            availableSize: CGSize(width: 1000, height: 800),
            axis: .vertical,
            ratio: 0.5,
            dividerThickness: 4,
            zoomTargetChildIndex: 0
        )

        XCTAssertEqual(result.first, 1000)
        XCTAssertEqual(result.second, 0)
        XCTAssertEqual(result.effectiveDividerThickness, 0)
    }

    func testBinarySplitZoomOnSecondChildGetsFullSizeVertical() {
        let result = TilingWorkspaceView.zoomAwareBinarySplitSizes(
            availableSize: CGSize(width: 1000, height: 800),
            axis: .vertical,
            ratio: 0.5,
            dividerThickness: 4,
            zoomTargetChildIndex: 1
        )

        XCTAssertEqual(result.first, 0)
        XCTAssertEqual(result.second, 1000)
        XCTAssertEqual(result.effectiveDividerThickness, 0)
    }

    func testBinarySplitZoomOnFirstChildGetsFullSizeHorizontal() {
        let result = TilingWorkspaceView.zoomAwareBinarySplitSizes(
            availableSize: CGSize(width: 1000, height: 800),
            axis: .horizontal,
            ratio: 0.5,
            dividerThickness: 4,
            zoomTargetChildIndex: 0
        )

        XCTAssertEqual(result.first, 800)
        XCTAssertEqual(result.second, 0)
        XCTAssertEqual(result.effectiveDividerThickness, 0)
    }

    func testBinarySplitZoomOnSecondChildGetsFullSizeHorizontal() {
        let result = TilingWorkspaceView.zoomAwareBinarySplitSizes(
            availableSize: CGSize(width: 1000, height: 800),
            axis: .horizontal,
            ratio: 0.5,
            dividerThickness: 4,
            zoomTargetChildIndex: 1
        )

        XCTAssertEqual(result.first, 0)
        XCTAssertEqual(result.second, 800)
        XCTAssertEqual(result.effectiveDividerThickness, 0)
    }

    func testBinarySplitAbsentZoomFallsBackToNormalSizing() {
        let zoomed = TilingWorkspaceView.zoomAwareBinarySplitSizes(
            availableSize: CGSize(width: 1000, height: 800),
            axis: .vertical,
            ratio: 0.5,
            dividerThickness: 4,
            zoomTargetChildIndex: nil
        )

        let normal = TilingWorkspaceView.zoomAwareBinarySplitSizes(
            availableSize: CGSize(width: 1000, height: 800),
            axis: .vertical,
            ratio: 0.5,
            dividerThickness: 4,
            zoomTargetChildIndex: nil
        )

        XCTAssertEqual(zoomed.first, normal.first)
        XCTAssertEqual(zoomed.second, normal.second)
        XCTAssertEqual(zoomed.effectiveDividerThickness, normal.effectiveDividerThickness)
    }

    func testMultiSplitNormalVerticalSizing() {
        let result = TilingWorkspaceView.zoomAwareMultiSplitSizes(
            availableSize: CGSize(width: 1000, height: 800),
            axis: .vertical,
            childCount: 3,
            spacing: 2,
            zoomTargetChildIndex: nil
        )

        XCTAssertEqual(result.sizes.count, 3)
        XCTAssertEqual(result.effectiveSpacing, 2)
        for size in result.sizes {
            XCTAssertGreaterThan(size, 0)
        }
        let total = result.sizes.reduce(0, +) + 2 * 2
        XCTAssertEqual(total, 1000, accuracy: 2)
    }

    func testMultiSplitNormalHorizontalSizing() {
        let result = TilingWorkspaceView.zoomAwareMultiSplitSizes(
            availableSize: CGSize(width: 1000, height: 800),
            axis: .horizontal,
            childCount: 4,
            spacing: 2,
            zoomTargetChildIndex: nil
        )

        XCTAssertEqual(result.sizes.count, 4)
        XCTAssertEqual(result.effectiveSpacing, 2)
        for size in result.sizes {
            XCTAssertGreaterThan(size, 0)
        }
        let total = result.sizes.reduce(0, +) + 2 * 3
        XCTAssertEqual(total, 800, accuracy: 2)
    }

    func testMultiSplitZoomOnChildGetsFullSizeOthersZero() {
        let result = TilingWorkspaceView.zoomAwareMultiSplitSizes(
            availableSize: CGSize(width: 1000, height: 800),
            axis: .vertical,
            childCount: 4,
            spacing: 2,
            zoomTargetChildIndex: 2
        )

        XCTAssertEqual(result.sizes.count, 4)
        XCTAssertEqual(result.effectiveSpacing, 0)
        XCTAssertEqual(result.sizes[0], 0)
        XCTAssertEqual(result.sizes[1], 0)
        XCTAssertEqual(result.sizes[2], 1000)
        XCTAssertEqual(result.sizes[3], 0)
    }

    func testMultiSplitZoomOnFirstChildGetsFullSizeVertical() {
        let result = TilingWorkspaceView.zoomAwareMultiSplitSizes(
            availableSize: CGSize(width: 1000, height: 800),
            axis: .vertical,
            childCount: 3,
            spacing: 2,
            zoomTargetChildIndex: 0
        )

        XCTAssertEqual(result.sizes[0], 1000)
        for i in 1..<result.sizes.count {
            XCTAssertEqual(result.sizes[i], 0)
        }
    }

    func testMultiSplitZoomOnLastChildGetsFullSizeHorizontal() {
        let result = TilingWorkspaceView.zoomAwareMultiSplitSizes(
            availableSize: CGSize(width: 1000, height: 800),
            axis: .horizontal,
            childCount: 3,
            spacing: 2,
            zoomTargetChildIndex: 2
        )

        XCTAssertEqual(result.sizes[0], 0)
        XCTAssertEqual(result.sizes[1], 0)
        XCTAssertEqual(result.sizes[2], 800)
    }

    func testMultiSplitAbsentZoomFallsBackToNormalSizing() {
        let result = TilingWorkspaceView.zoomAwareMultiSplitSizes(
            availableSize: CGSize(width: 1000, height: 800),
            axis: .vertical,
            childCount: 3,
            spacing: 2,
            zoomTargetChildIndex: nil
        )

        XCTAssertEqual(result.effectiveSpacing, 2)
        for size in result.sizes {
            XCTAssertGreaterThan(size, 0)
        }
    }

    func testMultiSplitEmptyChildrenReturnsEmptySizes() {
        let result = TilingWorkspaceView.zoomAwareMultiSplitSizes(
            availableSize: CGSize(width: 1000, height: 800),
            axis: .vertical,
            childCount: 0,
            spacing: 2,
            zoomTargetChildIndex: nil
        )

        XCTAssertTrue(result.sizes.isEmpty)
        XCTAssertEqual(result.effectiveSpacing, 2)
    }

    func testMultiSplitOutOfBoundsZoomIndexReturnsAllZeroSizes() {
        let result = TilingWorkspaceView.zoomAwareMultiSplitSizes(
            availableSize: CGSize(width: 1000, height: 800),
            axis: .vertical,
            childCount: 3,
            spacing: 2,
            zoomTargetChildIndex: 5
        )

        XCTAssertEqual(result.sizes.count, 3)
        XCTAssertEqual(result.effectiveSpacing, 0)
        for size in result.sizes {
            XCTAssertEqual(size, 0)
        }
    }

    func testZoomTargetChildIndexReturnsNilWhenNoZoom() {
        let left = WorkspacePaneNode(sessionID: UUID())
        let right = WorkspacePaneNode(sessionID: UUID())
        let node = WorkspacePaneNode(axis: .vertical, children: [left, right])

        XCTAssertNil(TilingWorkspaceView.zoomTargetChildIndex(in: node, zoomedPaneID: nil))
    }

    func testZoomTargetChildIndexReturnsZeroWhenLeftChildContainsZoom() {
        let zoomID = UUID()
        let left = WorkspacePaneNode(id: zoomID, sessionID: UUID())
        let right = WorkspacePaneNode(sessionID: UUID())
        let node = WorkspacePaneNode(axis: .vertical, children: [left, right])

        XCTAssertEqual(TilingWorkspaceView.zoomTargetChildIndex(in: node, zoomedPaneID: zoomID), 0)
    }

    func testZoomTargetChildIndexReturnsOneWhenRightChildContainsZoom() {
        let zoomID = UUID()
        let left = WorkspacePaneNode(sessionID: UUID())
        let right = WorkspacePaneNode(id: zoomID, sessionID: UUID())
        let node = WorkspacePaneNode(axis: .vertical, children: [left, right])

        XCTAssertEqual(TilingWorkspaceView.zoomTargetChildIndex(in: node, zoomedPaneID: zoomID), 1)
    }

    func testZoomTargetChildIndexFindsNestedZoom() {
        let zoomID = UUID()
        let deepLeaf = WorkspacePaneNode(id: zoomID, sessionID: UUID())
        let nestedBranch = WorkspacePaneNode(axis: .horizontal, children: [deepLeaf])
        let sibling = WorkspacePaneNode(sessionID: UUID())
        let root = WorkspacePaneNode(axis: .vertical, children: [nestedBranch, sibling])

        XCTAssertEqual(TilingWorkspaceView.zoomTargetChildIndex(in: root, zoomedPaneID: zoomID), 0)
    }

    func testZoomTargetChildIndexReturnsNilForAbsentZoom() {
        let left = WorkspacePaneNode(sessionID: UUID())
        let right = WorkspacePaneNode(sessionID: UUID())
        let node = WorkspacePaneNode(axis: .vertical, children: [left, right])

        XCTAssertNil(TilingWorkspaceView.zoomTargetChildIndex(in: node, zoomedPaneID: UUID()))
    }
}

final class PaneHeaderStateTests: XCTestCase {
    func testResolveWithNilDescriptorReturnsDefaults() {
        let state = PaneHeaderState.resolve(
            descriptor: nil,
            isFocused: false,
            isZoomed: false
        )

        XCTAssertEqual(state.title, "Session")
        XCTAssertNil(state.directoryName)
        XCTAssertNil(state.statusColorName)
        XCTAssertFalse(state.isZoomed)
        XCTAssertFalse(state.isFocused)
    }

    func testResolveExtractsTitleAndDirectoryFromDescriptor() {
        let descriptor = SessionDescriptor(
            ordinal: 1,
            workingDirectoryPath: "/Users/test/project"
        )
        let state = PaneHeaderState.resolve(
            descriptor: descriptor,
            isFocused: true,
            isZoomed: true
        )

        XCTAssertEqual(state.directoryName, "project")
        XCTAssertTrue(state.isFocused)
        XCTAssertTrue(state.isZoomed)
    }

    func testResolveMapsAgentStatusToColorName() {
        let running = SessionDescriptor(ordinal: 1, agentStatus: .running)
        XCTAssertEqual(
            PaneHeaderState.resolve(descriptor: running, isFocused: false, isZoomed: false).statusColorName,
            "green"
        )

        let waiting = SessionDescriptor(ordinal: 1, agentStatus: .waiting)
        XCTAssertEqual(
            PaneHeaderState.resolve(descriptor: waiting, isFocused: false, isZoomed: false).statusColorName,
            "orange"
        )

        let error = SessionDescriptor(ordinal: 1, agentStatus: .error)
        XCTAssertEqual(
            PaneHeaderState.resolve(descriptor: error, isFocused: false, isZoomed: false).statusColorName,
            "red"
        )

        let done = SessionDescriptor(ordinal: 1, agentStatus: .done)
        XCTAssertEqual(
            PaneHeaderState.resolve(descriptor: done, isFocused: false, isZoomed: false).statusColorName,
            "teal"
        )

        let none = SessionDescriptor(ordinal: 1, agentStatus: .none)
        XCTAssertNil(
            PaneHeaderState.resolve(descriptor: none, isFocused: false, isZoomed: false).statusColorName
        )
    }

    func testResolveUsesCustomTitleWhenSet() {
        var descriptor = SessionDescriptor(ordinal: 1, customTitle: "My Custom")
        descriptor.setCustomTitle("My Custom")
        let state = PaneHeaderState.resolve(
            descriptor: descriptor,
            isFocused: false,
            isZoomed: false
        )
        XCTAssertEqual(state.title, "My Custom")
    }

    func testResolveUsesDisplayIdentityAndContextForHeader() {
        let descriptor = SessionDescriptor(
            ordinal: 1,
            workingDirectoryPath: "/Users/test/codop",
            foregroundProcessName: "claude"
        )
        let identity = SessionDisplayIdentity(
            title: "codop · claude",
            contextLine: "codop  ·  main  ·  claude"
        )

        let state = PaneHeaderState.resolve(
            descriptor: descriptor,
            displayIdentity: identity,
            isFocused: true,
            isZoomed: false
        )

        XCTAssertEqual(state.title, "codop · claude")
        XCTAssertEqual(state.secondaryLabel, "codop  ·  main  ·  claude")
        XCTAssertEqual(state.directoryName, "codop")
    }

    func testResolveReflectsZoomedAndFocusState() {
        let descriptor = SessionDescriptor(ordinal: 1)
        let focusedZoomed = PaneHeaderState.resolve(descriptor: descriptor, isFocused: true, isZoomed: true)
        XCTAssertTrue(focusedZoomed.isFocused)
        XCTAssertTrue(focusedZoomed.isZoomed)

        let unfocusedNormal = PaneHeaderState.resolve(descriptor: descriptor, isFocused: false, isZoomed: false)
        XCTAssertFalse(unfocusedNormal.isFocused)
        XCTAssertFalse(unfocusedNormal.isZoomed)
    }
}
