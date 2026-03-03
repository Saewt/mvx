import SwiftUI

public struct TerminalHostFactory {
    public typealias NativeBuilder = @MainActor (
        _ session: TerminalSession,
        _ isFocused: Bool,
        _ onFocusRequest: @escaping () -> Void
    ) -> AnyView

    private let nativeBuilder: NativeBuilder?
    private let geometryReconcileScheduler: (@MainActor () -> Void)?
    private let movedTerminalRefreshScheduler: (@MainActor () -> Void)?

    public init(
        makeNativeHost: NativeBuilder? = nil,
        scheduleGeometryReconcile: (@MainActor () -> Void)? = nil,
        scheduleMovedTerminalRefresh: (@MainActor () -> Void)? = nil
    ) {
        self.nativeBuilder = makeNativeHost
        self.geometryReconcileScheduler = scheduleGeometryReconcile
        self.movedTerminalRefreshScheduler = scheduleMovedTerminalRefresh
    }

    public static let fallbackOnly = TerminalHostFactory()

    public static func native(
        _ builder: @escaping NativeBuilder,
        scheduleGeometryReconcile: (@MainActor () -> Void)? = nil,
        scheduleMovedTerminalRefresh: (@MainActor () -> Void)? = nil
    ) -> TerminalHostFactory {
        TerminalHostFactory(
            makeNativeHost: builder,
            scheduleGeometryReconcile: scheduleGeometryReconcile,
            scheduleMovedTerminalRefresh: scheduleMovedTerminalRefresh
        )
    }

    @MainActor
    public func makeNativeHost(
        session: TerminalSession,
        isFocused: Bool,
        onFocusRequest: @escaping () -> Void
    ) -> AnyView? {
        nativeBuilder?(session, isFocused, onFocusRequest)
    }

    @MainActor
    public func scheduleGeometryReconcile() {
        geometryReconcileScheduler?()
    }

    @MainActor
    public func scheduleMovedTerminalRefresh() {
        movedTerminalRefreshScheduler?()
    }
}
