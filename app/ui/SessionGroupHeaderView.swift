import SwiftUI

@MainActor
public struct SessionGroupHeaderView: View {
    @ObservedObject private var workspace: SessionWorkspace
    private let group: SessionGroup
    private let isActive: Bool
    private let isPendingInitialRename: Bool
    private let onInitialRenameConsumed: (() -> Void)?

    @State private var renameController = SessionTabRenameController()
    @State private var hasConsumedInitialRename = false

    public init(
        workspace: SessionWorkspace,
        group: SessionGroup,
        isActive: Bool,
        isPendingInitialRename: Bool = false,
        onInitialRenameConsumed: (() -> Void)? = nil
    ) {
        self.workspace = workspace
        self.group = group
        self.isActive = isActive
        self.isPendingInitialRename = isPendingInitialRename
        self.onInitialRenameConsumed = onInitialRenameConsumed
    }

    public var body: some View {
        let aggregateStatus = workspace.aggregatedAgentStatus(forGroup: group.id)
        let sessionCount = workspace.sessions(inGroup: group.id).count
        let collapseActionLabel = Self.collapseActionLabel(isCollapsed: group.isCollapsed)

        return HStack(spacing: 8) {
            Button {
                _ = workspace.setGroupCollapsed(id: group.id, isCollapsed: !group.isCollapsed)
            } label: {
                Image(systemName: group.isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .help(collapseActionLabel)
            .accessibilityLabel(Text(collapseActionLabel))

            if let colorTag = group.colorTag {
                Circle()
                    .fill(color(for: colorTag))
                    .frame(width: 8, height: 8)
            }

            if renameController.isRenaming {
                SessionInlineRenameField(
                    text: Binding(
                        get: { renameController.draftTitle },
                        set: { renameController.updateDraft($0) }
                    ),
                    activationID: renameController.activationID,
                    selectionBehavior: renameController.selectionBehavior,
                    onCommit: commitRename,
                    onCancel: cancelRename
                )
            } else {
                Text(group.name)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if group.isCollapsed, aggregateStatus != .none {
                Circle()
                    .fill(color(for: aggregateStatus))
                    .frame(width: 9, height: 9)
                    .help(aggregateStatus.badgeLabel ?? "")
                    .accessibilityLabel(Text(aggregateStatus.badgeLabel ?? ""))
            }

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
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isActive ? Color.accentColor.opacity(0.14) : Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isActive ? Color.accentColor.opacity(0.7) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            guard !renameController.isRenaming else {
                return
            }

            let _ = workspace.selectGroup(id: group.id)
            if group.isCollapsed {
                _ = workspace.setGroupCollapsed(id: group.id, isCollapsed: false)
            }
        }
        .onAppear {
            activateInitialRenameIfNeeded()
        }
        .onChange(of: isPendingInitialRename) { shouldRename in
            if !shouldRename {
                hasConsumedInitialRename = false
            }
            activateInitialRenameIfNeeded()
        }
        .dropDestination(for: String.self) { identifiers, _ in
            guard let identifier = identifiers.first else {
                return false
            }

            return workspace.handleDroppedSession(identifier: identifier, toGroup: group.id)
        }
        .contextMenu {
            Button("Rename Group") {
                renameController.beginRename(
                    currentTitle: group.name,
                    selectionBehavior: .placeCaretAtEnd
                )
            }

            Button("Delete Group") {
                _ = workspace.deleteGroup(id: group.id)
            }
        }
    }

    static func collapseActionLabel(isCollapsed: Bool) -> String {
        isCollapsed ? "Expand Group" : "Collapse Group"
    }

    private func activateInitialRenameIfNeeded() {
        guard isPendingInitialRename, !hasConsumedInitialRename else {
            return
        }

        hasConsumedInitialRename = true
        renameController.beginRename(
            currentTitle: group.name,
            selectionBehavior: .selectAll
        )
        onInitialRenameConsumed?()
    }

    private func commitRename() {
        let committed = renameController.commit()
        _ = workspace.renameGroup(id: group.id, name: committed)
    }

    private func cancelRename() {
        renameController.cancel()
    }

    private func color(for groupColor: SessionGroupColor) -> Color {
        switch groupColor {
        case .blue:
            return .blue
        case .green:
            return .green
        case .orange:
            return .orange
        case .red:
            return .red
        case .purple:
            return .purple
        case .teal:
            return .teal
        }
    }

    private func color(for status: SessionAgentStatus) -> Color {
        switch status.badgeColorName {
        case "green":
            return .green
        case "orange":
            return .orange
        case "blue":
            return .blue
        case "red":
            return .red
        default:
            return .clear
        }
    }
}
