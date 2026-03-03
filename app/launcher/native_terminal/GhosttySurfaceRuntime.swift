import AppKit
import Mvx
import Foundation

final class GhosttySurfaceRuntime {
    private struct Viewport {
        let xScale: CGFloat
        let yScale: CGFloat
        let layerScale: CGFloat
        let pixelWidth: UInt32
        let pixelHeight: UInt32
        let displayID: UInt32

        var isStable: Bool {
            pixelWidth >= 24 && pixelHeight >= 18
        }
    }

    let sessionID: UUID
    let supportPaths: GhosttySupportPaths
    let startupDirectory: URL?

    private weak var hostView: NativeGhosttyNSView?
    private weak var session: TerminalSession?
    private let renderView = NSView(frame: .zero)
    private var runtimeEventObservers: [UUID: (SessionRuntimeEvent) -> Void] = [:]
    private var surface: ghostty_surface_t?
    private var didRequestStart = false
    private var lastDisplayID: UInt32 = 0
    private var appliedDisplayID: UInt32 = 0
    private var appliedPixelWidth: UInt32 = 0
    private var appliedPixelHeight: UInt32 = 0
    private var appliedBackingScaleFactor: CGFloat = 0
    private var isInTransientMove = false
    private var isTearingDown = false

    private(set) var isStarted = false
    private(set) var isAttached = false
    private(set) var isFocused = false
    private(set) var isVisible = false
    private(set) var lastBounds: CGRect = .zero
    private(set) var lastBackingScaleFactor: CGFloat = 1

    init(sessionID: UUID, supportPaths: GhosttySupportPaths, startupDirectory: URL?) {
        self.sessionID = sessionID
        self.supportPaths = supportPaths
        self.startupDirectory = startupDirectory
        renderView.translatesAutoresizingMaskIntoConstraints = false
        renderView.wantsLayer = true
    }

