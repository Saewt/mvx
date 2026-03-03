import Foundation

public enum WorkspaceSplitAxis: String, Codable, Equatable, Hashable, CaseIterable {
    case horizontal
    case vertical
}

public struct WorkspacePaneNode: Identifiable, Codable, Equatable, Hashable {
    public let id: UUID
    public private(set) var axis: WorkspaceSplitAxis?
    public private(set) var sessionID: UUID?
    public private(set) var children: [WorkspacePaneNode]
    public var splitRatio: CGFloat

    public init(id: UUID = UUID(), sessionID: UUID) {
        self.id = id
        self.axis = nil
        self.sessionID = sessionID
        self.children = []
        self.splitRatio = 0.5
    }

    public init(id: UUID = UUID(), axis: WorkspaceSplitAxis, children: [WorkspacePaneNode], splitRatio: CGFloat = 0.5) {
        self.id = id
        self.axis = axis
        self.sessionID = nil
        self.children = children
        self.splitRatio = max(0.1, min(splitRatio, 0.9))
    }

    enum CodingKeys: String, CodingKey {
        case id, axis, sessionID, children, splitRatio
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        axis = try container.decodeIfPresent(WorkspaceSplitAxis.self, forKey: .axis)
        sessionID = try container.decodeIfPresent(UUID.self, forKey: .sessionID)
        children = try container.decodeIfPresent([WorkspacePaneNode].self, forKey: .children) ?? []
        splitRatio = try container.decodeIfPresent(CGFloat.self, forKey: .splitRatio) ?? 0.5
    }

    public var isLeaf: Bool {
        sessionID != nil
    }

    public var leafPanes: [WorkspacePaneNode] {
        if isLeaf {
            return [self]
        }

        return children.flatMap(\.leafPanes)
    }

    public func pane(for paneID: UUID) -> WorkspacePaneNode? {
        if id == paneID {
            return self
        }

        for child in children {
            if let match = child.pane(for: paneID) {
                return match
            }
        }

        return nil
    }

    public func paneID(for sessionID: UUID) -> UUID? {
        if self.sessionID == sessionID {
            return id
        }

        for child in children {
            if let paneID = child.paneID(for: sessionID) {
                return paneID
            }
        }

        return nil
    }

    public func parentPaneID(of paneID: UUID) -> UUID? {
        for child in children {
            if child.id == paneID {
                return id
            }

            if let parentPaneID = child.parentPaneID(of: paneID) {
                return parentPaneID
            }
        }

        return nil
    }

    public func contains(sessionID: UUID) -> Bool {
        paneID(for: sessionID) != nil
    }

    public func replacingSession(in paneID: UUID, with sessionID: UUID) -> WorkspacePaneNode {
        if isLeaf {
            guard id == paneID else {
                return self
            }

            return WorkspacePaneNode(id: id, sessionID: sessionID)
        }

        var updatedChildren: [WorkspacePaneNode] = []
        updatedChildren.reserveCapacity(children.count)

        for child in children {
            updatedChildren.append(child.replacingSession(in: paneID, with: sessionID))
        }

        return WorkspacePaneNode(id: id, axis: axis ?? .horizontal, children: updatedChildren, splitRatio: splitRatio)
    }

    public func withSplitRatio(_ ratio: CGFloat) -> WorkspacePaneNode {
        var copy = self
        copy.splitRatio = max(0.1, min(ratio, 0.9))
        return copy
    }

    public func updatingSplitRatio(for targetID: UUID, ratio: CGFloat) -> WorkspacePaneNode? {
        if id == targetID {
            return withSplitRatio(ratio)
        }

        guard !isLeaf else { return nil }

        var found = false
        var updatedChildren: [WorkspacePaneNode] = []
        updatedChildren.reserveCapacity(children.count)

        for child in children {
            if let updated = child.updatingSplitRatio(for: targetID, ratio: ratio) {
                updatedChildren.append(updated)
                found = true
            } else {
                updatedChildren.append(child)
            }
        }

        guard found else { return nil }
        return WorkspacePaneNode(id: id, axis: axis ?? .horizontal, children: updatedChildren, splitRatio: splitRatio)
    }

