import SwiftUI

public struct WorkspaceCardVisualState: Equatable {
    public let isActive: Bool
    public let showsGitStatus: Bool
    public let showsAttention: Bool
    public let backgroundOpacity: Double
    public let borderOpacity: Double
    public let glowOpacity: Double
    public let glowColorName: String

    public static func resolve(isActive: Bool, metadata: WorkspaceCardMetadata?) -> WorkspaceCardVisualState {
        let showsError = (metadata?.errorCount ?? 0) > 0
        let showsWaiting = (metadata?.waitingCount ?? 0) > 0
        let showsAttention = showsError || showsWaiting
        let glowColorName: String
        if showsError {
            glowColorName = "red"
        } else if showsWaiting {
            glowColorName = "orange"
        } else if isActive {
            glowColorName = "accent"
        } else {
            glowColorName = "none"
        }

        return WorkspaceCardVisualState(
            isActive: isActive,
            showsGitStatus: metadata?.hasGitStatus ?? false,
            showsAttention: showsAttention,
            backgroundOpacity: isActive ? 0.18 : 0.04,
            borderOpacity: isActive ? (showsAttention ? 0.78 : 0.7) : (showsAttention ? 0.18 : 0.08),
            glowOpacity: isActive ? (showsAttention ? 0.28 : 0.22) : 0,
            glowColorName: glowColorName
        )
    }
}

public struct SessionSidebarSectionState: Equatable {
    public let showsUngroupedSection: Bool

    @MainActor
    public static func resolve(workspace: SessionWorkspace) -> SessionSidebarSectionState {
        SessionSidebarSectionState(
            showsUngroupedSection: !workspace.sessions(inGroup: nil).isEmpty
        )
    }
}

@MainActor
public struct SessionSidebarView: View {
    @ObservedObject private var workspace: SessionWorkspace
    @ObservedObject private var commandHandler: WorkspaceCommandHandler
    var registry: WorkspaceRegistry?
    private let onCollapse: (() -> Void)?
    @StateObject private var fileTreeController: WorkspaceFileTreeController
    @State private var pendingRenameGroupID: UUID?
    @State private var pendingRenameWorkspaceID: UUID?
    @State private var workspaceRenameController = SessionTabRenameController()
    @State private var durationReferenceDate = Date()

    public init(
        workspace: SessionWorkspace,
        commandHandler: WorkspaceCommandHandler,
        registry: WorkspaceRegistry? = nil,
        onCollapse: (() -> Void)? = nil
    ) {
        self.workspace = workspace
        self.commandHandler = commandHandler
        self.registry = registry
        self.onCollapse = onCollapse
        _fileTreeController = StateObject(
            wrappedValue: WorkspaceFileTreeController(workspace: workspace)
        )
    }

    public var body: some View {
        let chrome = SessionRailChromeState.resolve(workspace: workspace)
        let metadata = workspace.workspaceMetadata
        let focusedSessionID = workspace.workspaceGraph.focusedSessionID

        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Text("MVX")
                    .font(.system(.caption, design: .monospaced).weight(.heavy))
                    .tracking(4)
                    .foregroundStyle(.secondary)
                    .layoutPriority(1)
                    .fixedSize()

                Spacer()

                ForEach(chrome.topActions) { action in
                    railActionButton(action)
                }

                WorkspaceNotesCardView(workspace: workspace, metadata: metadata)

                chromeButton(symbolName: "folder.badge.plus", tooltip: "New Group", action: createGroup)
                    .accessibilityLabel("New Group")

                if let onCollapse {
                    chromeButton(symbolName: "chevron.left", tooltip: "Hide Sidebar", action: onCollapse)
                        .accessibilityLabel("Hide Sidebar")
                }
            }
            .padding(.top, 10)

            if let registry {
                workspaceSwitcher(registry: registry)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(metadata.branchName)
                    .font(.system(.subheadline, design: .monospaced))
                    .lineLimit(1)

                Text(metadata.reviewState.label)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)

