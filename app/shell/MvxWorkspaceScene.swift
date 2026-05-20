import SwiftUI

@MainActor
public struct MvxWorkspaceScene: View {
    @ObservedObject private var proxy: ActiveWorkspaceProxy
    @ObservedObject private var registry: WorkspaceRegistry
    @State private var isSidebarCollapsed = false
    private let terminalHostFactory: TerminalHostFactory

    public init(
        proxy: ActiveWorkspaceProxy,
        registry: WorkspaceRegistry,
        terminalHostFactory: TerminalHostFactory = .fallbackOnly
    ) {
        self.proxy = proxy
        self.registry = registry
        self.terminalHostFactory = terminalHostFactory
    }

    public var body: some View {
        if let workspace = proxy.workspace,
           let commandHandler = proxy.commandHandler {
            WorkspaceShellScaffold(isLeftPaneCollapsed: isSidebarCollapsed) {
                SessionSidebarView(
                    workspace: workspace,
                    commandHandler: commandHandler,
                    registry: registry,
                    onCollapse: toggleSidebarCollapsed
                )
            } collapsedLeftPane: {
                sidebarRevealStrip
            } centerPane: {
                VStack(spacing: 0) {
                    CenterToolbarView(workspace: workspace, commandHandler: commandHandler)

                    Divider()

                    TilingWorkspaceView(
                        workspace: workspace,
                        terminalHostFactory: terminalHostFactory
                    )
                }
                .sheet(
                    isPresented: Binding(
                        get: { commandHandler.isCommandPalettePresented },
                        set: { isPresented in
                            if isPresented {
                                commandHandler.isCommandPalettePresented = true
                            } else {
                                commandHandler.dismissCommandPalette()
                            }
                        }
                    )
                ) {
                    CommandPaletteView(commandHandler: commandHandler)
                }
            }
            .id(proxy.activeWorkspaceID)
            .frame(minWidth: 750, minHeight: 760)
        } else {
            Text("No Active Workspace")
                .frame(minWidth: 750, minHeight: 760)
        }
    }

    private var sidebarRevealStrip: some View {
        VStack(spacing: 0) {
            Text("MVX")
                .font(.system(.caption, design: .monospaced).weight(.heavy))
                .tracking(4)
                .foregroundStyle(.secondary)
                .padding(.top, 20)

            Spacer()

            Button(action: toggleSidebarCollapsed) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show Sidebar")
            .help("Show Sidebar")
        }
        .background(Color(red: 0.10, green: 0.10, blue: 0.09))
        .overlay(alignment: .trailing) {
            Divider()
        }
    }

    private func toggleSidebarCollapsed() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isSidebarCollapsed.toggle()
        }
    }
}
