import SwiftUI

@MainActor
public struct MvxWorkspaceScene: View {
    @ObservedObject private var workspace: SessionWorkspace
    @ObservedObject private var commandHandler: WorkspaceCommandHandler
    @State private var isSidebarCollapsed = false
    private let terminalHostFactory: TerminalHostFactory

    public init(
        workspace: SessionWorkspace,
        commandHandler: WorkspaceCommandHandler,
        terminalHostFactory: TerminalHostFactory = .fallbackOnly
    ) {
        self.workspace = workspace
        self.commandHandler = commandHandler
        self.terminalHostFactory = terminalHostFactory
    }

    public var body: some View {
        WorkspaceShellScaffold(isLeftPaneCollapsed: isSidebarCollapsed) {
            SessionSidebarView(
                workspace: workspace,
                commandHandler: commandHandler,
                onCollapse: toggleSidebarCollapsed
            )
        } collapsedLeftPane: {
            sidebarRevealStrip
        } centerPane: {
            VStack(spacing: 0) {
                centerToolbar

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
        .frame(minWidth: 750, minHeight: 760)
    }

    private var sidebarRevealStrip: some View {
        Button(action: toggleSidebarCollapsed) {
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show Sidebar")
        .help("Show Sidebar")
        .background(Color(red: 0.10, green: 0.10, blue: 0.09))
        .overlay(alignment: .trailing) {
            Divider()
        }
    }

    private var centerToolbar: some View {
        let descriptor = workspace.activeDescriptor

        return HStack(spacing: 12) {
            Image(systemName: "terminal")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(red: 0.88, green: 0.56, blue: 0.36))

            VStack(alignment: .leading, spacing: 2) {
                Text(descriptor?.displayTitle ?? "No Active Session")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .lineLimit(1)

                Text(descriptor?.workingDirectoryPath?.split(separator: "/").last.map(String.init) ?? "No context")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 8) {
                ForEach(commandHandler.paneCommands(), id: \.command) { cmd in
                    Button {
                        _ = commandHandler.perform(cmd.command)
                    } label: {
                        Image(systemName: cmd.command.symbolName)
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 24, height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.white.opacity(cmd.isEnabled ? 0.08 : 0.03))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!cmd.isEnabled)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(red: 0.10, green: 0.10, blue: 0.09))
    }

    private func toggleSidebarCollapsed() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isSidebarCollapsed.toggle()
        }
    }
}
