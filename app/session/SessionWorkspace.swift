import Combine
import CoreGraphics
import Foundation

public enum WorkspaceDragPayloadKind: String, Codable, Equatable, Hashable {
    case pane
    case session
}

public struct WorkspaceDragPayload: Codable, Equatable, Hashable {
    public let kind: WorkspaceDragPayloadKind
    public let id: UUID

    public init(kind: WorkspaceDragPayloadKind, id: UUID) {
        self.kind = kind
        self.id = id
    }

    public var serializedValue: String {
        guard let data = try? JSONEncoder().encode(self),
              let value = String(data: data, encoding: .utf8) else {
            return ""
        }

        return value
    }

    public static func decode(from serializedValue: String) -> WorkspaceDragPayload? {
        guard let data = serializedValue.data(using: .utf8) else {
            return nil
        }

        return try? JSONDecoder().decode(WorkspaceDragPayload.self, from: data)
    }
}

public enum WorkspaceSplitInsertion: String, Codable, Equatable, Hashable {
    case before
    case after
}

public enum PaneDropZone: String, Codable, Equatable, Hashable {
    case swap
    case splitTop
    case splitBottom
    case splitLeft
    case splitRight

    public static func resolve(location: CGPoint, in size: CGSize) -> PaneDropZone {
        guard size.width > 0, size.height > 0 else {
            return .swap
        }

        let edgeBand = min(max(min(size.width, size.height) * 0.18, 18), 36)
        let clampedX = min(max(location.x, 0), size.width)
        let clampedY = min(max(location.y, 0), size.height)

        if clampedY <= edgeBand {
            return .splitTop
        }

        if clampedY >= max(size.height - edgeBand, edgeBand) {
            return .splitBottom
        }

        if clampedX <= edgeBand {
            return .splitLeft
        }

        if clampedX >= max(size.width - edgeBand, edgeBand) {
            return .splitRight
        }

        return .swap
    }

    public var splitPlacement: (axis: WorkspaceSplitAxis, insertion: WorkspaceSplitInsertion)? {
        switch self {
        case .swap:
            return nil
        case .splitTop:
            return (.horizontal, .before)
        case .splitBottom:
            return (.horizontal, .after)
        case .splitLeft:
            return (.vertical, .before)
        case .splitRight:
            return (.vertical, .after)
        }
    }
}

public enum WorkspacePaneDropAction: Equatable {
    case swapContents
    case replaceTarget
    case split(axis: WorkspaceSplitAxis, insertion: WorkspaceSplitInsertion)
}

public enum FocusedPanePlacementAction: Equatable {
    case splitLeft
    case splitRight
    case splitAbove
    case splitBelow
    case swap
    case replace
}

@MainActor
public final class SessionWorkspace: ObservableObject {
    @Published public private(set) var sessions: [SessionDescriptor] {
        didSet {
            invalidateCachedWorkspaceMetadata()
        }
    }
    @Published public private(set) var activeSessionID: UUID?
    @Published public private(set) var workspaceGraph: WorkspaceGraph {
        didSet {
            invalidateCachedWorkspaceMetadata()
        }
    }
    @Published public private(set) var activeGroupID: UUID?
    @Published public private(set) var sessionGroups: [SessionGroup]
    @Published public private(set) var sessionGroupAssignments: [UUID: UUID]
    @Published public private(set) var quitRequested = false
    @Published public private(set) var sessionGitChanges: [UUID: WorkspaceGitChangeSummary]
    @Published public private(set) var workspaceNote: WorkspaceNoteSnapshot?

    public let autoStartSessions: Bool

    private let sessionFactory: (URL?) -> TerminalSession
    private var runtimes: [UUID: TerminalSession]
    private var sessionStartedAtByID: [UUID: Date]
    private var nextOrdinal: Int
    private var ungroupedGraph: WorkspaceGraph
    private var pendingGitRefreshSessionIDs: Set<UUID>
    private var gitRefreshTask: Task<Void, Never>?
    private var isVisibleRefreshScheduled = false
    private var cachedWorkspaceMetadata: WorkspaceMetadataSnapshot?
    private var isWorkspaceMetadataDirty = true

    public convenience init(
        autoStartSessions: Bool = true,
        startsWithSession: Bool = true,
        sessionFactory: @escaping () -> TerminalSession = SessionWorkspace.unsupportedSessionFactory()
    ) {
        self.init(
            autoStartSessions: autoStartSessions,
            startsWithSession: startsWithSession,
            sessionFactoryWithStartupDirectory: { _ in sessionFactory() }
        )
    }

    public init(
        autoStartSessions: Bool = true,
        startsWithSession: Bool = true,
        sessionFactoryWithStartupDirectory: @escaping (URL?) -> TerminalSession = SessionWorkspace.unsupportedSessionFactoryWithStartupDirectory()
    ) {
        self.autoStartSessions = autoStartSessions
        self.sessionFactory = sessionFactoryWithStartupDirectory
        self.sessions = []
        self.activeSessionID = nil
        self.workspaceGraph = WorkspaceGraph()
        self.activeGroupID = nil
        self.sessionGroups = []
        self.sessionGroupAssignments = [:]
        self.sessionGitChanges = [:]
        self.workspaceNote = nil
        self.runtimes = [:]
        self.sessionStartedAtByID = [:]
        self.nextOrdinal = 1
        self.ungroupedGraph = WorkspaceGraph()
        self.pendingGitRefreshSessionIDs = []

        if startsWithSession {
            _ = createSession()
        }
    }

    public var activeDescriptor: SessionDescriptor? {
        guard let activeSessionID else {
            return nil
        }

        return descriptor(for: activeSessionID)
    }

    public var activeSession: TerminalSession? {
        guard let activeSessionID else {
            return nil
        }

        return runtimes[activeSessionID]
    }

    public var focusedPaneID: UUID? {
        workspaceGraph.focusedPaneID
    }

    public var workspaceMetadata: WorkspaceMetadataSnapshot {
        if isWorkspaceMetadataDirty || cachedWorkspaceMetadata == nil {
            cachedWorkspaceMetadata = WorkspaceMetadataSnapshot.resolve(workspace: self)
            isWorkspaceMetadataDirty = false
        }

        return cachedWorkspaceMetadata ?? WorkspaceMetadataSnapshot.resolve(workspace: self)
    }

    public var activeScopeNote: WorkspaceNoteSnapshot? {
        note(forGroup: activeGroupID)
    }

    public func descriptor(for id: UUID) -> SessionDescriptor? {
        sessions.first(where: { $0.id == id })
    }

    public func session(for id: UUID) -> TerminalSession? {
        runtimes[id]
    }

    func sessionStartedAt(for id: UUID) -> Date? {
        sessionStartedAtByID[id]
    }

    public func sessionIDs() -> [UUID] {
        sessions.map(\.id)
    }

    public func paneID(for sessionID: UUID) -> UUID? {
        workspaceGraph.paneID(for: sessionID)
    }

