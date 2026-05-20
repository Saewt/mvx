import SwiftUI

@MainActor
public struct UpdateView: View {
    @ObservedObject var controller: ReleaseUpdateController
    @Environment(\.dismiss) private var dismiss
    private let onClose: () -> Void
    private let onRestartRequested: () -> Void

    public init(
        controller: ReleaseUpdateController,
        onClose: @escaping () -> Void = {},
        onRestartRequested: @escaping () -> Void = {}
    ) {
        self.controller = controller
        self.onClose = onClose
        self.onRestartRequested = onRestartRequested
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerView

            switch controller.updateState {
            case .idle:
                idleView
            case .checking:
                checkingView
            case .updateAvailable(let version, let build, _):
                updateAvailableView(version: version, build: build)
            case .downloading:
                downloadingView
            case .readyToRelaunch(_, _, let version, let build):
                readyToRelaunchView(version: version, build: build)
            case .relaunching(let version, let build):
                relaunchingView(version: version, build: build)
            case .upToDate:
                upToDateView
            case .failed(let message):
                failedView(message: message)
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.10, green: 0.10, blue: 0.11))
        )
    }

    private func performClose() {
        controller.dismissUpdate()
        onClose()
        dismiss()
    }

    @ViewBuilder
    private var headerView: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 24))
                .foregroundStyle(iconColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(titleText)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(subtitleText)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var iconName: String {
        switch controller.updateState {
        case .idle, .checking: return "arrow.triangle.2.circlepath"
        case .updateAvailable: return "arrow.down.circle"
        case .downloading: return "arrow.down.circle"
        case .readyToRelaunch, .relaunching: return "checkmark.circle"
        case .upToDate: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private var iconColor: Color {
        switch controller.updateState {
        case .failed: return .red
        case .upToDate, .readyToRelaunch, .relaunching: return .green
        default: return .blue
        }
    }

    private var titleText: String {
        switch controller.updateState {
        case .idle: return "Software Update"
        case .checking: return "Checking for Updates\u{2026}"
        case .updateAvailable(let v, _, _): return "mvx \(v) Available"
        case .downloading: return "Downloading Update\u{2026}"
        case .readyToRelaunch: return "Update Ready"
        case .relaunching: return "Restarting mvx\u{2026}"
        case .upToDate: return "mvx is Up to Date"
        case .failed: return "Update Failed"
        }
    }

    private var subtitleText: String {
        switch controller.updateState {
        case .idle: return "Current version: \(controller.currentVersion) (\(controller.currentBuild))"
        case .checking: return "Contacting update server\u{2026}"
        case .updateAvailable: return "A newer version is available."
        case .downloading: return "Downloading and verifying\u{2026}"
        case .readyToRelaunch: return "Click Restart to complete the update."
        case .relaunching: return "Closing mvx and applying the update\u{2026}"
        case .upToDate: return "Version \(controller.currentVersion) (\(controller.currentBuild)) is the latest."
        case .failed: return "Could not update automatically."
        }
    }

    @ViewBuilder
    private var idleView: some View {
        HStack {
            Spacer()
            Button("Check for Updates") {
                controller.checkForUpdates()
            }
            .keyboardShortcut(.defaultAction)
            Spacer()
        }
    }

    @ViewBuilder
    private var checkingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Checking\u{2026}")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func updateAvailableView(version: String, build: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("mvx \(version) (build \(build)) is available.")
                .font(.system(size: 12, design: .rounded))
            HStack {
                Spacer()
                Button("Download and Install") {
                    controller.confirmAndInstall()
                }
                .keyboardShortcut(.defaultAction)
                Button("Later") {
                    performClose()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
    }

    @ViewBuilder
    private var downloadingView: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: controller.downloadProgress)
                .progressViewStyle(.linear)
                .tint(Color(red: 0.31, green: 0.57, blue: 0.96))
            HStack {
                Spacer()
                Button("Cancel") {
                    performClose()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
    }

    @ViewBuilder
    private func readyToRelaunchView(version: String, build: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("mvx \(version) (\(build)) is ready to install.")
                .font(.system(size: 12, design: .rounded))
            HStack {
                Spacer()
                Button("Restart to Update") {
                    if controller.relaunchToUpdate() {
                        onClose()
                        onRestartRequested()
                    }
                }
                .keyboardShortcut(.defaultAction)
                Button("Later") {
                    performClose()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
    }

    @ViewBuilder
    private func relaunchingView(version: String, build: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Installing mvx \(version) (\(build)) and restarting.")
                .font(.system(size: 12, design: .rounded))
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Restarting\u{2026}")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var upToDateView: some View {
        HStack {
            Spacer()
            Button("OK") {
                performClose()
            }
            .keyboardShortcut(.defaultAction)
            Spacer()
        }
    }

    @ViewBuilder
    private func failedView(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Try Again") {
                    controller.checkForUpdates()
                }
                Button("OK") {
                    performClose()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
    }
}