    public func splittingLeaf(
        paneID: UUID,
        axis: WorkspaceSplitAxis,
        newSessionID: UUID
    ) -> (node: WorkspacePaneNode, insertedPaneID: UUID?) {
        splittingLeaf(
            paneID: paneID,
            axis: axis,
            newSessionID: newSessionID,
            insertion: .after
        )
    }

    public func splittingLeaf(
        paneID: UUID,
        axis: WorkspaceSplitAxis,
        newSessionID: UUID,
        insertion: WorkspaceSplitInsertion
    ) -> (node: WorkspacePaneNode, insertedPaneID: UUID?) {
        if isLeaf {
            guard id == paneID, let existingSessionID = sessionID else {
                return (self, nil)
            }

            let currentLeaf = WorkspacePaneNode(id: id, sessionID: existingSessionID)
            let newLeaf = WorkspacePaneNode(sessionID: newSessionID)
            let orderedChildren = insertion == .before
                ? [newLeaf, currentLeaf]
                : [currentLeaf, newLeaf]
            return (
                WorkspacePaneNode(axis: axis, children: orderedChildren),
                newLeaf.id
            )
        }

        var insertedPaneID: UUID?
        var updatedChildren: [WorkspacePaneNode] = []
        updatedChildren.reserveCapacity(children.count)

        for child in children {
            let result = child.splittingLeaf(
                paneID: paneID,
                axis: axis,
                newSessionID: newSessionID,
                insertion: insertion
            )
            updatedChildren.append(result.node)
            insertedPaneID = insertedPaneID ?? result.insertedPaneID
        }

        return (
            WorkspacePaneNode(id: id, axis: self.axis ?? axis, children: updatedChildren, splitRatio: splitRatio),
            insertedPaneID
        )
    }

    public func removingLeaf(paneID: UUID) -> WorkspacePaneNode? {
        if isLeaf {
            return id == paneID ? nil : self
        }

        let updatedChildren = children.compactMap { $0.removingLeaf(paneID: paneID) }
        switch updatedChildren.count {
        case 0:
            return nil
        case 1:
            return updatedChildren[0]
        default:
            return WorkspacePaneNode(id: id, axis: axis ?? .horizontal, children: updatedChildren, splitRatio: splitRatio)
        }
    }

    public func swappingLeafSessions(
        firstPaneID: UUID,
        secondPaneID: UUID,
        firstSessionID: UUID,
        secondSessionID: UUID
    ) -> WorkspacePaneNode {
        if isLeaf {
            if id == firstPaneID {
                return WorkspacePaneNode(id: id, sessionID: secondSessionID)
            }

            if id == secondPaneID {
                return WorkspacePaneNode(id: id, sessionID: firstSessionID)
            }

            return self
        }

        let updatedChildren = children.map {
            $0.swappingLeafSessions(
                firstPaneID: firstPaneID,
                secondPaneID: secondPaneID,
                firstSessionID: firstSessionID,
                secondSessionID: secondSessionID
            )
        }

        return WorkspacePaneNode(
            id: id,
            axis: axis ?? .horizontal,
            children: updatedChildren,
            splitRatio: splitRatio
        )
    }
}

public struct WorkspaceGraph: Codable, Equatable, Hashable {
    public var windowID: UUID
    public var workspaceID: UUID
    public var rootPane: WorkspacePaneNode?
    public var focusedPaneID: UUID?

    public init(
        windowID: UUID = UUID(),
        workspaceID: UUID = UUID(),
        rootPane: WorkspacePaneNode? = nil,
        focusedPaneID: UUID? = nil
    ) {
        self.windowID = windowID
        self.workspaceID = workspaceID
        self.rootPane = rootPane
        self.focusedPaneID = focusedPaneID
    }

