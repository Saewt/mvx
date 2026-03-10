import Foundation
@testable import Mvx

final class InMemoryTestTerminalDriver: TerminalSessionDriver {
    let adapter: TerminalAdapter
    let ptyBridge: PtyBridge
    let renderBridge: RenderBridge
    let inputBridge: InputBridge
    let clipboardBridge: ClipboardBridge

    private(set) var isActive = false
    private(set) var usesAlternateScreen = false
    private(set) var enabledMouseModes: Set<MouseTrackingMode> = []
    private(set) var latestAgentStatus: SessionAgentStatus = .none
    private(set) var sentInput: [String] = []
    private(set) var injectedOutput: [String] = []
    private(set) var windowSize = TerminalWindowSize()

    private var activityObservers: [UUID: () -> Void] = [:]
    private var agentStatusObservers: [UUID: (SessionAgentStatusUpdate) -> Void] = [:]
    private var runtimeEventObservers: [UUID: (SessionRuntimeEvent) -> Void] = [:]

    init(
        adapter: TerminalAdapter = TerminalAdapter(),
        ptyBridge: PtyBridge = PtyBridge(),
        renderBridge: RenderBridge = RenderBridge(),
        inputBridge: InputBridge = InputBridge(),
        clipboardBridge: ClipboardBridge = ClipboardBridge()
    ) {
        self.adapter = adapter
        self.ptyBridge = ptyBridge
        self.renderBridge = renderBridge
        self.inputBridge = inputBridge
        self.clipboardBridge = clipboardBridge
    }

    func start() {
        isActive = true
        notifyActivityObservers()
    }

    func stop() {
        isActive = false
        notifyActivityObservers()
    }

    @discardableResult
    func sendUserInput(_ text: String) -> String {
        sentInput.append(text)
        if let status = parsedAgentStatus(from: text) {
            _ = processAgentStatusEscapeSequence(status.sequence)
        }
        notifyActivityObservers()
        return text
    }

    @discardableResult
    func handleKeyboard(_ command: KeyboardCommand, selection: String?) -> String {
        let dispatch = inputBridge.dispatch(command, selection: selection)

        if dispatch.clipboardAction == .copySelection, let selection {
            clipboardBridge.copy(selection)
        } else if dispatch.clipboardAction == .pasteClipboard {
            let pasted = clipboardBridge.paste()
            if !pasted.isEmpty {
                sentInput.append(pasted)
                notifyActivityObservers()
            }
            return pasted
        } else if !dispatch.bytes.isEmpty {
            ptyBridge.recordProtocolPacket(dispatch.bytes)
        }

        notifyActivityObservers()
        return String(decoding: dispatch.bytes, as: UTF8.self)
    }

    @discardableResult
    func handleMouse(_ event: MouseEvent) -> String {
        let bytes = inputBridge.encodeMouse(event, enabledModes: enabledMouseModes)
        ptyBridge.recordProtocolPacket(bytes)
        let payload = String(decoding: bytes, as: UTF8.self)
        notifyActivityObservers()
        return payload
    }

    func enableMouseModes(_ modes: Set<MouseTrackingMode>) {
        enabledMouseModes = modes
    }

    func setAlternateScreen(_ enabled: Bool) {
        usesAlternateScreen = enabled
    }

    func resize(columns: Int, rows: Int, pixelWidth: Int, pixelHeight: Int) {
        windowSize = TerminalWindowSize(
            columns: columns,
            rows: rows,
            pixelSize: TerminalPixelSize(width: pixelWidth, height: pixelHeight)
        )
        ptyBridge.updateWindowSize(columns: columns, rows: rows, pixelWidth: pixelWidth, pixelHeight: pixelHeight)
    }

    func injectOutput(_ text: String) {
        injectedOutput.append(text)
        notifyActivityObservers()
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

    func emitRuntimeEvent(_ event: SessionRuntimeEvent) {
        for observer in runtimeEventObservers.values {
            observer(event)
        }
    }

    func emitAgentStatus(_ status: SessionAgentStatus) {
        _ = processAgentStatusEscapeSequence(SessionAgentStatusUpdate(status: status).sequence)
    }

    private func parsedAgentStatus(from command: String) -> SessionAgentStatusUpdate? {
        let tokens = command.split(whereSeparator: \.isWhitespace)
        guard let lastToken = tokens.last,
              let status = SessionAgentStatus(rawValue: String(lastToken)) else {
            return nil
        }

        return SessionAgentStatusUpdate(status: status)
    }

    private func notifyActivityObservers() {
        for observer in activityObservers.values {
            observer()
        }
    }
}

func makeTestSession(
    adapter: TerminalAdapter = TerminalAdapter(),
    ptyBridge: PtyBridge = PtyBridge(),
    renderBridge: RenderBridge = RenderBridge(),
    inputBridge: InputBridge = InputBridge(),
    clipboardBridge: ClipboardBridge = ClipboardBridge()
) -> TerminalSession {
    TerminalSession(
        driver: InMemoryTestTerminalDriver(
            adapter: adapter,
            ptyBridge: ptyBridge,
            renderBridge: renderBridge,
            inputBridge: inputBridge,
            clipboardBridge: clipboardBridge
        ),
        backendKind: .nativeGhostty
    )
}

func makeTestWorkspace(
    autoStartSessions: Bool = true,
    startsWithSession: Bool = true,
    sessionFactoryWithStartupDirectory: ((URL?) -> TerminalSession)? = nil
) -> SessionWorkspace {
    let createWorkspace = {
        MainActor.assumeIsolated {
            if let sessionFactoryWithStartupDirectory {
                return SessionWorkspace(
                    autoStartSessions: autoStartSessions,
                    startsWithSession: startsWithSession,
                    sessionFactoryWithStartupDirectory: sessionFactoryWithStartupDirectory
                )
            }

            return SessionWorkspace(
                autoStartSessions: autoStartSessions,
                startsWithSession: startsWithSession,
                sessionFactory: { makeTestSession() }
            )
        }
    }

    if Thread.isMainThread {
        return createWorkspace()
    }

    var workspace: SessionWorkspace?
    DispatchQueue.main.sync {
        workspace = createWorkspace()
    }
    return workspace!
}
