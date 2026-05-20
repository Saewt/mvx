import AppKit
import Darwin
import SwiftUI

@MainActor
public struct MvxApp: App {
    @StateObject private var registry: WorkspaceRegistry
    @StateObject private var proxy: ActiveWorkspaceProxy
    @StateObject private var updateController: ReleaseUpdateController
    private let terminalHostFactory: TerminalHostFactory

    public init() {
        self.init(
            sessionFactory: SessionWorkspace.unsupportedSessionFactory(),
            terminalHostFactory: .fallbackOnly
        )
    }

    public init(
        sessionFactory: @escaping () -> TerminalSession,
        terminalHostFactory: TerminalHostFactory
    ) {
        self.init(
            sessionFactoryWithStartupDirectory: { _ in sessionFactory() },
            terminalHostFactory: terminalHostFactory
        )
    }

    public init(
        sessionFactoryWithStartupDirectory: @escaping (URL?) -> TerminalSession,
        terminalHostFactory: TerminalHostFactory
    ) {
        let resolvedPersistence = WorkspacePersistence()
        let resolvedUpdateController = ReleaseUpdateController()
        let resolvedRegistry = WorkspaceRegistry(
            persistence: resolvedPersistence,
            workspaceFactory: { _ in
                SessionWorkspace(
                    startsWithSession: true,
                    sessionFactoryWithStartupDirectory: sessionFactoryWithStartupDirectory
                )
            }
        )
        Self.bootstrap(registry: resolvedRegistry, persistence: resolvedPersistence)

        let resolvedProxy = ActiveWorkspaceProxy(updateController: resolvedUpdateController)
        resolvedProxy.bind(to: resolvedRegistry)

        self.terminalHostFactory = terminalHostFactory
        _registry = StateObject(wrappedValue: resolvedRegistry)
        _proxy = StateObject(wrappedValue: resolvedProxy)
        _updateController = StateObject(wrappedValue: resolvedUpdateController)
    }

    public var body: some Scene {
        WindowGroup {
            MvxWorkspaceScene(
                proxy: proxy,
                registry: registry,
                terminalHostFactory: terminalHostFactory
            )
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                try? registry.persistAll()
            }
            .task {
                try? await Task.sleep(nanoseconds: 3 * 1_000_000_000)
                updateController.scheduleAutoCheck {
                    proxy.commandHandler?.isUpdateSheetPresented = true
                }
            }
            .sheet(
                isPresented: Binding(
                    get: { proxy.commandHandler?.isUpdateSheetPresented ?? false },
                    set: { isPresented in
                        if isPresented {
                            proxy.commandHandler?.isUpdateSheetPresented = true
                        } else {
                            proxy.commandHandler?.dismissUpdateSheet()
                        }
                    }
                )
            ) {
                if let commandHandler = proxy.commandHandler {
                    UpdateView(
                        controller: commandHandler.updateController ?? ReleaseUpdateController(),
                        onClose: { commandHandler.isUpdateSheetPresented = false },
                        onRestartRequested: {
                            Self.performUpdateRestart(
                                registry: registry,
                                commandHandler: commandHandler
                            )
                        }
                    )
                }
            }
        }
        .commands {
            WorkspaceCommands(proxy: proxy)
        }
    }

    private static func bootstrap(registry: WorkspaceRegistry, persistence: WorkspacePersistence) {
        if let registrySnapshot = persistence.loadRegistry(),
           registry.restore(from: registrySnapshot),
           !registry.entries.isEmpty {
            return
        }

        if let savedSnapshot = persistence.load() {
            let entry = registry.createWorkspace(name: "Workspace 1")
            _ = registry.workspace(for: entry.id)?.restore(from: savedSnapshot)
            try? registry.persistAll()
            return
        }

        _ = registry.createWorkspace(name: "Workspace 1")
    }

    private static func performUpdateRestart(
        registry: WorkspaceRegistry,
        commandHandler: WorkspaceCommandHandler
    ) {
        commandHandler.isUpdateSheetPresented = false
        try? registry.persistAll()
        NSApplication.shared.terminate(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            Darwin.exit(0)
        }
    }
}