    public static func single(sessionID: UUID) -> WorkspaceGraph {
        let rootPane = WorkspacePaneNode(sessionID: sessionID)
        return WorkspaceGraph(rootPane: rootPane, focusedPaneID: rootPane.id)
    }

    public var leafPanes: [WorkspacePaneNode] {
        rootPane?.leafPanes ?? []
    }

    public var leafSessionIDs: [UUID] {
        leafPanes.compactMap(\.sessionID)
    }

    public var paneCount: Int {
        leafPanes.count
    }

    public var focusedSessionID: UUID? {
        guard let focusedPaneID else {
            return leafPanes.first?.sessionID
        }

        return sessionID(for: focusedPaneID) ?? leafPanes.first?.sessionID
    }

    public func sessionID(for paneID: UUID) -> UUID? {
        rootPane?.pane(for: paneID)?.sessionID
    }

    public func paneID(for sessionID: UUID) -> UUID? {
        rootPane?.paneID(for: sessionID)
    }

    public mutating func ensureRoot(sessionID: UUID) {
        guard rootPane == nil else {
            return
        }

        let rootPane = WorkspacePaneNode(sessionID: sessionID)
        self.rootPane = rootPane
        focusedPaneID = rootPane.id
    }

    @discardableResult
    public mutating func focusPane(_ paneID: UUID) -> Bool {
        guard sessionID(for: paneID) != nil else {
            return false
        }

        focusedPaneID = paneID
        return true
    }

    @discardableResult
    public mutating func focusNextPane(reverse: Bool = false) -> Bool {
        let leaves = leafPanes
        guard !leaves.isEmpty else {
            return false
        }

        guard
            let focusedPaneID,
            let currentIndex = leaves.firstIndex(where: { $0.id == focusedPaneID })
        else {
            self.focusedPaneID = leaves.first?.id
            return self.focusedPaneID != nil
        }

        let step = reverse ? -1 : 1
        let nextIndex = (currentIndex + step + leaves.count) % leaves.count
        self.focusedPaneID = leaves[nextIndex].id
        return true
    }

    @discardableResult
    public mutating func assignFocusedPane(sessionID: UUID) -> Bool {
        guard let rootPane else {
            self = .single(sessionID: sessionID)
            return true
        }

        let targetPaneID = focusedPaneID ?? rootPane.leafPanes.first?.id
        guard let targetPaneID else {
            self = .single(sessionID: sessionID)
            return true
        }

        self.rootPane = rootPane.replacingSession(in: targetPaneID, with: sessionID)
        focusedPaneID = targetPaneID
        return true
    }

    @discardableResult
    public mutating func assign(sessionID: UUID, toPaneID targetPaneID: UUID) -> Bool {
        if let existingPaneID = paneID(for: sessionID), existingPaneID != targetPaneID {
            return false
        }

        guard let rootPane, self.sessionID(for: targetPaneID) != nil else {
            return false
        }

        self.rootPane = rootPane.replacingSession(in: targetPaneID, with: sessionID)
        focusedPaneID = targetPaneID
        return true
    }

    @discardableResult
    public mutating func splitPane(
        _ targetPaneID: UUID,
        axis: WorkspaceSplitAxis,
        newSessionID: UUID,
        insertion: WorkspaceSplitInsertion
    ) -> UUID? {
        guard let rootPane, sessionID(for: targetPaneID) != nil else {
            return nil
        }

        let result = rootPane.splittingLeaf(
            paneID: targetPaneID,
            axis: axis,
            newSessionID: newSessionID,
            insertion: insertion
        )
        guard let insertedPaneID = result.insertedPaneID else {
            return nil
        }

        self.rootPane = result.node
        focusedPaneID = insertedPaneID
        return insertedPaneID
    }

