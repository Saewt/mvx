import SwiftUI

public struct WorkspaceShellLayoutSpec: Equatable {
    public let leftRailWidth: CGFloat
    public let collapsedRailWidth: CGFloat
    public let centerMinimumWidth: CGFloat
    public let primaryRegionCount: Int

    public init(
        leftRailWidth: CGFloat,
        collapsedRailWidth: CGFloat,
        centerMinimumWidth: CGFloat,
        primaryRegionCount: Int
    ) {
        self.leftRailWidth = Self.clampedLeftRailWidth(leftRailWidth)
        self.collapsedRailWidth = collapsedRailWidth
        self.centerMinimumWidth = centerMinimumWidth
        self.primaryRegionCount = primaryRegionCount
    }

    public static let wantedUI = WorkspaceShellLayoutSpec(
        leftRailWidth: CGFloat(AppPreferences.defaultSidebarWidth),
        collapsedRailWidth: 24,
        centerMinimumWidth: 420,
        primaryRegionCount: 2
    )

    public static func clampedLeftRailWidth(_ width: CGFloat) -> CGFloat {
        CGFloat(AppPreferences.clampedSidebarWidth(Double(width)))
    }

    public func withLeftRailWidth(_ width: CGFloat) -> WorkspaceShellLayoutSpec {
        WorkspaceShellLayoutSpec(
            leftRailWidth: width,
            collapsedRailWidth: collapsedRailWidth,
            centerMinimumWidth: centerMinimumWidth,
            primaryRegionCount: primaryRegionCount
        )
    }
}

public struct WorkspaceSidebarVisibilityState: Equatable {
    public let visibleLeftWidth: CGFloat
    public let showsExpandedSidebar: Bool
    public let showsStandaloneDivider: Bool

    public init(layout: WorkspaceShellLayoutSpec, isCollapsed: Bool) {
        self.init(layout: layout, isCollapsed: isCollapsed, isHidden: false)
    }

    public init(layout: WorkspaceShellLayoutSpec, isCollapsed: Bool, isHidden: Bool) {
        if isHidden {
            visibleLeftWidth = 0
            showsExpandedSidebar = false
            showsStandaloneDivider = false
        } else if isCollapsed {
            visibleLeftWidth = layout.collapsedRailWidth
            showsExpandedSidebar = false
            showsStandaloneDivider = false
        } else {
            visibleLeftWidth = layout.leftRailWidth
            showsExpandedSidebar = true
            showsStandaloneDivider = true
        }
    }
}

public struct SessionRailChromeState: Equatable {
    public struct TopAction: Equatable, Identifiable {
        public let command: WorkspaceCommand
        public let symbolName: String
        public let tooltip: String
        public let isEnabled: Bool

        public var id: WorkspaceCommand {
            command
        }

        public init(
            command: WorkspaceCommand,
            symbolName: String,
            tooltip: String,
            isEnabled: Bool
        ) {
            self.command = command
            self.symbolName = symbolName
            self.tooltip = tooltip
            self.isEnabled = isEnabled
        }
    }

    public let topActions: [TopAction]
    public let sessionCount: Int
    public let activeSessionTitle: String?
    public let attentionCount: Int
    public let attentionIsError: Bool

    @MainActor
    public static func resolve(workspace: SessionWorkspace) -> SessionRailChromeState {
        let attentionSessions = workspace.sessions.filter { $0.agentStatus.needsAttention }
        return SessionRailChromeState(
            topActions: [
                TopAction(
                    command: .newTab,
                    symbolName: WorkspaceCommand.newTab.symbolName,
                    tooltip: WorkspaceCommand.newTab.title,
                    isEnabled: true
                ),
            ],
            sessionCount: workspace.sessions.count,
            activeSessionTitle: workspace.activeDescriptor?.displayTitle,
            attentionCount: attentionSessions.count,
            attentionIsError: attentionSessions.contains { $0.agentStatus == .error }
        )
    }
}

public struct WorkspaceShellScaffold<LeftPane: View, CenterPane: View>: View {
    private let layout: WorkspaceShellLayoutSpec
    private let isLeftPaneCollapsed: Bool
    private let isLeftPaneHidden: Bool
    private let leftPane: LeftPane
    private let collapsedLeftPane: AnyView?
    private let centerPane: CenterPane
    private let onLeftRailWidthChanged: ((CGFloat) -> Void)?
    private let onLeftRailWidthChangeEnded: ((CGFloat) -> Void)?

