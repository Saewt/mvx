import SwiftUI

public struct WorkspaceNotesCardState: Equatable {
    public let title: String
    public let showsTriggerBadge: Bool
    public let isHighlighted: Bool
    public let highlightColorName: String
    public let showsClearAction: Bool

    public static func resolve(
        note: WorkspaceNoteSnapshot?,
        metadata: WorkspaceMetadataSnapshot
    ) -> WorkspaceNotesCardState {
        let highlightColorName: String
        switch metadata.reviewState {
        case .ready:
            highlightColorName = "teal"
        case .reviewRequested:
            highlightColorName = "orange"
        default:
            highlightColorName = "none"
        }

        let isHighlighted = highlightColorName != "none"

        return WorkspaceNotesCardState(
            title: "Notes",
            showsTriggerBadge: note != nil,
            isHighlighted: isHighlighted,
            highlightColorName: highlightColorName,
            showsClearAction: note != nil
        )
    }

    public static func resolveScopeLabel(
        activeGroupID: UUID?,
        sessionGroups: [SessionGroup]
    ) -> String {
        guard let activeGroupID else {
            return "Ungrouped"
        }

        return sessionGroups.first(where: { $0.id == activeGroupID })?.name ?? "Ungrouped"
    }
}

@MainActor
final class WorkspaceNotesEditorController: ObservableObject {
    @Published private(set) var draftBody: String

    private let workspace: SessionWorkspace
    private let debounceNanoseconds: UInt64
    private var scopeGroupID: UUID?
    private var pendingCommitTask: Task<Void, Never>?

    init(workspace: SessionWorkspace, debounceNanoseconds: UInt64 = 250_000_000) {
        self.workspace = workspace
        self.debounceNanoseconds = debounceNanoseconds
        self.scopeGroupID = workspace.activeGroupID
        self.draftBody = workspace.note(forGroup: workspace.activeGroupID)?.body ?? ""
    }

    func updateDraft(_ body: String) {
        guard draftBody != body else {
            return
        }

        draftBody = body
        scheduleCommit()
    }

    func clear() {
        pendingCommitTask?.cancel()
        pendingCommitTask = nil
        draftBody = ""
        _ = workspace.clearNote(forGroup: scopeGroupID)
    }

    func flush() {
        commitNow()
    }

    func switchScope(to groupID: UUID?) {
        guard scopeGroupID != groupID else {
            syncFromWorkspace()
            return
        }

        commitNow()
        scopeGroupID = groupID
        syncFromWorkspace()
    }

    func syncFromWorkspace() {
        guard pendingCommitTask == nil else {
            return
        }

        let nextDraft = workspace.note(forGroup: scopeGroupID)?.body ?? ""
        guard draftBody != nextDraft else {
            return
        }

        draftBody = nextDraft
    }

    private func scheduleCommit() {
        pendingCommitTask?.cancel()
        pendingCommitTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                try await Task.sleep(nanoseconds: debounceNanoseconds)
            } catch {
                return
            }

            guard !Task.isCancelled else {
                return
            }

            commitNow()
        }
    }

    private func commitNow() {
        pendingCommitTask?.cancel()
        pendingCommitTask = nil
        _ = workspace.updateNote(body: draftBody, forGroup: scopeGroupID)
        draftBody = workspace.note(forGroup: scopeGroupID)?.body ?? ""
    }
}

@MainActor
public struct WorkspaceNotesCardView: View {
    @ObservedObject private var workspace: SessionWorkspace
    private let metadata: WorkspaceMetadataSnapshot
    @StateObject private var controller: WorkspaceNotesEditorController
    @State private var isPopoverPresented = false
    @FocusState private var isEditorFocused: Bool

    public init(workspace: SessionWorkspace, metadata: WorkspaceMetadataSnapshot) {
        self.workspace = workspace
        self.metadata = metadata
        _controller = StateObject(wrappedValue: WorkspaceNotesEditorController(workspace: workspace))
    }

    public var body: some View {
        let state = WorkspaceNotesCardState.resolve(
            note: workspace.activeScopeNote,
            metadata: metadata
        )
        let scopeLabel = WorkspaceNotesCardState.resolveScopeLabel(
            activeGroupID: workspace.activeGroupID,
            sessionGroups: workspace.sessionGroups
        )
        let highlightColor = color(for: state.highlightColorName)
        let showsClearAction = state.showsClearAction || !controller.draftBody.isEmpty

        Button(action: togglePopover) {
            Image(systemName: "note.text")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            isPopoverPresented
                                ? (state.isHighlighted
                                    ? highlightColor.opacity(0.18)
                                    : Color.white.opacity(0.12))
                                : (state.isHighlighted
                                    ? highlightColor.opacity(0.10)
                                    : Color.white.opacity(0.08))
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(
                            state.isHighlighted
                                ? highlightColor.opacity(isPopoverPresented ? 0.55 : 0.36)
                                : Color.white.opacity(isPopoverPresented ? 0.16 : 0.08),
                            lineWidth: 1
                        )
                )
                .overlay(alignment: .topTrailing) {
                    if state.showsTriggerBadge {
                        Circle()
                            .fill(state.isHighlighted ? highlightColor : .accentColor)
                            .frame(width: 7, height: 7)
                            .offset(x: 2, y: -2)
                    }
                }
        }
        .onAppear {
            controller.syncFromWorkspace()
        }
        .popover(isPresented: $isPopoverPresented, arrowEdge: .top) {
            popoverContent(
                title: state.title,
                scopeLabel: scopeLabel,
                showsClearAction: showsClearAction
            )
        }
        .onChange(of: workspace.activeGroupID) { newValue in
            controller.switchScope(to: newValue)
        }
        .onChange(of: workspace.activeScopeNote?.body) { newValue in
            _ = newValue
            controller.syncFromWorkspace()
        }
        .onChange(of: isPopoverPresented) { isPresented in
            if isPresented {
                controller.syncFromWorkspace()
                DispatchQueue.main.async {
                    isEditorFocused = true
                }
            } else {
                isEditorFocused = false
                controller.flush()
            }
        }
        .onDisappear {
            controller.flush()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Notes")
        .help("Notes")
    }

    private func actionButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }

    private func popoverContent(title: String, scopeLabel: String, showsClearAction: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.caption, design: .rounded).weight(.semibold))

                    Text(scopeLabel)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if showsClearAction {
                    actionButton(title: "Clear", action: clearNote)
                }
            }

            TextEditor(
                text: Binding(
                    get: { controller.draftBody },
                    set: { controller.updateDraft($0) }
                )
            )
            .font(.system(.caption2, design: .monospaced))
            .frame(width: 304, height: 178)
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                if controller.draftBody.isEmpty {
                    Text("Pick up where you left off…")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(EdgeInsets(top: 8, leading: 6, bottom: 0, trailing: 0))
                        .allowsHitTesting(false)
                }
            }
            .focused($isEditorFocused)
        }
        .padding(10)
    }

    private func clearNote() {
        controller.clear()
    }

    private func togglePopover() {
        isPopoverPresented.toggle()
    }

    private func color(for colorName: String) -> Color {
        switch colorName {
        case "teal":
            return .teal
        case "orange":
            return .orange
        default:
            return .clear
        }
    }
}
