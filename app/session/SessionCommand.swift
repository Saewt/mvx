import Foundation

public enum SessionCommand: Equatable {
    case new
    case closeCurrent
    case close(id: UUID)
    case closeFocusedPane
    case select(UUID)
    case selectNext
    case selectPrevious
    case selectNextPane
    case selectPreviousPane
    case selectNextAttention
    case rename(id: UUID, title: String?)
    case updateContext(id: UUID, workingDirectoryPath: String?, foregroundProcessName: String?)
    case updateAgentStatus(id: UUID, status: SessionAgentStatus)
    case applyAgentStatusEscapeSequence(id: UUID, sequence: String)
    case move(id: UUID, toIndex: Int)
    case createGroup(name: String, colorTag: SessionGroupColor?)
    case renameGroup(id: UUID, name: String)
    case deleteGroup(id: UUID)
    case moveGroup(id: UUID, toIndex: Int)
    case selectGroup(id: UUID?)
    case assignSessionToGroup(sessionID: UUID, groupID: UUID?)
    case setGroupCollapsed(id: UUID, isCollapsed: Bool)
    case splitHorizontal
    case splitVertical
}
