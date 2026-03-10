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
        self.leftRailWidth = leftRailWidth
        self.collapsedRailWidth = collapsedRailWidth
        self.centerMinimumWidth = centerMinimumWidth
        self.primaryRegionCount = primaryRegionCount
    }

    public static let wantedUI = WorkspaceShellLayoutSpec(
        leftRailWidth: 230,
        collapsedRailWidth: 24,
        centerMinimumWidth: 420,
        primaryRegionCount: 2
    )
}

public struct WorkspaceSidebarVisibilityState: Equatable {
    public let visibleLeftWidth: CGFloat
    public let showsExpandedSidebar: Bool
    public let showsStandaloneDivider: Bool

    public init(layout: WorkspaceShellLayoutSpec, isCollapsed: Bool) {
        if isCollapsed {
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

    @MainActor
    public static func resolve(workspace: SessionWorkspace) -> SessionRailChromeState {
        SessionRailChromeState(
            topActions: [
                TopAction(
                    command: .commandPalette,
                    symbolName: WorkspaceCommand.commandPalette.symbolName,
                    tooltip: WorkspaceCommand.commandPalette.title,
                    isEnabled: true
                ),
                TopAction(
                    command: .nextAttention,
                    symbolName: WorkspaceCommand.nextAttention.symbolName,
                    tooltip: WorkspaceCommand.nextAttention.title,
                    isEnabled: workspace.nextAttentionSessionID() != nil
                ),
                TopAction(
                    command: .newTab,
                    symbolName: WorkspaceCommand.newTab.symbolName,
                    tooltip: WorkspaceCommand.newTab.title,
                    isEnabled: true
                ),
            ],
            sessionCount: workspace.sessions.count,
            activeSessionTitle: workspace.activeDescriptor?.displayTitle,
            attentionCount: workspace.sessions.filter { $0.agentStatus.needsAttention }.count
        )
    }
}

public struct WorkspaceShellScaffold<LeftPane: View, CenterPane: View>: View {
    private let layout: WorkspaceShellLayoutSpec
    private let isLeftPaneCollapsed: Bool
    private let leftPane: LeftPane
    private let collapsedLeftPane: AnyView?
    private let centerPane: CenterPane

    public init(
        layout: WorkspaceShellLayoutSpec = .wantedUI,
        @ViewBuilder leftPane: () -> LeftPane,
        @ViewBuilder centerPane: () -> CenterPane
    ) {
        self.layout = layout
        self.isLeftPaneCollapsed = false
        self.leftPane = leftPane()
        self.collapsedLeftPane = nil
        self.centerPane = centerPane()
    }

    public init<CollapsedLeftPane: View>(
        layout: WorkspaceShellLayoutSpec = .wantedUI,
        isLeftPaneCollapsed: Bool,
        @ViewBuilder leftPane: () -> LeftPane,
        @ViewBuilder collapsedLeftPane: () -> CollapsedLeftPane,
        @ViewBuilder centerPane: () -> CenterPane
    ) {
        self.layout = layout
        self.isLeftPaneCollapsed = isLeftPaneCollapsed
        self.leftPane = leftPane()
        self.collapsedLeftPane = AnyView(collapsedLeftPane())
        self.centerPane = centerPane()
    }

    public var body: some View {
        let visibility = WorkspaceSidebarVisibilityState(
            layout: layout,
            isCollapsed: isLeftPaneCollapsed
        )

        HStack(spacing: 0) {
            Group {
                if visibility.showsExpandedSidebar {
                    leftPane
                } else if let collapsedLeftPane {
                    collapsedLeftPane
                } else {
                    EmptyView()
                }
            }
            .frame(width: visibility.visibleLeftWidth)

            if visibility.showsStandaloneDivider {
                Divider()
            }

            centerPane
                .frame(minWidth: layout.centerMinimumWidth, maxWidth: .infinity)
                .layoutPriority(1)
        }
        .background(Color(red: 0.10, green: 0.10, blue: 0.09))
    }
}