public struct NativeRuntimeUnavailableView: View {
    private let message: String
    private let details: [String]

    public init(message: String, details: [String]) {
        self.message = message
        self.details = details
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Ghostty runtime unavailable")
                .font(.system(size: 28, weight: .semibold, design: .rounded))

            Text(message)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(details, id: \.self) { detail in
                    Text(detail)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )

            Button("Quit mvx") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)

            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(minWidth: 860, minHeight: 520, alignment: .topLeading)
        .background(Color(red: 0.09, green: 0.09, blue: 0.10))
    }
}

public struct WorkspaceCommands: Commands {
    @ObservedObject public var proxy: ActiveWorkspaceProxy

    public init(proxy: ActiveWorkspaceProxy) {
        self.proxy = proxy
    }

    public var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates") {
                perform(.checkForUpdates)
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])
            .disabled(commandHandler == nil)
        }

        CommandMenu("Workspace") {
            Button("Command Palette") {
                perform(.commandPalette)
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(commandHandler == nil)

            Divider()

            Button("New Window") {
                perform(.newWindow)
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(commandHandler == nil)

            Button("New Tab") {
                perform(.newTab)
            }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(commandHandler == nil)

            Divider()

            Button("Close Session") {
                perform(.closeCurrentSession)
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(commandHandler == nil)

            Button("Close Pane") {
                perform(.closePane)
            }
            .keyboardShortcut("w", modifiers: [.command, .option])
            .disabled(commandHandler == nil)

            Button("Split Vertical") {
                perform(.splitVertical)
            }
            .keyboardShortcut("\\", modifiers: [.command, .shift])
            .disabled(commandHandler == nil)

            Button("Split Horizontal") {
                perform(.splitHorizontal)
            }
            .keyboardShortcut("-", modifiers: [.command, .shift])
            .disabled(commandHandler == nil)

            Button("Next Pane") {
                perform(.nextPane)
            }
            .keyboardShortcut("]", modifiers: [.command, .option])
            .disabled(commandHandler == nil)

            Button("Previous Pane") {
                perform(.previousPane)
            }
            .keyboardShortcut("[", modifiers: [.command, .option])
            .disabled(commandHandler == nil)

            Button("Next Session") {
                perform(.nextSession)
            }
            .keyboardShortcut("`", modifiers: .command)
            .disabled(commandHandler == nil)

            Button("Next Session Needing Attention") {
                perform(.nextAttention)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(commandHandler == nil)

            Divider()

            Button("Close Done Sessions in Active Group") {
                perform(.closeDoneSessionsInActiveGroup)
            }
            .disabled(commandHandler == nil)

            Button("Close All Sessions in Active Group") {
                perform(.closeAllSessionsInActiveGroup)
            }
            .disabled(commandHandler == nil)

            Button("Move Active Group Sessions to Ungrouped") {
                perform(.moveActiveGroupToUngrouped)
            }
            .disabled(commandHandler == nil)

            Button("Collapse Other Groups") {
                perform(.collapseOtherGroups)
            }
            .disabled(commandHandler == nil)

            Divider()

            Button("Copy") {
                perform(.copy)
            }
            .keyboardShortcut("c", modifiers: .command)
            .disabled(commandHandler == nil)

            Button("Paste") {
                perform(.paste)
            }
            .keyboardShortcut("v", modifiers: .command)
            .disabled(commandHandler == nil)

            Button("Select All") {
                perform(.selectAll)
            }
            .keyboardShortcut("a", modifiers: .command)
            .disabled(commandHandler == nil)

            Divider()

            Button("Quit mvx") {
                perform(.quit)
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
            .disabled(commandHandler == nil)
        }
    }

    private var commandHandler: WorkspaceCommandHandler? {
        proxy.commandHandler
    }

    private func perform(_ command: WorkspaceCommand) {
        _ = commandHandler?.perform(command)
    }
}