                Text("\(metadata.notificationCount) alerts · \(metadata.paneCount) pane\(metadata.paneCount == 1 ? "" : "s")")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )

            WorkspaceFileTreeSectionView(
                controller: fileTreeController,
                workspace: workspace
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(chrome.activeSessionTitle ?? "Sessions")
                    .font(.system(.headline, design: .rounded))
                    .lineLimit(1)

                Text("\(chrome.sessionCount) session\(chrome.sessionCount == 1 ? "" : "s")")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                LazyVStack(spacing: 6) {
                    sidebarSections(focusedSessionID: focusedSessionID)
                }
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.never)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(red: 0.09, green: 0.10, blue: 0.13))
        .onAppear {
            fileTreeController.bind(to: workspace)
            _ = fileTreeController.syncFromWorkspace()
        }
        .onChange(of: workspace.activeSessionID) { _ in
            fileTreeController.bind(to: workspace)
            _ = fileTreeController.syncFromWorkspace()
        }
        .onChange(of: workspace.activeDescriptor?.workingDirectoryPath) { _ in
            _ = fileTreeController.syncFromWorkspace()
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            durationReferenceDate = Date()
        }
    }

    @ViewBuilder
    private func workspaceSwitcher(registry: WorkspaceRegistry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Workspaces")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                chromeButton(symbolName: "plus", tooltip: "New Workspace") {
                    createWorkspace(in: registry)
                }
                .accessibilityLabel("New Workspace")
            }

            ForEach(registry.entries) { entry in
                let isActive = registry.activeWorkspaceID == entry.id
                let metadata = registry.cardMetadata(for: entry.id)
                let isRenaming = pendingRenameWorkspaceID == entry.id && workspaceRenameController.isRenaming
                let visualState = WorkspaceCardVisualState.resolve(
                    isActive: isActive,
                    metadata: metadata
                )
                let glowColor = workspaceCardGlowColor(for: visualState)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        Capsule(style: .continuous)
                            .fill(isActive ? Color.accentColor : Color.gray.opacity(0.35))
                            .frame(width: isActive ? 14 : 8, height: 5)

                        if isRenaming {
                            SessionInlineRenameField(
                                text: Binding(
                                    get: { workspaceRenameController.draftTitle },
                                    set: { workspaceRenameController.updateDraft($0) }
                                ),
                                activationID: workspaceRenameController.activationID,
                                selectionBehavior: workspaceRenameController.selectionBehavior,
                                onCommit: { commitWorkspaceRename(entry: entry, registry: registry) },
                                onCancel: cancelWorkspaceRename
                            )
                        } else {
                            Text(metadata?.name ?? entry.name)
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)

                        if let metadata {
                            workspaceMetricBadge(
                                "\(metadata.paneCount) pane\(metadata.paneCount == 1 ? "" : "s")"
                            )
                        }
                    }

                    if let metadata {
                        Text("\(metadata.sessionCount) session\(metadata.sessionCount == 1 ? "" : "s") · \(metadata.groupCount) group\(metadata.groupCount == 1 ? "" : "s") · \(metadata.paneCount) pane\(metadata.paneCount == 1 ? "" : "s")")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Text(metadata?.branchName ?? "No Branch")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        if let addedCount = metadata?.gitAddedCount,
                           let removedCount = metadata?.gitRemovedCount {
                            Text("+\(addedCount)")
                                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                                .foregroundStyle(.green)

                            Text("-\(removedCount)")
                                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                                .foregroundStyle(.red)
                        }

                        if let metadata, metadata.waitingCount > 0 {
                            workspaceMetricBadge("\(metadata.waitingCount) waiting")
                        }

                        if let metadata, metadata.errorCount > 0 {
                            workspaceMetricBadge("\(metadata.errorCount) error\(metadata.errorCount == 1 ? "" : "s")")
                        }

                        Spacer(minLength: 0)

                        if let metadata, metadata.notificationCount > 0 {
                            workspaceMetricBadge(
                                "\(metadata.notificationCount) alert\(metadata.notificationCount == 1 ? "" : "s")"
                            )
                        }
                    }
                }
                .padding(.vertical, 9)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            isActive
                                ? Color.accentColor.opacity(visualState.backgroundOpacity)
                                : Color.white.opacity(visualState.backgroundOpacity)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            isActive
                                ? glowColor.opacity(visualState.borderOpacity)
                                : (visualState.showsAttention
                                    ? glowColor.opacity(visualState.borderOpacity)
                                    : Color.white.opacity(visualState.borderOpacity)),
                            lineWidth: 1
                        )
                )
                .shadow(
                    color: isActive ? glowColor.opacity(visualState.glowOpacity) : .clear,
                    radius: 10
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !isRenaming else {
                        return
                    }
                    _ = registry.activateWorkspace(id: entry.id)
                }
                .contextMenu {
                    Button("Rename Workspace") {
                        beginWorkspaceRename(entry: entry)
                    }

                    Button("Close Workspace") {
                        _ = registry.closeWorkspace(id: entry.id)
                    }
                    .disabled(registry.entries.count <= 1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    Text(
                        metadata.map {
                            "\($0.name), \($0.sessionCount) sessions, \($0.groupCount) groups, \($0.paneCount) panes"
                        } ?? entry.name
                    )
                )
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
    }

    private func workspaceMetricBadge(_ label: String) -> some View {
        Text(label)
            .font(.system(.caption2, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
    }

    private func workspaceCardGlowColor(for visualState: WorkspaceCardVisualState) -> Color {
        switch visualState.glowColorName {
        case "red":
            return .red
        case "orange":
            return .orange
        case "accent":
            return .accentColor
        default:
            return .clear
        }
    }

    private func railActionButton(_ action: SessionRailChromeState.TopAction) -> some View {
        chromeButton(
            symbolName: action.symbolName,
            isEnabled: action.isEnabled,
            tooltip: action.tooltip
        ) {
            _ = commandHandler.perform(action.command)
        }
    }

    @ViewBuilder
    private func sidebarSections(focusedSessionID: UUID?) -> some View {
        if workspace.sessionGroups.isEmpty {
            ForEach(workspace.sessions) { descriptor in
                sessionRow(for: descriptor, focusedSessionID: focusedSessionID)
            }
        } else {
            let ungrouped = workspace.sessions(inGroup: nil)
            let sectionState = SessionSidebarSectionState.resolve(workspace: workspace)

            if sectionState.showsUngroupedSection {
                ungroupedSectionHeader(
                    sessionCount: ungrouped.count,
                    isActive: workspace.activeGroupID == nil
                )

                ForEach(ungrouped) { descriptor in
                    sessionRow(for: descriptor, focusedSessionID: focusedSessionID)
                }
            }

            ForEach(workspace.sessionGroups) { group in
                SessionGroupHeaderView(
                    workspace: workspace,
                    group: group,
                    isActive: workspace.activeGroupID == group.id,
                    isPendingInitialRename: pendingRenameGroupID == group.id,
                    onInitialRenameConsumed: {
                        if pendingRenameGroupID == group.id {
                            pendingRenameGroupID = nil
                        }
                    }
                )

                if !group.isCollapsed {
                    ForEach(workspace.sessions(inGroup: group.id)) { descriptor in
                        sessionRow(for: descriptor, focusedSessionID: focusedSessionID)
                    }
                }
            }
        }
    }

    private func sessionRow(for descriptor: SessionDescriptor, focusedSessionID: UUID?) -> some View {
        SessionTabRowView(
            workspace: workspace,
            descriptor: descriptor,
            isFocusedInTiling: descriptor.id == focusedSessionID,
            gitChangeSummary: workspace.gitChangeSummary(for: descriptor.id),
            durationReferenceDate: durationReferenceDate
        )
    }

    private func ungroupedSectionHeader(sessionCount: Int, isActive: Bool) -> some View {
        HStack(spacing: 8) {
            Text("Ungrouped")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Text("\(sessionCount)")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isActive ? Color.accentColor.opacity(0.14) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isActive ? Color.accentColor.opacity(0.7) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            _ = workspace.selectGroup(id: nil)
        }
        .dropDestination(for: String.self) { identifiers, _ in
            guard let identifier = identifiers.first else {
                return false
            }

            return workspace.handleDroppedSession(identifier: identifier, toGroup: nil)
        }
    }

    private func chromeButton(
        symbolName: String,
        isEnabled: Bool = true,
        tooltip: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            guard isEnabled else {
                return
            }

            action()
        } label: {
            Image(systemName: symbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.72))
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(isEnabled ? 0.08 : 0.04))
                )
        }
        .buttonStyle(.plain)
        .help(tooltip ?? "")
    }

    private func createGroup() {
        let group = workspace.createGroup(name: "", colorTag: nil)
        _ = workspace.selectGroup(id: group.id)
        pendingRenameGroupID = group.id
    }

    private func createWorkspace(in registry: WorkspaceRegistry) {
        let entry = registry.createWorkspace(name: nextWorkspaceName(in: registry))
        beginWorkspaceRename(entry: entry)
    }

    private func beginWorkspaceRename(entry: WorkspaceEntry) {
        pendingRenameWorkspaceID = entry.id
        workspaceRenameController.beginRename(
            currentTitle: entry.name,
            selectionBehavior: .selectAll
        )
    }

    private func commitWorkspaceRename(entry: WorkspaceEntry, registry: WorkspaceRegistry) {
        let committed = workspaceRenameController.commit()
        _ = registry.renameWorkspace(id: entry.id, name: committed)
        pendingRenameWorkspaceID = nil
    }

    private func cancelWorkspaceRename() {
        workspaceRenameController.cancel()
        pendingRenameWorkspaceID = nil
    }

    private func nextWorkspaceName(in registry: WorkspaceRegistry) -> String {
        var index = registry.entries.count + 1
        while registry.entries.contains(where: { $0.name == "Workspace \(index)" }) {
            index += 1
        }
        return "Workspace \(index)"
    }
}
