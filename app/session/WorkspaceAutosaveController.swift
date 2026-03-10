import Combine
import Foundation

private struct GroupNoteAutosaveState: Equatable {
    let id: UUID
    let note: WorkspaceNoteSnapshot?
}

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
        let workspaceNoteChanges = workspace.$workspaceNote
            .removeDuplicates()
            .dropFirst()
            .map { _ in () }

        let groupNoteChanges = workspace.$sessionGroups
            .map { groups in
                groups
                    .map { GroupNoteAutosaveState(id: $0.id, note: $0.note) }
                    .sorted { $0.id.uuidString < $1.id.uuidString }
            }
            .removeDuplicates()
            .dropFirst()
            .map { _ in () }

        Publishers.Merge(workspaceNoteChanges, groupNoteChanges)
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
