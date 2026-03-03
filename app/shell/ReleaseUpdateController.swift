import AppKit
import Foundation

@MainActor
public final class ReleaseUpdateController: ObservableObject {
    @Published public private(set) var configuration: AppUpdateConfiguration

    private let openURL: (URL) -> Bool

    public init(
        configuration: AppUpdateConfiguration,
        openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) {
        self.configuration = configuration
        self.openURL = openURL
    }

    public convenience init(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) {
        self.init(
            configuration: AppUpdateConfiguration.resolve(bundle: bundle, environment: environment),
            openURL: openURL
        )
    }

    public var canCheckForUpdates: Bool {
        configuration.canCheckForUpdates
    }

    public var sparkleRuntimeDetected: Bool {
        NSClassFromString("SPUStandardUpdaterController") != nil
    }

    @discardableResult
    public func checkForUpdates() -> Bool {
        guard let targetURL = effectiveUpdateURL else {
            return false
        }

        return openURL(targetURL)
    }

    public func reload(bundle: Bundle = .main, environment: [String: String] = ProcessInfo.processInfo.environment) {
        configuration = AppUpdateConfiguration.resolve(bundle: bundle, environment: environment)
    }

    private var effectiveUpdateURL: URL? {
        if sparkleRuntimeDetected, let appcastURL = configuration.appcastURL {
            return appcastURL
        }

        return configuration.fallbackDownloadURL ?? configuration.appcastURL
    }
}
