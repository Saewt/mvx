import Foundation

public struct SessionGroup: Identifiable, Codable, Equatable, Hashable {
    public let id: UUID
    public var name: String
    public var colorTag: SessionGroupColor?
    public var isCollapsed: Bool
    public var paneGraph: WorkspaceGraph
    public var note: WorkspaceNoteSnapshot?

    public init(
        id: UUID = UUID(),
        name: String,
        colorTag: SessionGroupColor? = nil,
        isCollapsed: Bool = false,
        paneGraph: WorkspaceGraph = WorkspaceGraph(),
        note: WorkspaceNoteSnapshot? = nil
    ) {
        self.id = id
        self.name = name
        self.colorTag = colorTag
        self.isCollapsed = isCollapsed
        self.paneGraph = paneGraph
        self.note = note
    }
}

public enum SessionGroupColor: String, Codable, CaseIterable {
    case blue
    case green
    case orange
    case red
    case purple
    case teal
}