    public init(
        layout: WorkspaceShellLayoutSpec = .wantedUI,
        onLeftRailWidthChanged: ((CGFloat) -> Void)? = nil,
        onLeftRailWidthChangeEnded: ((CGFloat) -> Void)? = nil,
        @ViewBuilder leftPane: () -> LeftPane,
        @ViewBuilder centerPane: () -> CenterPane
    ) {
        self.layout = layout
        self.isLeftPaneCollapsed = false
        self.isLeftPaneHidden = false
        self.leftPane = leftPane()
        self.collapsedLeftPane = nil
        self.centerPane = centerPane()
        self.onLeftRailWidthChanged = onLeftRailWidthChanged
        self.onLeftRailWidthChangeEnded = onLeftRailWidthChangeEnded
    }

    public init<CollapsedLeftPane: View>(
        layout: WorkspaceShellLayoutSpec = .wantedUI,
        isLeftPaneCollapsed: Bool,
        isLeftPaneHidden: Bool = false,
        onLeftRailWidthChanged: ((CGFloat) -> Void)? = nil,
        onLeftRailWidthChangeEnded: ((CGFloat) -> Void)? = nil,
        @ViewBuilder leftPane: () -> LeftPane,
        @ViewBuilder collapsedLeftPane: () -> CollapsedLeftPane,
        @ViewBuilder centerPane: () -> CenterPane
    ) {
        self.layout = layout
        self.isLeftPaneCollapsed = isLeftPaneCollapsed
        self.isLeftPaneHidden = isLeftPaneHidden
        self.leftPane = leftPane()
        self.collapsedLeftPane = AnyView(collapsedLeftPane())
        self.centerPane = centerPane()
        self.onLeftRailWidthChanged = onLeftRailWidthChanged
        self.onLeftRailWidthChangeEnded = onLeftRailWidthChangeEnded
    }

    public var body: some View {
        let visibility = WorkspaceSidebarVisibilityState(
            layout: layout,
            isCollapsed: isLeftPaneCollapsed,
            isHidden: isLeftPaneHidden
        )

        HStack(spacing: 0) {
            Group {
                if visibility.showsExpandedSidebar {
                    leftPane
                } else if let collapsedLeftPane, !isLeftPaneHidden {
                    collapsedLeftPane
                } else {
                    EmptyView()
                }
            }
            .frame(width: visibility.visibleLeftWidth)

            if visibility.showsStandaloneDivider {
                SidebarResizeHandle(
                    currentWidth: layout.leftRailWidth,
                    onWidthChanged: onLeftRailWidthChanged,
                    onWidthChangeEnded: onLeftRailWidthChangeEnded
                )
            }

            centerPane
                .frame(minWidth: layout.centerMinimumWidth, maxWidth: .infinity)
                .layoutPriority(1)
        }
        .background(MvxSurface.base)
    }
}

private struct SidebarResizeHandle: View {
    let currentWidth: CGFloat
    let onWidthChanged: ((CGFloat) -> Void)?
    let onWidthChangeEnded: ((CGFloat) -> Void)?

    @State private var dragStartWidth: CGFloat?
    @State private var isHovered = false
    @State private var isDragging = false

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 6)
            .overlay(alignment: .center) {
                Rectangle()
                    .fill(dividerColor)
                    .frame(width: 2)
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if dragStartWidth == nil {
                            dragStartWidth = currentWidth
                        }
                        isDragging = true

                        let nextWidth = WorkspaceShellLayoutSpec.clampedLeftRailWidth(
                            (dragStartWidth ?? currentWidth) + value.translation.width
                        )
                        onWidthChanged?(nextWidth)
                    }
                    .onEnded { value in
                        let startWidth = dragStartWidth ?? currentWidth
                        let nextWidth = WorkspaceShellLayoutSpec.clampedLeftRailWidth(startWidth + value.translation.width)
                        dragStartWidth = nil
                        isDragging = false
                        onWidthChangeEnded?(nextWidth)
                    }
            )
            .animation(.easeInOut(duration: 0.14), value: isHovered)
            .animation(.easeInOut(duration: 0.12), value: isDragging)
    }

    private var dividerColor: Color {
        if isDragging {
            return Color.accentColor.opacity(0.9)
        }

        if isHovered {
            return Color.white.opacity(0.22)
        }

        return MvxSurface.hairline
    }
}
