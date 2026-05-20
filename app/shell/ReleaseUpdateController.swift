import AppKit
import CryptoKit
import Foundation
import Combine

@MainActor
public final class ReleaseUpdateController: ObservableObject {
    @Published public internal(set) var updateState: UpdateState = .idle
    @Published public internal(set) var latestRelease: LatestRelease?
    @Published public internal(set) var downloadProgress: Double = 0

    public let currentVersion: String
    public let currentBuild: String
    public let currentBundleURL: URL
    public let latestReleaseURL: URL

    private let networkSession: URLSession
    private let fileManager: FileManager
    private let updateHelperScriptPath: String?
    private var cancellables: Set<AnyCancellable> = []
    private var activeDownloadTask: URLSessionDownloadTask?
    private var activeTempDirectory: URL?

    public init(
        bundle: Bundle = .main,
        latestReleaseURL: URL? = nil,
        networkSession: URLSession = .shared,
        fileManager: FileManager = .default,
        updateHelperScriptPath: String? = nil
    ) {
        self.currentVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        self.currentBuild = bundle.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String ?? "0"
        self.currentBundleURL = bundle.bundleURL
        let config = AppUpdateConfiguration.resolve(bundle: bundle, environment: ProcessInfo.processInfo.environment)
        self.latestReleaseURL = latestReleaseURL ?? config.latestReleaseURL ?? URL(string: DistributionDefaults.defaultLatestReleaseURL)!
        self.networkSession = networkSession
        self.fileManager = fileManager
        self.updateHelperScriptPath = updateHelperScriptPath
    }

    public convenience init(
        configuration: AppUpdateConfiguration,
        networkSession: URLSession = .shared,
        fileManager: FileManager = .default,
        openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) {
        self.init(bundle: .main, latestReleaseURL: configuration.latestReleaseURL, networkSession: networkSession, fileManager: fileManager)
    }

    public var canCheckForUpdates: Bool {
        switch updateState {
        case .idle, .upToDate, .failed:
            return true
        default:
            return false
        }
    }

    public var sparkleRuntimeDetected: Bool { false }

    /// Performs a manual check that always shows a result (up-to-date or failure).
    @discardableResult
    public func checkForUpdates() -> Bool {
        checkForUpdates(interactive: true)
    }

