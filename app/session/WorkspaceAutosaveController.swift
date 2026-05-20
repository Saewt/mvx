import Combine
import Foundation

@MainActor
public final class WorkspaceAutosaveController {
    private let workspace: SessionWorkspace
    private let persistSnapshot: (WorkspaceSnapshot) throws -> Void
    private var cancellables: Set<AnyCancellable>

    public init(
        workspace: SessionWorkspace,
        persistence: WorkspacePersistence,
        debounceInterval: DispatchQueue.SchedulerTimeType.Stride = .milliseconds(500),
        scheduler: DispatchQueue = .main
    ) {
        self.workspace = workspace
        self.persistSnapshot = { snapshot in
            try persistence.save(snapshot)
        }
        self.cancellables = []
        bind(debounceInterval: debounceInterval, scheduler: scheduler)
    }

    init(
        workspace: SessionWorkspace,
        debounceInterval: DispatchQueue.SchedulerTimeType.Stride,
        scheduler: DispatchQueue = .main,
        persistSnapshot: @escaping (WorkspaceSnapshot) throws -> Void
    ) {
        self.workspace = workspace
        self.persistSnapshot = persistSnapshot
        self.cancellables = []
        bind(debounceInterval: debounceInterval, scheduler: scheduler)
    }

    public func persistNow() throws {
        try persistSnapshot(workspace.snapshot())
    }

    private func bind(
        debounceInterval: DispatchQueue.SchedulerTimeType.Stride,
        scheduler: DispatchQueue
    ) {
        let sessionStructures = workspace.$sessions
            .map { sessions in
                sessions.map { SessionStructuralAutosaveState(descriptor: $0) }
            }

        let groupStructures = workspace.$sessionGroups
            .map { groups in
                groups.map { GroupStructuralAutosaveState(group: $0) }
            }

        Publishers.CombineLatest4(
            sessionStructures,
            workspace.$activeSessionID,
            workspace.$workspaceGraph,
            workspace.$activeGroupID
        )
        .combineLatest(
            Publishers.CombineLatest3(
                groupStructures,
                workspace.$sessionGroupAssignments,
                workspace.$workspaceNote
            )
        )
            .map { structural, secondary in
                StructuralAutosaveProjection(
                    sessions: structural.0,
                    activeSessionID: structural.1,
                    workspaceGraph: structural.2,
                    activeGroupID: structural.3,
                    sessionGroups: secondary.0,
                    sessionGroupAssignments: secondary.1,
                    workspaceNote: secondary.2
                )
            }
            .removeDuplicates()
            .dropFirst()
            .debounce(for: debounceInterval, scheduler: scheduler)
            .sink { [weak self] _ in
                self?.persistLatestSnapshot()
            }
            .store(in: &cancellables)
    }

    private func persistLatestSnapshot() {
        do {
            try persistNow()
        } catch {
            return
        }
    }
}

private struct StructuralAutosaveProjection: Equatable {
    let sessions: [SessionStructuralAutosaveState]
    let activeSessionID: UUID?
    let workspaceGraph: WorkspaceGraph
    let activeGroupID: UUID?
    let sessionGroups: [GroupStructuralAutosaveState]
    let sessionGroupAssignments: [UUID: UUID]
    let workspaceNote: WorkspaceNoteSnapshot?
}

private struct SessionStructuralAutosaveState: Equatable {
    let id: UUID
    let ordinal: Int
    let customTitle: String?
    let workingDirectoryPath: String?

    init(descriptor: SessionDescriptor) {
        self.id = descriptor.id
        self.ordinal = descriptor.ordinal
        self.customTitle = descriptor.customTitle
        self.workingDirectoryPath = descriptor.workingDirectoryPath
    }
}

private struct GroupStructuralAutosaveState: Equatable {
    let id: UUID
    let name: String
    let colorTag: SessionGroupColor?
    let isCollapsed: Bool
    let paneGraph: WorkspaceGraph
    let note: WorkspaceNoteSnapshot?

    init(group: SessionGroup) {
        self.id = group.id
        self.name = group.name
        self.colorTag = group.colorTag
        self.isCollapsed = group.isCollapsed
        self.paneGraph = group.paneGraph
        self.note = group.note
    }
}
