import SwiftUI
import UniformTypeIdentifiers

public struct TilingWorkspaceLayoutState: Equatable {
    public let paneCount: Int
    public let focusedPaneID: UUID?
    public let visibleAxes: [WorkspaceSplitAxis]
    public let paneTitles: [String]

    @MainActor
    public static func resolve(workspace: SessionWorkspace) -> TilingWorkspaceLayoutState {
        let rootPane = workspace.workspaceGraph.rootPane
        let descriptorsByID = Dictionary(uniqueKeysWithValues: workspace.sessions.map { ($0.id, $0) })
        return TilingWorkspaceLayoutState(
            paneCount: workspace.workspaceGraph.paneCount,
            focusedPaneID: workspace.focusedPaneID,
            visibleAxes: rootPane.map(axes(in:)) ?? [],
            paneTitles: workspace.workspaceGraph.leafPanes.compactMap { pane in
                guard let sessionID = pane.sessionID else {
                    return nil
                }

                return descriptorsByID[sessionID]?.displayTitle ?? "Session"
            }
        )
    }

    private static func axes(in node: WorkspacePaneNode) -> [WorkspaceSplitAxis] {
        var result: [WorkspaceSplitAxis] = []
        if let axis = node.axis {
            result.append(axis)
        }

        for child in node.children {
            result.append(contentsOf: axes(in: child))
        }

        return result
    }
}

private struct PaneDropTargetState: Equatable {
    let paneID: UUID
    let zone: PaneDropZone
}

private struct PaneDropDelegate: DropDelegate {
    let targetPaneID: UUID
    let paneSize: CGSize
    @Binding var activeDropTarget: PaneDropTargetState?
    let workspace: SessionWorkspace

    func validateDrop(info: DropInfo) -> Bool {
        !info.itemProviders(for: [UTType.plainText]).isEmpty
    }

    func dropEntered(info: DropInfo) {
        updateTarget(with: info.location)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateTarget(with: info.location)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        clearTarget()
    }

    func performDrop(info: DropInfo) -> Bool {
        let zone = PaneDropZone.resolve(location: info.location, in: paneSize)
        guard let provider = info.itemProviders(for: [UTType.plainText]).first else {
            clearTarget()
            return false
        }

        loadPayload(from: provider) { payload in
            guard let payload else {
                return
            }

            Task { @MainActor in
                _ = workspace.performPaneDrop(payload: payload, targetPaneID: targetPaneID, zone: zone)
            }
        }

        clearTarget()
        return true
    }

    private func updateTarget(with location: CGPoint) {
        activeDropTarget = PaneDropTargetState(
            paneID: targetPaneID,
            zone: PaneDropZone.resolve(location: location, in: paneSize)
        )
    }

    private func clearTarget() {
        if activeDropTarget?.paneID == targetPaneID {
            activeDropTarget = nil
        }
    }

    private func loadPayload(
        from provider: NSItemProvider,
        completion: @escaping (WorkspaceDragPayload?) -> Void
    ) {
        provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
            let rawValue: String?
            switch item {
            case let string as String:
                rawValue = string
            case let string as NSString:
                rawValue = string as String
            case let data as Data:
                rawValue = String(data: data, encoding: .utf8)
            default:
                rawValue = nil
            }

            completion(rawValue.flatMap { WorkspaceDragPayload.decode(from: $0) })
        }
    }
}

@MainActor
public struct TilingWorkspaceView: View {
    @ObservedObject private var workspace: SessionWorkspace
    @State private var lastObservedLayoutState: TilingWorkspaceLayoutState?
    @State private var activeDropTarget: PaneDropTargetState?
    private let terminalHostFactory: TerminalHostFactory
    private let dividerThickness: CGFloat = 6

    public init(
        workspace: SessionWorkspace,
        terminalHostFactory: TerminalHostFactory = .fallbackOnly
    ) {
        self.workspace = workspace
        self.terminalHostFactory = terminalHostFactory
    }