    public func sessionID(forPane paneID: UUID) -> UUID? {
        workspaceGraph.sessionID(for: paneID)
    }

    public func gitChangeSummary(for sessionID: UUID) -> WorkspaceGitChangeSummary? {
        sessionGitChanges[sessionID]
    }

    public func aggregatedGitChangeSummary() -> WorkspaceGitChangeSummary? {
        guard !sessionGitChanges.isEmpty else {
            return nil
        }

        return sessionGitChanges.values.reduce(into: WorkspaceGitChangeSummary()) { partial, summary in
            partial.addedCount += summary.addedCount
            partial.removedCount += summary.removedCount
        }
    }

    @discardableResult
    public func updateWorkspaceNote(body: String) -> Bool {
        updateNote(body: body, forGroup: nil)
    }

    @discardableResult
    public func updateNote(body: String, forGroup groupID: UUID?) -> Bool {
        let normalizedBody = Self.normalizedWorkspaceNoteBody(body)
        if let groupID {
            guard let index = sessionGroups.firstIndex(where: { $0.id == groupID }) else {
                return false
            }

            guard sessionGroups[index].note?.body != normalizedBody else {
                return false
            }

            guard let normalizedBody else {
                sessionGroups[index].note = nil
                return true
            }

            sessionGroups[index].note = WorkspaceNoteSnapshot(body: normalizedBody)
            return true
        }

        guard workspaceNote?.body != normalizedBody else {
            return false
        }

        guard let normalizedBody else {
            workspaceNote = nil
            return true
        }

        workspaceNote = WorkspaceNoteSnapshot(body: normalizedBody)
        return true
    }

    @discardableResult
    public func clearWorkspaceNote() -> Bool {
        clearNote(forGroup: nil)
    }

    @discardableResult
    public func clearNote(forGroup groupID: UUID?) -> Bool {
        if let groupID {
            guard let index = sessionGroups.firstIndex(where: { $0.id == groupID }),
                  sessionGroups[index].note != nil else {
                return false
            }

            sessionGroups[index].note = nil
            return true
        }

        guard workspaceNote != nil else {
            return false
        }

        workspaceNote = nil
        return true
    }

    public func note(forGroup groupID: UUID?) -> WorkspaceNoteSnapshot? {
        guard let groupID else {
            return workspaceNote
        }

        return sessionGroups.first(where: { $0.id == groupID })?.note
    }

    public func sessions(inGroup groupID: UUID?) -> [SessionDescriptor] {
        sessions.filter { descriptor in
            sessionGroupAssignments[descriptor.id] == groupID
        }
    }

    public func createGroup(name: String, colorTag: SessionGroupColor?) -> SessionGroup {
        let group = SessionGroup(
            name: resolvedGroupName(name, fallback: nextDefaultGroupName()),
            colorTag: colorTag,
            isCollapsed: false
        )
        sessionGroups.append(group)
        return group
    }

    @discardableResult
    public func renameGroup(id: UUID, name: String) -> Bool {
        guard let index = sessionGroups.firstIndex(where: { $0.id == id }) else {
            return false
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return false
        }

        guard sessionGroups[index].name != trimmedName else {
            return false
        }

        sessionGroups[index].name = trimmedName
        return true
    }

    @discardableResult
    public func deleteGroup(id: UUID) -> Bool {
        guard let index = sessionGroups.firstIndex(where: { $0.id == id }) else {
            return false
        }

        let deletedGroup = sessionGroups[index]

        if activeGroupID == id {
            _ = selectGroup(id: nil)
        }

        let movedSessionIDs = sessions(inGroup: id).map(\.id)
        let normalizedDeletedGraph = normalize(
            deletedGroup.paneGraph,
            allowedSessionIDs: Set(movedSessionIDs),
            preferredSessionID: movedSessionIDs.first
        )

        for sessionID in movedSessionIDs {
            sessionGroupAssignments.removeValue(forKey: sessionID)
        }

        if ungroupedGraph.rootPane == nil {
            ungroupedGraph = normalize(
                normalizedDeletedGraph,
                allowedSessionIDs: Set(sessions(inGroup: nil).map(\.id)),
                preferredSessionID: activeSessionID
            )
        }

        sessionGroups.remove(at: index)

        if activeGroupID == nil {
            workspaceGraph = normalize(
                ungroupedGraph,
                allowedSessionIDs: Set(sessions(inGroup: nil).map(\.id)),
                preferredSessionID: activeSessionID
            )
            ungroupedGraph = workspaceGraph
            synchronizeActiveSessionID(preferredSessionID: activeSessionID, in: nil)
        }

        return true
    }

    @discardableResult
    public func moveGroup(id: UUID, toIndex requestedIndex: Int) -> Bool {
        guard let sourceIndex = sessionGroups.firstIndex(where: { $0.id == id }) else {
            return false
        }

        let boundedIndex = min(max(requestedIndex, 0), sessionGroups.count - 1)
        guard boundedIndex != sourceIndex else {
            return false
        }

        let group = sessionGroups.remove(at: sourceIndex)
        sessionGroups.insert(group, at: boundedIndex)
        return true
    }

    @discardableResult
    public func assignSession(id: UUID, toGroup groupID: UUID?) -> Bool {
        guard runtimes[id] != nil, sessions.contains(where: { $0.id == id }) else {
            return false
        }

        if let groupID, group(for: groupID) == nil {
            return false
        }

        guard sessionGroupAssignments[id] != groupID else {
            return false
        }

        guard reassignSessionScope(id: id, toGroup: groupID, preserveOrder: false) else {
            return false
        }

        return true
    }

    @discardableResult
    public func setGroupCollapsed(id: UUID, isCollapsed: Bool) -> Bool {
        guard let index = sessionGroups.firstIndex(where: { $0.id == id }) else {
            return false
        }

        guard sessionGroups[index].isCollapsed != isCollapsed else {
            return false
        }

        sessionGroups[index].isCollapsed = isCollapsed
        return true
    }

    @discardableResult
    public func setGroupColorTag(id: UUID, colorTag: SessionGroupColor?) -> Bool {
        guard let index = sessionGroups.firstIndex(where: { $0.id == id }) else {
            return false
        }
        guard sessionGroups[index].colorTag != colorTag else {
            return false
        }
        sessionGroups[index].colorTag = colorTag
        return true
    }

    public func aggregatedAgentStatus(forGroup groupID: UUID) -> SessionAgentStatus {
        let statuses = sessions(inGroup: groupID).map(\.agentStatus)
        if statuses.contains(.error) {
            return .error
        }
        if statuses.contains(.waiting) {
            return .waiting
        }
        if statuses.contains(.running) {
            return .running
        }
        if statuses.contains(.done) {
            return .done
        }
        return .none
    }

    @discardableResult
    public func handleDroppedSession(identifier: String, toGroup groupID: UUID?) -> Bool {
        guard let payload = WorkspaceDragPayload.decode(from: identifier),
              payload.kind == .session else {
            return false
        }

        return assignSession(id: payload.id, toGroup: groupID)
    }

