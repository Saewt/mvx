import AppKit
import Mvx
import QuartzCore

final class NativeGhosttyNSView: NSView {
    private weak var runtime: GhosttySurfaceRuntime?
    private var session: TerminalSession
    private var wantsTerminalFocus = false
    private var markedText: String?
    private var keyTextAccumulator: String?
    private var pendingInterpretEvent: NSEvent?
    private var didHandleInterpretCommand = false
    private var windowObservers: [NSObjectProtocol] = []

    var onFocusRequest: (() -> Void)?

    init(
        session: TerminalSession,
        runtime: GhosttySurfaceRuntime?,
        isFocused: Bool,
        onFocusRequest: @escaping () -> Void
    ) {
        self.session = session
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor(red: 0.07, green: 0.08, blue: 0.09, alpha: 1).cgColor

        NativeGhosttyGeometryCoordinator.shared.register(self)
        configure(session: session, runtime: runtime, isFocused: isFocused, onFocusRequest: onFocusRequest)
    }

    deinit {
        clearWindowObservers()
        NativeGhosttyGeometryCoordinator.shared.unregister(self)
        runtime?.detach(from: self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            runtime?.beginTransientMove()
        }

        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateWindowObservers()

        if window != nil {
            runtime?.endTransientMove()
        }

        _ = reconcileGeometryNow(forceRefresh: true)
        focusIfNeeded()
        NativeGhosttyGeometryCoordinator.shared.scheduleGeometryReconcile(forceRefresh: true)
    }

    override func layout() {
        super.layout()
        _ = reconcileGeometryNow()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        _ = reconcileGeometryNow(forceRefresh: true)
    }

    func configure(
        session: TerminalSession,
        runtime: GhosttySurfaceRuntime?,
        isFocused: Bool,
        onFocusRequest: @escaping () -> Void
    ) {
        self.session = session
        self.onFocusRequest = onFocusRequest
        wantsTerminalFocus = isFocused
        setRuntime(runtime)
        self.runtime?.attach(
            to: self,
            session: session,
            isFocused: isFocused,
            onFocusRequest: onFocusRequest
        )
        NativeGhosttyGeometryCoordinator.shared.scheduleGeometryReconcile()
        focusIfNeeded()
    }