    public var body: some View {
        let layoutState = TilingWorkspaceLayoutState.resolve(workspace: workspace)

        Group {
            if let rootPane = workspace.workspaceGraph.rootPane {
                GeometryReader { geometry in
                    paneBody(for: rootPane, availableSize: geometry.size)
                }
            } else {
                emptyState
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.07, green: 0.08, blue: 0.09))
        .onAppear {
            scheduleNativeGeometryReconcile(from: lastObservedLayoutState, to: layoutState)
            lastObservedLayoutState = layoutState
        }
        .onChange(of: layoutState) { newLayoutState in
            scheduleNativeGeometryReconcile(from: lastObservedLayoutState, to: newLayoutState)
            lastObservedLayoutState = newLayoutState
        }
    }

    private func paneBody(for node: WorkspacePaneNode, availableSize: CGSize) -> AnyView {
        if let axis = node.axis, node.children.count == 2 {
            return binarySplitView(node: node, axis: axis, availableSize: availableSize)
        } else if let axis = node.axis, node.children.count > 2 {
            return multiSplitView(node: node, axis: axis, availableSize: availableSize)
        } else {
            return leafPaneView(node: node)
        }
    }

    private func binarySplitView(
        node: WorkspacePaneNode,
        axis: WorkspaceSplitAxis,
        availableSize: CGSize
    ) -> AnyView {
        let ratio = node.splitRatio
        let isActiveFocusLine = dividerShouldHighlight(for: node)

        if axis == .vertical {
            let widths = verticalSplitWidths(
                availableSize: availableSize,
                ratio: ratio,
                dividerThickness: dividerThickness
            )

            return AnyView(
                HStack(spacing: 0) {
                    paneBody(
                        for: node.children[0],
                        availableSize: CGSize(width: widths.first, height: availableSize.height)
                    )
                    .frame(width: widths.first)

                    PaneDividerView(axis: axis, isActiveFocusLine: isActiveFocusLine) { delta in
                        resizeVerticalSplit(
                            nodeID: node.id,
                            currentRatio: ratio,
                            availableWidth: availableSize.width,
                            delta: delta
                        )
                    }

                    paneBody(
                        for: node.children[1],
                        availableSize: CGSize(width: widths.second, height: availableSize.height)
                    )
                    .frame(width: widths.second)
                }
            )
        }

        let heights = horizontalSplitHeights(
            availableSize: availableSize,
            ratio: ratio,
            dividerThickness: dividerThickness
        )

        return AnyView(
            VStack(spacing: 0) {
                paneBody(
                    for: node.children[0],
                    availableSize: CGSize(width: availableSize.width, height: heights.first)
                )
                .frame(height: heights.first)

                PaneDividerView(axis: axis, isActiveFocusLine: isActiveFocusLine) { delta in
                    resizeHorizontalSplit(
                        nodeID: node.id,
                        currentRatio: ratio,
                        availableHeight: availableSize.height,
                        delta: delta
                    )
                }

                paneBody(
                    for: node.children[1],
                    availableSize: CGSize(width: availableSize.width, height: heights.second)
                )
                .frame(height: heights.second)
            }
        )
    }

    private func multiSplitView(
        node: WorkspacePaneNode,
        axis: WorkspaceSplitAxis,
        availableSize: CGSize
    ) -> AnyView {
        let count = CGFloat(node.children.count)
        let spacing: CGFloat = 4

        if axis == .vertical {
            let childWidth = max((availableSize.width - spacing * (count - 1)) / count, 1)
            return AnyView(
                HStack(spacing: spacing) {
                    ForEach(node.children) { child in
                        paneBody(
                            for: child,
                            availableSize: CGSize(width: childWidth, height: availableSize.height)
                        )
                    }
                }
            )
        }

        let childHeight = max((availableSize.height - spacing * (count - 1)) / count, 1)
        return AnyView(
            VStack(spacing: spacing) {
                ForEach(node.children) { child in
                    paneBody(
                        for: child,
                        availableSize: CGSize(width: availableSize.width, height: childHeight)
                    )
                }
            }
        )
    }

