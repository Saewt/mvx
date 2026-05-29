import AppKit
import Darwin
import SwiftUI
import Mvx

@main
struct MvxLauncher: App {
    @StateObject private var registry: WorkspaceRegistry
    @StateObject private var proxy: ActiveWorkspaceProxy
    @StateObject private var updateController: ReleaseUpdateController
    private let terminalHostFactory: TerminalHostFactory
    private let blockedMessage: String?
    private let blockedDetails: [String]

    init() {
        let resolvedPersistence = WorkspacePersistence()
        let resolvedUpdateController = ReleaseUpdateController()
        let resolvedSessionFactory: (URL?) -> TerminalSession
        let resolvedTerminalHostFactory: TerminalHostFactory
        let resolvedBlockedMessage: String?
        let resolvedBlockedDetails: [String]

        switch LauncherTerminalBootstrap.resolve() {
        case .ready(let sessionFactory, let terminalHostFactory):
            resolvedSessionFactory = sessionFactory
            resolvedTerminalHostFactory = terminalHostFactory
            resolvedBlockedMessage = nil
            resolvedBlockedDetails = []

        case .blocked(let message, let details):
            resolvedSessionFactory = { _ in SessionWorkspace.unsupportedSessionFactory()() }
            resolvedTerminalHostFactory = .fallbackOnly
            resolvedBlockedMessage = message
            resolvedBlockedDetails = details
        }

        let resolvedRegistry = WorkspaceRegistry(
            persistence: resolvedPersistence,
            workspaceFactory: { _ in
                SessionWorkspace(
                    startsWithSession: true,
                    sessionFactoryWithStartupDirectory: resolvedSessionFactory
                )
            }
        )
        Self.bootstrap(registry: resolvedRegistry, persistence: resolvedPersistence)

        let resolvedProxy = ActiveWorkspaceProxy(updateController: resolvedUpdateController)
        resolvedProxy.bind(to: resolvedRegistry)

        self.terminalHostFactory = resolvedTerminalHostFactory
        self.blockedMessage = resolvedBlockedMessage
        self.blockedDetails = resolvedBlockedDetails
        _registry = StateObject(wrappedValue: resolvedRegistry)
        _proxy = StateObject(wrappedValue: resolvedProxy)
        _updateController = StateObject(wrappedValue: resolvedUpdateController)
    }

var body: some Scene {
        WindowGroup {
            Group {
                if let blockedMessage {
                    NativeRuntimeUnavailableView(message: blockedMessage, details: blockedDetails)
                } else {
                    MvxWorkspaceScene(
                        proxy: proxy,
                        registry: registry,
                        terminalHostFactory: terminalHostFactory
                    )
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                try? registry.persistAll()
            }
            .task {
                try? await Task.sleep(nanoseconds: 3 * 1_000_000_000)
                updateController.scheduleAutoCheck {
                    proxy.commandHandler?.isUpdateSheetPresented = true
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
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

private enum LauncherBootstrapResult {
    case ready(
        sessionFactory: (URL?) -> TerminalSession,
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

            let sessionFactory: (URL?) -> TerminalSession = { startupDirectory in
                TerminalSession(
                    driver: NativeGhosttySessionDriver(
                        adapter: TerminalAdapter(renderConfiguration: resolvedRenderConfiguration),
                        startupDirectory: startupDirectory,
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