    @discardableResult
    public func perform(_ command: SessionCommand) -> Bool {
        switch command {
        case .new:
            _ = createSession()
            return true
        case .closeCurrent:
            return closeCurrentSession()
        case .close(let id):
            return closeSession(id: id)
        case .closeFocusedPane:
            return closeFocusedPane()
        case .select(let id):
            return selectSession(id: id)
        case .selectNext:
            return selectNextSession()
        case .selectPrevious:
            return selectPreviousSession()
        case .selectNextPane:
            return focusNextPane()
        case .selectPreviousPane:
            return focusPreviousPane()
        case .selectNextAttention:
            return selectNextAttentionSession()
        case .rename(let id, let title):
            return renameSession(id: id, title: title)
        case .updateContext(let id, let workingDirectoryPath, let foregroundProcessName):
            return updateSessionContext(
                id: id,
                workingDirectoryPath: workingDirectoryPath,
                foregroundProcessName: foregroundProcessName
            )
        case .updateAgentStatus(let id, let status):
            return updateAgentStatus(id: id, status: status)
        case .applyAgentStatusEscapeSequence(let id, let sequence):
            return applyAgentStatusEscapeSequence(id: id, sequence: sequence)
        case .move(let id, let toIndex):
            return moveSession(id: id, toIndex: toIndex)
        case .createGroup(let name, let colorTag):
            _ = createGroup(name: name, colorTag: colorTag)
            return true
        case .renameGroup(let id, let name):
            return renameGroup(id: id, name: name)
        case .deleteGroup(let id):
            return deleteGroup(id: id)
        case .moveGroup(let id, let toIndex):
            return moveGroup(id: id, toIndex: toIndex)
        case .selectGroup(let id):
            return selectGroup(id: id)
        case .assignSessionToGroup(let sessionID, let groupID):
            return assignSession(id: sessionID, toGroup: groupID)
        case .setGroupCollapsed(let id, let isCollapsed):
            return setGroupCollapsed(id: id, isCollapsed: isCollapsed)
        case .splitHorizontal:
            return performAdaptiveSplit(.horizontal)
        case .splitVertical:
            return performAdaptiveSplit(.vertical)
        }
    }

    @discardableResult
    public func createSession(selectNewSession: Bool = true) -> SessionDescriptor {
        let ordinal = nextOrdinal
        nextOrdinal += 1

        let descriptor = SessionDescriptor(ordinal: ordinal)
        let runtime = sessionFactory(nil)
        configureRuntime(runtime, for: descriptor.id)
        if autoStartSessions {
            runtime.start()
        }

        runtimes[descriptor.id] = runtime
        sessionStartedAtByID[descriptor.id] = Date()
        sessions.append(descriptor)

        if let activeGroupID {
            sessionGroupAssignments[descriptor.id] = activeGroupID
        }

        if workspaceGraph.rootPane == nil {
            workspaceGraph.ensureRoot(sessionID: descriptor.id)
        }

        if selectNewSession || activeSessionID == nil {
            _ = selectSession(id: descriptor.id)
        } else {
            synchronizeActiveSessionID(in: activeGroupID)
        }

        return descriptor
    }

    @discardableResult
    public func closeCurrentSession() -> Bool {
        guard let activeSessionID else {
            return false
        }

        return closeSession(id: activeSessionID)
    }

    @discardableResult
    public func selectGroup(id: UUID?) -> Bool {
        if let id, group(for: id) == nil {
            return false
        }

        guard activeGroupID != id else {
            return false
        }

        let preferredSessionID = activeSessionID
        persistActiveGraphIntoBackingStore()

        let allowedSessionIDs = Set(scopedSessionIDs(for: id))
        let normalizedGraph = normalize(
            backingGraph(for: id),
            allowedSessionIDs: allowedSessionIDs,
            preferredSessionID: preferredSessionID
        )

        workspaceGraph = normalizedGraph
        activeGroupID = id
        setBackingGraph(normalizedGraph, for: id)
        synchronizeActiveSessionID(preferredSessionID: preferredSessionID, in: id)
        scheduleGitRefresh(for: workspaceGraph.leafSessionIDs)
        return true
    }

    @discardableResult
    public func closeSession(id: UUID) -> Bool {
        guard let index = indexForSession(id: id) else {
            return false
        }

        let wasActive = activeSessionID == id
        let removedGroupID = groupID(forSession: id)
        let fallbackSessionID = wasActive ? fallbackSessionID(afterRemoving: id, at: index, in: removedGroupID) : activeSessionID
        _ = detachSession(id: id, fromGroup: removedGroupID)

        if let runtime = runtimes.removeValue(forKey: id) {
            runtime.stop()
        }

        sessionStartedAtByID.removeValue(forKey: id)
        sessionGroupAssignments.removeValue(forKey: id)
        sessions.remove(at: index)
        removeGitChangeSummary(for: id)

        if sessions.isEmpty {
            let descriptor = createSession(selectNewSession: true)
            activeSessionID = descriptor.id
            return true
        }

        let normalizedGraph = normalize(
            workspaceGraph,
            allowedSessionIDs: Set(scopedSessionIDs(for: activeGroupID)),
            preferredSessionID: fallbackSessionID
        )
        workspaceGraph = normalizedGraph
        setBackingGraph(normalizedGraph, for: activeGroupID)
        synchronizeActiveSessionID(preferredSessionID: fallbackSessionID, in: activeGroupID)
        return true
    }

    @discardableResult
    public func closeFocusedPane() -> Bool {
        guard let removedSessionID = workspaceGraph.removeFocusedPane() else {
            return false
        }

        return closeSession(id: removedSessionID)
    }

    @discardableResult
    public func selectSession(id: UUID) -> Bool {
        guard runtimes[id] != nil, sessions.contains(where: { $0.id == id }) else {
            return false
        }

        let targetGroupID = groupID(forSession: id)
        if targetGroupID != activeGroupID {
            guard selectGroup(id: targetGroupID) else {
                return false
            }
        }

        if let paneID = workspaceGraph.paneID(for: id) {
            _ = workspaceGraph.focusPane(paneID)
        } else {
            _ = workspaceGraph.assignFocusedPane(sessionID: id)
        }

        synchronizeActiveSessionID(preferredSessionID: id, in: activeGroupID)
        setBackingGraph(workspaceGraph, for: activeGroupID)
        scheduleGitRefresh(for: [id])
        return true
    }

    @discardableResult
    public func selectNextSession() -> Bool {
        cycleSelection(step: 1)
    }

    @discardableResult
    public func selectPreviousSession() -> Bool {
        cycleSelection(step: -1)
    }

    @discardableResult
    public func focusPane(id paneID: UUID) -> Bool {
        guard workspaceGraph.focusPane(paneID) else {
            return false
        }

        synchronizeActiveSessionID(in: activeGroupID)
        setBackingGraph(workspaceGraph, for: activeGroupID)
        scheduleGitRefresh(for: focusedLeafSessionIDs())
        return true
    }

