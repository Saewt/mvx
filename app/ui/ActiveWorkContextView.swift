import SwiftUI

public struct WorkflowQuickActionState: Equatable, Identifiable {
    public let command: WorkspaceCommand
    public let title: String
    public let symbolName: String
    public let isEnabled: Bool

    public var id: String {
        command.rawValue
    }
}

public struct ActiveWorkContextState: Equatable {
    public let title: String
    public let statusLabel: String
    public let statusAccentName: String
    public let contextLine: String
    public let promptHint: String
    public let contextDetails: [String]
    public let quickActions: [WorkflowQuickActionState]
    public let paneActions: [WorkflowQuickActionState]
    public let workspaceSummary: String

    @MainActor
    public static func resolve(
        workspace: SessionWorkspace,
        commandHandler: WorkspaceCommandHandler
    ) -> ActiveWorkContextState {
        let descriptor = workspace.activeDescriptor
        let metadata = workspace.workspaceMetadata
        let title = descriptor?.displayTitle ?? "No Active Session"
        let status = descriptor?.agentStatus ?? .none
        let statusLabel = status.badgeLabel ?? "Idle"
        let statusAccentName: String
        switch status {
        case .none:
            statusAccentName = "secondary"
        case .running:
            statusAccentName = "green"
        case .waiting:
            statusAccentName = "orange"
        case .done:
            statusAccentName = "teal"
        case .error:
            statusAccentName = "red"
        }

        let workingDirectory = descriptor?.workingDirectoryPath?.split(separator: "/").last.map(String.init)
        let processName = descriptor?.foregroundProcessName
        let parts = [workingDirectory, processName].compactMap { $0 }.filter { !$0.isEmpty }
        let contextLine = parts.isEmpty ? "No working context captured yet" : parts.joined(separator: "  •  ")
        let paneCount = workspace.workspaceGraph.paneCount
        let workspaceSummary = "Focused pane in \(paneCount) pane\(paneCount == 1 ? "" : "s")  •  \(metadata.reviewState.label)"

        let promptHint: String
        switch status {
        case .waiting:
            promptHint = "This session is waiting on you. Use the visible actions or jump back into the live terminal."
        case .running:
            promptHint = "The agent is actively working. Keep the live terminal visible while you manage surrounding tasks."
        case .done:
            promptHint = "This session finished its latest task. Review output or move to the next active thread."
        case .error:
            promptHint = "The session hit an error. Inspect the terminal and decide the next corrective action."
        case .none:
            promptHint = "Use this pane to manage the active session without hunting through menus."
        }

        let contextDetails = [
            descriptor?.workingDirectoryPath.map { "Directory: \($0)" },
            descriptor?.foregroundProcessName.map { "Process: \($0)" },
            "Panes: \(workspace.workspaceGraph.paneCount)",
            "Waiting: \(metadata.waitingCount)",
            "Errors: \(metadata.errorCount)",
        ]
        .compactMap { $0 }

        let quickActions = commandHandler.chromeCommands().map { descriptor in
            WorkflowQuickActionState(
                command: descriptor.command,
                title: descriptor.title,
                symbolName: symbolName(for: descriptor.command),
                isEnabled: descriptor.isEnabled
            )
        }

        let paneActions = commandHandler.paneCommands().map { descriptor in
            WorkflowQuickActionState(
                command: descriptor.command,
                title: descriptor.title,
                symbolName: symbolName(for: descriptor.command),
                isEnabled: descriptor.isEnabled
            )
        }

        return ActiveWorkContextState(
            title: title,
            statusLabel: statusLabel,
            statusAccentName: statusAccentName,
            contextLine: contextLine,
            promptHint: promptHint,
            contextDetails: contextDetails,
            quickActions: quickActions,
            paneActions: paneActions,
            workspaceSummary: workspaceSummary
        )
    }

