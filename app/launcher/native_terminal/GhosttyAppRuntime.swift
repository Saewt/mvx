import AppKit
import Foundation

final class GhosttyAppRuntime {
    static let shared = GhosttyAppRuntime()

    private(set) var isAvailable = false
    private(set) var initializationError: String?
    private(set) var app: ghostty_app_t?

    private var didAttemptStart = false
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var config: ghostty_config_t?

    private init() {}

    deinit {
        if let app {
            ghostty_app_free(app)
        }
        if let config {
            ghostty_config_free(config)
        }
        for observer in lifecycleObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func startIfNeeded(supportPaths: GhosttySupportPaths) {
        guard !didAttemptStart else {
            return
        }

        didAttemptStart = true
        registerAppLifecycleObservers()
        configureProcessEnvironment(supportPaths: supportPaths)
        isAvailable = false
        initializationError = nil

        let initResult = ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv)
        guard initResult == GHOSTTY_SUCCESS else {
            initializationError = "ghostty_init failed with status \(initResult)."
            return
        }

        guard let primaryConfig = ghostty_config_new() else {
            initializationError = "ghostty_config_new failed."
            return
        }

        ghostty_config_load_default_files(primaryConfig)
        ghostty_config_finalize(primaryConfig)

        var runtimeConfig = ghostty_runtime_config_s()
        runtimeConfig.userdata = Unmanaged.passUnretained(self).toOpaque()
        runtimeConfig.supports_selection_clipboard = true
        runtimeConfig.wakeup_cb = { userdata in
            guard let runtime = GhosttyAppRuntime.fromOpaque(userdata) else {
                return
            }

            DispatchQueue.main.async {
                runtime.tickIfNeeded()
            }
        }
        runtimeConfig.action_cb = { _, target, action in
            GhosttyAppRuntime.handleAction(target: target, action: action)
        }
        runtimeConfig.read_clipboard_cb = { userdata, location, state in
            GhosttySurfaceRuntime.completeClipboardRead(userdata: userdata, location: location, state: state)
        }
        runtimeConfig.confirm_read_clipboard_cb = { userdata, string, state, _ in
            GhosttySurfaceRuntime.completeConfirmedClipboardRead(
                userdata: userdata,
                string: string,
                state: state
            )
        }
        runtimeConfig.write_clipboard_cb = { _, location, content, len, _ in
            GhosttySurfaceRuntime.writeClipboard(location: location, content: content, count: len)
        }
        runtimeConfig.close_surface_cb = { userdata, needsConfirmClose in
            GhosttySurfaceRuntime.handleCloseSurfaceRequest(
                userdata: userdata,
                needsConfirmClose: needsConfirmClose
            )
        }

        if let createdApp = ghostty_app_new(&runtimeConfig, primaryConfig) {
            app = createdApp
            config = primaryConfig
            isAvailable = true
            updateAppFocus()
            tickIfNeeded()
            return
        }

        ghostty_config_free(primaryConfig)

        guard let fallbackConfig = ghostty_config_new() else {
            initializationError = "ghostty_app_new failed and fallback ghostty_config_new also failed."
            return
        }

        ghostty_config_finalize(fallbackConfig)

        if let createdApp = ghostty_app_new(&runtimeConfig, fallbackConfig) {
            app = createdApp
            config = fallbackConfig
            isAvailable = true
            updateAppFocus()
            tickIfNeeded()
            return
        }

        ghostty_config_free(fallbackConfig)
        initializationError = "ghostty_app_new failed for both primary and fallback configuration."
    }

    func tickIfNeeded() {
        guard let app else {
            return
        }

        ghostty_app_tick(app)
    }

    func registerAppLifecycleObservers() {
        guard lifecycleObservers.isEmpty else {
            return
        }

        lifecycleObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.updateAppFocus()
                self?.tickIfNeeded()
            }
        )
        lifecycleObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.updateAppFocus()
                self?.tickIfNeeded()
            }
        )
    }

    private func configureProcessEnvironment(supportPaths: GhosttySupportPaths) {
        unsetenv("NO_COLOR")
        setenv("GHOSTTY_RESOURCES_DIR", supportPaths.resourcesRoot.path, 1)
        setenv("TERM", "xterm-ghostty", 1)
        setenv("TERM_PROGRAM", "ghostty", 1)

        let existingXDGDataDirs = ProcessInfo.processInfo.environment["XDG_DATA_DIRS"]
        let updatedXDGDataDirs = prependPathComponent(
            supportPaths.resourcesRoot.deletingLastPathComponent().path,
            to: existingXDGDataDirs
        )
        setenv("XDG_DATA_DIRS", updatedXDGDataDirs, 1)

        let existingManPath = ProcessInfo.processInfo.environment["MANPATH"]
        let updatedManPath = prependPathComponent(
            supportPaths.resourcesRoot.deletingLastPathComponent().path,
            to: existingManPath
        )
        setenv("MANPATH", updatedManPath, 1)
    }

    private func prependPathComponent(_ component: String, to existingValue: String?) -> String {
        guard let existingValue, !existingValue.isEmpty else {
            return component
        }

        let parts = existingValue.split(separator: ":").map(String.init)
        guard !parts.contains(component) else {
            return existingValue
        }

        return ([component] + parts).joined(separator: ":")
    }

    private func updateAppFocus() {
        guard let app else {
            return
        }

        ghostty_app_set_focus(app, NSApp?.isActive ?? false)
    }

    private static func fromOpaque(_ opaque: UnsafeMutableRawPointer?) -> GhosttyAppRuntime? {
        guard let opaque else {
            return nil
        }

        return Unmanaged<GhosttyAppRuntime>.fromOpaque(opaque).takeUnretainedValue()
    }

    private static func handleAction(target: ghostty_target_s, action: ghostty_action_s) -> Bool {
        guard target.tag == GHOSTTY_TARGET_SURFACE,
              let surface = target.target.surface,
              let userdata = ghostty_surface_userdata(surface),
              let runtime = GhosttySurfaceRuntime.fromOpaque(userdata) else {
            return false
        }

        return runtime.handle(action: action)
    }
}
