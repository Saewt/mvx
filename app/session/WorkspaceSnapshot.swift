import Foundation

public struct WorkspaceSnapshot: Codable, Equatable {
    public static let currentSchemaVersion = 6

    public struct PersistedSession: Codable, Equatable {
        public var descriptor: SessionDescriptor

        public init(descriptor: SessionDescriptor) {
            self.descriptor = descriptor
        }
    }

    public struct PersistedSessionGroup: Codable, Equatable {
        public var id: UUID
        public var name: String
        public var colorTag: SessionGroupColor?
        public var isCollapsed: Bool
        public var paneGraph: WorkspaceGraph?

        public init(
            id: UUID,
            name: String,
            colorTag: SessionGroupColor?,
            isCollapsed: Bool,
            paneGraph: WorkspaceGraph? = nil
        ) {
            self.id = id
            self.name = name
            self.colorTag = colorTag
            self.isCollapsed = isCollapsed
            self.paneGraph = paneGraph
        }
    }

    public var schemaVersion: Int
    public var sessions: [PersistedSession]
    public var activeSessionID: UUID?
    public var nextOrdinal: Int
    public var workspaceGraph: WorkspaceGraph?
    public var sessionGroups: [PersistedSessionGroup]
    public var activeGroupID: UUID?
    public var sessionGroupAssignments: [String: String]

    public init(
        schemaVersion: Int = WorkspaceSnapshot.currentSchemaVersion,
        sessions: [PersistedSession],
        activeSessionID: UUID?,
        nextOrdinal: Int,
        workspaceGraph: WorkspaceGraph? = nil,
        sessionGroups: [PersistedSessionGroup] = [],
        activeGroupID: UUID? = nil,
        sessionGroupAssignments: [String: String] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.sessions = sessions
        self.activeSessionID = activeSessionID
        self.nextOrdinal = max(nextOrdinal, 1)
        self.workspaceGraph = workspaceGraph
        self.sessionGroups = sessionGroups
        self.activeGroupID = activeGroupID
        self.sessionGroupAssignments = sessionGroupAssignments
    }

    public var isSupported: Bool {
        schemaVersion >= 1 && schemaVersion <= Self.currentSchemaVersion
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case sessions
        case activeSessionID
        case nextOrdinal
        case workspaceGraph
        case sessionGroups
        case activeGroupID
        case sessionGroupAssignments
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        sessions = try container.decode([PersistedSession].self, forKey: .sessions)
        activeSessionID = try container.decodeIfPresent(UUID.self, forKey: .activeSessionID)
        nextOrdinal = max(try container.decode(Int.self, forKey: .nextOrdinal), 1)
        workspaceGraph = try container.decodeIfPresent(WorkspaceGraph.self, forKey: .workspaceGraph)
        sessionGroups = try container.decodeIfPresent([PersistedSessionGroup].self, forKey: .sessionGroups) ?? []
        activeGroupID = try container.decodeIfPresent(UUID.self, forKey: .activeGroupID)
        sessionGroupAssignments = try container.decodeIfPresent([String: String].self, forKey: .sessionGroupAssignments) ?? [:]
    }
}