    private static func symbolName(for command: WorkspaceCommand) -> String {
        switch command {
        case .checkForUpdates:
            return "arrow.triangle.2.circlepath"
        case .commandPalette:
            return "square.grid.2x2"
        case .newWindow:
            return "macwindow.badge.plus"
        case .newTab:
            return "plus"
        case .closeCurrentSession:
            return "xmark"
        case .closePane:
            return "rectangle.portrait.and.arrow.right"
        case .splitHorizontal:
            return "rectangle.split.2x1"
        case .splitVertical:
            return "rectangle.split.1x2"
        case .nextSession:
            return "arrow.right"
        case .previousSession:
            return "arrow.left"
        case .nextPane:
            return "rectangle.on.rectangle.angled"
        case .previousPane:
            return "rectangle.on.rectangle.angled.fill"
        case .nextAttention:
            return "bell"
        case .copy:
            return "doc.on.doc"
        case .paste:
            return "clipboard"
        case .selectAll:
            return "text.cursor"
        case .quit:
            return "power"
        }
    }
}

@MainActor
public struct ActiveWorkContextView: View {
    @ObservedObject private var workspace: SessionWorkspace
    @ObservedObject private var commandHandler: WorkspaceCommandHandler

    public init(workspace: SessionWorkspace, commandHandler: WorkspaceCommandHandler) {
        self.workspace = workspace
        self.commandHandler = commandHandler
    }

    public var body: some View {
        let state = ActiveWorkContextState.resolve(workspace: workspace, commandHandler: commandHandler)

        VStack(alignment: .leading, spacing: 18) {
            header(for: state)

            quickActions(for: state)

            paneActions(for: state)

            VStack(alignment: .leading, spacing: 10) {
                Text("Active Workflow")
                    .font(.system(.headline, design: .rounded))

                Text(state.promptHint)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(state.workspaceSummary)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Recent Context")
                    .font(.system(.headline, design: .rounded))

                if state.contextDetails.isEmpty {
                    Text("No session metadata has been captured yet.")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(state.contextDetails, id: \.self) { line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.03))
            )

            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.13, green: 0.13, blue: 0.11))
    }

    @ViewBuilder
    private func header(for state: ActiveWorkContextState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "terminal")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(red: 0.88, green: 0.56, blue: 0.36))

                VStack(alignment: .leading, spacing: 3) {
                    Text(state.title)
                        .font(.system(size: 26, weight: .semibold, design: .rounded))

                    Text(state.contextLine)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                statusPill(label: state.statusLabel, accentName: state.statusAccentName)
            }
        }
    }

    @ViewBuilder
    private func quickActions(for state: ActiveWorkContextState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Actions")
                .font(.system(.headline, design: .rounded))

            HStack(spacing: 10) {
                ForEach(state.quickActions) { action in
                    Button {
                        _ = commandHandler.perform(action.command)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: action.symbolName)
                            Text(action.title)
                                .lineLimit(1)
                        }
                        .font(.system(.subheadline, design: .rounded))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(action.isEnabled ? 0.07 : 0.03))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!action.isEnabled)
                }
            }
        }
    }

    @ViewBuilder
    private func paneActions(for state: ActiveWorkContextState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pane Controls")
                .font(.system(.headline, design: .rounded))

            HStack(spacing: 10) {
                ForEach(state.paneActions) { action in
                    Button {
                        _ = commandHandler.perform(action.command)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: action.symbolName)
                            Text(action.title)
                                .lineLimit(1)
                        }
                        .font(.system(.subheadline, design: .rounded))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(action.isEnabled ? 0.07 : 0.03))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!action.isEnabled)
                }
            }
        }
    }

    private func statusPill(label: String, accentName: String) -> some View {
        let accent: Color
        switch accentName {
        case "green":
            accent = .green
        case "orange":
            accent = .orange
        case "teal":
            accent = .teal
        case "red":
            accent = .red
        default:
            accent = .secondary
        }

        return HStack(spacing: 8) {
            Circle()
                .fill(accent)
                .frame(width: 8, height: 8)

            Text(label)
                .font(.system(.caption, design: .rounded))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }
}
