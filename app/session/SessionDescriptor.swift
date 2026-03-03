import Foundation

public struct SessionDescriptor: Identifiable, Codable, Equatable, Hashable {
    public let id: UUID
    public let ordinal: Int
    public var automaticTitle: String
    public var customTitle: String?
    public var agentStatus: SessionAgentStatus
    public var workingDirectoryPath: String?
    public var foregroundProcessName: String?

    /// Runtime-only title from terminal OSC updates; not persisted.
    public var terminalTitle: String?

    public init(
        id: UUID = UUID(),
        ordinal: Int,
        customTitle: String? = nil,
        agentStatus: SessionAgentStatus = .none,
        workingDirectoryPath: String? = nil,
        foregroundProcessName: String? = nil
    ) {
        let normalizedOrdinal = max(ordinal, 1)

        self.id = id
        self.ordinal = normalizedOrdinal
        self.workingDirectoryPath = workingDirectoryPath
        self.foregroundProcessName = foregroundProcessName
        self.terminalTitle = nil
        self.customTitle = SessionNaming.normalizedCustomTitle(customTitle)
        self.agentStatus = agentStatus
        self.automaticTitle = SessionNaming.automaticTitle(
            workingDirectoryPath: workingDirectoryPath,
            foregroundProcessName: foregroundProcessName,
            fallbackOrdinal: normalizedOrdinal
        )
    }

    public var displayTitle: String {
        customTitle ?? automaticTitle
    }

    public var hasCustomTitle: Bool {
        customTitle != nil
    }

    public var showsAgentStatusBadge: Bool {
        agentStatus.showsBadge
    }

    public mutating func updateContext(
        workingDirectoryPath: String?,
        foregroundProcessName: String?
    ) {
        self.workingDirectoryPath = workingDirectoryPath
        self.foregroundProcessName = foregroundProcessName
        refreshAutomaticTitle()
    }

    public mutating func setCustomTitle(_ title: String?) {
        customTitle = SessionNaming.normalizedCustomTitle(title)
    }

    public mutating func setTerminalTitle(_ title: String?) {
        terminalTitle = SessionNaming.normalizedCustomTitle(title)
        refreshAutomaticTitle()
    }

    public mutating func setAgentStatus(_ status: SessionAgentStatus) {
        agentStatus = status
    }

    public mutating func refreshAutomaticTitle() {
        automaticTitle = SessionNaming.automaticTitle(
            terminalTitle: terminalTitle,
            workingDirectoryPath: workingDirectoryPath,
            foregroundProcessName: foregroundProcessName,
            fallbackOrdinal: ordinal
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case ordinal
        case customTitle
        case agentStatus
        case workingDirectoryPath
        case foregroundProcessName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedOrdinal = max(try container.decode(Int.self, forKey: .ordinal), 1)

        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            ordinal: decodedOrdinal,
            customTitle: try container.decodeIfPresent(String.self, forKey: .customTitle),
            agentStatus: try container.decodeIfPresent(SessionAgentStatus.self, forKey: .agentStatus) ?? .none,
            workingDirectoryPath: try container.decodeIfPresent(String.self, forKey: .workingDirectoryPath),
            foregroundProcessName: try container.decodeIfPresent(String.self, forKey: .foregroundProcessName)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(ordinal, forKey: .ordinal)
        try container.encodeIfPresent(customTitle, forKey: .customTitle)
        try container.encode(agentStatus, forKey: .agentStatus)
        try container.encodeIfPresent(workingDirectoryPath, forKey: .workingDirectoryPath)
        try container.encodeIfPresent(foregroundProcessName, forKey: .foregroundProcessName)
    }
}
