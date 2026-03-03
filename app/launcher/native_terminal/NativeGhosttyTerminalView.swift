import Mvx
import SwiftUI

@MainActor
struct NativeGhosttyTerminalView: NSViewRepresentable {
    let session: TerminalSession
    let isFocused: Bool
    let onFocusRequest: () -> Void

    func makeNSView(context: Context) -> NativeGhosttyNSView {
        NativeGhosttyNSView(
            session: session,
            runtime: runtime(for: session),
            isFocused: isFocused,
            onFocusRequest: onFocusRequest
        )
    }

    func updateNSView(_ nsView: NativeGhosttyNSView, context: Context) {
        nsView.configure(
            session: session,
            runtime: runtime(for: session),
            isFocused: isFocused,
            onFocusRequest: onFocusRequest
        )
    }

    static func dismantleNSView(_ nsView: NativeGhosttyNSView, coordinator: ()) {
        nsView.dismantle()
    }

    private func runtime(for session: TerminalSession) -> GhosttySurfaceRuntime? {
        guard let driver = session.backendObject as? NativeGhosttySessionDriver else {
            assertionFailure("NativeGhosttyTerminalView requires a NativeGhosttySessionDriver backend")
            return nil
        }

        return driver.surfaceRuntime
    }
}