    @discardableResult
    public mutating func splitFocusedPane(axis: WorkspaceSplitAxis, newSessionID: UUID) -> Bool {
        guard let rootPane else {
            self = .single(sessionID: newSessionID)
            return true
        }

        let targetPaneID = focusedPaneID ?? rootPane.leafPanes.first?.id
        guard let targetPaneID else {
            return false
        }

        return splitPane(
            targetPaneID,
            axis: axis,
            newSessionID: newSessionID,
            insertion: .after
        ) != nil
    }

    @discardableResult
    public mutating func removeFocusedPane() -> UUID? {
        guard
            paneCount > 1,
            let rootPane,
            let targetPaneID = focusedPaneID ?? rootPane.leafPanes.first?.id
        else {
            return nil
        }

        let leaves = rootPane.leafPanes
        guard let currentIndex = leaves.firstIndex(where: { $0.id == targetPaneID }) else {
            return nil
        }

        let removedSessionID = leaves[currentIndex].sessionID
        self.rootPane = rootPane.removingLeaf(paneID: targetPaneID)

        let remainingLeaves = self.rootPane?.leafPanes ?? []
        if remainingLeaves.isEmpty {
            focusedPaneID = nil
        } else {
            let replacementIndex = min(currentIndex, remainingLeaves.count - 1)
            focusedPaneID = remainingLeaves[replacementIndex].id
        }

        return removedSessionID
    }

    @discardableResult
    public mutating func resizeSplit(branchPaneID: UUID, ratio: CGFloat) -> Bool {
        guard let rootPane else { return false }
        guard let updated = rootPane.updatingSplitRatio(for: branchPaneID, ratio: ratio) else {
            return false
        }
        self.rootPane = updated
        return true
    }

    @discardableResult
    public mutating func swapLeafPanes(_ lhsPaneID: UUID, _ rhsPaneID: UUID) -> Bool {
        guard lhsPaneID != rhsPaneID,
              let rootPane,
              let lhsSessionID = sessionID(for: lhsPaneID),
              let rhsSessionID = sessionID(for: rhsPaneID) else {
            return false
        }

        self.rootPane = rootPane.swappingLeafSessions(
            firstPaneID: lhsPaneID,
            secondPaneID: rhsPaneID,
            firstSessionID: lhsSessionID,
            secondSessionID: rhsSessionID
        )
        focusedPaneID = rhsPaneID
        return true
    }

    @discardableResult
    public mutating func moveLeafPane(
        _ sourcePaneID: UUID,
        beside targetPaneID: UUID,
        axis: WorkspaceSplitAxis,
        insertion: WorkspaceSplitInsertion
    ) -> Bool {
        guard sourcePaneID != targetPaneID,
              let rootPane,
              let sourceSessionID = sessionID(for: sourcePaneID),
              sessionID(for: targetPaneID) != nil else {
            return false
        }

        guard let prunedRoot = rootPane.removingLeaf(paneID: sourcePaneID) else {
            return false
        }

        let result = prunedRoot.splittingLeaf(
            paneID: targetPaneID,
            axis: axis,
            newSessionID: sourceSessionID,
            insertion: insertion
        )
        guard let insertedPaneID = result.insertedPaneID else {
            return false
        }

        self.rootPane = result.node
        focusedPaneID = insertedPaneID
        return true
    }

    @discardableResult
    public mutating func detach(sessionID: UUID) -> Bool {
        guard let paneID = paneID(for: sessionID) else {
            return false
        }

        let leafCount = paneCount
        if leafCount <= 1 {
            rootPane = nil
            focusedPaneID = nil
            return true
        }

        guard let updatedRoot = rootPane?.removingLeaf(paneID: paneID) else {
            return false
        }

        rootPane = updatedRoot
        if focusedPaneID == paneID {
            focusedPaneID = updatedRoot.leafPanes.first?.id
        }

        return true
    }
}