    private func leafPaneView(node: WorkspacePaneNode) -> AnyView {
        AnyView(
            GeometryReader { geometry in
                leafPaneContent(node: node, paneSize: geometry.size)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        )
    }

    private func leafPaneContent(node: WorkspacePaneNode, paneSize: CGSize) -> some View {
        let sessionID = node.sessionID
        let isFocused = workspace.focusedPaneID == node.id
        let dropState = activeDropTarget?.paneID == node.id ? activeDropTarget : nil
        let isDropTarget = dropState != nil
        let dragPayload = WorkspaceDragPayload(kind: .pane, id: node.id).serializedValue
        let borderColor = isDropTarget
            ? Color.accentColor.opacity(isFocused ? 0.96 : 0.74)
            : (isFocused ? Color.accentColor : Color.clear)
        let glowColor = isDropTarget
            ? Color.accentColor.opacity(isFocused ? 0.5 : 0.28)
            : (isFocused ? Color.accentColor.opacity(0.4) : .clear)

        return ZStack {
            if let sessionID, let session = workspace.session(for: sessionID) {
                if let nativeHost = terminalHostFactory.makeNativeHost(
                    session: session,
                    isFocused: isFocused,
                    onFocusRequest: {
                        _ = workspace.focusPane(id: node.id)
                    }
                ) {
                    nativeHost
                } else {
                    detachedPlaceholder(for: node.id)
                }
            } else {
                detachedPlaceholder(for: node.id)
            }
        }
        .overlay(
            dropPreviewOverlay(for: dropState, in: paneSize)
                .allowsHitTesting(false)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(borderColor, lineWidth: isFocused || isDropTarget ? 2 : 0)
                .shadow(color: glowColor, radius: isDropTarget ? 10 : 8)
                .animation(.easeInOut(duration: 0.2), value: isFocused)
                .animation(.easeInOut(duration: 0.2), value: isDropTarget)
        )
        .overlay(alignment: .top) {
            paneDragHandle(payload: dragPayload, paneID: node.id)
        }
        .onDrop(
            of: [UTType.plainText],
            delegate: PaneDropDelegate(
                targetPaneID: node.id,
                paneSize: paneSize,
                activeDropTarget: $activeDropTarget,
                workspace: workspace
            )
        )
    }

    @ViewBuilder
    private func dropPreviewOverlay(for dropState: PaneDropTargetState?, in paneSize: CGSize) -> some View {
        if let dropState {
            let previewFrame = previewFrame(for: dropState.zone, in: paneSize)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(dropState.zone == .swap ? Color.accentColor.opacity(0.08) : Color.clear)

                Rectangle()
                    .fill(Color.accentColor.opacity(dropState.zone == .swap ? 0.08 : 0.18))
                    .frame(width: previewFrame.width, height: previewFrame.height)
                    .offset(x: previewFrame.minX, y: previewFrame.minY)
            }
        } else {
            Color.clear
        }
    }

