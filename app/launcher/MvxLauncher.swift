import SwiftUI
import Mvx

@main
struct MvxLauncher: App {
    @StateObject private var workspace: SessionWorkspace
    @StateObject private var commandHandler: WorkspaceCommandHandler
    @StateObject private var updateController: ReleaseUpdateController
    private let workspacePersistence: WorkspacePersistence
    private let workspaceAutosaveController: WorkspaceAutosaveController
    private let terminalHostFactory: TerminalHostFactory
    private let blockedMessage: String?
    private let blockedDetails: [String]

    init() {
        let resolvedPersistence = WorkspacePersistence()
        let resolvedUpdateController = ReleaseUpdateController()

        switch LauncherTerminalBootstrap.resolve() {
        case .ready(let sessionFactory, let terminalHostFactory):
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
            self.workspaceAutosaveController = WorkspaceAutosaveController(
                workspace: resolvedWorkspace,
                persistence: resolvedPersistence
            )
            self.terminalHostFactory = terminalHostFactory
            self.blockedMessage = nil
            self.blockedDetails = []
            _workspace = StateObject(wrappedValue: resolvedWorkspace)
            _updateController = StateObject(wrappedValue: resolvedUpdateController)
            _commandHandler = StateObject(
                wrappedValue: WorkspaceCommandHandler(
                    workspace: resolvedWorkspace,
                    updateController: resolvedUpdateController
                )
            )

        case .blocked(let message, let details):
            let resolvedWorkspace = SessionWorkspace(
                startsWithSession: false,
                sessionFactory: SessionWorkspace.unsupportedSessionFactory()
            )

            self.workspacePersistence = resolvedPersistence
            self.workspaceAutosaveController = WorkspaceAutosaveController(
                workspace: resolvedWorkspace,
                persistence: resolvedPersistence
            )
            self.terminalHostFactory = .fallbackOnly
            self.blockedMessage = message
            self.blockedDetails = details
            _workspace = StateObject(wrappedValue: resolvedWorkspace)
            _updateController = StateObject(wrappedValue: resolvedUpdateController)
            _commandHandler = StateObject(
                wrappedValue: WorkspaceCommandHandler(
                    workspace: resolvedWorkspace,
                    updateController: resolvedUpdateController
                )
            )
        }
    }

    var body: some Scene {
        WindowGroup {
            if let blockedMessage {
                NativeRuntimeUnavailableView(message: blockedMessage, details: blockedDetails)
            } else {
                MvxWorkspaceScene(
                    workspace: workspace,
                    commandHandler: commandHandler,
                    terminalHostFactory: terminalHostFactory
                )
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    try? workspaceAutosaveController.persistNow()
                }
            }
        }
        .commands {
            WorkspaceCommands(commandHandler: commandHandler)
        }
    }
}

private enum LauncherBootstrapResult {
    case ready(
        sessionFactory: () -> TerminalSession,
        terminalHostFactory: TerminalHostFactory
    )
    case blocked(message: String, details: [String])
}

private enum LauncherTerminalBootstrap {
    static func resolve() -> LauncherBootstrapResult {
        let details = [
            "Expected: vendor/ghostty/GhosttyKit.xcframework",
            "Expected resources: vendor/ghostty/resources/ghostty",
            "Expected resources: vendor/ghostty/resources/terminfo",
            "Expected resources: vendor/ghostty/resources/shell-integration",
        ]

        do {
            let resolvedPreferences = ConfigStore().load()
            let resolvedRenderConfiguration = resolvedPreferences.resolvedRenderConfiguration()
            let supportPaths = try GhosttySupportPaths.default()
            GhosttyAppRuntime.shared.startIfNeeded(supportPaths: supportPaths)
            guard GhosttyAppRuntime.shared.isAvailable else {
                let message = GhosttyAppRuntime.shared.initializationError
                    ?? "The native Ghostty runtime could not be initialized."
                return .blocked(message: message, details: details)
            }

            let sessionFactory = {
                TerminalSession(
                    driver: NativeGhosttySessionDriver(
                        adapter: TerminalAdapter(renderConfiguration: resolvedRenderConfiguration),
                        supportPaths: supportPaths
                    ),
                    backendKind: .nativeGhostty
                )
            }
            let hostFactory = TerminalHostFactory.native(
                { session, isFocused, onFocusRequest in
                    AnyView(
                        NativeGhosttyTerminalView(
                            session: session,
                            isFocused: isFocused,
                            onFocusRequest: onFocusRequest
                        )
                    )
                },
                scheduleGeometryReconcile: {
                    NativeGhosttyGeometryCoordinator.shared.scheduleGeometryReconcile()
                },
                scheduleMovedTerminalRefresh: {
                    NativeGhosttyGeometryCoordinator.shared.scheduleMovedTerminalRefresh()
                }
            )
            return .ready(
                sessionFactory: sessionFactory,
                terminalHostFactory: hostFactory
            )
        } catch {
            return .blocked(
                message: error.localizedDescription,
                details: details
            )
        }
    }
}
