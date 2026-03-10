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

    public var title: String {
        switch self {
        case .checkForUpdates:
            return "Check for Updates"
        case .commandPalette:
            return "Command Palette"
        case .newWindow:
            return "New Window"
        case .newTab:
            return "New Tab"
        case .closeCurrentSession:
            return "Close Session"
        case .closePane:
            return "Close Pane"
        case .splitHorizontal:
            return "Split Horizontal"
        case .splitVertical:
            return "Split Vertical"
        case .nextSession:
            return "Next Session"
        case .previousSession:
            return "Previous Session"
        case .nextPane:
            return "Next Pane"
        case .previousPane:
            return "Previous Pane"
        case .nextAttention:
            return "Next Session Needing Attention"
        case .copy:
            return "Copy"
        case .paste:
            return "Paste"
        case .selectAll:
            return "Select All"
        case .quit:
            return "Quit mvx"
        }
    }

    public var symbolName: String {
        switch self {
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
            return "rectangle.split.1x2"
        case .splitVertical:
            return "rectangle.split.2x1"
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
            _ = workspace.performAdaptiveSplit(.horizontal)
            return nil
        case .splitVertical:
            _ = workspace.performAdaptiveSplit(.vertical)
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
            WorkspaceCommandDescriptor(command: .commandPalette, title: WorkspaceCommand.commandPalette.title, keywords: ["search", "actions"]),
            WorkspaceCommandDescriptor(command: .newWindow, title: WorkspaceCommand.newWindow.title, keywords: ["session", "create"]),
            WorkspaceCommandDescriptor(command: .newTab, title: WorkspaceCommand.newTab.title, keywords: ["session", "create"]),
            WorkspaceCommandDescriptor(command: .closeCurrentSession, title: WorkspaceCommand.closeCurrentSession.title, keywords: ["tab", "close"], isEnabled: workspace.activeSessionID != nil),
            WorkspaceCommandDescriptor(command: .closePane, title: WorkspaceCommand.closePane.title, keywords: ["split", "pane", "close"], isEnabled: workspace.workspaceGraph.paneCount > 1),
            WorkspaceCommandDescriptor(command: .splitHorizontal, title: WorkspaceCommand.splitHorizontal.title, keywords: ["pane", "layout", "horizontal"], isEnabled: workspace.activeSessionID != nil),
            WorkspaceCommandDescriptor(command: .splitVertical, title: WorkspaceCommand.splitVertical.title, keywords: ["pane", "layout", "vertical"], isEnabled: workspace.activeSessionID != nil),
            WorkspaceCommandDescriptor(command: .nextSession, title: WorkspaceCommand.nextSession.title, keywords: ["cycle", "tab"], isEnabled: activeGroupSessionCount > 1),
            WorkspaceCommandDescriptor(command: .previousSession, title: WorkspaceCommand.previousSession.title, keywords: ["cycle", "tab"], isEnabled: activeGroupSessionCount > 1),
            WorkspaceCommandDescriptor(command: .nextPane, title: WorkspaceCommand.nextPane.title, keywords: ["cycle", "pane"], isEnabled: workspace.workspaceGraph.paneCount > 1),
            WorkspaceCommandDescriptor(command: .previousPane, title: WorkspaceCommand.previousPane.title, keywords: ["cycle", "pane"], isEnabled: workspace.workspaceGraph.paneCount > 1),
            WorkspaceCommandDescriptor(command: .nextAttention, title: WorkspaceCommand.nextAttention.title, keywords: ["waiting", "error", "badge"], isEnabled: workspace.nextAttentionSessionID() != nil),
            WorkspaceCommandDescriptor(command: .copy, title: WorkspaceCommand.copy.title, keywords: ["clipboard"], isEnabled: workspace.activeSessionID != nil),
            WorkspaceCommandDescriptor(command: .paste, title: WorkspaceCommand.paste.title, keywords: ["clipboard"], isEnabled: workspace.activeSessionID != nil),
            WorkspaceCommandDescriptor(command: .selectAll, title: WorkspaceCommand.selectAll.title, keywords: ["selection", "content"], isEnabled: workspace.activeSessionID != nil),
            WorkspaceCommandDescriptor(command: .quit, title: WorkspaceCommand.quit.title, keywords: ["exit", "application"]),
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
