import SwiftUI

#if canImport(AppKit)
import AppKit

struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.backgroundColor = NSColor(red: 0.071, green: 0.075, blue: 0.086, alpha: 1.0)
            window.isMovableByWindowBackground = true
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
#else
struct WindowAccessor: View {
    var body: some View {
        EmptyView()
    }
}
#endif