    @discardableResult
    public func focusNextPane() -> Bool {
        guard workspaceGraph.focusNextPane() else {
            return false
        }

        synchronizeActiveSessionID(in: activeGroupID)
        setBackingGraph(workspaceGraph, for: activeGroupID)
        scheduleGitRefresh(for: focusedLeafSessionIDs())
        return true
    }

    @discardableResult
    public func resizeSplit(branchPaneID: UUID, ratio: CGFloat) -> Bool {
        guard workspaceGraph.resizeSplit(branchPaneID: branchPaneID, ratio: ratio) else {
            return false
        }
        setBackingGraph(workspaceGraph, for: activeGroupID)
        return true
    }

    @discardableResult
    public func swapPaneContents(sourcePaneID: UUID, targetPaneID: UUID) -> Bool {
        guard workspaceGraph.swapLeafPanes(sourcePaneID, targetPaneID) else {
            return false
        }

        synchronizeActiveSessionID(in: activeGroupID)
        setBackingGraph(workspaceGraph, for: activeGroupID)
        scheduleGitRefresh(for: focusedLeafSessionIDs())
        return true
    }

    @discardableResult
    public func performPaneDrop(
        payload: WorkspaceDragPayload,
        targetPaneID: UUID,
        zone: PaneDropZone
    ) -> Bool {
        guard workspaceGraph.sessionID(for: targetPaneID) != nil else {
            return false
        }

        if payload.kind == .session, groupID(forSession: payload.id) != activeGroupID {
            return false
        }

        let action: WorkspacePaneDropAction
        switch payload.kind {
        case .pane:
            if let placement = zone.splitPlacement {
                action = .split(axis: placement.axis, insertion: placement.insertion)
            } else {
                action = .swapContents
            }
        case .session:
            if let placement = zone.splitPlacement {
                action = .split(axis: placement.axis, insertion: placement.insertion)
            } else if workspaceGraph.paneID(for: payload.id) != nil {
                action = .swapContents
            } else {
                action = .replaceTarget
            }
        }

        return performPaneDrop(
            payload: payload,
            targetPaneID: targetPaneID,
            action: action
        )
    }

    @discardableResult
    public func placeSession(id: UUID, inFocusedPaneUsing action: FocusedPanePlacementAction) -> Bool {
        guard let focusedPaneID else {
            return false
        }

        return placeSession(id: id, inPane: focusedPaneID, using: action)
    }

    @discardableResult
    public func placeSession(id: UUID, inPane targetPaneID: UUID, using action: FocusedPanePlacementAction) -> Bool {
        guard runtimes[id] != nil,
              groupID(forSession: id) == activeGroupID,
              let targetSessionID = workspaceGraph.sessionID(for: targetPaneID),
              targetSessionID != id else {
            return false
        }

        let payload = WorkspaceDragPayload(kind: .session, id: id)
        let isAttached = workspaceGraph.paneID(for: id) != nil

        switch action {
        case .splitLeft:
            return performPaneDrop(
                payload: payload,
                targetPaneID: targetPaneID,
                action: .split(axis: .vertical, insertion: .before)
            )
        case .splitRight:
            return performPaneDrop(
                payload: payload,
                targetPaneID: targetPaneID,
                action: .split(axis: .vertical, insertion: .after)
            )
        case .splitAbove:
            return performPaneDrop(
                payload: payload,
                targetPaneID: targetPaneID,
                action: .split(axis: .horizontal, insertion: .before)
            )
        case .splitBelow:
            return performPaneDrop(
                payload: payload,
                targetPaneID: targetPaneID,
                action: .split(axis: .horizontal, insertion: .after)
            )
        case .swap:
            guard isAttached else {
                return false
            }

            return performPaneDrop(
                payload: payload,
                targetPaneID: targetPaneID,
                action: .swapContents
            )
        case .replace:
            guard !isAttached else {
                return false
            }

            return performPaneDrop(
                payload: payload,
                targetPaneID: targetPaneID,
                action: .replaceTarget
            )
        }
    }

    @discardableResult
    public func focusPreviousPane() -> Bool {
        guard workspaceGraph.focusNextPane(reverse: true) else {
            return false
        }

        synchronizeActiveSessionID(in: activeGroupID)
        setBackingGraph(workspaceGraph, for: activeGroupID)
        scheduleGitRefresh(for: focusedLeafSessionIDs())
        return true
    }

    @discardableResult
    public func splitActivePane(_ axis: WorkspaceSplitAxis) -> Bool {
        splitPane(targetPaneID: nil, axis: axis)
    }

    @discardableResult
    func performAdaptiveSplit(_ axis: WorkspaceSplitAxis) -> Bool {
        splitPane(targetPaneID: adaptiveSplitTargetPaneID(for: axis), axis: axis)
    }

    @discardableResult
    private func splitPane(targetPaneID: UUID?, axis: WorkspaceSplitAxis) -> Bool {
        let newSession = createSession(selectNewSession: false)
        let didSplit: Bool
        if let targetPaneID {
            didSplit =
                workspaceGraph.splitPane(
                    targetPaneID,
                    axis: axis,
                    newSessionID: newSession.id,
                    insertion: .after
                ) != nil
        } else {
            didSplit = workspaceGraph.splitFocusedPane(axis: axis, newSessionID: newSession.id)
        }

        guard didSplit else {
            _ = removeSessionWithoutReplacement(id: newSession.id)
            return false
        }

        synchronizeActiveSessionID(preferredSessionID: newSession.id, in: activeGroupID)
        setBackingGraph(workspaceGraph, for: activeGroupID)
        scheduleGitRefresh(for: [newSession.id])
        return true
    }

    private func adaptiveSplitTargetPaneID(for axis: WorkspaceSplitAxis) -> UUID? {
        guard axis == .vertical,
              let rootPane = workspaceGraph.rootPane,
              rootPane.axis == .horizontal,
              rootPane.children.count == 2 else {
            return nil
        }

        let topNode = rootPane.children[0]
        let bottomNode = rootPane.children[1]

        if topNode.isLeaf, bottomNode.isLeaf {
            return topNode.id
        }

        guard topNode.axis == .vertical,
              topNode.children.count == 2,
              topNode.children.allSatisfy(\.isLeaf),
              bottomNode.isLeaf else {
            return nil
        }

        return bottomNode.id
    }

    private func adaptivelyPlaceSession(id sessionID: UUID) -> Bool {
        guard let rootPane = workspaceGraph.rootPane else { return false }

        // 1 pane → force horizontal split (top/bottom)
        if rootPane.isLeaf {
            guard let insertedPaneID = workspaceGraph.splitPane(
                rootPane.id, axis: .horizontal, newSessionID: sessionID, insertion: .after
            ) else { return false }
            _ = workspaceGraph.focusPane(insertedPaneID)
            return true
        }

        // 2-3 panes → use existing adaptive vertical target
        guard let targetID = adaptiveSplitTargetPaneID(for: .vertical) else {
            return false  // 4+ panes: no adaptive placement
        }

        guard let insertedPaneID = workspaceGraph.splitPane(
            targetID, axis: .vertical, newSessionID: sessionID, insertion: .after
        ) else { return false }
        _ = workspaceGraph.focusPane(insertedPaneID)
        return true
    }

