import Foundation

public enum WorkspaceReviewState: String, Codable, Equatable, Hashable, CaseIterable {
    case none
    case active
    case reviewRequested
    case blocked
    case ready

    public var label: String {
        switch self {
        case .none:
            return "No Review State"
        case .active:
            return "Active"
        case .reviewRequested:
            return "Needs Review"
        case .blocked:
            return "Blocked"
        case .ready:
            return "Ready"
        }
    }
}

public struct WorkspaceGitChangeSummary: Equatable, Hashable {
    public var addedCount: Int
    public var removedCount: Int

    public init(addedCount: Int = 0, removedCount: Int = 0) {
        self.addedCount = max(addedCount, 0)
        self.removedCount = max(removedCount, 0)
    }
}

public struct WorkspaceMetadataSnapshot: Codable, Equatable, Hashable {
    public var branchName: String
    public var reviewState: WorkspaceReviewState
    public var notificationCount: Int
    public var waitingCount: Int
    public var errorCount: Int
    public var paneCount: Int

    public init(
        branchName: String = "No Branch",
        reviewState: WorkspaceReviewState = .none,
        notificationCount: Int = 0,
        waitingCount: Int = 0,
        errorCount: Int = 0,
        paneCount: Int = 0
    ) {
        self.branchName = branchName
        self.reviewState = reviewState
        self.notificationCount = max(notificationCount, 0)
        self.waitingCount = max(waitingCount, 0)
        self.errorCount = max(errorCount, 0)
        self.paneCount = max(paneCount, 0)
    }

    public var summaryLine: String {
        "\(branchName)  •  \(reviewState.label)  •  \(notificationCount) alerts"
    }

    @MainActor
    public static func resolve(workspace: SessionWorkspace) -> WorkspaceMetadataSnapshot {
        let descriptorsByID = Dictionary(uniqueKeysWithValues: workspace.sessions.map { ($0.id, $0) })
        let relevantDescriptors = workspace.workspaceGraph.leafSessionIDs.compactMap { sessionID in
            descriptorsByID[sessionID]
        }

        let scopedDescriptors = workspace.sessions(inGroup: workspace.activeGroupID)
        let descriptors = relevantDescriptors.isEmpty ? scopedDescriptors : relevantDescriptors
        let statuses = descriptors.map(\.agentStatus)

        let errorCount = statuses.filter { $0 == .error }.count
        let waitingCount = statuses.filter { $0 == .waiting }.count
        let doneCount = statuses.filter { $0 == .done }.count

        let reviewState: WorkspaceReviewState
        if errorCount > 0 {
            reviewState = .blocked
        } else if waitingCount > 0 {
            reviewState = .reviewRequested
        } else if doneCount > 0 {
            reviewState = .ready
        } else if descriptors.isEmpty {
            reviewState = .none
        } else {
            reviewState = .active
        }

        let branchName = resolvedBranchName(from: descriptors) ?? "No Branch"
        return WorkspaceMetadataSnapshot(
            branchName: branchName,
            reviewState: reviewState,
            notificationCount: waitingCount + errorCount,
            waitingCount: waitingCount,
            errorCount: errorCount,
            paneCount: descriptors.isEmpty ? 0 : max(workspace.workspaceGraph.paneCount, 1)
        )
    }

    @MainActor
    public static func focusedGitChangeSummary(in workspace: SessionWorkspace) -> WorkspaceGitChangeSummary? {
        guard let descriptor = focusedDescriptor(in: workspace),
              let workingDirectoryPath = descriptor.workingDirectoryPath else {
            return nil
        }

        return gitWorkingTreeDelta(workingDirectory: workingDirectoryPath)
    }

    @MainActor
    static func focusedDescriptor(in workspace: SessionWorkspace) -> SessionDescriptor? {
        if let focusedSessionID = workspace.workspaceGraph.focusedSessionID,
           let descriptor = workspace.descriptor(for: focusedSessionID) {
            return descriptor
        }

        return workspace.activeDescriptor
    }