    /// Checks for updates. When `interactive` is `true`, the result is always surfaced.
    /// When `interactive` is `false`, only an available update is surfaced; network
    /// failures and up-to-date results are ignored silently.
    /// An optional `publisher` can be supplied for testing; otherwise the controller
    /// fetches from `latestReleaseURL` using its `networkSession`.
    @discardableResult
    public func checkForUpdates(
        interactive: Bool,
        publisher: AnyPublisher<LatestRelease, Error>? = nil
    ) -> Bool {
        guard canCheckForUpdates else { return false }
        updateState = .checking
        let fetchPublisher = publisher ?? LatestRelease.fetch(
            from: latestReleaseURL,
            networkSession: networkSession
        )
        fetchPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                guard let self else { return }
                if case .failure(let error) = completion, self.updateState == .checking {
                    if interactive {
                        self.updateState = .failed(error.localizedDescription)
                    } else {
                        self.updateState = .idle
                    }
                }
            } receiveValue: { [weak self] release in
                guard let self else { return }
                self.handleFetchedRelease(release, interactive: interactive)
            }
            .store(in: &cancellables)
        return true
    }

    public func confirmAndInstall() {
        guard case .updateAvailable = updateState, let release = latestRelease else { return }
        updateState = .downloading
        downloadProgress = 0
        downloadAndVerify(release: release)
    }

    public func dismissUpdate() {
        activeDownloadTask?.cancel()
        activeDownloadTask = nil
        if let tempDir = activeTempDirectory {
            cleanupTemp(tempDir)
            activeTempDirectory = nil
        }
        latestRelease = nil
        downloadProgress = 0
        updateState = .idle
    }

    public func reload(bundle: Bundle = .main, environment: [String: String] = ProcessInfo.processInfo.environment) {}

    // MARK: - Auto-check throttling

    nonisolated public static let lastUpdateCheckDefaultsKey = "lastUpdateCheckAt"
    nonisolated public static let updateCheckThrottleInterval: TimeInterval = 24 * 60 * 60 // 24 hours

    /// Schedules a non-interactive background check if the throttle window has passed.
    /// Throttle is recorded only after a successful feed fetch. Network failures do not
    /// record throttle so the app retries sooner. The `onUpdateAvailable` callback fires
    /// only when a newer release is found.
    /// An optional `publisher` can be supplied for testing; otherwise the controller
    /// fetches from `latestReleaseURL` using its `networkSession`.
    public func scheduleAutoCheck(
        onUpdateAvailable: @escaping () -> Void = {},
        publisher: AnyPublisher<LatestRelease, Error>? = nil
    ) {
        guard shouldPerformAutoCheck else { return }
        guard canCheckForUpdates else { return }

        updateState = .checking
        let fetchPublisher = publisher ?? LatestRelease.fetch(
            from: latestReleaseURL,
            networkSession: networkSession
        )
        fetchPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                guard let self else { return }
                if case .failure = completion, self.updateState == .checking {
                    self.updateState = .idle
                }
            } receiveValue: { [weak self] release in
                guard let self else { return }
                self.recordAutoCheck()
                self.handleFetchedRelease(release, interactive: false)
                if case .updateAvailable = self.updateState {
                    onUpdateAvailable()
                }
            }
            .store(in: &cancellables)
    }

    public var shouldPerformAutoCheck: Bool {
        let lastCheck = UserDefaults.standard.object(forKey: Self.lastUpdateCheckDefaultsKey) as? Date
        guard let lastCheck else { return true }
        return Date().timeIntervalSince(lastCheck) >= Self.updateCheckThrottleInterval
    }

    public func recordAutoCheck() {
        UserDefaults.standard.set(Date(), forKey: Self.lastUpdateCheckDefaultsKey)
    }

    // MARK: - Private

    private func handleFetchedRelease(_ release: LatestRelease, interactive: Bool) {
        guard updateState == .checking else { return }
        latestRelease = release

        let current = SemanticVersion("\(currentVersion).\(currentBuild)")
        let remote = SemanticVersion("\(release.version).\(release.build)")

        #if arch(arm64)
        let platformOK = true
        #else
        let platformOK = false
        #endif

        if !platformOK {
            if interactive {
                updateState = .failed(UpdateError.unsupportedPlatform.localizedDescription)
            } else {
                updateState = .idle
            }
            return
        }

        if remote > current {
            if !isBundlePathWritable() {
                if interactive {
                    updateState = .failed(UpdateError.bundlePathNotWritable.localizedDescription)
                } else {
                    updateState = .idle
                }
                return
            }
            updateState = .updateAvailable(
                version: release.version,
                build: release.build,
                downloadSize: nil
            )
        } else {
            if interactive {
                updateState = .upToDate
            } else {
                updateState = .idle
            }
        }
    }

    private func isBundlePathWritable() -> Bool {
        let appPath = currentBundleURL.path
        return fileManager.isWritableFile(atPath: appPath)
    }

    private func downloadAndVerify(release: LatestRelease) {
        guard let tarballURL = release.tarballURL else {
            updateState = .failed(UpdateError.networkUnavailable.localizedDescription)
            return
        }

        let tempDir = fileManager.temporaryDirectory
            .appendingPathComponent("mvx-update-\(UUID().uuidString)", isDirectory: true)

        do {
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            updateState = .failed(UpdateError.filesystemError(error.localizedDescription).localizedDescription)
            return
        }

        activeTempDirectory = tempDir
        let destination = tempDir.appendingPathComponent(tarballURL.lastPathComponent)

        let task = networkSession.downloadTask(with: tarballURL) { [weak self] localURL, _, error in
            Task { @MainActor in
                guard let self else { return }
                self.handleDownloadResult(
                    localURL: localURL,
                    error: error,
                    destination: destination,
                    tempDir: tempDir,
                    release: release
                )
            }
        }
        activeDownloadTask = task
        task.resume()
    }

    private func handleDownloadResult(
        localURL: URL?,
        error: Error?,
        destination: URL,
        tempDir: URL,
        release: LatestRelease
    ) {
        activeDownloadTask = nil
        activeTempDirectory = nil

        guard updateState == .downloading else {
            cleanupTemp(tempDir)
            return
        }

        if error != nil {
            updateState = .failed(UpdateError.networkUnavailable.localizedDescription)
            cleanupTemp(tempDir)
            return
        }

        guard let localURL else {
            updateState = .failed(UpdateError.networkUnavailable.localizedDescription)
            cleanupTemp(tempDir)
            return
        }

        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: localURL, to: destination)
        } catch {
            updateState = .failed(UpdateError.filesystemError(error.localizedDescription).localizedDescription)
            cleanupTemp(tempDir)
            return
        }

        let verified = verifyChecksum(file: destination, expected: release.expectedSHA256)
        if !verified {
            updateState = .failed(UpdateError.checksumMismatch.localizedDescription)
            cleanupTemp(tempDir)
            return
        }

        let extractedAppDir = tempDir.appendingPathComponent("extracted")
        do {
            try fileManager.createDirectory(at: extractedAppDir, withIntermediateDirectories: true)
            try unpackTarball(at: destination, to: extractedAppDir)
        } catch {
            updateState = .failed(UpdateError.filesystemError(error.localizedDescription).localizedDescription)
            cleanupTemp(tempDir)
            return
        }

        let extractedAppPath = extractedAppDir.appendingPathComponent(DistributionDefaults.appBundleName)
        guard fileManager.fileExists(atPath: extractedAppPath.path) else {
            updateState = .failed(UpdateError.filesystemError("Extracted app bundle not found").localizedDescription)
            cleanupTemp(tempDir)
            return
        }

        updateState = .readyToRelaunch(
            extractedAppPath: extractedAppPath.path,
            appPath: currentBundleURL.path,
            version: release.version,
            build: release.build
        )
    }

    private func verifyChecksum(file: URL, expected: String) -> Bool {
        guard let data = fileManager.contents(atPath: file.path) else { return false }
        let hash = SHA256.hash(data: data)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
        return hashString == expected.lowercased()
    }

    private func unpackTarball(at tarballPath: URL, to directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xzf", tarballPath.path, "-C", directory.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError.filesystemError("tar extraction failed with exit code \(process.terminationStatus)")
        }
    }

    private func cleanupTemp(_ url: URL) {
        try? fileManager.removeItem(at: url)
    }

    @discardableResult
    public func relaunchToUpdate() -> Bool {
        guard case .readyToRelaunch(let extractedAppPath, let appPath, let version, let build) = updateState else {
            return false
        }

        let pid = ProcessInfo.processInfo.processIdentifier

        guard let helperScript = resolveUpdateHelperScriptPath() else {
            updateState = .failed("Failed to locate the update helper script.")
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [helperScript, extractedAppPath, appPath, String(pid)]

        do {
            try process.run()
        } catch {
            updateState = .failed("Failed to launch update helper: \(error.localizedDescription)")
            return false
        }

        updateState = .relaunching(version: version, build: build)
        return true
    }

    private func resolveUpdateHelperScriptPath() -> String? {
        if let updateHelperScriptPath, fileManager.fileExists(atPath: updateHelperScriptPath) {
            return updateHelperScriptPath
        }

        if let resourceURL = Bundle.main.resourceURL {
            let bundledPath = resourceURL.appendingPathComponent("update-helpers/mvx-update-helper.sh").path
            if fileManager.fileExists(atPath: bundledPath) {
                return bundledPath
            }
        }

        let fallbackPath = "/usr/local/lib/mvx/mvx-update-helper.sh"
        if fileManager.fileExists(atPath: fallbackPath) {
            return fallbackPath
        }

        return nil
    }
}