    @discardableResult
    public func renameSession(id: UUID, title: String?) -> Bool {
        guard updateDescriptor(id: id, { descriptor in
            descriptor.setCustomTitle(title)
        }) != nil else {
            return false
        }
        return true
    }

    @discardableResult
    public func updateSessionTerminalTitle(id: UUID, title: String?) -> Bool {
        guard updateDescriptor(id: id, { descriptor in
            descriptor.setTerminalTitle(title)
        }) != nil else {
            return false
        }
        return true
    }

    @discardableResult
    public func updateSessionContext(
        id: UUID,
        workingDirectoryPath: String?,
        foregroundProcessName: String?
    ) -> Bool {
        guard let changed = updateDescriptor(id: id, { descriptor in
            descriptor.updateContext(
                workingDirectoryPath: workingDirectoryPath,
                foregroundProcessName: foregroundProcessName
            )
        }) else {
            return false
        }

        if changed {
            scheduleGitRefresh(for: [id])
        }
        return true
    }

    @discardableResult
    public func updateAgentStatus(id: UUID, status: SessionAgentStatus) -> Bool {
        guard updateDescriptor(id: id, { descriptor in
            descriptor.setAgentStatus(status)
        }) != nil else {
            return false
        }
        return true
    }

    @discardableResult
    public func applyAgentStatusEscapeSequence(id: UUID, sequence: String) -> Bool {
        guard let session = runtimes[id], let update = session.processAgentStatusEscapeSequence(sequence) else {
            return false
        }

        return updateAgentStatus(id: id, status: update.status)
    }

    @discardableResult
    public func moveSession(id: UUID, toIndex requestedIndex: Int) -> Bool {
        guard let sourceIndex = indexForSession(id: id) else {
            return false
        }

        let boundedIndex = min(max(requestedIndex, 0), sessions.count - 1)
        guard boundedIndex != sourceIndex else {
            return false
        }

        let descriptor = sessions.remove(at: sourceIndex)
        sessions.insert(descriptor, at: boundedIndex)
        return true
    }

    @discardableResult
    public func moveSession(id: UUID, before targetID: UUID) -> Bool {
        guard
            let sourceIndex = indexForSession(id: id),
            let targetIndex = indexForSession(id: targetID)
        else {
            return false
        }

        var destinationIndex = targetIndex
        if sourceIndex < targetIndex {
            destinationIndex -= 1
        }

        return moveSession(id: id, toIndex: destinationIndex)
    }

    @discardableResult
    public func handleDroppedSession(identifier: String, before targetID: UUID) -> Bool {
        guard let payload = WorkspaceDragPayload.decode(from: identifier),
              payload.kind == .session else {
            return false
        }

        let targetGroupID = groupID(forSession: targetID)
        guard moveSession(id: payload.id, before: targetID) else {
            return false
        }

        if sessionGroupAssignments[payload.id] == targetGroupID {
            return true
        }

        return reassignSessionScope(id: payload.id, toGroup: targetGroupID, preserveOrder: true)
    }

    @discardableResult
    public func selectNextAttentionSession() -> Bool {
        guard let nextAttentionID = nextAttentionSessionID() else {
            return false
        }

        return selectSession(id: nextAttentionID)
    }

    public func nextAttentionSessionID(after startingID: UUID? = nil) -> UUID? {
        let scopedDescriptors = sessions(inGroup: activeGroupID)
        guard !scopedDescriptors.isEmpty else {
            return nil
        }

        let anchorID = startingID ?? activeSessionID
        guard let anchorID,
              let currentIndex = scopedDescriptors.firstIndex(where: { $0.id == anchorID }) else {
            return scopedDescriptors.first(where: { $0.agentStatus.needsAttention })?.id
        }

        for offset in 1...scopedDescriptors.count {
            let candidateIndex = (currentIndex + offset) % scopedDescriptors.count
            let descriptor = scopedDescriptors[candidateIndex]

            if descriptor.agentStatus.needsAttention {
                return descriptor.id
            }
        }

        return nil
    }

    @discardableResult
    public func sendInputToActiveSession(_ text: String, appendNewline: Bool = true) -> String {
        guard let activeSession else {
            return ""
        }

        let payload = appendNewline ? "\(text)\n" : text
        let result = activeSession.sendUserInput(payload)
        refreshVisibleState()
        return result
    }

    public func requestQuit() {
        quitRequested = true
    }

    public func clearQuitRequest() {
        quitRequested = false
    }