    func attach(
        to view: NativeGhosttyNSView,
        session: TerminalSession,
        isFocused: Bool,
        onFocusRequest: @escaping () -> Void
    ) {
        _ = onFocusRequest
        hostView = view
        self.session = session

        if renderView.superview !== view {
            renderView.removeFromSuperview()
            view.addSubview(renderView)
            NSLayoutConstraint.activate([
                renderView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                renderView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                renderView.topAnchor.constraint(equalTo: view.topAnchor),
                renderView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
        }

        isAttached = true
        setFocused(isFocused)

        if view.window == nil {
            beginTransientMove()
        } else {
            endTransientMove()
            setVisible(!view.isHidden)
        }

        ensureSurfaceIfPossible()
    }

    func detach(from view: NativeGhosttyNSView? = nil) {
        guard view == nil || hostView === view else {
            return
        }

        renderView.removeFromSuperview()
        hostView = nil
        isAttached = false
        if !isInTransientMove {
            isVisible = false
        }
    }

    func beginTransientMove() {
        isInTransientMove = true
    }

    func endTransientMove() {
        isInTransientMove = false
    }

    func startIfNeeded() {
        didRequestStart = true
        ensureSurfaceIfPossible()
    }

    func stop() {
        guard !isTearingDown else {
            return
        }

        let surfaceToFree = surface
        surface = nil
        isTearingDown = true
        if let surfaceToFree {
            ghostty_surface_free(surfaceToFree)
        }
        isTearingDown = false

        isStarted = false
        didRequestStart = false
        isInTransientMove = false
        appliedDisplayID = 0
        appliedPixelWidth = 0
        appliedPixelHeight = 0
        appliedBackingScaleFactor = 0
    }

    func setFocused(_ focused: Bool) {
        isFocused = focused

        guard let surface else {
            return
        }

        if !focused && isInTransientMove {
            return
        }

        ghostty_surface_set_focus(surface, focused)
        if focused {
            reassertDisplayID()
        }
    }

    func setVisible(_ visible: Bool) {
        isVisible = visible

        guard let surface else {
            return
        }

        if !visible && isInTransientMove {
            return
        }

        ghostty_surface_set_occlusion(surface, visible)
    }

    func resize(bounds: CGRect, backingScaleFactor: CGFloat) {
        lastBounds = bounds
        lastBackingScaleFactor = max(backingScaleFactor, 1)

        guard let hostView else {
            return
        }

        _ = reconcileGeometry(in: hostView, forceRefresh: false)
    }

    func updateViewport(bounds: CGRect, backingScaleFactor: CGFloat, displayID: UInt32?) {
        lastBounds = bounds
        lastBackingScaleFactor = max(backingScaleFactor, 1)
        if let displayID, displayID != 0 {
            lastDisplayID = displayID
        }

        guard let hostView else {
            return
        }

        _ = reconcileGeometry(in: hostView, forceRefresh: false)
    }

    @discardableResult
    func reconcileGeometry(in view: NativeGhosttyNSView, forceRefresh: Bool) -> Bool {
        guard !isTearingDown else {
            return false
        }

        hostView = view
        lastBounds = view.bounds

        let viewport = targetViewport(for: view)
        lastBackingScaleFactor = viewport.xScale
        if viewport.displayID != 0 {
            lastDisplayID = viewport.displayID
        }

        guard view.window != nil else {
            beginTransientMove()
            return false
        }

        endTransientMove()
        ensureSurfaceIfPossible(viewport: viewport)

        guard let surface else {
            return false
        }

        let didUpdate = pushViewport(
            viewport,
            to: surface,
            forceRefresh: forceRefresh,
            forceDisplayReassert: forceRefresh
        )
        if didUpdate {
            GhosttyAppRuntime.shared.tickIfNeeded()
        }

        return viewport.isStable
    }

    func reassertDisplayID() {
        guard let surface else {
            return
        }

        let displayID = resolvedDisplayID()
        guard displayID != 0 else {
            return
        }

        lastDisplayID = displayID
        ghostty_surface_set_display_id(surface, displayID)
        appliedDisplayID = displayID
        GhosttyAppRuntime.shared.tickIfNeeded()
    }

    func forceRefresh() {
        guard let surface,
              let hostView,
              hostView.window != nil else {
            return
        }

        let viewport = targetViewport(for: hostView)
        guard viewport.pixelWidth > 0, viewport.pixelHeight > 0 else {
            return
        }

        let didUpdate = pushViewport(
            viewport,
            to: surface,
            forceRefresh: true,
            forceDisplayReassert: true
        )
        if didUpdate {
            GhosttyAppRuntime.shared.tickIfNeeded()
        }
    }

    func sendText(_ text: String) {
        guard let surface, !text.isEmpty else {
            return
        }

        text.withCString { textPtr in
            ghostty_surface_text(surface, textPtr, UInt(text.utf8.count))
        }
        GhosttyAppRuntime.shared.tickIfNeeded()
    }

    func pasteText(_ text: String) {
        sendText(text)
    }

    func sendPreedit(_ text: String) {
        guard let surface else {
            return
        }

        if text.isEmpty {
            ghostty_surface_preedit(surface, nil, 0)
        } else {
            text.withCString { textPtr in
                ghostty_surface_preedit(surface, textPtr, UInt(text.utf8.count))
            }
        }

        GhosttyAppRuntime.shared.tickIfNeeded()
    }

    func imePoint(_ x: inout Double, _ y: inout Double, _ w: inout Double, _ h: inout Double) {
        guard let surface else {
            x = 0
            y = 0
            w = 0
            h = 0
            return
        }

        ghostty_surface_ime_point(surface, &x, &y, &w, &h)
    }

    func sendKey(event: NSEvent) -> Bool {
        sendKey(
            event: event,
            textOverride: TerminalKeyFallback.fallbackText(for: event.characters),
            composing: false
        )
    }

    func sendKeyWithoutText(event: NSEvent) -> Bool {
        sendKey(event: event, textOverride: nil, composing: false)
    }

    func sendKeyWithText(event: NSEvent, text: String) -> Bool {
        guard !text.isEmpty else {
            return false
        }

        return sendKey(event: event, textOverride: text, composing: false)
    }

    private func sendKey(
        event: NSEvent,
        textOverride: String?,
        composing: Bool
    ) -> Bool {
        guard let surface else {
            return false
        }

        let performCall: (UnsafePointer<CChar>?) -> Bool = { textPtr in
            let key = self.makeKeyInput(
                event: event,
                text: textPtr,
                composing: composing
            )
            return ghostty_surface_key(surface, key)
        }

        let handled: Bool
        if let textOverride, !textOverride.isEmpty {
            handled = textOverride.withCString(performCall)
        } else {
            handled = performCall(nil)
        }
        GhosttyAppRuntime.shared.tickIfNeeded()
        return handled
    }

    func sendMouse(event: NSEvent) {
        guard let surface else {
            return
        }

        let modifiers = Self.modifiers(from: event.modifierFlags)
        let point = renderView.convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(surface, Double(point.x), Double(renderView.bounds.height - point.y), modifiers)

        switch event.type {
        case .leftMouseDown:
            _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, modifiers)
        case .leftMouseUp:
            _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, modifiers)
        case .rightMouseDown:
            _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RIGHT, modifiers)
        case .rightMouseUp:
            _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_RIGHT, modifiers)
        case .otherMouseDown:
            _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, Self.mouseButton(for: event), modifiers)
        case .otherMouseUp:
            _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, Self.mouseButton(for: event), modifiers)
        case .scrollWheel:
            let scroll = Self.scrollPayload(for: event)
            ghostty_surface_mouse_scroll(
                surface,
                scroll.x,
                scroll.y,
                scroll.mods
            )
        default:
            break
        }

        GhosttyAppRuntime.shared.tickIfNeeded()
    }

    func copySelection() -> String? {
        guard let surface, ghostty_surface_has_selection(surface) else {
            return nil
        }

        var text = ghostty_text_s()
        guard ghostty_surface_read_selection(surface, &text),
              let textPtr = text.text else {
            return nil
        }

        defer {
            ghostty_surface_free_text(surface, &text)
        }

        let data = Data(bytes: textPtr, count: Int(text.text_len))
        return String(data: data, encoding: .utf8)
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

    func performBindingAction(_ action: String) -> Bool {
        guard let surface else {
            return false
        }

        let handled = action.withCString { actionPtr in
            ghostty_surface_binding_action(surface, actionPtr, UInt(action.utf8.count))
        }
        GhosttyAppRuntime.shared.tickIfNeeded()
        return handled
    }

    func handle(action: ghostty_action_s) -> Bool {
        switch action.tag {
        case GHOSTTY_ACTION_SET_TITLE:
            notifyRuntimeEventObservers(.titleChanged(Self.optionalString(action.action.set_title.title)))
            return true
        case GHOSTTY_ACTION_PWD:
            notifyRuntimeEventObservers(
                .contextChanged(
                    workingDirectoryPath: Self.optionalString(action.action.pwd.pwd),
                    foregroundProcessName: nil
                )
            )
            return true
        case GHOSTTY_ACTION_SHOW_CHILD_EXITED:
            notifyRuntimeEventObservers(.childExited(exitCode: Int32(action.action.child_exited.exit_code)))
            return true
        case GHOSTTY_ACTION_NEW_SPLIT:
            let axis: WorkspaceSplitAxis = Self.splitAxis(from: action.action.new_split)
            notifyRuntimeEventObservers(.splitRequested(axis))
            return true
        case GHOSTTY_ACTION_OPEN_URL:
            if let url = Self.url(from: action.action.open_url) {
                NSWorkspace.shared.open(url)
                return true
            }
            return false
        default:
            return false
        }
    }

    static func fromOpaque(_ opaque: UnsafeMutableRawPointer?) -> GhosttySurfaceRuntime? {
        guard let opaque else {
            return nil
        }

        return Unmanaged<GhosttySurfaceRuntime>.fromOpaque(opaque).takeUnretainedValue()
    }

    static func completeClipboardRead(
        userdata: UnsafeMutableRawPointer?,
        location: ghostty_clipboard_e,
        state: UnsafeMutableRawPointer?
    ) {
        guard let runtime = fromOpaque(userdata),
              let surface = runtime.surface else {
            return
        }

        let pasteboard = pasteboard(for: location)
        let contents = pasteboard?.string(forType: .string) ?? ""
        contents.withCString { contentsPtr in
            ghostty_surface_complete_clipboard_request(surface, contentsPtr, state, false)
        }
    }

    static func completeConfirmedClipboardRead(
        userdata: UnsafeMutableRawPointer?,
        string: UnsafePointer<CChar>?,
        state: UnsafeMutableRawPointer?
    ) {
        guard let runtime = fromOpaque(userdata),
              let surface = runtime.surface,
              let string else {
            return
        }

        ghostty_surface_complete_clipboard_request(surface, string, state, true)
    }

    static func writeClipboard(
        location: ghostty_clipboard_e,
        content: UnsafePointer<ghostty_clipboard_content_s>?,
        count: Int
    ) {
        guard let pasteboard = pasteboard(for: location) else {
            return
        }

        var fallbackText: String?
        if let content {
            let buffer = UnsafeBufferPointer(start: content, count: count)
            for item in buffer {
                guard let data = item.data else {
                    continue
                }

                let value = String(cString: data)
                if let mime = item.mime, String(cString: mime).hasPrefix("text/plain") {
                    pasteboard.clearContents()
                    pasteboard.setString(value, forType: .string)
                    return
                }

                if fallbackText == nil {
                    fallbackText = value
                }
            }
        }

        if let fallbackText {
            pasteboard.clearContents()
            pasteboard.setString(fallbackText, forType: .string)
        }
    }

    static func handleCloseSurfaceRequest(
        userdata: UnsafeMutableRawPointer?,
        needsConfirmClose: Bool
    ) {
        guard let runtime = fromOpaque(userdata) else {
            return
        }

        if !needsConfirmClose {
            runtime.notifyRuntimeEventObservers(.childExited(exitCode: nil))
        }
    }

    private func ensureSurfaceIfPossible(viewport: Viewport? = nil) {
        guard didRequestStart,
              surface == nil,
              isAttached,
              GhosttyAppRuntime.shared.isAvailable,
              let app = GhosttyAppRuntime.shared.app,
              let hostView,
              hostView.window != nil else {
            return
        }

        let resolvedViewport = viewport ?? targetViewport(for: hostView)
        guard resolvedViewport.isStable else {
            return
        }

        var surfaceConfig = ghostty_surface_config_new()
        surfaceConfig.platform_tag = GHOSTTY_PLATFORM_MACOS
        surfaceConfig.platform.macos.nsview = Unmanaged.passUnretained(renderView).toOpaque()
        surfaceConfig.userdata = Unmanaged.passUnretained(self).toOpaque()
        surfaceConfig.scale_factor = Double(resolvedViewport.xScale)
        surfaceConfig.font_size = Float(session?.adapter.renderConfiguration.fontSize ?? 13)
        surfaceConfig.context = GHOSTTY_SURFACE_CONTEXT_SPLIT

        if let startupDirectory {
            startupDirectory.path.withCString { pathPtr in
                surfaceConfig.working_directory = pathPtr
                surface = ghostty_surface_new(app, &surfaceConfig)
            }
        } else {
            surface = ghostty_surface_new(app, &surfaceConfig)
        }

        guard let surface else {
            return
        }

        isStarted = true
        endTransientMove()
        _ = pushViewport(
            resolvedViewport,
            to: surface,
            forceRefresh: true,
            forceDisplayReassert: true
        )
        ghostty_surface_set_focus(surface, isFocused)
        if !isInTransientMove {
            ghostty_surface_set_occlusion(surface, isVisible)
        }
        GhosttyAppRuntime.shared.tickIfNeeded()
    }

    private func pushViewport(
        _ viewport: Viewport,
        to surface: ghostty_surface_t,
        forceRefresh: Bool,
        forceDisplayReassert: Bool
    ) -> Bool {
        var didUpdate = false

        if viewport.displayID != 0,
           forceRefresh || forceDisplayReassert || viewport.displayID != appliedDisplayID {
            ghostty_surface_set_display_id(surface, viewport.displayID)
            appliedDisplayID = viewport.displayID
            didUpdate = true
        }

        if forceRefresh || !scaleApproximatelyEqual(viewport.xScale, appliedBackingScaleFactor) {
            renderView.layer?.contentsScale = viewport.xScale
            ghostty_surface_set_content_scale(
                surface,
                Double(viewport.xScale),
                Double(viewport.yScale)
            )
            appliedBackingScaleFactor = viewport.xScale
            didUpdate = true
        }

        if viewport.pixelWidth > 0,
           viewport.pixelHeight > 0,
           forceRefresh ||
            viewport.pixelWidth != appliedPixelWidth ||
            viewport.pixelHeight != appliedPixelHeight {
            ghostty_surface_set_size(surface, viewport.pixelWidth, viewport.pixelHeight)
            appliedPixelWidth = viewport.pixelWidth
            appliedPixelHeight = viewport.pixelHeight
            didUpdate = true
        }

        if didUpdate || forceRefresh {
            ghostty_surface_refresh(surface)
            return true
        }

        return false
    }

    private func targetViewport(for view: NativeGhosttyNSView) -> Viewport {
        let scales = scaleFactors(for: view)
        let pixelWidth = pixelDimension(from: view.bounds.width * scales.x)
        let pixelHeight = pixelDimension(from: view.bounds.height * scales.y)

        let displayID: UInt32
        if let screenDisplayID = Self.displayID(for: view.window?.screen ?? NSScreen.main),
           screenDisplayID != 0 {
            displayID = screenDisplayID
        } else {
            displayID = lastDisplayID
        }

        return Viewport(
            xScale: scales.x,
            yScale: scales.y,
            layerScale: scales.layer,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            displayID: displayID
        )
    }

    private func resolvedDisplayID() -> UInt32 {
        if let hostView,
           let displayID = Self.displayID(for: hostView.window?.screen ?? NSScreen.main),
           displayID != 0 {
            return displayID
        }

        return lastDisplayID
    }

    private func scaleFactors(for view: NativeGhosttyNSView) -> (x: CGFloat, y: CGFloat, layer: CGFloat) {
        let layerScale = max(
            CGFloat(1),
            view.layer?.contentsScale
                ?? view.window?.backingScaleFactor
                ?? NSScreen.main?.backingScaleFactor
                ?? 1
        )
        let scale = max(
            CGFloat(1),
            view.window?.backingScaleFactor
                ?? view.layer?.contentsScale
                ?? NSScreen.main?.backingScaleFactor
                ?? 1
        )
        return (x: scale, y: scale, layer: layerScale)
    }

    private func pixelDimension(from value: CGFloat) -> UInt32 {
        guard value.isFinite else {
            return 0
        }

        let floored = floor(max(0, value))
        if floored >= CGFloat(UInt32.max) {
            return UInt32.max
        }

        return UInt32(floored)
    }

    private func scaleApproximatelyEqual(
        _ lhs: CGFloat,
        _ rhs: CGFloat,
        epsilon: Double = 0.0001
    ) -> Bool {
        abs(lhs - rhs) <= CGFloat(epsilon)
    }

    private func makeKeyInput(
        event: NSEvent,
        text: UnsafePointer<CChar>?,
        composing: Bool
    ) -> ghostty_input_key_s {
        let action: ghostty_input_action_e
        switch event.type {
        case .keyUp:
            action = GHOSTTY_ACTION_RELEASE
        default:
            action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
        }

        let unshifted = event.charactersIgnoringModifiers?.unicodeScalars.first?.value ?? 0
        let modifiers = Self.modifiers(from: event.modifierFlags)

        return ghostty_input_key_s(
            action: action,
            mods: modifiers,
            consumed_mods: GHOSTTY_MODS_NONE,
            keycode: UInt32(event.keyCode),
            text: text,
            unshifted_codepoint: UInt32(unshifted),
            composing: composing
        )
    }

    private static func displayID(for screen: NSScreen?) -> UInt32? {
        guard let screen else {
            return nil
        }

        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let value = screen.deviceDescription[key] as? UInt32 {
            return value
        }
        if let value = screen.deviceDescription[key] as? Int {
            return UInt32(value)
        }
        if let value = screen.deviceDescription[key] as? NSNumber {
            return value.uint32Value
        }

        return nil
    }

    private func notifyRuntimeEventObservers(_ event: SessionRuntimeEvent) {
        for observer in runtimeEventObservers.values {
            observer(event)
        }
    }

    private static func optionalString(_ value: UnsafePointer<CChar>?) -> String? {
        guard let value else {
            return nil
        }

        let string = String(cString: value)
        return string.isEmpty ? nil : string
    }

    private static func url(from action: ghostty_action_open_url_s) -> URL? {
        guard let rawURL = action.url else {
            return nil
        }

        let data = Data(bytes: rawURL, count: Int(action.len))
        guard let value = String(data: data, encoding: .utf8), !value.isEmpty else {
            return nil
        }

        if let url = URL(string: value) {
            return url
        }

        if NSString(string: value).isAbsolutePath {
            return URL(fileURLWithPath: value)
        }

        return nil
    }

    private static func splitAxis(from direction: ghostty_action_split_direction_e) -> WorkspaceSplitAxis {
        switch direction {
        case GHOSTTY_SPLIT_DIRECTION_UP, GHOSTTY_SPLIT_DIRECTION_DOWN:
            return .horizontal
        default:
            return .vertical
        }
    }

    private static func modifiers(from flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var modifiers = GHOSTTY_MODS_NONE.rawValue
        if flags.contains(.shift) {
            modifiers |= GHOSTTY_MODS_SHIFT.rawValue
        }
        if flags.contains(.control) {
            modifiers |= GHOSTTY_MODS_CTRL.rawValue
        }
        if flags.contains(.option) {
            modifiers |= GHOSTTY_MODS_ALT.rawValue
        }
        if flags.contains(.command) {
            modifiers |= GHOSTTY_MODS_SUPER.rawValue
        }
        if flags.contains(.capsLock) {
            modifiers |= GHOSTTY_MODS_CAPS.rawValue
        }
        if flags.contains(.numericPad) {
            modifiers |= GHOSTTY_MODS_NUM.rawValue
        }
        return ghostty_input_mods_e(modifiers)
    }

    private static func scrollPayload(
        for event: NSEvent
    ) -> (x: Double, y: Double, mods: ghostty_input_scroll_mods_t) {
        let isPrecise = event.hasPreciseScrollingDeltas
        var x = Double(event.scrollingDeltaX)
        var y = Double(event.scrollingDeltaY)

        if isPrecise {
            x *= 2.0
            y *= 2.0
        }

        var mods: ghostty_input_scroll_mods_t = 0
        if isPrecise {
            mods |= 1
        }

        let momentum = momentumPhase(from: event.momentumPhase)
        mods |= ghostty_input_scroll_mods_t(Int32(momentum.rawValue) << 1)

        return (x, y, mods)
    }

    private static func momentumPhase(
        from phase: NSEvent.Phase
    ) -> ghostty_input_mouse_momentum_e {
        if phase.contains(.began) {
            return GHOSTTY_MOUSE_MOMENTUM_BEGAN
        }
        if phase.contains(.stationary) {
            return GHOSTTY_MOUSE_MOMENTUM_STATIONARY
        }
        if phase.contains(.changed) {
            return GHOSTTY_MOUSE_MOMENTUM_CHANGED
        }
        if phase.contains(.ended) {
            return GHOSTTY_MOUSE_MOMENTUM_ENDED
        }
        if phase.contains(.cancelled) {
            return GHOSTTY_MOUSE_MOMENTUM_CANCELLED
        }
        if phase.contains(.mayBegin) {
            return GHOSTTY_MOUSE_MOMENTUM_MAY_BEGIN
        }

        return GHOSTTY_MOUSE_MOMENTUM_NONE
    }

    private static func mouseButton(for event: NSEvent) -> ghostty_input_mouse_button_e {
        switch event.buttonNumber {
        case 2:
            return GHOSTTY_MOUSE_MIDDLE
        case 3:
            return GHOSTTY_MOUSE_FOUR
        case 4:
            return GHOSTTY_MOUSE_FIVE
        default:
            return GHOSTTY_MOUSE_MIDDLE
        }
    }

    private static func pasteboard(for location: ghostty_clipboard_e) -> NSPasteboard? {
        switch location {
        case GHOSTTY_CLIPBOARD_STANDARD:
            return .general
        case GHOSTTY_CLIPBOARD_SELECTION:
            return NSPasteboard(name: NSPasteboard.Name("com.mvx.ghostty.selection"))
        default:
            return nil
        }
    }
}
