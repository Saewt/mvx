import Combine
import Foundation

@MainActor
public final class ActiveWorkspaceProxy: ObservableObject {
    @Published public private(set) var workspace: SessionWorkspace?
    @Published public private(set) var commandHandler: WorkspaceCommandHandler?
    @Published public private(set) var activeWorkspaceID: UUID?

    private weak var registry: WorkspaceRegistry?
    private let updateController: ReleaseUpdateController?
    private var cancellables: Set<AnyCancellable>

    public init(updateController: ReleaseUpdateController? = nil) {
        self.updateController = updateController
        self.cancellables = []
    }

    public func bind(to registry: WorkspaceRegistry) {
        self.registry = registry
        cancellables.removeAll()
        syncActiveWorkspace(id: registry.activeWorkspaceID)

        registry.$activeWorkspaceID
            .removeDuplicates()
            .sink { [weak self] id in
                self?.syncActiveWorkspace(id: id)
            }
            .store(in: &cancellables)
    }

    private func syncActiveWorkspace(id: UUID?) {
        guard let registry else {
            activeWorkspaceID = nil
            workspace = nil
            commandHandler = nil
            return
        }

        activeWorkspaceID = id
        workspace = id.flatMap { registry.workspace(for: $0) }
        commandHandler = workspace.map {
            WorkspaceCommandHandler(workspace: $0, updateController: updateController)
        }
    }
}
