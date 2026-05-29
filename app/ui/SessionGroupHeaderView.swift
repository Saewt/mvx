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
        let doneSessionCount = workspace.sessions(inGroup: group.id)
            .filter { $0.agentStatus == .done }
            .count
        let collapseActionLabel = Self.collapseActionLabel(isCollapsed: group.isCollapsed)

        return HStack(spacing: MvxLayout.indicatorGap) {
            Button {
                _ = workspace.setGroupCollapsed(id: group.id, isCollapsed: !group.isCollapsed)
            } label: {
                Image(systemName: group.isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: MvxIcon.glyph, weight: .semibold))
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                    .frame(width: MvxLayout.indicatorLane, height: MvxLayout.indicatorLane)
            }
            .buttonStyle(.plain)
            .help(collapseActionLabel)
            .accessibilityLabel(Text(collapseActionLabel))

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
                    .font(MvxText.rowTitle)
                    .lineLimit(1)
            }

            if let colorTag = group.colorTag {
                Circle()
                    .fill(MvxStatusStyle.color(for: colorTag))
                    .frame(width: MvxIcon.statusDot, height: MvxIcon.statusDot)
            }

            Spacer(minLength: 0)

            if group.isCollapsed, aggregateStatus != .none {
                Circle()
                    .fill(MvxStatusStyle.color(for: aggregateStatus))
                    .frame(width: MvxIcon.statusDot, height: MvxIcon.statusDot)
                    .help(aggregateStatus.badgeLabel ?? "")
                    .accessibilityLabel(Text(aggregateStatus.badgeLabel ?? ""))
            }

            Text("\(sessionCount)")
                .font(MvxText.meta)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(MvxSurface.cardTint)
                )
        }
        .padding(.horizontal, MvxSpacing.md)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: MvxRadius.control, style: .continuous)
                .fill(isActive ? MvxSurface.selectionTint : Color.clear)
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

            Menu("Color") {
                ForEach(SessionGroupColor.allCases, id: \.self) { colorOption in
                    Button {
                        _ = workspace.setGroupColorTag(id: group.id, colorTag: colorOption)
                    } label: {
                        Label(colorOption.displayName, systemImage: group.colorTag == colorOption ? "checkmark.circle.fill" : "circle.fill")
                    }
                }

                Divider()

                Button("None") {
                    _ = workspace.setGroupColorTag(id: group.id, colorTag: nil)
                }
            }

            Divider()

            Button("Close Done Sessions") {
                _ = workspace.closeDoneSessions(inGroup: group.id)
            }
            .disabled(doneSessionCount == 0)

            Button("Close All Sessions") {
                _ = workspace.closeAllSessions(inGroup: group.id)
            }
            .disabled(sessionCount == 0)

            Button("Move All to Ungrouped") {
                _ = workspace.moveAllSessions(fromGroup: group.id, toGroup: nil)
            }
            .disabled(sessionCount == 0)

            Button("Collapse Other Groups") {
                _ = workspace.collapseOtherGroups(excluding: group.id)
            }

            Divider()

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
}
