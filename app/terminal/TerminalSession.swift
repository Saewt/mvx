import Foundation

public final class TerminalSession {
    private let driver: TerminalSessionDriver
    public let backendKind: TerminalBackendKind
    public var backendObject: AnyObject? { driver as AnyObject }

    public var adapter: TerminalAdapter { driver.adapter }
    public var ptyBridge: PtyBridge { driver.ptyBridge }
    public var renderBridge: RenderBridge { driver.renderBridge }
    public var inputBridge: InputBridge { driver.inputBridge }
    public var clipboardBridge: ClipboardBridge { driver.clipboardBridge }
    public var isActive: Bool { driver.isActive }
    public var usesAlternateScreen: Bool { driver.usesAlternateScreen }
    public var enabledMouseModes: Set<MouseTrackingMode> { driver.enabledMouseModes }
    public var latestAgentStatus: SessionAgentStatus { driver.latestAgentStatus }

    public init(
        driver: TerminalSessionDriver,
        backendKind: TerminalBackendKind = .nativeGhostty
    ) {
        self.driver = driver
        self.backendKind = backendKind
    }

    public func start() {
        driver.start()
    }

    public func stop() {
        driver.stop()
    }

    @discardableResult
    public func sendUserInput(_ text: String) -> String {
        driver.sendUserInput(text)
    }

    @discardableResult
    public func handleKeyboard(_ command: KeyboardCommand, selection: String? = nil) -> String {
        driver.handleKeyboard(command, selection: selection)
    }

    @discardableResult
    public func handleMouse(_ event: MouseEvent) -> String {
        driver.handleMouse(event)
    }

    public func enableMouseModes(_ modes: Set<MouseTrackingMode>) {
        driver.enableMouseModes(modes)
    }

    public func setAlternateScreen(_ enabled: Bool) {
        driver.setAlternateScreen(enabled)
    }

    public func resize(columns: Int, rows: Int, pixelWidth: Int, pixelHeight: Int) {
        driver.resize(columns: columns, rows: rows, pixelWidth: pixelWidth, pixelHeight: pixelHeight)
    }

    public func injectOutput(_ text: String) {
        driver.injectOutput(text)
    }

    public func processOSC52(_ sequence: String) -> OSC52Response {
        driver.processOSC52(sequence)
    }

    @discardableResult
    public func addActivityObserver(_ handler: @escaping () -> Void) -> UUID {
        driver.addActivityObserver(handler)
    }

    public func removeActivityObserver(_ token: UUID) {
        driver.removeActivityObserver(token)
    }

    @discardableResult
    public func addAgentStatusObserver(_ handler: @escaping (SessionAgentStatusUpdate) -> Void) -> UUID {
        driver.addAgentStatusObserver(handler)
    }

    public func removeAgentStatusObserver(_ token: UUID) {
        driver.removeAgentStatusObserver(token)
    }

    @discardableResult
    public func addRuntimeEventObserver(_ handler: @escaping (SessionRuntimeEvent) -> Void) -> UUID {
        driver.addRuntimeEventObserver(handler)
    }

    public func removeRuntimeEventObserver(_ token: UUID) {
        driver.removeRuntimeEventObserver(token)
    }

    public func processAgentStatusEscapeSequence(_ sequence: String) -> SessionAgentStatusUpdate? {
        driver.processAgentStatusEscapeSequence(sequence)
    }

    public func currentPromptVisible() -> Bool {
        driver.currentPromptVisible()
    }

    public func clipboardContents() -> String {
        driver.clipboardContents()
    }
}
