import SwiftUI
import UniformTypeIdentifiers

public struct TilingWorkspaceGeometryState: Equatable {
    public let paneCount: Int
    public let focusedPaneID: UUID?
    public let visibleAxes: [WorkspaceSplitAxis]

    @MainActor
    public static func resolve(workspace: SessionWorkspace) -> TilingWorkspaceGeometryState {
        let rootPane = workspace.workspaceGraph.rootPane
        return TilingWorkspaceGeometryState(
            paneCount: workspace.workspaceGraph.paneCount,
            focusedPaneID: workspace.focusedPaneID,
            visibleAxes: rootPane.map(axes(in:)) ?? []
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

public struct TilingWorkspaceLayoutState: Equatable {
    public let paneCount: Int
    public let focusedPaneID: UUID?
    public let visibleAxes: [WorkspaceSplitAxis]
    public let paneTitles: [String]

    @MainActor
    public static func resolve(workspace: SessionWorkspace) -> TilingWorkspaceLayoutState {
        let rootPane = workspace.workspaceGraph.rootPane
        let descriptorsByID = Dictionary(uniqueKeysWithValues: workspace.sessions.map { ($0.id, $0) })
        let resolvedTitles = SessionDisplayIdentityResolver.resolvedTitles(for: workspace.sessions)
        return TilingWorkspaceLayoutState(
            paneCount: workspace.workspaceGraph.paneCount,
            focusedPaneID: workspace.focusedPaneID,
            visibleAxes: rootPane.map(axes(in:)) ?? [],
            paneTitles: workspace.workspaceGraph.leafPanes.compactMap { pane in
                guard let sessionID = pane.sessionID else {
                    return nil
                }

                guard let descriptor = descriptorsByID[sessionID] else {
                    return "Session"
                }

                return resolvedTitles[sessionID] ?? descriptor.displayTitle
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
    @State private var lastObservedGeometryState: TilingWorkspaceGeometryState?
    @State private var activeDropTarget: PaneDropTargetState?
    private let terminalHostFactory: TerminalHostFactory
    private let zoomedPaneID: UUID?
    private let onPaneAction: ((UUID, WorkspaceCommand) -> Void)?
    private let dividerThickness: CGFloat = 4
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        workspace: SessionWorkspace,
        terminalHostFactory: TerminalHostFactory = .fallbackOnly,
        zoomedPaneID: UUID? = nil,
        onPaneAction: ((UUID, WorkspaceCommand) -> Void)? = nil
    ) {
        self.workspace = workspace
        self.terminalHostFactory = terminalHostFactory
        self.zoomedPaneID = zoomedPaneID
        self.onPaneAction = onPaneAction
    }

    public var body: some View {
        let geometryState = TilingWorkspaceGeometryState.resolve(workspace: workspace)

        Group {
            if let rootPane = workspace.workspaceGraph.rootPane {
                GeometryReader { geometry in
                    paneBody(for: rootPane, availableSize: geometry.size, zoomedPaneID: zoomedPaneID)
                }
            } else {
                emptyState
            }
        }
        .padding(2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MvxSurface.base)
        .onAppear {
            scheduleNativeGeometryReconcile(from: lastObservedGeometryState, to: geometryState)
            lastObservedGeometryState = geometryState
        }
        .onChange(of: geometryState) { newGeometryState in
            scheduleNativeGeometryReconcile(from: lastObservedGeometryState, to: newGeometryState)
            lastObservedGeometryState = newGeometryState
        }
        .animation(reduceMotion ? .none : MvxMotion.emphasized, value: zoomedPaneID)
    }

    private func paneBody(for node: WorkspacePaneNode, availableSize: CGSize, zoomedPaneID: UUID?) -> AnyView {
        if let axis = node.axis, node.children.count == 2 {
            return binarySplitView(node: node, axis: axis, availableSize: availableSize, zoomedPaneID: zoomedPaneID)
        } else if let axis = node.axis, node.children.count > 2 {
            return multiSplitView(node: node, axis: axis, availableSize: availableSize, zoomedPaneID: zoomedPaneID)
        } else {
            return leafPaneView(node: node)
        }
    }

    private func binarySplitView(
        node: WorkspacePaneNode,
        axis: WorkspaceSplitAxis,
        availableSize: CGSize,
        zoomedPaneID: UUID?
    ) -> AnyView {
        let ratio = node.splitRatio
        let isActiveFocusLine = dividerShouldHighlight(for: node)
        let zoomTargetChildIndex = Self.zoomTargetChildIndex(in: node, zoomedPaneID: zoomedPaneID)
        let sizes = Self.zoomAwareBinarySplitSizes(
            availableSize: availableSize,
            axis: axis,
            ratio: ratio,
            dividerThickness: dividerThickness,
            zoomTargetChildIndex: zoomTargetChildIndex
        )
        let isZoomed = zoomTargetChildIndex != nil

        if axis == .vertical {
            return AnyView(
                HStack(spacing: 0) {
                    paneBody(
                        for: node.children[0],
                        availableSize: CGSize(width: sizes.first, height: availableSize.height),
                        zoomedPaneID: zoomedPaneID
                    )
                    .frame(width: sizes.first)

                    PaneDividerView(axis: axis, isActiveFocusLine: isActiveFocusLine, thickness: sizes.effectiveDividerThickness) { delta in
                        resizeVerticalSplit(
                            nodeID: node.id,
                            currentRatio: ratio,
                            availableWidth: availableSize.width,
                            delta: delta
                        )
                    }
                    .opacity(isZoomed ? 0 : 1)
                    .allowsHitTesting(!isZoomed)

                    paneBody(
                        for: node.children[1],
                        availableSize: CGSize(width: sizes.second, height: availableSize.height),
                        zoomedPaneID: zoomedPaneID
                    )
                    .frame(width: sizes.second)
                }
            )
        }

        return AnyView(
            VStack(spacing: 0) {
                paneBody(
                    for: node.children[0],
                    availableSize: CGSize(width: availableSize.width, height: sizes.first),
                    zoomedPaneID: zoomedPaneID
                )
                .frame(height: sizes.first)

                PaneDividerView(axis: axis, isActiveFocusLine: isActiveFocusLine, thickness: sizes.effectiveDividerThickness) { delta in
                    resizeHorizontalSplit(
                        nodeID: node.id,
                        currentRatio: ratio,
                        availableHeight: availableSize.height,
                        delta: delta
                    )
                }
                .opacity(isZoomed ? 0 : 1)
                .allowsHitTesting(!isZoomed)

                paneBody(
                    for: node.children[1],
                    availableSize: CGSize(width: availableSize.width, height: sizes.second),
                    zoomedPaneID: zoomedPaneID
                )
                .frame(height: sizes.second)
            }
        )
    }

    private func multiSplitView(
        node: WorkspacePaneNode,
        axis: WorkspaceSplitAxis,
        availableSize: CGSize,
        zoomedPaneID: UUID?
    ) -> AnyView {
        let spacing: CGFloat = 2
        let zoomTargetChildIndex: Int? = {
            guard let zoomedPaneID else { return nil }
            return node.children.firstIndex(where: { $0.pane(for: zoomedPaneID) != nil })
        }()
        let sizesResult = Self.zoomAwareMultiSplitSizes(
            availableSize: availableSize,
            axis: axis,
            childCount: node.children.count,
            spacing: spacing,
            zoomTargetChildIndex: zoomTargetChildIndex
        )

        if axis == .vertical {
            return AnyView(
                HStack(spacing: sizesResult.effectiveSpacing) {
                    ForEach(Array(node.children.enumerated()), id: \.element.id) { index, child in
                        paneBody(
                            for: child,
                            availableSize: CGSize(width: sizesResult.sizes[index], height: availableSize.height),
                            zoomedPaneID: zoomedPaneID
                        )
                        .frame(width: sizesResult.sizes[index])
                    }
                }
            )
        }

        return AnyView(
            VStack(spacing: sizesResult.effectiveSpacing) {
                ForEach(Array(node.children.enumerated()), id: \.element.id) { index, child in
                    paneBody(
                        for: child,
                        availableSize: CGSize(width: availableSize.width, height: sizesResult.sizes[index]),
                        zoomedPaneID: zoomedPaneID
                    )
                    .frame(height: sizesResult.sizes[index])
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
        let descriptor = sessionID.flatMap { workspace.descriptor(for: $0) }
        let displayIdentity = descriptor.map { descriptor in
            SessionDisplayIdentityResolver.resolve(
                descriptor: descriptor,
                visibleDescriptors: workspace.sessions,
                branchName: workspace.workspaceMetadata.branchName,
                gitChangeSummary: workspace.gitChangeSummary(for: descriptor.id)
            )
        }
        let headerState = PaneHeaderState.resolve(
            descriptor: descriptor,
            displayIdentity: displayIdentity,
            isFocused: isFocused,
            isZoomed: zoomedPaneID == node.id
        )

        return VStack(spacing: 0) {
            PaneHeaderView(
                state: headerState,
                payload: dragPayload,
                paneID: node.id,
                workspace: workspace,
                onAction: onPaneAction
            )

            ZStack {
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

                dropPreviewOverlay(for: dropState, in: paneSize)
                    .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(borderColor, lineWidth: isFocused || isDropTarget ? 2 : 0)
                .shadow(color: glowColor, radius: isDropTarget ? 10 : 8)
                .animation(reduceMotion ? .none : MvxMotion.standard, value: isFocused)
                .animation(reduceMotion ? .none : MvxMotion.standard, value: isDropTarget)
        )
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

    nonisolated static func zoomTargetChildIndex(in node: WorkspacePaneNode, zoomedPaneID: UUID?) -> Int? {
        guard let zoomedPaneID else { return nil }
        if node.children[0].pane(for: zoomedPaneID) != nil { return 0 }
        if node.children[1].pane(for: zoomedPaneID) != nil { return 1 }
        return nil
    }

    nonisolated static func zoomAwareBinarySplitSizes(
        availableSize: CGSize,
        axis: WorkspaceSplitAxis,
        ratio: CGFloat,
        dividerThickness: CGFloat,
        zoomTargetChildIndex: Int?
    ) -> (first: CGFloat, second: CGFloat, effectiveDividerThickness: CGFloat) {
        guard let zoomTarget = zoomTargetChildIndex else {
            if axis == .vertical {
                let widths = _verticalSplitWidths(availableWidth: availableSize.width, ratio: ratio, dividerThickness: dividerThickness)
                return (widths.first, widths.second, dividerThickness)
            } else {
                let heights = _horizontalSplitHeights(availableHeight: availableSize.height, ratio: ratio, dividerThickness: dividerThickness)
                return (heights.first, heights.second, dividerThickness)
            }
        }

        let dimension = axis == .vertical ? availableSize.width : availableSize.height
        if zoomTarget == 0 {
            return axis == .vertical
                ? (first: dimension, second: 0, effectiveDividerThickness: 0)
                : (first: dimension, second: 0, effectiveDividerThickness: 0)
        } else {
            return axis == .vertical
                ? (first: 0, second: dimension, effectiveDividerThickness: 0)
                : (first: 0, second: dimension, effectiveDividerThickness: 0)
        }
    }

    nonisolated static func zoomAwareMultiSplitSizes(
        availableSize: CGSize,
        axis: WorkspaceSplitAxis,
        childCount: Int,
        spacing: CGFloat,
        zoomTargetChildIndex: Int?
    ) -> (sizes: [CGFloat], effectiveSpacing: CGFloat) {
        guard childCount > 0 else { return ([], spacing) }

        guard let zoomTarget = zoomTargetChildIndex else {
            let count = CGFloat(childCount)
            let totalSpacing = spacing * (count - 1)
            let available = (axis == .vertical ? availableSize.width : availableSize.height) - totalSpacing
            let childSize = max(available / count, 1)
            return (Array(repeating: childSize, count: childCount), spacing)
        }

        let fullSize = axis == .vertical ? availableSize.width : availableSize.height
        var sizes = Array(repeating: CGFloat(0), count: childCount)
        if zoomTarget >= 0 && zoomTarget < childCount {
            sizes[zoomTarget] = fullSize
        }
        return (sizes, 0)
    }

    nonisolated static func _verticalSplitWidths(availableWidth: CGFloat, ratio: CGFloat, dividerThickness: CGFloat) -> (first: CGFloat, second: CGFloat) {
        let firstWidth = max((availableWidth - dividerThickness) * ratio, 1)
        let secondWidth = max(availableWidth - dividerThickness - firstWidth, 1)
        return (first: firstWidth, second: secondWidth)
    }

    nonisolated static func _horizontalSplitHeights(availableHeight: CGFloat, ratio: CGFloat, dividerThickness: CGFloat) -> (first: CGFloat, second: CGFloat) {
        let firstHeight = max((availableHeight - dividerThickness) * ratio, 1)
        let secondHeight = max(availableHeight - dividerThickness - firstHeight, 1)
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
        VStack(spacing: MvxSpacing.md) {
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
        .background(MvxSurface.raised)
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
        from previous: TilingWorkspaceGeometryState?,
        to current: TilingWorkspaceGeometryState
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

// MARK: - PaneHeaderState

public struct PaneHeaderState: Equatable {
    public let title: String
    public let directoryName: String?
    public let secondaryLabel: String?
    public let statusColorName: String?
    public let isZoomed: Bool
    public let isFocused: Bool

    public static func resolve(
        descriptor: SessionDescriptor?,
        displayIdentity: SessionDisplayIdentity? = nil,
        isFocused: Bool,
        isZoomed: Bool
    ) -> PaneHeaderState {
        let title = displayIdentity?.title ?? descriptor?.displayTitle ?? "Session"
        let directoryName = descriptor?.workingDirectoryPath?.split(separator: "/").last.map(String.init)
        let secondaryLabel = displayIdentity?.contextLine ?? descriptor?.agentStatus.badgeLabel

        return PaneHeaderState(
            title: title,
            directoryName: directoryName,
            secondaryLabel: secondaryLabel == title ? nil : secondaryLabel,
            statusColorName: MvxStatusStyle.colorName(for: descriptor?.agentStatus ?? .none),
            isZoomed: isZoomed,
            isFocused: isFocused
        )
    }
}

private struct PaneHeaderView: View {
    let state: PaneHeaderState
    let payload: String
    let paneID: UUID
    let workspace: SessionWorkspace
    let onAction: ((UUID, WorkspaceCommand) -> Void)?
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                if let statusColorName = state.statusColorName {
                    Circle()
                        .fill(MvxStatusStyle.color(forLegacyAgentColorName: statusColorName))
                        .frame(width: 7, height: 7)
                }

                Text(state.title)
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundStyle(state.isFocused ? .primary : .secondary)
                    .lineLimit(1)

                if let secondaryLabel = state.secondaryLabel {
                    Text(secondaryLabel)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if isHovered {
                HStack(spacing: 4) {
                    paneActionButton(.splitVertical)
                    paneActionButton(.splitHorizontal)
                    paneActionButton(
                        .zoomPane,
                        symbolName: state.isZoomed ? WorkspaceCommand.exitZoom.symbolName : WorkspaceCommand.zoomPane.symbolName,
                        tooltip: state.isZoomed ? WorkspaceCommand.exitZoom.title : WorkspaceCommand.zoomPane.title
                    )
                    paneActionButton(.closePane, symbolSize: 9, weight: .bold)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(state.isFocused ? MvxSurface.toolbar : MvxSurface.raised)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(state.isFocused ? Color.accentColor.opacity(0.78) : Color.clear)
                .frame(height: 1)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            _ = workspace.focusPane(id: paneID)
        }
        .onDrag {
            _ = workspace.focusPane(id: paneID)
            return NSItemProvider(object: payload as NSString)
        }
    }

    private func paneActionButton(
        _ command: WorkspaceCommand,
        symbolName: String? = nil,
        tooltip: String? = nil,
        symbolSize: CGFloat = 11,
        weight: Font.Weight = .medium
    ) -> some View {
        Button {
            _ = workspace.focusPane(id: paneID)
            onAction?(paneID, command)
        } label: {
            Image(systemName: symbolName ?? command.symbolName)
                .font(.system(size: symbolSize, weight: weight))
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: MvxRadius.control / 2, style: .continuous)
                        .fill(MvxSurface.hairline)
                )
        }
        .buttonStyle(.plain)
        .help(tooltip ?? command.title)
    }
}
