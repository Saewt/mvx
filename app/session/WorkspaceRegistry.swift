import Combine
import Foundation

public struct WorkspaceEntry: Identifiable, Equatable {
    public let id: UUID
    public var name: String

    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

public struct WorkspaceCardMetadata: Equatable {
    public let workspaceID: UUID
    public let name: String
    public let branchName: String
    public let paneCount: Int
    public let notificationCount: Int
    public let waitingCount: Int
    public let errorCount: Int
    public let gitAddedCount: Int?
    public let gitRemovedCount: Int?

    public init(
        workspaceID: UUID,
        name: String,
        branchName: String,
        paneCount: Int,
        notificationCount: Int,
        waitingCount: Int,
        errorCount: Int,
        gitAddedCount: Int?,
        gitRemovedCount: Int?
    ) {
        self.workspaceID = workspaceID
        self.name = name
        self.branchName = branchName
        self.paneCount = max(paneCount, 0)
        self.notificationCount = max(notificationCount, 0)
        self.waitingCount = max(waitingCount, 0)
        self.errorCount = max(errorCount, 0)
        self.gitAddedCount = gitAddedCount
        self.gitRemovedCount = gitRemovedCount
    }

    public var hasGitStatus: Bool {
        gitAddedCount != nil && gitRemovedCount != nil
    }
}

public struct RegistrySnapshot: Codable, Equatable {
    public static let currentSchemaVersion = 1

    public struct PersistedWorkspace: Codable, Equatable {
        public var id: UUID
        public var name: String
        public var workspaceSnapshot: WorkspaceSnapshot

        public init(id: UUID, name: String, workspaceSnapshot: WorkspaceSnapshot) {
            self.id = id
            self.name = name
            self.workspaceSnapshot = workspaceSnapshot
        }
    }

    public var schemaVersion: Int
    public var workspaces: [PersistedWorkspace]
    public var activeWorkspaceID: UUID?

    public init(
        schemaVersion: Int = RegistrySnapshot.currentSchemaVersion,
        workspaces: [PersistedWorkspace],
        activeWorkspaceID: UUID?
    ) {
        self.schemaVersion = schemaVersion
        self.workspaces = workspaces
        self.activeWorkspaceID = activeWorkspaceID
    }

    public var isSupported: Bool {
        schemaVersion >= 1 && schemaVersion <= Self.currentSchemaVersion
    }
}

@MainActor
public final class WorkspaceRegistry: ObservableObject {
    @Published public private(set) var entries: [WorkspaceEntry]
    @Published public private(set) var activeWorkspaceID: UUID?

    private var workspaces: [UUID: SessionWorkspace]
    private let workspaceFactory: (String) -> SessionWorkspace

    public init(
        workspaceFactory: @escaping @MainActor (String) -> SessionWorkspace = { @MainActor _ in
            SessionWorkspace(
                startsWithSession: false,
                sessionFactory: SessionWorkspace.unsupportedSessionFactory()
            )
        }
    ) {
        self.entries = []
        self.activeWorkspaceID = nil
        self.workspaces = [:]
        self.workspaceFactory = workspaceFactory
    }

    public var activeWorkspace: SessionWorkspace? {
        guard let activeWorkspaceID else { return nil }
        return workspaces[activeWorkspaceID]
    }

    public func cardMetadata(for entryID: UUID) -> WorkspaceCardMetadata? {
        guard let entry = entries.first(where: { $0.id == entryID }),
              let workspace = workspaces[entryID] else {
            return nil
        }

        let metadata = workspace.workspaceMetadata
        let gitSummary = workspace.aggregatedGitChangeSummary()
        return WorkspaceCardMetadata(
            workspaceID: entry.id,
            name: entry.name,
            branchName: metadata.branchName,
            paneCount: metadata.paneCount,
            notificationCount: metadata.notificationCount,
            waitingCount: metadata.waitingCount,
            errorCount: metadata.errorCount,
            gitAddedCount: gitSummary?.addedCount,
            gitRemovedCount: gitSummary?.removedCount
        )
    }

    public func workspace(for id: UUID) -> SessionWorkspace? {
        workspaces[id]
    }

    @discardableResult
    public func createWorkspace(name: String, activate: Bool = true) -> WorkspaceEntry {
        let entry = WorkspaceEntry(name: name)
        let workspace = workspaceFactory(name)
        entries.append(entry)
        workspaces[entry.id] = workspace

        if activate || activeWorkspaceID == nil {
            activeWorkspaceID = entry.id
        }

        return entry
    }

    @discardableResult
    public func activateWorkspace(id: UUID) -> Bool {
        guard workspaces[id] != nil else { return false }
        activeWorkspaceID = id
        return true
    }

    @discardableResult
    public func closeWorkspace(id: UUID) -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return false }

        entries.remove(at: index)
        workspaces.removeValue(forKey: id)

        if activeWorkspaceID == id {
            activeWorkspaceID = entries.first?.id
        }

        return true
    }

    @discardableResult
    public func renameWorkspace(id: UUID, name: String) -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return false }
        entries[index].name = name
        return true
    }

    public func registrySnapshot() -> RegistrySnapshot {
        let persistedWorkspaces = entries.compactMap { entry -> RegistrySnapshot.PersistedWorkspace? in
            guard let workspace = workspaces[entry.id] else { return nil }
            return RegistrySnapshot.PersistedWorkspace(
                id: entry.id,
                name: entry.name,
                workspaceSnapshot: workspace.snapshot()
            )
        }

        return RegistrySnapshot(
            workspaces: persistedWorkspaces,
            activeWorkspaceID: activeWorkspaceID
        )
    }

    @discardableResult
    public func restore(from snapshot: RegistrySnapshot) -> Bool {
        guard snapshot.isSupported else { return false }

        entries.removeAll()
        workspaces.removeAll()
        activeWorkspaceID = nil

        for persisted in snapshot.workspaces {
            let entry = WorkspaceEntry(id: persisted.id, name: persisted.name)
            let workspace = workspaceFactory(persisted.name)
            _ = workspace.restore(from: persisted.workspaceSnapshot)
            entries.append(entry)
            workspaces[entry.id] = workspace
        }

        if let snapshotActiveID = snapshot.activeWorkspaceID, workspaces[snapshotActiveID] != nil {
            activeWorkspaceID = snapshotActiveID
        } else {
            activeWorkspaceID = entries.first?.id
        }

        return true
    }
}
