import AppKit
import SwiftUI

public struct SessionTabRowVisualState: Equatable {
    public let isSelected: Bool
    public let isFocusedInTiling: Bool
    public let selectionIndicatorStyleName: String
    public let selectionIndicatorColorName: String
    public let showsAgentBadge: Bool
    public let agentBadgeShapeName: String?
    public let agentBadgeLabel: String?
    public let agentBadgeColorName: String?
    public let showsGitBadge: Bool
    public let gitAddedCount: Int?
    public let gitRemovedCount: Int?
    public let focusBorderOpacity: Double
    public let focusGlowOpacity: Double

    public static func resolve(
        descriptor: SessionDescriptor,
        activeSessionID: UUID?,
        isFocusedInTiling: Bool = false,
        gitChangeSummary: WorkspaceGitChangeSummary? = nil
    ) -> SessionTabRowVisualState {
        let isSelected = descriptor.id == activeSessionID
        let showsAgentBadge = descriptor.agentStatus.showsBadge
        let showsGitBadge = gitChangeSummary != nil
        return SessionTabRowVisualState(
            isSelected: isSelected,
            isFocusedInTiling: isFocusedInTiling,
            selectionIndicatorStyleName: isSelected ? "bar" : "dot",
            selectionIndicatorColorName: isSelected ? "accent" : "secondary",
            showsAgentBadge: showsAgentBadge,
            agentBadgeShapeName: showsAgentBadge ? "dot" : nil,
            agentBadgeLabel: descriptor.agentStatus.badgeLabel,
            agentBadgeColorName: badgeColorName(for: descriptor.agentStatus),
            showsGitBadge: showsGitBadge,
            gitAddedCount: gitChangeSummary?.addedCount,
            gitRemovedCount: gitChangeSummary?.removedCount,
            focusBorderOpacity: isFocusedInTiling ? (isSelected ? 0.78 : 0.42) : 0,
            focusGlowOpacity: isFocusedInTiling ? (isSelected ? 0.26 : 0.18) : 0
        )
    }

    private static func badgeColorName(for status: SessionAgentStatus) -> String? {
        switch status {
        case .none:
            return nil
        case .running:
            return "green"
        case .waiting:
            return "orange"
        case .done:
            return "teal"
        case .error:
            return "red"
        }
    }
}

struct SessionTabDurationState: Equatable {
    let label: String?

    static func resolve(
        startedAt: Date?,
        isRenaming: Bool,
        referenceDate: Date
    ) -> SessionTabDurationState {
        guard !isRenaming, let startedAt else {
            return SessionTabDurationState(label: nil)
        }

        return SessionTabDurationState(
            label: formattedLabel(startedAt: startedAt, referenceDate: referenceDate)
        )
    }

    static func formattedLabel(startedAt: Date, referenceDate: Date) -> String {
        let elapsedSeconds = max(referenceDate.timeIntervalSince(startedAt), 0)
        let elapsedMinutes = Int(elapsedSeconds / 60)

        if elapsedMinutes < 60 {
            return "\(elapsedMinutes)m"
        }

        let elapsedHours = elapsedMinutes / 60
        if elapsedHours < 24 {
            return "\(elapsedHours)h"
        }

        return "\(elapsedHours / 24)d"
    }
}

public enum SessionTabRenameSelectionBehavior: Equatable {
    case selectAll
    case placeCaretAtEnd
}

public struct SessionTabRenameController: Equatable {
    public private(set) var isRenaming = false
    public private(set) var draftTitle = ""
    public private(set) var selectionBehavior: SessionTabRenameSelectionBehavior = .selectAll
    public private(set) var activationID = 0

    public init() {}

    public mutating func beginRename(
        currentTitle: String,
        selectionBehavior: SessionTabRenameSelectionBehavior = .selectAll
    ) {
        isRenaming = true
        draftTitle = currentTitle
        self.selectionBehavior = selectionBehavior
        activationID &+= 1
    }

    public mutating func updateDraft(_ title: String) {
        draftTitle = title
    }

    public mutating func commit() -> String {
        let committed = draftTitle
        isRenaming = false
        draftTitle = ""
        selectionBehavior = .selectAll
        return committed
    }

    public mutating func cancel() {
        isRenaming = false
        draftTitle = ""
        selectionBehavior = .selectAll
    }
}

@MainActor
struct SessionTabSplitCandidate: Identifiable, Equatable {
    let id: UUID
    let title: String
}

@MainActor
struct SessionTabSplitMenuState: Equatable {
    let isEnabled: Bool
    let sourceSessionID: UUID?
    let candidates: [SessionTabSplitCandidate]

