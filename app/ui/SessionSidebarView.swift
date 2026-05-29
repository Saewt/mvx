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
            backgroundOpacity: isActive ? 0.12 : 0,
            borderOpacity: 0,
            glowOpacity: 0,
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
    @State private var attentionPulseOpacity: Double = 1.0
    @State private var isNotesPopoverPresented = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

        VStack(spacing: MvxSpacing.md) {
            HStack(spacing: MvxSpacing.sm) {
                Text("MVX")
                    .font(MvxText.wordmark)
                    .tracking(4)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(0)

                if chrome.attentionCount > 0 {
                    Button {
                        _ = commandHandler.perform(.nextAttention)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: MvxIcon.glyph, weight: .bold))
                            Text("\(chrome.attentionCount)")
                                .font(MvxText.meta)
                        }
                        .foregroundStyle(chrome.attentionIsError ? .red : .orange)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: MvxRadius.control / 2, style: .continuous)
                                .fill(MvxSurface.cardTint)
                        )
                    }
                    .buttonStyle(.plain)
                    .opacity(chrome.attentionCount > 0 ? attentionPulseOpacity : 1)
                    .animation(
                        chrome.attentionCount > 0 && !reduceMotion ? MvxMotion.pulse : .none,
                        value: attentionPulseOpacity
                    )
                    .help("Jump to next session needing attention (\(chrome.attentionCount))")
                    .accessibilityLabel("Jump to next session needing attention (\(chrome.attentionCount))")
                }

                Spacer()

                ForEach(chrome.topActions) { action in
                    railActionButton(action)
                }

                Menu {
                    Button {
                        isNotesPopoverPresented = true
                    } label: {
                        Label("Notes", systemImage: "note.text")
                    }

                    Button {
                        createGroup()
                    } label: {
                        Label("New Group", systemImage: "folder.badge.plus")
                    }
                } label: {
                    chromeButtonLabel(symbolName: "ellipsis", isEnabled: true)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("More")
                .accessibilityLabel("More")

                if let onCollapse {
                    chromeButton(symbolName: "chevron.left", tooltip: "Hide Sidebar", action: onCollapse)
                        .accessibilityLabel("Hide Sidebar")
                        .layoutPriority(3)
                }
            }
            .padding(.top, MvxLayout.topChromeInset)
            .padding(.leading, MvxLayout.titleLeadingInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .topTrailing) {
                WorkspaceNotesCardView(
                    workspace: workspace,
                    metadata: metadata,
                    isPresented: $isNotesPopoverPresented,
                    showsButton: false
                )
            }

            if let registry {
                workspaceSwitcher(registry: registry)
            }

            MvxSectionHeader(title: "Sessions", count: chrome.sessionCount)

            ScrollView {
                LazyVStack(spacing: 4) {
                    sidebarSections(focusedSessionID: focusedSessionID)
                }
                .frame(maxWidth: .infinity)
                .animation(reduceMotion ? .none : MvxMotion.standard, value: workspace.sessions.map(\.id))
            }
            .scrollIndicators(.never)
            .frame(maxHeight: .infinity)

            Rectangle()
                .fill(MvxSurface.hairline)
                .frame(height: 1)

            WorkspaceFileTreeSectionView(
                controller: fileTreeController,
                workspace: workspace
            )
        }
        .padding(.horizontal, MvxSpacing.sm)
        .padding(.bottom, MvxSpacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(MvxSurface.sidebar)
        .onAppear {
            fileTreeController.bind(to: workspace)
            _ = fileTreeController.syncFromWorkspace()
            updateAttentionPulse(hasAttention: chrome.attentionCount > 0)
        }
        .onChange(of: chrome.attentionCount) { attentionCount in
            updateAttentionPulse(hasAttention: attentionCount > 0)
        }
        .onChange(of: reduceMotion) { _ in
            updateAttentionPulse(hasAttention: chrome.attentionCount > 0)
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
        VStack(alignment: .leading, spacing: MvxSpacing.xs) {
            HStack(spacing: MvxSpacing.xs) {
                MvxSectionHeader(title: "Workspaces")

                chromeButton(symbolName: "plus", tooltip: "New Workspace") {
                    createWorkspace(in: registry)
                }
                .accessibilityLabel("New Workspace")
            }
            .padding(.trailing, MvxSpacing.md)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(registry.entries) { entry in
                        workspaceRow(entry: entry, registry: registry)
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(maxHeight: workspaceSwitcherMaxHeight(for: registry.entries.count))
        }
    }

    private func workspaceSwitcherMaxHeight(for count: Int) -> CGFloat {
        min(CGFloat(max(count, 1)) * 24, 76)
    }

    private func workspaceRow(entry: WorkspaceEntry, registry: WorkspaceRegistry) -> some View {
        let isActive = registry.activeWorkspaceID == entry.id
        let metadata = registry.cardMetadata(for: entry.id)
        let isRenaming = pendingRenameWorkspaceID == entry.id && workspaceRenameController.isRenaming
        let visualState = WorkspaceCardVisualState.resolve(
            isActive: isActive,
            metadata: metadata
        )

        return HStack(spacing: MvxLayout.indicatorGap) {
            Color.clear
                .frame(width: MvxLayout.indicatorLane)

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
                    .font(MvxText.meta)
                    .foregroundStyle(isActive ? Color.primary : Color.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if let metadata {
                HStack(spacing: 4) {
                    if metadata.errorCount > 0 {
                        Circle()
                            .fill(MvxStatusStyle.color(forLegacyAgentColorName: "red"))
                            .frame(width: MvxIcon.statusDot - 3, height: MvxIcon.statusDot - 3)
                    }
                    if metadata.waitingCount > 0 {
                        Circle()
                            .fill(MvxStatusStyle.color(forLegacyAgentColorName: "orange"))
                            .frame(width: MvxIcon.statusDot - 3, height: MvxIcon.statusDot - 3)
                    }
                }

                Text("\(metadata.paneCount)")
                    .font(MvxText.meta)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        Capsule(style: .continuous)
                            .fill(MvxSurface.cardTint)
                    )
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, MvxSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: MvxRadius.control, style: .continuous)
                .fill(isActive ? Color.accentColor.opacity(visualState.backgroundOpacity) : Color.clear)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(isActive ? Color.accentColor : Color.clear)
                .frame(width: 2)
                .padding(.vertical, 4)
        }
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
                MvxSectionHeader(title: "Ungrouped", count: ungrouped.count)
                    .background(
                        RoundedRectangle(cornerRadius: MvxRadius.control, style: .continuous)
                            .fill(workspace.activeGroupID == nil ? MvxSurface.selectionTint : Color.clear)
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
        let identity = SessionDisplayIdentityResolver.resolve(
            descriptor: descriptor,
            visibleDescriptors: workspace.sessions,
            branchName: workspace.workspaceMetadata.branchName,
            gitChangeSummary: workspace.gitChangeSummary(for: descriptor.id)
        )

        return SessionTabRowView(
            workspace: workspace,
            descriptor: descriptor,
            displayIdentity: identity,
            isFocusedInTiling: descriptor.id == focusedSessionID,
            gitChangeSummary: workspace.gitChangeSummary(for: descriptor.id),
            durationReferenceDate: durationReferenceDate
        )
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
            chromeButtonLabel(symbolName: symbolName, isEnabled: isEnabled)
        }
        .buttonStyle(.plain)
        .help(tooltip ?? "")
    }

    private func chromeButtonLabel(symbolName: String, isEnabled: Bool) -> some View {
        Image(systemName: symbolName)
            .font(.system(size: MvxIcon.controlSymbolSize, weight: .semibold))
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.72))
            .frame(width: MvxIcon.controlButtonSize, height: MvxIcon.controlButtonSize)
            .background(
                RoundedRectangle(cornerRadius: MvxRadius.control, style: .continuous)
                    .fill(isEnabled ? MvxSurface.hairline : MvxSurface.cardTint)
            )
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

    private func updateAttentionPulse(hasAttention: Bool) {
        attentionPulseOpacity = hasAttention && !reduceMotion ? 0.6 : 1.0
    }
}