    public func refreshVisibleState() {
        guard !isVisibleRefreshScheduled else {
            return
        }

        isVisibleRefreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            self.isVisibleRefreshScheduled = false
            self.objectWillChange.send()
        }
    }

    public func snapshot() -> WorkspaceSnapshot {
        persistActiveGraphIntoBackingStore()

        let persistedSessions = sessions.map { descriptor in
            WorkspaceSnapshot.PersistedSession(
                descriptor: descriptor
            )
        }
        let persistedGroups = sessionGroups.map { group in
            WorkspaceSnapshot.PersistedSessionGroup(
                id: group.id,
                name: group.name,
                colorTag: group.colorTag,
                isCollapsed: group.isCollapsed,
                paneGraph: group.paneGraph,
                note: group.note
            )
        }
        let persistedAssignments = sessionGroupAssignments.reduce(into: [String: String]()) { partial, entry in
            partial[entry.key.uuidString] = entry.value.uuidString
        }

        return WorkspaceSnapshot(
            sessions: persistedSessions,
            activeSessionID: activeSessionID,
            nextOrdinal: nextOrdinal,
            workspaceGraph: ungroupedGraph,
            sessionGroups: persistedGroups,
            activeGroupID: activeGroupID,
            sessionGroupAssignments: persistedAssignments,
            workspaceNote: workspaceNote
        )
    }

    @discardableResult
    public func restore(from snapshot: WorkspaceSnapshot) -> Bool {
        guard snapshot.isSupported else {
            return false
        }

        for runtime in runtimes.values {
            runtime.stop()
        }

        runtimes.removeAll()
        sessionStartedAtByID.removeAll()
        sessions.removeAll()
        activeSessionID = nil
        activeGroupID = nil
        workspaceGraph = WorkspaceGraph()
        ungroupedGraph = snapshot.workspaceGraph ?? WorkspaceGraph()
        sessionGroups = snapshot.sessionGroups.map { group in
            SessionGroup(
                id: group.id,
                name: group.name,
                colorTag: group.colorTag,
                isCollapsed: group.isCollapsed,
                paneGraph: group.paneGraph ?? WorkspaceGraph(),
                note: group.note
            )
        }
        sessionGroupAssignments = [:]
        sessionGitChanges = [:]
        workspaceNote = snapshot.workspaceNote
        pendingGitRefreshSessionIDs.removeAll()
        gitRefreshTask?.cancel()
        gitRefreshTask = nil
        nextOrdinal = max(
            snapshot.nextOrdinal,
            (snapshot.sessions.map(\.descriptor.ordinal).max() ?? 0) + 1
        )

        guard !snapshot.sessions.isEmpty else {
            let replacement = createSession(selectNewSession: true)
            activeSessionID = replacement.id
            return true
        }

        let restoredAt = Date()
        for persisted in snapshot.sessions {
            let descriptor = persisted.descriptor
            let runtime = sessionFactory(Self.startupDirectoryURL(from: descriptor.workingDirectoryPath))
            configureRuntime(runtime, for: descriptor.id)
            if autoStartSessions {
                runtime.start()
            }

            runtimes[descriptor.id] = runtime
            sessionStartedAtByID[descriptor.id] = restoredAt
            sessions.append(descriptor)
        }

        sessionGroupAssignments = snapshot.sessionGroupAssignments.reduce(into: [UUID: UUID]()) { partial, entry in
            guard let sessionID = UUID(uuidString: entry.key),
                  let groupID = UUID(uuidString: entry.value) else {
                return
            }

            partial[sessionID] = groupID
        }
        cleanupInvalidGroupAssignments()

        ungroupedGraph = normalize(
            ungroupedGraph,
            allowedSessionIDs: Set(scopedSessionIDs(for: nil)),
            preferredSessionID: snapshot.activeSessionID
        )
        for index in sessionGroups.indices {
            let groupID = sessionGroups[index].id
            sessionGroups[index].paneGraph = normalize(
                sessionGroups[index].paneGraph,
                allowedSessionIDs: Set(scopedSessionIDs(for: groupID)),
                preferredSessionID: snapshot.activeSessionID
            )
        }

        let restoredActiveGroupID = snapshot.activeGroupID.flatMap { group(for: $0)?.id }
        activeGroupID = restoredActiveGroupID
        workspaceGraph = backingGraph(for: restoredActiveGroupID)
        synchronizeActiveSessionID(preferredSessionID: snapshot.activeSessionID, in: restoredActiveGroupID)
        scheduleGitRefresh(for: Set(workspaceGraph.leafSessionIDs))
        return true
    }

    private static func normalizedWorkspaceNoteBody(_ body: String) -> String? {
        let normalized = body
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return normalized
    }

    private func cycleSelection(step: Int) -> Bool {
        let scopedSessionIDs = scopedSessionIDs(for: activeGroupID)
        guard !scopedSessionIDs.isEmpty else {
            return false
        }

        guard let activeSessionID,
              let currentIndex = scopedSessionIDs.firstIndex(of: activeSessionID) else {
            let fallbackID = scopedSessionIDs.first
            if let fallbackID {
                return selectSession(id: fallbackID)
            }

            return false
        }

        let nextIndex = (currentIndex + step + scopedSessionIDs.count) % scopedSessionIDs.count
        return selectSession(id: scopedSessionIDs[nextIndex])
    }

    private func synchronizeActiveSessionID(preferredSessionID: UUID? = nil, in groupID: UUID? = nil) {
        let scopedSessionIDSet = Set(scopedSessionIDs(for: groupID))

        if let preferredSessionID,
           scopedSessionIDSet.contains(preferredSessionID),
           runtimes[preferredSessionID] != nil {
            activeSessionID = preferredSessionID
            return
        }

        if let focusedSessionID = workspaceGraph.focusedSessionID,
           scopedSessionIDSet.contains(focusedSessionID),
           runtimes[focusedSessionID] != nil {
            activeSessionID = focusedSessionID
            return
        }

        if let firstSessionID = firstScopedSessionID(for: groupID) {
            activeSessionID = firstSessionID
            workspaceGraph.ensureRoot(sessionID: firstSessionID)
            if let paneID = workspaceGraph.paneID(for: firstSessionID) {
                _ = workspaceGraph.focusPane(paneID)
            }
            setBackingGraph(workspaceGraph, for: groupID)
            return
        }

        activeSessionID = nil
    }

    private func performPaneDrop(
        payload: WorkspaceDragPayload,
        targetPaneID: UUID,
        action: WorkspacePaneDropAction
    ) -> Bool {
        switch (payload.kind, action) {
        case (.pane, .swapContents):
            return swapPaneContents(sourcePaneID: payload.id, targetPaneID: targetPaneID)
        case (.pane, .replaceTarget):
            return false
        case (.pane, .split(let axis, let insertion)):
            guard let sourceSessionID = workspaceGraph.sessionID(for: payload.id),
                  workspaceGraph.moveLeafPane(
                    payload.id,
                    beside: targetPaneID,
                    axis: axis,
                    insertion: insertion
                  ) else {
                return false
            }

            synchronizeActiveSessionID(preferredSessionID: sourceSessionID, in: activeGroupID)
            setBackingGraph(workspaceGraph, for: activeGroupID)
            scheduleGitRefresh(for: focusedLeafSessionIDs())
            return true
        case (.session, .swapContents):
            guard let sourcePaneID = workspaceGraph.paneID(for: payload.id) else {
                return replacePaneContents(targetPaneID: targetPaneID, sessionID: payload.id)
            }

            return swapPaneContents(sourcePaneID: sourcePaneID, targetPaneID: targetPaneID)
        case (.session, .replaceTarget):
            return replacePaneContents(targetPaneID: targetPaneID, sessionID: payload.id)
        case (.session, .split(let axis, let insertion)):
            if let sourcePaneID = workspaceGraph.paneID(for: payload.id) {
                guard workspaceGraph.moveLeafPane(
                    sourcePaneID,
                    beside: targetPaneID,
                    axis: axis,
                    insertion: insertion
                ) else {
                    return false
                }

                synchronizeActiveSessionID(preferredSessionID: payload.id, in: activeGroupID)
                setBackingGraph(workspaceGraph, for: activeGroupID)
                scheduleGitRefresh(for: focusedLeafSessionIDs())
                return true
            }

            // Not in a pane → ADD: try adaptive placement first
            if adaptivelyPlaceSession(id: payload.id) {
                synchronizeActiveSessionID(preferredSessionID: payload.id, in: activeGroupID)
                setBackingGraph(workspaceGraph, for: activeGroupID)
                scheduleGitRefresh(for: focusedLeafSessionIDs().union([payload.id]))
                return true
            }

            // Fallback: explicit drop zone placement (5+ panes)
            guard let insertedPaneID = workspaceGraph.splitPane(
                targetPaneID,
                axis: axis,
                newSessionID: payload.id,
                insertion: insertion
            ) else {
                return false
            }

            _ = workspaceGraph.focusPane(insertedPaneID)
            synchronizeActiveSessionID(preferredSessionID: payload.id, in: activeGroupID)
            setBackingGraph(workspaceGraph, for: activeGroupID)
            scheduleGitRefresh(for: focusedLeafSessionIDs().union([payload.id]))
            return true
        }
    }

    @discardableResult
    private func removeSessionWithoutReplacement(id: UUID) -> Bool {
        guard let index = indexForSession(id: id) else {
            return false
        }

        let groupID = groupID(forSession: id)
        let fallbackSessionID = fallbackSessionID(afterRemoving: id, at: index, in: groupID)
        _ = detachSession(id: id, fromGroup: groupID)

        if let runtime = runtimes.removeValue(forKey: id) {
            runtime.stop()
        }

        sessionStartedAtByID.removeValue(forKey: id)
        sessionGroupAssignments.removeValue(forKey: id)
        sessions.remove(at: index)
        removeGitChangeSummary(for: id)
        let normalizedGraph = normalize(
            workspaceGraph,
            allowedSessionIDs: Set(scopedSessionIDs(for: activeGroupID)),
            preferredSessionID: fallbackSessionID
        )
        workspaceGraph = normalizedGraph
        setBackingGraph(normalizedGraph, for: activeGroupID)
        synchronizeActiveSessionID(preferredSessionID: fallbackSessionID, in: activeGroupID)
        return true
    }

    private func indexForSession(id: UUID) -> Int? {
        sessions.firstIndex(where: { $0.id == id })
    }

    private func group(for id: UUID) -> SessionGroup? {
        sessionGroups.first(where: { $0.id == id })
    }

    private func groupID(forSession id: UUID) -> UUID? {
        sessionGroupAssignments[id]
    }

    private func scopedSessionIDs(for groupID: UUID?) -> [UUID] {
        sessions(inGroup: groupID).map(\.id)
    }

    private func firstScopedSessionID(for groupID: UUID?) -> UUID? {
        sessions.first { descriptor in
            sessionGroupAssignments[descriptor.id] == groupID
        }?.id
    }

    private func backingGraph(for groupID: UUID?) -> WorkspaceGraph {
        guard let groupID,
              let group = group(for: groupID) else {
            return ungroupedGraph
        }

        return group.paneGraph
    }

    private func setBackingGraph(_ graph: WorkspaceGraph, for groupID: UUID?) {
        if let groupID,
           let index = sessionGroups.firstIndex(where: { $0.id == groupID }) {
            sessionGroups[index].paneGraph = graph
            return
        }

        ungroupedGraph = graph
    }

    private func persistActiveGraphIntoBackingStore() {
        setBackingGraph(workspaceGraph, for: activeGroupID)
    }

    private func normalize(
        _ graph: WorkspaceGraph,
        allowedSessionIDs: Set<UUID>,
        preferredSessionID: UUID?
    ) -> WorkspaceGraph {
        var normalizedGraph = graph

        for sessionID in normalizedGraph.leafSessionIDs where !allowedSessionIDs.contains(sessionID) {
            _ = normalizedGraph.detach(sessionID: sessionID)
        }

        if normalizedGraph.rootPane == nil {
            if let preferredSessionID, allowedSessionIDs.contains(preferredSessionID) {
                normalizedGraph.ensureRoot(sessionID: preferredSessionID)
            } else if let firstAllowedSessionID = sessions.first(where: { allowedSessionIDs.contains($0.id) })?.id {
                normalizedGraph.ensureRoot(sessionID: firstAllowedSessionID)
            }
        }

        if let focusedPaneID = normalizedGraph.focusedPaneID,
           normalizedGraph.sessionID(for: focusedPaneID) == nil {
            normalizedGraph.focusedPaneID = normalizedGraph.rootPane?.leafPanes.first?.id
        } else if normalizedGraph.focusedPaneID == nil {
            normalizedGraph.focusedPaneID = normalizedGraph.rootPane?.leafPanes.first?.id
        }

        return normalizedGraph
    }

    @discardableResult
    private func detachSession(id: UUID, fromGroup groupID: UUID?) -> Bool {
        if groupID == activeGroupID {
            let detached = workspaceGraph.detach(sessionID: id)
            if detached {
                setBackingGraph(workspaceGraph, for: activeGroupID)
            }
            return detached
        }

        var graph = backingGraph(for: groupID)
        let detached = graph.detach(sessionID: id)
        if detached {
            setBackingGraph(graph, for: groupID)
        }
        return detached
    }

    private func fallbackSessionID(afterRemoving id: UUID, at index: Int, in groupID: UUID?) -> UUID? {
        let remainingGroupSessionIDs = sessions
            .enumerated()
            .compactMap { currentIndex, descriptor -> UUID? in
                guard currentIndex != index,
                      sessionGroupAssignments[descriptor.id] == groupID else {
                    return nil
                }

                return descriptor.id
            }

        guard !remainingGroupSessionIDs.isEmpty else {
            return nil
        }

        let replacementIndex = min(index, remainingGroupSessionIDs.count - 1)
        return remainingGroupSessionIDs[replacementIndex]
    }

    @discardableResult
    private func reassignSessionScope(id: UUID, toGroup groupID: UUID?, preserveOrder: Bool) -> Bool {
        let previousGroupID = sessionGroupAssignments[id]
        guard previousGroupID != groupID else {
            return false
        }

        _ = detachSession(id: id, fromGroup: previousGroupID)

        var updatedAssignments = sessionGroupAssignments
        if let groupID {
            updatedAssignments[id] = groupID
        } else {
            updatedAssignments.removeValue(forKey: id)
        }
        sessionGroupAssignments = updatedAssignments

        if !preserveOrder {
            _ = moveSessionToEndOfGroup(id: id, groupID: groupID)
        }

        if activeGroupID == groupID {
            let normalizedGraph = normalize(
                workspaceGraph,
                allowedSessionIDs: Set(scopedSessionIDs(for: groupID)),
                preferredSessionID: activeSessionID
            )
            workspaceGraph = normalizedGraph
            setBackingGraph(normalizedGraph, for: groupID)
            synchronizeActiveSessionID(preferredSessionID: activeSessionID, in: groupID)
        }

        return true
    }

    private func resolvedGroupName(_ raw: String, fallback: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func nextDefaultGroupName() -> String {
        var candidateIndex = 1
        while true {
            let candidate = candidateIndex == 1 ? "New Group" : "New Group \(candidateIndex)"
            if !sessionGroups.contains(where: { $0.name == candidate }) {
                return candidate
            }
            candidateIndex += 1
        }
    }

    @discardableResult
    private func moveSessionToEndOfGroup(id: UUID, groupID: UUID?) -> Bool {
        let targetSessions = sessions(inGroup: groupID)
            .map(\.id)
            .filter { $0 != id }
        guard let anchorID = targetSessions.last,
              let sourceIndex = indexForSession(id: id),
              let targetIndex = indexForSession(id: anchorID) else {
            return false
        }

        let destinationIndex = sourceIndex < targetIndex ? targetIndex : targetIndex + 1
        return moveSession(id: id, toIndex: destinationIndex)
    }

    private func cleanupInvalidGroupAssignments() {
        let validSessionIDs = Set(sessions.map(\.id))
        let validGroupIDs = self.validGroupIDs()
        sessionGroupAssignments = sessionGroupAssignments.filter { entry in
            validSessionIDs.contains(entry.key) && validGroupIDs.contains(entry.value)
        }
    }

    private func validGroupIDs() -> Set<UUID> {
        Set(sessionGroups.map(\.id))
    }

    private func replacePaneContents(targetPaneID: UUID, sessionID: UUID) -> Bool {
        guard runtimes[sessionID] != nil,
              workspaceGraph.assign(sessionID: sessionID, toPaneID: targetPaneID) else {
            return false
        }

        synchronizeActiveSessionID(preferredSessionID: sessionID, in: activeGroupID)
        setBackingGraph(workspaceGraph, for: activeGroupID)
        scheduleGitRefresh(for: [sessionID])
        return true
    }

    private func focusedLeafSessionIDs() -> Set<UUID> {
        guard let focusedSessionID = workspaceGraph.focusedSessionID else {
            return []
        }

        return [focusedSessionID]
    }

    private func removeGitChangeSummary(for sessionID: UUID) {
        pendingGitRefreshSessionIDs.remove(sessionID)
        guard sessionGitChanges[sessionID] != nil else {
            return
        }

        var updatedChanges = sessionGitChanges
        updatedChanges.removeValue(forKey: sessionID)
        sessionGitChanges = updatedChanges
    }

    private func scheduleGitRefresh<S: Sequence>(for sessionIDs: S) where S.Element == UUID {
        let validSessionIDs = Set(sessionIDs.filter { runtimes[$0] != nil })
        guard !validSessionIDs.isEmpty else {
            return
        }

        pendingGitRefreshSessionIDs.formUnion(validSessionIDs)
        gitRefreshTask?.cancel()
        gitRefreshTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                try await Task.sleep(nanoseconds: 500_000_000)
            } catch {
                return
            }

            await self.refreshPendingGitChanges()
        }
    }

    private func refreshPendingGitChanges() async {
        let pendingSessionIDs = pendingGitRefreshSessionIDs
        pendingGitRefreshSessionIDs.removeAll()
        guard !pendingSessionIDs.isEmpty else {
            gitRefreshTask = nil
            return
        }

        let descriptorSnapshot = pendingSessionIDs.reduce(into: [UUID: SessionDescriptor]()) { partial, sessionID in
            guard let descriptor = descriptor(for: sessionID) else {
                return
            }

            partial[sessionID] = descriptor
        }

        let requestContexts = descriptorSnapshot.compactMap { sessionID, descriptor -> (UUID, String)? in
            guard let workingDirectoryPath = descriptor.workingDirectoryPath?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !workingDirectoryPath.isEmpty else {
                return nil
            }

            return (sessionID, workingDirectoryPath)
        }

        let refreshedContext = await Task.detached(priority: .utility) {
            var groupedSessionIDs: [String: [UUID]] = [:]

            for (sessionID, workingDirectoryPath) in requestContexts {
                guard let gitRoot = WorkspaceMetadataSnapshot.gitRoot(for: workingDirectoryPath) else {
                    continue
                }

                groupedSessionIDs[gitRoot, default: []].append(sessionID)
            }

            var refreshedChanges: [UUID: WorkspaceGitChangeSummary] = [:]
            for (gitRoot, sessionIDs) in groupedSessionIDs {
                guard let summary = WorkspaceMetadataSnapshot.gitWorkingTreeDelta(workingDirectory: gitRoot) else {
                    continue
                }

                for sessionID in sessionIDs {
                    refreshedChanges[sessionID] = summary
                }
            }

            let sessionIDsWithGitRoots = Set(groupedSessionIDs.values.flatMap { $0 })
            return (refreshedChanges, sessionIDsWithGitRoots)
        }.value

        let (refreshedChanges, sessionIDsWithGitRoots) = refreshedContext
        let clearedSessionIDs = Set(descriptorSnapshot.keys).subtracting(sessionIDsWithGitRoots)

        var updatedChanges = sessionGitChanges
        for sessionID in clearedSessionIDs {
            updatedChanges.removeValue(forKey: sessionID)
        }

        for sessionID in pendingSessionIDs where descriptorSnapshot[sessionID] == nil {
            updatedChanges.removeValue(forKey: sessionID)
        }

        for (sessionID, summary) in refreshedChanges {
            updatedChanges[sessionID] = summary
        }

        for sessionID in sessionIDsWithGitRoots where refreshedChanges[sessionID] == nil {
            updatedChanges.removeValue(forKey: sessionID)
        }

        sessionGitChanges = updatedChanges
        gitRefreshTask = nil
    }

    nonisolated public static func unsupportedSessionFactory() -> () -> TerminalSession {
        {
            fatalError("Mvx requires an explicit native terminal sessionFactory")
        }
    }

    nonisolated public static func unsupportedSessionFactoryWithStartupDirectory() -> (URL?) -> TerminalSession {
        { _ in
            fatalError("Mvx requires an explicit native terminal sessionFactory")
        }
    }

    private static func startupDirectoryURL(from workingDirectoryPath: String?) -> URL? {
        guard let normalized = workingDirectoryPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !normalized.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: normalized)
    }

    private func configureRuntime(_ runtime: TerminalSession, for sessionID: UUID) {
        _ = runtime.addAgentStatusObserver { [weak self] update in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                _ = self.updateAgentStatus(id: sessionID, status: update.status)
            }
        }

        _ = runtime.addRuntimeEventObserver { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                switch event {
                case .titleChanged(let title):
                    _ = self.updateSessionTerminalTitle(id: sessionID, title: title)
                case .contextChanged(let workingDirectoryPath, let foregroundProcessName):
                    let descriptor = self.descriptor(for: sessionID)
                    _ = self.updateSessionContext(
                        id: sessionID,
                        workingDirectoryPath: workingDirectoryPath ?? descriptor?.workingDirectoryPath,
                        foregroundProcessName: foregroundProcessName ?? descriptor?.foregroundProcessName
                    )
                case .childExited:
                    self.refreshVisibleState()
                case .splitRequested(let axis):
                    guard self.selectSession(id: sessionID) else {
                        return
                    }

                    _ = self.performAdaptiveSplit(axis)
                }
            }
        }

        _ = runtime.addActivityObserver { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshVisibleState()
            }
        }
    }

    private func updateDescriptor(
        id: UUID,
        _ transform: (inout SessionDescriptor) -> Void
    ) -> Bool? {
        guard let index = indexForSession(id: id) else {
            return nil
        }

        let original = sessions[index]
        var updated = original
        transform(&updated)
        guard updated != original else {
            return false
        }

        sessions[index] = updated
        return true
    }

    private func invalidateCachedWorkspaceMetadata() {
        cachedWorkspaceMetadata = nil
        isWorkspaceMetadataDirty = true
    }
}
