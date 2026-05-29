import SwiftUI

@MainActor
public struct MvxWorkspaceScene: View {
    @ObservedObject private var proxy: ActiveWorkspaceProxy
    @ObservedObject private var registry: WorkspaceRegistry
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
            WorkspaceBodyView(
                workspace: workspace,
                commandHandler: commandHandler,
                registry: registry,
                terminalHostFactory: terminalHostFactory
            )
            .id(proxy.activeWorkspaceID)
            .frame(minWidth: 750, minHeight: 760)
            .background(WindowAccessor())
        } else {
            Text("No Active Workspace")
                .frame(minWidth: 750, minHeight: 760)
                .background(WindowAccessor())
        }
    }
}

@MainActor
private struct WorkspaceBodyView: View {
    @ObservedObject var workspace: SessionWorkspace
    @ObservedObject var commandHandler: WorkspaceCommandHandler
    @ObservedObject var registry: WorkspaceRegistry
    let terminalHostFactory: TerminalHostFactory
    private let configStore = ConfigStore()
    @State private var isSidebarCollapsed = false
    @State private var isFocusOverlayVisible = false
    @State private var focusOverlayHideTask: DispatchWorkItem? = nil
    @State private var sidebarWidth = CGFloat(ConfigStore().load().sidebarWidth)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            WorkspaceShellScaffold(
                layout: .wantedUI.withLeftRailWidth(sidebarWidth),
                isLeftPaneCollapsed: isSidebarCollapsed,
                isLeftPaneHidden: commandHandler.isFocusModeActive,
                onLeftRailWidthChanged: updateSidebarWidth,
                onLeftRailWidthChangeEnded: persistSidebarWidth
            ) {
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
                    TilingWorkspaceView(
                        workspace: workspace,
                        terminalHostFactory: terminalHostFactory,
                        zoomedPaneID: commandHandler.zoomedPaneID,
                        onPaneAction: { paneID, command in
                            _ = workspace.focusPane(id: paneID)
                            _ = commandHandler.perform(command)
                        }
                    )
                }
                .padding(.top, centerTopChromeInset)
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

            focusModeRevealOverlay
        }
        .animation(reduceMotion ? .none : MvxMotion.emphasized, value: commandHandler.isFocusModeActive)
        .onChange(of: workspace.workspaceGraph) { _ in
            commandHandler.exitZoom()
        }
        .onChange(of: commandHandler.zoomedPaneID) { _ in
            terminalHostFactory.scheduleMovedTerminalRefresh()
        }
        .onChange(of: commandHandler.isFocusModeActive) { newValue in
            focusOverlayHideTask?.cancel()
            focusOverlayHideTask = nil
            isFocusOverlayVisible = false
            terminalHostFactory.scheduleMovedTerminalRefresh()

            if !newValue {
                return
            }
        }
    }

    private var focusModeRevealOverlay: some View {
        Group {
            if commandHandler.isFocusModeActive {
                ZStack(alignment: .topLeading) {
                    focusRevealTriggerZone
                        .frame(height: 32)
                        .frame(maxWidth: .infinity, alignment: .top)

                    focusRevealTriggerZone
                        .frame(width: 24)
                        .frame(maxHeight: .infinity, alignment: .leading)

                    if isFocusOverlayVisible {
                        HStack(spacing: 10) {
                            Button {
                                commandHandler.perform(.toggleFocusMode)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: WorkspaceCommand.toggleFocusMode.symbolName)
                                        .font(.system(size: 11, weight: .semibold))

                                    Text("Exit Focus Mode")
                                        .font(.system(.caption, design: .rounded).weight(.medium))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Color.white.opacity(0.12))
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 6)
                            .padding(.leading, 28)
                        }
                    }
                }
            }
        }
        .onDisappear {
            focusOverlayHideTask?.cancel()
            focusOverlayHideTask = nil
            isFocusOverlayVisible = false
        }
    }

    @ViewBuilder
    private var focusRevealTriggerZone: some View {
        Color.clear
            .contentShape(Rectangle())
            .onHover { hovering in
                guard commandHandler.isFocusModeActive else {
                    return
                }

                if hovering {
                    focusOverlayHideTask?.cancel()
                    focusOverlayHideTask = nil
                    withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.16)) {
                        isFocusOverlayVisible = true
                    }
                    scheduleFocusOverlayAutoHide(delay: 2.5)
                } else {
                    scheduleFocusOverlayAutoHide(delay: 0.4)
                }
            }
    }

    private func scheduleFocusOverlayAutoHide(delay: TimeInterval) {
        focusOverlayHideTask?.cancel()
        let task = DispatchWorkItem {
            withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.16)) {
                isFocusOverlayVisible = false
            }
        }
        focusOverlayHideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }

    private var sidebarRevealStrip: some View {
        let chrome = SessionRailChromeState.resolve(workspace: workspace)
        return VStack(spacing: 0) {
            VStack(spacing: 2) {
                Text("M")
                Text("V")
                Text("X")
            }
            .font(MvxText.wordmark)
            .foregroundStyle(.secondary)
            .padding(.top, topLeadingInset / 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 5)

            if chrome.attentionCount > 0 {
                Button {
                    _ = commandHandler.perform(.nextAttention)
                } label: {
                    HStack(spacing: 2) {
                        Circle()
                            .fill(chrome.attentionIsError ? .red : .orange)
                            .frame(width: 6, height: 6)
                        Text("\(chrome.attentionCount)")
                            .font(MvxText.meta)
                            .foregroundStyle(chrome.attentionIsError ? .red : .orange)
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, MvxSpacing.xs)
                .help("Jump to next session needing attention (\(chrome.attentionCount))")
                .accessibilityLabel("Jump to next session needing attention (\(chrome.attentionCount))")
            }

            Spacer()

            Button(action: toggleSidebarCollapsed) {
                Image(systemName: "chevron.right")
                    .font(.system(size: MvxIcon.controlSymbolSize, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show Sidebar")
            .help("Show Sidebar")
        }
        .background(MvxSurface.sidebar)
        .overlay(alignment: .trailing) {
            Divider()
        }
    }

    private func toggleSidebarCollapsed() {
        withAnimation(reduceMotion ? .none : MvxMotion.emphasized) {
            isSidebarCollapsed.toggle()
        }
    }

    private func updateSidebarWidth(_ width: CGFloat) {
        sidebarWidth = WorkspaceShellLayoutSpec.clampedLeftRailWidth(width)
    }

    private func persistSidebarWidth(_ width: CGFloat) {
        let clampedWidth = WorkspaceShellLayoutSpec.clampedLeftRailWidth(width)
        sidebarWidth = clampedWidth

        var preferences = configStore.load()
        preferences.sidebarWidth = Double(clampedWidth)
        try? configStore.save(preferences)
    }

    private var topLeadingInset: CGFloat {
        78
    }

    private var focusModeTopChromeInset: CGFloat {
        32
    }

    private var centerTopChromeInset: CGFloat {
        commandHandler.isFocusModeActive ? focusModeTopChromeInset : 0
    }
}