    private static func resolvedBranchName(from descriptors: [SessionDescriptor]) -> String? {
        for descriptor in descriptors {
            if let workingDir = descriptor.workingDirectoryPath {
                if let branch = gitBranchFromHead(workingDirectory: workingDir) {
                    return branch
                }
            }
        }

        for descriptor in descriptors {
            if let branch = branchNameHeuristic(from: descriptor.workingDirectoryPath) {
                return branch
            }
        }

        return nil
    }

    static func gitBranchFromHead(workingDirectory: String) -> String? {
        guard let gitRoot = gitRoot(for: workingDirectory) else {
            return nil
        }

        let gitHeadPath = (gitRoot as NSString).appendingPathComponent(".git/HEAD")
        guard let headContents = try? String(contentsOfFile: gitHeadPath, encoding: .utf8) else {
            return nil
        }

        return parseBranchFromHead(headContents)
    }

    static func gitRoot(for workingDirectory: String) -> String? {
        let normalized = workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return nil
        }

        let fileManager = FileManager.default
        var candidate = URL(fileURLWithPath: normalized, isDirectory: true).standardizedFileURL.path

        while true {
            let gitPath = (candidate as NSString).appendingPathComponent(".git")
            if fileManager.fileExists(atPath: gitPath) {
                return candidate
            }

            let parent = (candidate as NSString).deletingLastPathComponent
            if parent.isEmpty || parent == candidate {
                return nil
            }

            candidate = parent
        }
    }

    static func gitWorkingTreeDelta(workingDirectory: String) -> WorkspaceGitChangeSummary? {
        guard let gitRoot = gitRoot(for: workingDirectory) else {
            return nil
        }

        let process = Process()
        let stdout = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = [
            "-C",
            gitRoot,
            "status",
            "--porcelain",
            "--untracked-files=all",
        ]
        process.standardOutput = stdout

        do {
            try process.run()
        } catch {
            return nil
        }

        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return nil
        }

        guard let rawOutput = String(data: output, encoding: .utf8) else {
            return nil
        }

        return parseGitStatusPorcelain(rawOutput)
    }

    static func parseGitStatusPorcelain(_ output: String) -> WorkspaceGitChangeSummary {
        var addedCount = 0
        var removedCount = 0

        for line in output.split(whereSeparator: \.isNewline) {
            let status = String(line.prefix(2))
            guard status.count == 2 else {
                continue
            }

            if status == "!!" {
                continue
            }

            if status == "??" {
                addedCount += 1
                continue
            }

            let codes = Set(status)
            if codes.contains("R") || codes.contains("M") {
                addedCount += 1
                removedCount += 1
                continue
            }

            if codes.contains("A") || codes.contains("C") {
                addedCount += 1
            }

            if codes.contains("D") {
                removedCount += 1
            }
        }

        return WorkspaceGitChangeSummary(
            addedCount: addedCount,
            removedCount: removedCount
        )
    }

    private static func parseBranchFromHead(_ contents: String) -> String? {
        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        let refPrefix = "ref: refs/heads/"
        guard trimmed.hasPrefix(refPrefix) else {
            let shortHash = String(trimmed.prefix(8))
            return shortHash.isEmpty ? nil : shortHash
        }

        return String(trimmed.dropFirst(refPrefix.count))
    }

    private static func branchNameHeuristic(from workingDirectoryPath: String?) -> String? {
        guard let workingDirectoryPath else {
            return nil
        }

        let normalized = workingDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return nil
        }

        let components = normalized.split(separator: "/").map(String.init)
        guard let last = components.last else {
            return nil
        }

        if last == "main" || last == "master" {
            return last
        }

        guard components.count >= 2 else {
            return last
        }

        return "\(components[components.count - 2])/\(last)"
    }
}
