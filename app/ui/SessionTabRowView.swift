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
    public let needsAttention: Bool
    public let attentionColorName: String?
    public let attentionLabel: String?
    public let isRunning: Bool
    public let statusRailColorName: String?
    public let railColorName: String?
    public let statusSymbolName: String?

    public static func resolve(
        descriptor: SessionDescriptor,
        activeSessionID: UUID?,
        isFocusedInTiling: Bool = false,
        gitChangeSummary: WorkspaceGitChangeSummary? = nil
    ) -> SessionTabRowVisualState {
        let isSelected = descriptor.id == activeSessionID
        let showsAgentBadge = descriptor.agentStatus.showsBadge
        let showsGitBadge = gitChangeSummary != nil
        let needsAttention = descriptor.agentStatus.needsAttention
        let agentIsRunning = descriptor.agentStatus == .running
        let resolvedColorName = badgeColorName(for: descriptor.agentStatus)
        let attentionColorName: String?
        let attentionLabel: String?
        if needsAttention {
            attentionColorName = resolvedColorName
            attentionLabel = descriptor.agentStatus.attentionLabel
        } else {
            attentionColorName = nil
            attentionLabel = nil
        }
        return SessionTabRowVisualState(
            isSelected: isSelected,
            isFocusedInTiling: isFocusedInTiling,
            selectionIndicatorStyleName: isSelected ? "bar" : "dot",
            selectionIndicatorColorName: isSelected ? "accent" : "secondary",
            showsAgentBadge: showsAgentBadge,
            agentBadgeShapeName: showsAgentBadge ? "dot" : nil,
            agentBadgeLabel: descriptor.agentStatus.badgeLabel,
            agentBadgeColorName: resolvedColorName,
            showsGitBadge: showsGitBadge,
            gitAddedCount: gitChangeSummary?.addedCount,
            gitRemovedCount: gitChangeSummary?.removedCount,
            focusBorderOpacity: isFocusedInTiling ? (isSelected ? 0.62 : 0.38) : 0,
            focusGlowOpacity: isFocusedInTiling ? (isSelected ? 0.08 : 0.05) : 0,
            needsAttention: needsAttention,
            attentionColorName: attentionColorName,
            attentionLabel: attentionLabel,
            isRunning: agentIsRunning,
            statusRailColorName: resolvedColorName,
            railColorName: isSelected ? "accent" : resolvedColorName,
            statusSymbolName: MvxStatusStyle.symbolName(for: descriptor.agentStatus)
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
        let resolvedTitles = SessionDisplayIdentityResolver.resolvedTitles(for: eligibleDescriptors)
        let candidates = eligibleDescriptors.map { descriptor in
            let title = resolvedTitles[descriptor.id] ?? descriptor.displayTitle
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
    private let displayIdentity: SessionDisplayIdentity?
    private let isFocusedInTiling: Bool
    private let gitChangeSummary: WorkspaceGitChangeSummary?
    private let durationReferenceDate: Date

    @State private var renameController = SessionTabRenameController()
    @State private var runningPulseOpacity: Double = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        workspace: SessionWorkspace,
        descriptor: SessionDescriptor,
        displayIdentity: SessionDisplayIdentity? = nil,
        isFocusedInTiling: Bool = false,
        gitChangeSummary: WorkspaceGitChangeSummary? = nil,
        durationReferenceDate: Date = Date()
    ) {
        self.workspace = workspace
        self.descriptor = descriptor
        self.displayIdentity = displayIdentity
        self.isFocusedInTiling = isFocusedInTiling
        self.gitChangeSummary = gitChangeSummary
        self.durationReferenceDate = durationReferenceDate
    }

    public var body: some View {
        HStack(alignment: .top, spacing: MvxLayout.indicatorGap) {
            statusIndicatorLane
            VStack(alignment: .leading, spacing: 2) {
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
                        Text(resolvedDisplayIdentity.title)
                            .font(MvxText.rowTitle)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if let durationLabel {
                            Text(durationLabel)
                                .font(MvxText.metaMono)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: true, vertical: false)
                        }

                        Spacer(minLength: 0)

                        if visualState.needsAttention && !visualState.isSelected,
                           let attentionLabel = visualState.attentionLabel {
                            Text(attentionLabel)
                                .font(MvxText.meta)
                                .foregroundStyle(
                                    MvxStatusStyle.color(forLegacyAgentColorName: visualState.attentionColorName)
                                )
                                .lineLimit(1)
                        }
                    }

                    if let contextLine = resolvedDisplayIdentity.contextLine {
                        Text(contextLine)
                            .font(MvxText.rowContext)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.horizontal, MvxSpacing.md)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: MvxRadius.control, style: .continuous)
                .fill(visualState.isSelected ? MvxSurface.selectedRow : Color.clear)
        )
        .overlay(alignment: .leading) {
            selectionIndicator
        }
        .overlay(
            RoundedRectangle(cornerRadius: MvxRadius.control, style: .continuous)
                .stroke(
                    Color.accentColor.opacity(visualState.focusBorderOpacity),
                    lineWidth: visualState.isFocusedInTiling ? 1 : 0
                )
        )
        .shadow(
            color: Color.accentColor.opacity(visualState.focusGlowOpacity),
            radius: visualState.isFocusedInTiling ? 6 : 0
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
        .onAppear {
            if visualState.isRunning {
                runningPulseOpacity = 0.5
            } else {
                runningPulseOpacity = 1.0
            }
        }
        .onChange(of: visualState.isRunning) { isRunning in
            if isRunning {
                runningPulseOpacity = 0.5
            } else {
                runningPulseOpacity = 1.0
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

    private var resolvedDisplayIdentity: SessionDisplayIdentity {
        displayIdentity ?? SessionDisplayIdentityResolver.resolve(
            descriptor: descriptor,
            visibleDescriptors: [descriptor],
            branchName: workspace.workspaceMetadata.branchName,
            gitChangeSummary: gitChangeSummary
        )
    }

    private var durationLabel: String? {
        guard let sessionStartedAt = workspace.sessionStartedAt(for: descriptor.id) else {
            return nil
        }

        return SessionTabDurationState.resolve(
            startedAt: sessionStartedAt,
            isRenaming: renameController.isRenaming,
            referenceDate: durationReferenceDate
        ).label
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
        let color = selectionRailColor
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color)
            .frame(width: visualState.isSelected ? MvxLayout.selectionBarWidth + 1 : MvxLayout.selectionBarWidth)
            .frame(maxHeight: .infinity)
            .opacity(visualState.isRunning && !visualState.isSelected ? runningPulseOpacity : 1)
            .animation(
                visualState.isRunning && !reduceMotion ? MvxMotion.pulse : .none,
                value: runningPulseOpacity
            )
            .padding(.vertical, 5)
    }

    @ViewBuilder
    private var statusIndicatorLane: some View {
        ZStack {
            if let symbolName = visualState.statusSymbolName {
                Image(systemName: symbolName)
                    .font(.system(size: MvxIcon.glyph, weight: .semibold))
                    .foregroundStyle(
                        MvxStatusStyle.color(forLegacyAgentColorName: visualState.agentBadgeColorName)
                    )
                    .opacity(visualState.isRunning ? runningPulseOpacity : 1)
                    .animation(
                        visualState.isRunning && !reduceMotion ? MvxMotion.pulse : .none,
                        value: runningPulseOpacity
                    )
                    .help(visualState.agentBadgeLabel ?? "")
                    .accessibilityLabel(Text(visualState.agentBadgeLabel ?? ""))
            } else {
                Color.clear
            }
        }
        .frame(width: MvxLayout.indicatorLane, height: MvxLayout.indicatorLane)
        .padding(.top, 2)
    }

    private var selectionRailColor: Color {
        if let railColorName = visualState.railColorName {
            if railColorName == "accent" {
                return .accentColor
            }

            return MvxStatusStyle.color(forLegacyAgentColorName: railColorName)
        }

        return .clear
    }

    private func commitRename() {
        let committed = renameController.commit()
        _ = workspace.renameSession(id: descriptor.id, title: committed)
    }

    private func cancelRename() {
        renameController.cancel()
    }
}