    private func paneDragHandle(payload: String, paneID: UUID) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Capsule()
                .fill(Color.white.opacity(0.24))
                .frame(width: 34, height: 4)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 18)
        .padding(.top, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            _ = workspace.focusPane(id: paneID)
        }
        .onDrag {
            _ = workspace.focusPane(id: paneID)
            return NSItemProvider(object: payload as NSString)
        }
    }

    private func previewFrame(for zone: PaneDropZone, in paneSize: CGSize) -> CGRect {
        switch zone {
        case .swap:
            return CGRect(origin: .zero, size: paneSize)
        case .splitTop:
            let height = max(paneSize.height * 0.25, 1)
            return CGRect(x: 0, y: 0, width: paneSize.width, height: height)
        case .splitBottom:
            let height = max(paneSize.height * 0.25, 1)
            return CGRect(x: 0, y: max(paneSize.height - height, 0), width: paneSize.width, height: height)
        case .splitLeft:
            let width = max(paneSize.width * 0.25, 1)
            return CGRect(x: 0, y: 0, width: width, height: paneSize.height)
        case .splitRight:
            let width = max(paneSize.width * 0.25, 1)
            return CGRect(x: max(paneSize.width - width, 0), y: 0, width: width, height: paneSize.height)
        }
    }

    private func verticalSplitWidths(
        availableSize: CGSize,
        ratio: CGFloat,
        dividerThickness: CGFloat
    ) -> (first: CGFloat, second: CGFloat) {
        let firstWidth = max((availableSize.width - dividerThickness) * ratio, 1)
        let secondWidth = max(availableSize.width - dividerThickness - firstWidth, 1)
        return (first: firstWidth, second: secondWidth)
    }

    private func horizontalSplitHeights(
        availableSize: CGSize,
        ratio: CGFloat,
        dividerThickness: CGFloat
    ) -> (first: CGFloat, second: CGFloat) {
        let firstHeight = max((availableSize.height - dividerThickness) * ratio, 1)
        let secondHeight = max(availableSize.height - dividerThickness - firstHeight, 1)
        return (first: firstHeight, second: secondHeight)
    }

    private func resizeVerticalSplit(
        nodeID: UUID,
        currentRatio: CGFloat,
        availableWidth: CGFloat,
        delta: CGFloat
    ) {
        let totalWidth = availableWidth - dividerThickness
        guard totalWidth > 0 else { return }

        let currentFirst = totalWidth * currentRatio
        let newFirst = currentFirst + delta
        let newRatio = newFirst / totalWidth
        _ = workspace.resizeSplit(branchPaneID: nodeID, ratio: newRatio)
    }

    private func resizeHorizontalSplit(
        nodeID: UUID,
        currentRatio: CGFloat,
        availableHeight: CGFloat,
        delta: CGFloat
    ) {
        let totalHeight = availableHeight - dividerThickness
        guard totalHeight > 0 else { return }

        let currentFirst = totalHeight * currentRatio
        let newFirst = currentFirst + delta
        let newRatio = newFirst / totalHeight
        _ = workspace.resizeSplit(branchPaneID: nodeID, ratio: newRatio)
    }

    private func detachedPlaceholder(for paneID: UUID) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "terminal")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)

            Text("Detached Pane")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.secondary)

            Text("Select a session from the sidebar to attach it here.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.08, green: 0.09, blue: 0.10))
        .contentShape(Rectangle())
        .onTapGesture {
            _ = workspace.focusPane(id: paneID)
        }
    }

    private var emptyState: some View {
        Text("Create a session to start a tiled workspace.")
            .font(.system(.body, design: .rounded))
            .foregroundStyle(.secondary)
    }

    private func dividerShouldHighlight(for node: WorkspacePaneNode) -> Bool {
        guard let focusedPaneID = workspace.focusedPaneID, node.children.count == 2 else {
            return false
        }

        let leftContainsFocus = node.children[0].pane(for: focusedPaneID) != nil
        let rightContainsFocus = node.children[1].pane(for: focusedPaneID) != nil
        return leftContainsFocus != rightContainsFocus
    }

    private func scheduleNativeGeometryReconcile(
        from previous: TilingWorkspaceLayoutState?,
        to current: TilingWorkspaceLayoutState
    ) {
        terminalHostFactory.scheduleGeometryReconcile()

        guard let previous else {
            return
        }

        if previous.paneCount != current.paneCount ||
            previous.visibleAxes != current.visibleAxes {
            terminalHostFactory.scheduleMovedTerminalRefresh()
        }
    }
}