    static func resolve(workspace: SessionWorkspace) -> SessionTabSplitMenuState {
        guard let sourceSessionID = workspace.workspaceGraph.focusedSessionID else {
            return SessionTabSplitMenuState(
                isEnabled: false,
                sourceSessionID: nil,
                candidates: []
            )
        }

        let eligibleDescriptors = workspace.sessions.filter { descriptor in
            descriptor.id != sourceSessionID && workspace.paneID(for: descriptor.id) != nil
        }
        let titleCounts = eligibleDescriptors.reduce(into: [String: Int]()) { counts, descriptor in
            counts[descriptor.displayTitle, default: 0] += 1
        }

        let candidates = eligibleDescriptors.map { descriptor in
            let titleCount = titleCounts[descriptor.displayTitle] ?? 0
            let title = titleCount > 1
                ? "\(descriptor.displayTitle) (#\(descriptor.ordinal))"
                : descriptor.displayTitle
            return SessionTabSplitCandidate(id: descriptor.id, title: title)
        }

        return SessionTabSplitMenuState(
            isEnabled: !candidates.isEmpty,
            sourceSessionID: sourceSessionID,
            candidates: candidates
        )
    }
}

struct SessionInlineRenameField: NSViewRepresentable {
    @Binding var text: String
    let activationID: Int
    let selectionBehavior: SessionTabRenameSelectionBehavior
    let onCommit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            onCommit: onCommit,
            onCancel: onCancel
        )
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField(string: text)
        textField.delegate = context.coordinator
        textField.isBordered = true
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.drawsBackground = true
        textField.focusRingType = .default
        textField.usesSingleLineMode = true
        textField.lineBreakMode = .byTruncatingTail
        textField.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.onCommit = onCommit
        context.coordinator.onCancel = onCancel

        if nsView.stringValue != text {
            nsView.stringValue = text
        }

        if context.coordinator.lastActivationID != activationID {
            context.coordinator.applySelection(
                to: nsView,
                activationID: activationID,
                behavior: selectionBehavior
            )
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        private let text: Binding<String>
        var onCommit: () -> Void
        var onCancel: () -> Void
        var lastActivationID: Int?

        init(
            text: Binding<String>,
            onCommit: @escaping () -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.text = text
            self.onCommit = onCommit
            self.onCancel = onCancel
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else {
                return
            }

            text.wrappedValue = textField.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                onCommit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                onCancel()
                return true
            default:
                return false
            }
        }

        func applySelection(
            to textField: NSTextField,
            activationID: Int,
            behavior: SessionTabRenameSelectionBehavior,
            attemptsRemaining: Int = 2
        ) {
            lastActivationID = activationID

            DispatchQueue.main.async { [weak textField] in
                guard let textField else {
                    return
                }

                guard textField.window != nil else {
                    if attemptsRemaining > 0 {
                        self.applySelection(
                            to: textField,
                            activationID: activationID,
                            behavior: behavior,
                            attemptsRemaining: attemptsRemaining - 1
                        )
                    }
                    return
                }

                textField.window?.makeFirstResponder(textField)

                guard let editor = textField.currentEditor() as? NSTextView else {
                    if attemptsRemaining > 0 {
                        self.applySelection(
                            to: textField,
                            activationID: activationID,
                            behavior: behavior,
                            attemptsRemaining: attemptsRemaining - 1
                        )
                    }
                    return
                }

                let textLength = textField.stringValue.utf16.count
                switch behavior {
                case .selectAll:
                    editor.setSelectedRange(NSRange(location: 0, length: textLength))
                case .placeCaretAtEnd:
                    editor.setSelectedRange(NSRange(location: textLength, length: 0))
                }
            }
        }
    }
}

@MainActor
public struct SessionTabRowView: View {
    @ObservedObject private var workspace: SessionWorkspace
    private let descriptor: SessionDescriptor
    private let isFocusedInTiling: Bool
    private let gitChangeSummary: WorkspaceGitChangeSummary?

    @State private var renameController = SessionTabRenameController()

    public init(
        workspace: SessionWorkspace,
        descriptor: SessionDescriptor,
        isFocusedInTiling: Bool = false,
        gitChangeSummary: WorkspaceGitChangeSummary? = nil
    ) {
        self.workspace = workspace
        self.descriptor = descriptor
        self.isFocusedInTiling = isFocusedInTiling
        self.gitChangeSummary = gitChangeSummary
    }

