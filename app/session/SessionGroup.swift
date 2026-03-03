import Foundation

public struct SessionGroup: Identifiable, Codable, Equatable, Hashable {
    public let id: UUID
    public var name: String
    public var colorTag: SessionGroupColor?
    public var isCollapsed: Bool
    public var paneGraph: WorkspaceGraph

    public init(
        id: UUID = UUID(),
        name: String,
        colorTag: SessionGroupColor? = nil,
        isCollapsed: Bool = false,
        paneGraph: WorkspaceGraph = WorkspaceGraph()
    ) {
        self.id = id
        self.name = name
        self.colorTag = colorTag
        self.isCollapsed = isCollapsed
        self.paneGraph = paneGraph
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