public enum UpdateState: Equatable {
    case idle
    case checking
    case updateAvailable(version: String, build: String, downloadSize: Int?)
    case downloading
    case readyToRelaunch(extractedAppPath: String, appPath: String, version: String, build: String)
    case relaunching(version: String, build: String)
    case upToDate
    case failed(String)
}

public enum UpdateError: Error, LocalizedError {
    case networkUnavailable
    case checksumMismatch
    case unsupportedPlatform
    case bundlePathNotWritable
    case filesystemError(String)

    public var errorDescription: String? {
        switch self {
        case .networkUnavailable:
            return "Unable to reach the update server. Check your network connection and try again."
        case .checksumMismatch:
            return "The downloaded update failed integrity verification. Try again or use install.sh to update manually."
        case .unsupportedPlatform:
            return "This platform is not supported for automatic updates. mvx requires Apple Silicon (arm64)."
        case .bundlePathNotWritable:
            return "mvx does not have write access to its install location. Move mvx to ~/Applications or use: curl -fsSL https://raw.githubusercontent.com/Saewt/mvx/main/scripts/install.sh | bash"
        case .filesystemError(let message):
            return "File system error: \(message)"
        }
    }
}

extension LatestRelease {
    static func fetch(
        from url: URL,
        networkSession: URLSession = .shared
    ) -> AnyPublisher<LatestRelease, Error> {
        networkSession.dataTaskPublisher(for: url)
            .mapError { _ in UpdateError.networkUnavailable as Error }
            .tryMap { data, _ -> Data in data }
            .tryMap { data in
                guard let release = LatestRelease.fromJSON(data) else {
                    throw UpdateError.networkUnavailable
                }
                return release
            }
            .eraseToAnyPublisher()
    }
}
