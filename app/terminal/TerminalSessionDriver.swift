import Foundation

public enum SessionRuntimeEvent: Equatable {
    case titleChanged(String?)
    case contextChanged(workingDirectoryPath: String?, foregroundProcessName: String?)
    case childExited(exitCode: Int32?)
    case splitRequested(WorkspaceSplitAxis)
}

public protocol TerminalSessionDriver: AnyObject {
    var adapter: TerminalAdapter { get }
    var ptyBridge: PtyBridge { get }
    var renderBridge: RenderBridge { get }
    var inputBridge: InputBridge { get }
    var clipboardBridge: ClipboardBridge { get }
    var isActive: Bool { get }
    var usesAlternateScreen: Bool { get }
    var enabledMouseModes: Set<MouseTrackingMode> { get }
    var latestAgentStatus: SessionAgentStatus { get }

    func start()
    func stop()
    @discardableResult func sendUserInput(_ text: String) -> String
    @discardableResult func handleKeyboard(_ command: KeyboardCommand, selection: String?) -> String
    @discardableResult func handleMouse(_ event: MouseEvent) -> String
    func enableMouseModes(_ modes: Set<MouseTrackingMode>)
    func setAlternateScreen(_ enabled: Bool)
    func resize(columns: Int, rows: Int, pixelWidth: Int, pixelHeight: Int)
    func injectOutput(_ text: String)
    func processOSC52(_ sequence: String) -> OSC52Response
    @discardableResult func addActivityObserver(_ handler: @escaping () -> Void) -> UUID
    func removeActivityObserver(_ token: UUID)
    @discardableResult func addAgentStatusObserver(_ handler: @escaping (SessionAgentStatusUpdate) -> Void) -> UUID
    func removeAgentStatusObserver(_ token: UUID)
    @discardableResult func addRuntimeEventObserver(_ handler: @escaping (SessionRuntimeEvent) -> Void) -> UUID
    func removeRuntimeEventObserver(_ token: UUID)
    func processAgentStatusEscapeSequence(_ sequence: String) -> SessionAgentStatusUpdate?
    func currentPromptVisible() -> Bool
    func clipboardContents() -> String
}
