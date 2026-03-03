import AppKit
import Foundation
import Mvx

final class NativeGhosttySessionDriver: TerminalSessionDriver {
    private var activityObservers: [UUID: () -> Void] = [:]
    private var agentStatusObservers: [UUID: (SessionAgentStatusUpdate) -> Void] = [:]
    private var runtimeEventObservers: [UUID: (SessionRuntimeEvent) -> Void] = [:]

    let adapter: TerminalAdapter
    let ptyBridge: PtyBridge
    let renderBridge: RenderBridge
    let inputBridge: InputBridge
    let clipboardBridge: ClipboardBridge
    let surfaceRuntime: GhosttySurfaceRuntime

    var isActive: Bool { surfaceRuntime.isStarted }
    private(set) var usesAlternateScreen = false
    private(set) var enabledMouseModes: Set<MouseTrackingMode> = []
    private(set) var latestAgentStatus: SessionAgentStatus = .none

    init(
        adapter: TerminalAdapter = TerminalAdapter(),
        ptyBridge: PtyBridge? = nil,
        renderBridge: RenderBridge = RenderBridge(),
        inputBridge: InputBridge = InputBridge(),
        clipboardBridge: ClipboardBridge = ClipboardBridge(),
        startupDirectory: URL? = nil,
        supportPaths: GhosttySupportPaths
    ) {
        self.adapter = adapter
        self.ptyBridge = ptyBridge ?? PtyBridge(startupDirectory: startupDirectory)
        self.renderBridge = renderBridge
        self.inputBridge = inputBridge
        self.clipboardBridge = clipboardBridge
        self.surfaceRuntime = GhosttySurfaceRuntime(
            sessionID: UUID(),
            supportPaths: supportPaths,
            startupDirectory: startupDirectory
        )

        _ = self.surfaceRuntime.addRuntimeEventObserver { [weak self] event in
            self?.notifyRuntimeEventObservers(event)
            self?.notifyActivityObservers()
        }
    }

    func start() {
        surfaceRuntime.startIfNeeded()
        notifyActivityObservers()
    }

    func stop() {
        surfaceRuntime.stop()
        notifyActivityObservers()
    }

    @discardableResult
    func sendUserInput(_ text: String) -> String {
        surfaceRuntime.sendText(text)
        notifyActivityObservers()
        return text
    }

    @discardableResult
    func handleKeyboard(_ command: KeyboardCommand, selection: String?) -> String {
        switch command {
        case .commandC:
            _ = surfaceRuntime.performBindingAction("copy_to_clipboard")
            return selection ?? ""
        case .commandV:
            if surfaceRuntime.performBindingAction("paste_from_clipboard") {
                return clipboardBridge.paste()
            }

            let pasted = clipboardBridge.paste()
            surfaceRuntime.pasteText(pasted)
            notifyActivityObservers()
            return pasted
        default:
            return ""
        }
    }

    @discardableResult
    func handleMouse(_ event: MouseEvent) -> String {
        _ = event
        return ""
    }

    func enableMouseModes(_ modes: Set<MouseTrackingMode>) {
        enabledMouseModes = modes
    }

    func setAlternateScreen(_ enabled: Bool) {
        usesAlternateScreen = enabled
    }

    func resize(columns: Int, rows: Int, pixelWidth: Int, pixelHeight: Int) {
        _ = columns
        _ = rows
        _ = pixelWidth
        _ = pixelHeight

        guard surfaceRuntime.isAttached else {
            return
        }

        surfaceRuntime.resize(
            bounds: surfaceRuntime.lastBounds,
            backingScaleFactor: surfaceRuntime.lastBackingScaleFactor
        )
    }

    func injectOutput(_ text: String) {
        _ = text
    }

    func processOSC52(_ sequence: String) -> OSC52Response {
        clipboardBridge.handleOSC52(sequence)
    }

    @discardableResult
    func addActivityObserver(_ handler: @escaping () -> Void) -> UUID {
        let token = UUID()
        activityObservers[token] = handler
        return token
    }

    func removeActivityObserver(_ token: UUID) {
        activityObservers.removeValue(forKey: token)
    }

    @discardableResult
    func addAgentStatusObserver(_ handler: @escaping (SessionAgentStatusUpdate) -> Void) -> UUID {
        let token = UUID()
        agentStatusObservers[token] = handler
        return token
    }

    func removeAgentStatusObserver(_ token: UUID) {
        agentStatusObservers.removeValue(forKey: token)
    }

    @discardableResult
    func addRuntimeEventObserver(_ handler: @escaping (SessionRuntimeEvent) -> Void) -> UUID {
        let token = UUID()
        runtimeEventObservers[token] = handler
        return token
    }

    func removeRuntimeEventObserver(_ token: UUID) {
        runtimeEventObservers.removeValue(forKey: token)
    }

    func processAgentStatusEscapeSequence(_ sequence: String) -> SessionAgentStatusUpdate? {
        guard let update = SessionAgentStatusUpdate.parse(sequence) else {
            return nil
        }

        latestAgentStatus = update.status
        for observer in agentStatusObservers.values {
            observer(update)
        }
        return update
    }

    func currentPromptVisible() -> Bool {
        true
    }

    func clipboardContents() -> String {
        clipboardBridge.paste()
    }

    private func notifyActivityObservers() {
        for observer in activityObservers.values {
            observer()
        }
    }

    private func notifyRuntimeEventObservers(_ event: SessionRuntimeEvent) {
        for observer in runtimeEventObservers.values {
            observer(event)
        }
    }
}
