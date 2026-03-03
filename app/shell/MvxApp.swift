import AppKit
import SwiftUI

@MainActor
public struct MvxApp: App {
    @StateObject private var workspace: SessionWorkspace
    @StateObject private var commandHandler: WorkspaceCommandHandler
    @StateObject private var updateController: ReleaseUpdateController
    private let workspacePersistence: WorkspacePersistence
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
        let resolvedConfigStore = ConfigStore()
        _ = resolvedConfigStore.load()
        let resolvedPersistence = WorkspacePersistence()
        let resolvedWorkspace = SessionWorkspace(
            startsWithSession: false,
            sessionFactory: sessionFactory
        )

        if let savedSnapshot = resolvedPersistence.load() {
            let restored = resolvedWorkspace.restore(from: savedSnapshot)
            if !restored {
                _ = resolvedWorkspace.createSession()
            }
        } else {
            _ = resolvedWorkspace.createSession()
        }

        self.workspacePersistence = resolvedPersistence
        self.terminalHostFactory = terminalHostFactory
        let resolvedUpdateController = ReleaseUpdateController()
        _workspace = StateObject(wrappedValue: resolvedWorkspace)
        _updateController = StateObject(wrappedValue: resolvedUpdateController)
        _commandHandler = StateObject(
            wrappedValue: WorkspaceCommandHandler(
                workspace: resolvedWorkspace,
                updateController: resolvedUpdateController
            )
        )
    }

    public var body: some Scene {
        WindowGroup {
            MvxWorkspaceScene(
                workspace: workspace,
                commandHandler: commandHandler,
                terminalHostFactory: terminalHostFactory
            )
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                try? workspacePersistence.save(workspace.snapshot())
            }
        }
        .commands {
            WorkspaceCommands(commandHandler: commandHandler)
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
    @ObservedObject public var commandHandler: WorkspaceCommandHandler

    public init(commandHandler: WorkspaceCommandHandler) {
        self.commandHandler = commandHandler
    }

    public var body: some Commands {
        CommandMenu("Workspace") {
            Button("Command Palette") {
                _ = commandHandler.perform(.commandPalette)
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])

            Divider()

            Button("New Window") {
                _ = commandHandler.perform(.newWindow)
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("New Tab") {
                _ = commandHandler.perform(.newTab)
            }
            .keyboardShortcut("t", modifiers: .command)

            Divider()

            Button("Close Session") {
                _ = commandHandler.perform(.closeCurrentSession)
            }
            .keyboardShortcut("w", modifiers: .command)

            Button("Close Pane") {
                _ = commandHandler.perform(.closePane)
            }
            .keyboardShortcut("w", modifiers: [.command, .option])

            Button("Split Vertical") {
                _ = commandHandler.perform(.splitVertical)
            }
            .keyboardShortcut("\\", modifiers: [.command, .shift])

            Button("Split Horizontal") {
                _ = commandHandler.perform(.splitHorizontal)
            }
            .keyboardShortcut("-", modifiers: [.command, .shift])

            Button("Next Pane") {
                _ = commandHandler.perform(.nextPane)
            }
            .keyboardShortcut("]", modifiers: [.command, .option])

            Button("Previous Pane") {
                _ = commandHandler.perform(.previousPane)
            }
            .keyboardShortcut("[", modifiers: [.command, .option])

            Button("Next Session") {
                _ = commandHandler.perform(.nextSession)
            }
            .keyboardShortcut("`", modifiers: .command)

            Button("Next Session Needing Attention") {
                _ = commandHandler.perform(.nextAttention)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Divider()

            Button("Copy") {
                _ = commandHandler.perform(.copy)
            }
            .keyboardShortcut("c", modifiers: .command)

            Button("Paste") {
                _ = commandHandler.perform(.paste)
            }
            .keyboardShortcut("v", modifiers: .command)

            Button("Select All") {
                _ = commandHandler.perform(.selectAll)
            }
            .keyboardShortcut("a", modifiers: .command)

            Divider()

            Button("Quit mvx") {
                _ = commandHandler.perform(.quit)
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}