    @discardableResult
    func reconcileGeometryNow(forceRefresh: Bool = false) -> Bool {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                _ = self?.reconcileGeometryNow(forceRefresh: forceRefresh)
            }
            return false
        }

        return synchronizeGeometryAndContent(forceRefresh: forceRefresh)
    }

    func dismantle() {
        runtime?.beginTransientMove()
        runtime?.detach(from: self)
        runtime = nil
        onFocusRequest = nil
        clearWindowObservers()
        NativeGhosttyGeometryCoordinator.shared.scheduleMovedTerminalRefresh()
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            runtime?.setFocused(true)
            runtime?.reassertDisplayID()
        }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        runtime?.setFocused(false)
        return accepted
    }

    override func keyDown(with event: NSEvent) {
        runtime?.setFocused(true)

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.control) && !flags.contains(.command) && !flags.contains(.option) {
            _ = runtime?.sendKeyWithoutText(event: event)
            return
        }

        pendingInterpretEvent = event
        keyTextAccumulator = ""
        didHandleInterpretCommand = false

        interpretKeyEvents([event])

        let accumulated = keyTextAccumulator ?? ""
        let handledCommand = didHandleInterpretCommand
        pendingInterpretEvent = nil
        keyTextAccumulator = nil
        didHandleInterpretCommand = false

        if !accumulated.isEmpty {
            _ = runtime?.sendKeyWithText(event: event, text: accumulated)
            return
        }

        if handledCommand || markedText != nil {
            return
        }

        if let text = TerminalKeyFallback.fallbackText(for: event.characters) {
            _ = runtime?.sendKeyWithText(event: event, text: text)
        }
    }

    override func keyUp(with event: NSEvent) {
        _ = runtime?.sendKeyWithoutText(event: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let firstResponder = window?.firstResponder as? NSView,
              firstResponder === self || firstResponder.isDescendant(of: self) else {
            return false
        }

        if runtime?.sendKeyWithoutText(event: event) == true {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    override func doCommand(by selector: Selector) {
        guard let pendingInterpretEvent else {
            super.doCommand(by: selector)
            return
        }

        if !didHandleInterpretCommand {
            _ = runtime?.sendKeyWithoutText(event: pendingInterpretEvent)
        }
        didHandleInterpretCommand = true
    }

    override func mouseDown(with event: NSEvent) {
        onFocusRequest?()
        window?.makeFirstResponder(self)
        runtime?.sendMouse(event: event)
    }

    override func mouseUp(with event: NSEvent) {
        runtime?.sendMouse(event: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        onFocusRequest?()
        window?.makeFirstResponder(self)
        runtime?.sendMouse(event: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        runtime?.sendMouse(event: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        onFocusRequest?()
        window?.makeFirstResponder(self)
        runtime?.sendMouse(event: event)
    }

    override func otherMouseUp(with event: NSEvent) {
        runtime?.sendMouse(event: event)
    }

    override func mouseMoved(with event: NSEvent) {
        runtime?.sendMouse(event: event)
    }

    override func mouseDragged(with event: NSEvent) {
        runtime?.sendMouse(event: event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        runtime?.sendMouse(event: event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        runtime?.sendMouse(event: event)
    }

    override func scrollWheel(with event: NSEvent) {
        runtime?.sendMouse(event: event)
    }

    @objc
    func copy(_ sender: Any?) {
        if runtime?.performBindingAction("copy_to_clipboard") == true {
            return
        }

        if let selection = runtime?.copySelection(), !selection.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(selection, forType: .string)
        }
    }

    @objc
    func paste(_ sender: Any?) {
        if runtime?.performBindingAction("paste_from_clipboard") == true {
            return
        }

        if let text = NSPasteboard.general.string(forType: .string), !text.isEmpty {
            runtime?.pasteText(text)
        }
    }

    override func selectAll(_ sender: Any?) {
        _ = runtime?.performBindingAction("select_all")
    }

    private func setRuntime(_ newRuntime: GhosttySurfaceRuntime?) {
        if runtime === newRuntime {
            return
        }

        runtime?.beginTransientMove()
        runtime?.detach(from: self)
        runtime = newRuntime
    }

    @discardableResult
    private func synchronizeGeometryAndContent(forceRefresh: Bool) -> Bool {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        if window == nil {
            runtime?.beginTransientMove()
            return false
        }

        runtime?.endTransientMove()
        runtime?.setVisible(!isHidden)

        let isStable = runtime?.reconcileGeometry(in: self, forceRefresh: forceRefresh) ?? true
        if forceRefresh {
            runtime?.forceRefresh()
        }

        return isStable
    }

    private func focusIfNeeded() {
        guard wantsTerminalFocus else {
            return
        }

        window?.makeFirstResponder(self)
        runtime?.setFocused(true)
        runtime?.reassertDisplayID()
    }

    private func textInputString(from input: Any) -> String? {
        if let text = input as? String {
            return text
        }

        if let attributedText = input as? NSAttributedString {
            return attributedText.string
        }

        return nil
    }

    private func updateWindowObservers() {
        clearWindowObservers()
        guard let window else {
            return
        }

        windowObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeScreenNotification,
                object: window,
                queue: .main
            ) { [weak self] notification in
                self?.windowDidChangeScreen(notification)
            }
        )
    }

    private func clearWindowObservers() {
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        windowObservers.removeAll()
    }

    private func windowDidChangeScreen(_ notification: Notification) {
        guard let window,
              let object = notification.object as? NSWindow,
              object == window else {
            return
        }

        runtime?.reassertDisplayID()
        NativeGhosttyGeometryCoordinator.shared.scheduleGeometryReconcile(forceRefresh: true)
    }
}

extension NativeGhosttyNSView: NSTextInputClient {
    func insertText(_ string: Any, replacementRange: NSRange) {
        _ = replacementRange

        guard let text = textInputString(from: string), !text.isEmpty else {
            return
        }

        unmarkText()

        if keyTextAccumulator != nil {
            keyTextAccumulator?.append(text)
        } else if let pendingInterpretEvent {
            _ = runtime?.sendKeyWithText(event: pendingInterpretEvent, text: text)
        } else {
            runtime?.sendText(text)
        }
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        _ = selectedRange
        _ = replacementRange

        let text = textInputString(from: string) ?? ""
        markedText = text.isEmpty ? nil : text
        runtime?.sendPreedit(text)
    }

    func unmarkText() {
        markedText = nil
        runtime?.sendPreedit("")
    }

    func selectedRange() -> NSRange {
        NSRange(location: NSNotFound, length: 0)
    }

    func markedRange() -> NSRange {
        guard let markedText, !markedText.isEmpty else {
            return NSRange(location: NSNotFound, length: 0)
        }

        return NSRange(location: 0, length: markedText.utf16.count)
    }

    func hasMarkedText() -> Bool {
        guard let markedText else {
            return false
        }

        return !markedText.isEmpty
    }

    func attributedSubstring(
        forProposedRange range: NSRange,
        actualRange: NSRangePointer?
    ) -> NSAttributedString? {
        _ = range
        _ = actualRange
        return nil
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    func firstRect(
        forCharacterRange range: NSRange,
        actualRange: NSRangePointer?
    ) -> NSRect {
        actualRange?.pointee = range

        var x = 0.0
        var y = 0.0
        var width = 0.0
        var height = 0.0
        runtime?.imePoint(&x, &y, &width, &height)

        let cellRect = NSRect(x: x, y: y, width: width, height: height)
        guard let window else {
            return cellRect
        }

        let windowRect = convert(cellRect, to: nil)
        return window.convertToScreen(windowRect)
    }

    func characterIndex(for point: NSPoint) -> Int {
        _ = point
        return 0
    }
}

private extension NSScreen {
    var displayID: UInt32? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let value = deviceDescription[key] as? UInt32 {
            return value
        }
        if let value = deviceDescription[key] as? Int {
            return UInt32(value)
        }
        if let value = deviceDescription[key] as? NSNumber {
            return value.uint32Value
        }
        return nil
    }
}

final class NativeGhosttyGeometryCoordinator {
    static let shared = NativeGhosttyGeometryCoordinator()

    private struct WeakHost {
        weak var value: NativeGhosttyNSView?
    }

    private var hosts: [ObjectIdentifier: WeakHost] = [:]
    private var reconcileScheduled = false
    private var pendingForceRefresh = false
    private var movedRefreshGeneration = 0

    private init() {}

    func register(_ host: NativeGhosttyNSView) {
        hosts[ObjectIdentifier(host)] = WeakHost(value: host)
    }

    func unregister(_ host: NativeGhosttyNSView) {
        hosts.removeValue(forKey: ObjectIdentifier(host))
    }

    func scheduleGeometryReconcile(forceRefresh: Bool = false) {
        pendingForceRefresh = pendingForceRefresh || forceRefresh

        guard !reconcileScheduled else {
            return
        }

        reconcileScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            let forceRefresh = self.pendingForceRefresh
            self.pendingForceRefresh = false
            self.reconcileScheduled = false
            self.runScheduledGeometryReconcile(remainingPasses: 4, forceRefresh: forceRefresh)
        }
    }

    func scheduleMovedTerminalRefresh() {
        scheduleGeometryReconcile(forceRefresh: true)

        movedRefreshGeneration += 1
        let generation = movedRefreshGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(30)) { [weak self] in
            guard let self, self.movedRefreshGeneration == generation else {
                return
            }

            self.scheduleGeometryReconcile(forceRefresh: true)
        }
    }

    private func runScheduledGeometryReconcile(remainingPasses: Int, forceRefresh: Bool) {
        let needsAnotherPass = reconcileTerminalGeometryPass(forceRefresh: forceRefresh)
        guard needsAnotherPass, remainingPasses > 1 else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.runScheduledGeometryReconcile(
                remainingPasses: remainingPasses - 1,
                forceRefresh: true
            )
        }
    }

    private func reconcileTerminalGeometryPass(forceRefresh: Bool) -> Bool {
        let activeHosts = pruneStaleHosts()

        let affectedWindows = Set(activeHosts.compactMap(\.window))
        for window in affectedWindows {
            window.contentView?.layoutSubtreeIfNeeded()
        }

        var needsAnotherPass = false
        for host in activeHosts {
            let isStable = host.reconcileGeometryNow(forceRefresh: forceRefresh)
            if !isStable {
                needsAnotherPass = true
            }
        }

        return needsAnotherPass
    }

    private func pruneStaleHosts() -> [NativeGhosttyNSView] {
        var activeHosts: [NativeGhosttyNSView] = []
        hosts = hosts.reduce(into: [:]) { result, element in
            if let host = element.value.value {
                result[element.key] = element.value
                activeHosts.append(host)
            }
        }
        return activeHosts
    }
}
