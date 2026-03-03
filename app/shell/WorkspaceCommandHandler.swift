import Foundation
#if canImport(AppKit)
import AppKit
#endif

public enum WorkspaceCommand: String, Equatable, Hashable {
    case checkForUpdates
    case commandPalette
    case newWindow
    case newTab
    case closeCurrentSession
    case closePane
    case splitHorizontal
    case splitVertical
    case nextSession
    case previousSession
    case nextPane
    case previousPane
    case nextAttention
    case copy
    case paste
    case selectAll
    case quit
}

public struct WorkspaceCommandDescriptor: Identifiable, Equatable {
    public var command: WorkspaceCommand
    public var title: String
    public var keywords: [String]
    public var isEnabled: Bool

    public var id: String {
        command.rawValue
    }

    public init(command: WorkspaceCommand, title: String, keywords: [String], isEnabled: Bool = true) {
        self.command = command
        self.title = title
        self.keywords = keywords
        self.isEnabled = isEnabled
    }
}

@MainActor
public final class WorkspaceCommandHandler: ObservableObject {
    public let workspace: SessionWorkspace
    public let updateController: ReleaseUpdateController?
    @Published public var isCommandPalettePresented = false

    public init(workspace: SessionWorkspace, updateController: ReleaseUpdateController? = nil) {
        self.workspace = workspace
        self.updateController = updateController
    }