    public var body: some View {
        HStack(spacing: 8) {
            selectionIndicator

            if visualState.showsAgentBadge {
                Circle()
                    .fill(agentBadgeColor)
                    .frame(width: 9, height: 9)
                    .help(visualState.agentBadgeLabel ?? "")
                    .accessibilityLabel(Text(visualState.agentBadgeLabel ?? ""))
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
                HStack(spacing: 6) {
                    Text(descriptor.displayTitle)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let sessionStartedAt = workspace.sessionStartedAt(for: descriptor.id) {
                        TimelineView(.periodic(from: sessionStartedAt, by: 60)) { context in
                            let durationState = SessionTabDurationState.resolve(
                                startedAt: sessionStartedAt,
                                isRenaming: renameController.isRenaming,
                                referenceDate: context.date
                            )

                            if let label = durationState.label {
                                Text(label)
                                    .font(.system(.caption2, design: .monospaced).weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            if visualState.showsGitBadge,
               let gitAddedCount = visualState.gitAddedCount,
               let gitRemovedCount = visualState.gitRemovedCount {
                HStack(spacing: 4) {
                    Text("+\(gitAddedCount)")
                        .font(.system(.caption2, design: .monospaced).weight(.semibold))
                        .foregroundStyle(.green)

                    Text("-\(gitRemovedCount)")
                        .font(.system(.caption2, design: .monospaced).weight(.semibold))
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(visualState.isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    Color.accentColor.opacity(visualState.focusBorderOpacity),
                    lineWidth: visualState.isFocusedInTiling ? 1.5 : 0
                )
        )
        .shadow(
            color: Color.accentColor.opacity(visualState.focusGlowOpacity),
            radius: visualState.isFocusedInTiling ? 10 : 0
        )
        .contentShape(Rectangle())
        .onTapGesture {
            _ = workspace.selectSession(id: descriptor.id)
        }
        .onTapGesture(count: 2) {
            renameController.beginRename(
                currentTitle: descriptor.displayTitle,
                selectionBehavior: .selectAll
            )
        }
        .draggable(WorkspaceDragPayload(kind: .session, id: descriptor.id).serializedValue)
        .dropDestination(for: String.self) { identifiers, _ in
            guard let sourceIdentifier = identifiers.first else {
                return false
            }

            return workspace.handleDroppedSession(identifier: sourceIdentifier, before: descriptor.id)
        }
        .contextMenu {
            Menu("Split") {
                splitDirectionMenu("Left", action: .splitLeft)
                splitDirectionMenu("Right", action: .splitRight)
                splitDirectionMenu("Above", action: .splitAbove)
                splitDirectionMenu("Below", action: .splitBelow)
            }
            .disabled(!splitMenuState.isEnabled)

            Divider()

            Button("Rename") {
                renameController.beginRename(
                    currentTitle: descriptor.displayTitle,
                    selectionBehavior: .placeCaretAtEnd
                )
            }

            Button("Close") {
                _ = workspace.closeSession(id: descriptor.id)
            }
        }
    }

    private var visualState: SessionTabRowVisualState {
        SessionTabRowVisualState.resolve(
            descriptor: descriptor,
            activeSessionID: workspace.activeSessionID,
            isFocusedInTiling: isFocusedInTiling,
            gitChangeSummary: gitChangeSummary
        )
    }

    private var splitMenuState: SessionTabSplitMenuState {
        SessionTabSplitMenuState.resolve(workspace: workspace)
    }

    @ViewBuilder
    private func splitDirectionMenu(_ title: String, action: FocusedPanePlacementAction) -> some View {
        Menu(title) {
            ForEach(splitMenuState.candidates) { candidate in
                Button(candidate.title) {
                    guard let sourceSessionID = splitMenuState.sourceSessionID,
                          let targetPaneID = workspace.paneID(for: candidate.id) else {
                        return
                    }

                    _ = workspace.placeSession(
                        id: sourceSessionID,
                        inPane: targetPaneID,
                        using: action
                    )
                }
            }
        }
        .disabled(!splitMenuState.isEnabled)
    }

    @ViewBuilder
    private var selectionIndicator: some View {
        if visualState.isSelected {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(selectionIndicatorColor)
                .frame(width: 4, height: 16)
        } else {
            Circle()
                .fill(selectionIndicatorColor.opacity(0.35))
                .frame(width: 7, height: 7)
        }
    }

    private var selectionIndicatorColor: Color {
        switch visualState.selectionIndicatorColorName {
        case "accent":
            return .accentColor
        case "secondary":
            return .secondary
        default:
            return .secondary
        }
    }

    private var agentBadgeColor: Color {
        switch visualState.agentBadgeColorName {
        case "green":
            return .green
        case "orange":
            return .orange
        case "teal":
            return .teal
        case "red":
            return .red
        default:
            return .clear
        }
    }

    private func commitRename() {
        let committed = renameController.commit()
        _ = workspace.renameSession(id: descriptor.id, title: committed)
    }

    private func cancelRename() {
        renameController.cancel()
    }
}
