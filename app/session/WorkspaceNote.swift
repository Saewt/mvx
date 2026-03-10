import Foundation

public struct WorkspaceNoteSnapshot: Codable, Equatable, Hashable {
    public var body: String
    public var updatedAt: Date

    public init(body: String, updatedAt: Date = Date()) {
        self.body = body
        self.updatedAt = updatedAt
    }
}