    @discardableResult
    public func perform(_ command: WorkspaceCommand, selection: String? = nil) -> String? {
        switch command {
        case .checkForUpdates:
            _ = updateController?.checkForUpdates()
            return nil
        case .commandPalette:
            isCommandPalettePresented = true
            return nil
        case .newWindow, .newTab:
            _ = workspace.createSession()
            return nil
        case .closeCurrentSession:
            _ = workspace.closeCurrentSession()
            return nil
        case .closePane:
            _ = workspace.closeFocusedPane()
            return nil
        case .splitHorizontal:
            _ = workspace.splitActivePane(.horizontal)
            return nil
        case .splitVertical:
            _ = workspace.splitActivePane(.vertical)
            return nil
        case .nextSession:
            _ = workspace.selectNextSession()
            return nil
        case .previousSession:
            _ = workspace.selectPreviousSession()
            return nil
        case .nextPane:
            _ = workspace.focusNextPane()
            return nil
        case .previousPane:
            _ = workspace.focusPreviousPane()
            return nil
        case .nextAttention:
            _ = workspace.selectNextAttentionSession()
            return nil
        case .copy:
            guard let activeSession else {
                return nil
            }

            if activeSession.backendKind == .nativeGhostty, performNativeEditAction(#selector(NSText.copy(_:))) {
                workspace.refreshVisibleState()
                return nil
            }

            _ = activeSession.handleKeyboard(.commandC, selection: selection)
            workspace.refreshVisibleState()
            return nil
        case .paste:
            guard let activeSession else {
                return nil
            }

            if activeSession.backendKind == .nativeGhostty, performNativeEditAction(#selector(NSText.paste(_:))) {
                workspace.refreshVisibleState()
                return nil
            }

            let pasted = activeSession.handleKeyboard(.commandV)
            workspace.refreshVisibleState()
            return pasted
        case .selectAll:
            guard let activeSession else {
                return nil
            }

            if activeSession.backendKind == .nativeGhostty {
                _ = performNativeEditAction(#selector(NSText.selectAll(_:)))
            }
            workspace.refreshVisibleState()
            return nil
        case .quit:
            workspace.requestQuit()
            return nil
        }
    }

    public func dismissCommandPalette() {
        isCommandPalettePresented = false
    }

    public func chromeCommands() -> [WorkspaceCommandDescriptor] {
        let preferredOrder: [WorkspaceCommand] = [
            .commandPalette,
            .newTab,
            .nextAttention,
            .closeCurrentSession
        ]

        let descriptors = Dictionary(uniqueKeysWithValues: availableCommands().map { ($0.command, $0) })
        return preferredOrder.compactMap { descriptors[$0] }
    }

    public func paneCommands() -> [WorkspaceCommandDescriptor] {
        let preferredOrder: [WorkspaceCommand] = [
            .splitVertical,
            .splitHorizontal,
            .nextPane,
            .closePane
        ]

        let descriptors = Dictionary(uniqueKeysWithValues: availableCommands().map { ($0.command, $0) })
        return preferredOrder.compactMap { descriptors[$0] }
    }

    public func availableCommands() -> [WorkspaceCommandDescriptor] {
        let activeGroupSessionCount = workspace.sessions(inGroup: workspace.activeGroupID).count

        return [
            WorkspaceCommandDescriptor(command: .commandPalette, title: "Command Palette", keywords: ["search", "actions"]),
            WorkspaceCommandDescriptor(command: .newWindow, title: "New Window", keywords: ["session", "create"]),
            WorkspaceCommandDescriptor(command: .newTab, title: "New Tab", keywords: ["session", "create"]),
            WorkspaceCommandDescriptor(command: .closeCurrentSession, title: "Close Session", keywords: ["tab", "close"], isEnabled: workspace.activeSessionID != nil),
            WorkspaceCommandDescriptor(command: .closePane, title: "Close Pane", keywords: ["split", "pane", "close"], isEnabled: workspace.workspaceGraph.paneCount > 1),
            WorkspaceCommandDescriptor(command: .splitHorizontal, title: "Split Horizontal", keywords: ["pane", "layout", "horizontal"], isEnabled: workspace.activeSessionID != nil),
            WorkspaceCommandDescriptor(command: .splitVertical, title: "Split Vertical", keywords: ["pane", "layout", "vertical"], isEnabled: workspace.activeSessionID != nil),
            WorkspaceCommandDescriptor(command: .nextSession, title: "Next Session", keywords: ["cycle", "tab"], isEnabled: activeGroupSessionCount > 1),
            WorkspaceCommandDescriptor(command: .previousSession, title: "Previous Session", keywords: ["cycle", "tab"], isEnabled: activeGroupSessionCount > 1),
            WorkspaceCommandDescriptor(command: .nextPane, title: "Next Pane", keywords: ["cycle", "pane"], isEnabled: workspace.workspaceGraph.paneCount > 1),
            WorkspaceCommandDescriptor(command: .previousPane, title: "Previous Pane", keywords: ["cycle", "pane"], isEnabled: workspace.workspaceGraph.paneCount > 1),
            WorkspaceCommandDescriptor(command: .nextAttention, title: "Next Session Needing Attention", keywords: ["waiting", "error", "badge"], isEnabled: workspace.nextAttentionSessionID() != nil),
            WorkspaceCommandDescriptor(command: .copy, title: "Copy", keywords: ["clipboard"], isEnabled: workspace.activeSessionID != nil),
            WorkspaceCommandDescriptor(command: .paste, title: "Paste", keywords: ["clipboard"], isEnabled: workspace.activeSessionID != nil),
            WorkspaceCommandDescriptor(command: .selectAll, title: "Select All", keywords: ["selection", "content"], isEnabled: workspace.activeSessionID != nil),
            WorkspaceCommandDescriptor(command: .quit, title: "Quit mvx", keywords: ["exit", "application"]),
        ]
    }

    public func searchCommands(matching query: String) -> [WorkspaceCommandDescriptor] {
        let normalizedQuery = query
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        let commands = availableCommands()
        guard !normalizedQuery.isEmpty else {
            return commands
        }

        return commands.filter { command in
            let searchableText = ([command.title] + command.keywords)
                .joined(separator: " ")
                .lowercased()

            return normalizedQuery.allSatisfy { token in
                searchableText.contains(token)
            }
        }
    }

    private var activeSession: TerminalSession? {
        workspace.activeSession
    }

    private func performNativeEditAction(_ selector: Selector) -> Bool {
        #if canImport(AppKit)
        return NSApp?.sendAction(selector, to: nil, from: nil) ?? false
        #else
        return false
        #endif
    }
}
