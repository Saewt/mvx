import XCTest
@testable import Mvx

@MainActor
final class WorkspaceFileTreeTests: XCTestCase {
    func testFileTreeUsesGitRootWhenActiveDirectoryIsNested() async throws {
        let rootDirectory = try makeTemporaryDirectory()
        let repositoryRoot = rootDirectory.appendingPathComponent("repo", isDirectory: true)
        let nestedDirectory = repositoryRoot
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("Feature", isDirectory: true)

        try FileManager.default.createDirectory(
            at: repositoryRoot.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
        try Data().write(to: repositoryRoot.appendingPathComponent("README.md"))

        let workspace = makeTestWorkspace(autoStartSessions: false)
        let sessionID = try XCTUnwrap(workspace.activeSessionID)
        XCTAssertTrue(workspace.updateSessionContext(
            id: sessionID,
            workingDirectoryPath: nestedDirectory.path,
            foregroundProcessName: "zsh"
        ))

        let controller = WorkspaceFileTreeController(workspace: workspace)
        await controller.syncFromWorkspace(forceRefresh: true)?.value

        XCTAssertEqual(controller.rootPath, repositoryRoot.path)
        XCTAssertEqual(controller.rootNodes.map(\.name), ["Sources", "README.md"])
    }

    func testFileTreeFallsBackToWorkingDirectoryAndSortsFoldersBeforeFiles() async throws {
        let rootDirectory = try makeTemporaryDirectory()
        let workspaceDirectory = rootDirectory.appendingPathComponent("workspace", isDirectory: true)
        let alphaDirectory = workspaceDirectory.appendingPathComponent("Alpha", isDirectory: true)
        let betaFile = workspaceDirectory.appendingPathComponent("beta.txt")
        let gammaFile = workspaceDirectory.appendingPathComponent("Gamma.txt")

        try FileManager.default.createDirectory(at: alphaDirectory, withIntermediateDirectories: true)
        try Data().write(to: betaFile)
        try Data().write(to: gammaFile)

        let workspace = makeTestWorkspace(autoStartSessions: false)
        let sessionID = try XCTUnwrap(workspace.activeSessionID)
        XCTAssertTrue(workspace.updateSessionContext(
            id: sessionID,
            workingDirectoryPath: workspaceDirectory.path,
            foregroundProcessName: "zsh"
        ))

        let controller = WorkspaceFileTreeController(workspace: workspace)
        await controller.syncFromWorkspace(forceRefresh: true)?.value

        XCTAssertEqual(controller.rootPath, workspaceDirectory.path)
        XCTAssertEqual(controller.rootEmptyState, .empty)
        XCTAssertEqual(controller.rootNodes.map(\.name), ["Alpha", "beta.txt", "Gamma.txt"])
    }

    func testFileTreeLoadsChildrenLazilyAndTreatsPackagesAsLeafRows() async throws {
        let rootDirectory = try makeTemporaryDirectory()
        let workspaceDirectory = rootDirectory.appendingPathComponent("workspace", isDirectory: true)
        let sourcesDirectory = workspaceDirectory.appendingPathComponent("Sources", isDirectory: true)
        let packageDirectory = workspaceDirectory.appendingPathComponent("Preview.app", isDirectory: true)
        let childFile = sourcesDirectory.appendingPathComponent("main.swift")

        try FileManager.default.createDirectory(at: sourcesDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: packageDirectory, withIntermediateDirectories: true)
        try Data().write(to: childFile)

        let workspace = makeTestWorkspace(autoStartSessions: false)
        let sessionID = try XCTUnwrap(workspace.activeSessionID)
        XCTAssertTrue(workspace.updateSessionContext(
            id: sessionID,
            workingDirectoryPath: workspaceDirectory.path,
            foregroundProcessName: "zsh"
        ))

        let controller = WorkspaceFileTreeController(workspace: workspace)
        await controller.syncFromWorkspace(forceRefresh: true)?.value

        let sourcesNode = try XCTUnwrap(controller.rootNodes.first(where: { $0.name == "Sources" }))
        let packageNode = try XCTUnwrap(controller.rootNodes.first(where: { $0.name == "Preview.app" }))

        XCTAssertNil(sourcesNode.children)
        XCTAssertTrue(sourcesNode.isExpandable)
        XCTAssertFalse(packageNode.isExpandable)

        await controller.toggleExpansion(for: sourcesNode.id)?.value

        let expandedSourcesNode = try XCTUnwrap(controller.rootNodes.first(where: { $0.id == sourcesNode.id }))
        XCTAssertTrue(expandedSourcesNode.isExpanded)
        XCTAssertEqual(expandedSourcesNode.children?.map(\.name), ["main.swift"])
        XCTAssertEqual(expandedSourcesNode.childEmptyState, .empty)
    }

    func testFileTreeExcludesDotGitDirectory() async throws {
        let rootDirectory = try makeTemporaryDirectory()
        let workspaceDirectory = rootDirectory.appendingPathComponent("workspace", isDirectory: true)

        try FileManager.default.createDirectory(
            at: workspaceDirectory.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data().write(to: workspaceDirectory.appendingPathComponent("README.md"))

        let workspace = makeTestWorkspace(autoStartSessions: false)
        let sessionID = try XCTUnwrap(workspace.activeSessionID)
        XCTAssertTrue(workspace.updateSessionContext(
            id: sessionID,
            workingDirectoryPath: workspaceDirectory.path,
            foregroundProcessName: "zsh"
        ))

        let controller = WorkspaceFileTreeController(workspace: workspace)
        await controller.syncFromWorkspace(forceRefresh: true)?.value

        XCTAssertFalse(controller.rootNodes.contains(where: { $0.name == ".git" }))
        XCTAssertEqual(controller.rootNodes.map(\.name), ["README.md"])
    }

    func testFileTreeExcludesDotStoreMetadataEntries() async throws {
        let rootDirectory = try makeTemporaryDirectory()
        let workspaceDirectory = rootDirectory.appendingPathComponent("workspace", isDirectory: true)

        try FileManager.default.createDirectory(at: workspaceDirectory, withIntermediateDirectories: true)
        try Data().write(to: workspaceDirectory.appendingPathComponent(".DS_Store"))
        try Data().write(to: workspaceDirectory.appendingPathComponent("README.md"))

        let workspace = makeTestWorkspace(autoStartSessions: false)
        let sessionID = try XCTUnwrap(workspace.activeSessionID)
        XCTAssertTrue(workspace.updateSessionContext(
            id: sessionID,
            workingDirectoryPath: workspaceDirectory.path,
            foregroundProcessName: "zsh"
        ))

        let controller = WorkspaceFileTreeController(workspace: workspace)
        await controller.syncFromWorkspace(forceRefresh: true)?.value

        XCTAssertFalse(controller.rootNodes.contains(where: { $0.name == ".DS_Store" }))
        XCTAssertEqual(controller.rootNodes.map(\.name), ["README.md"])
    }

    func testFileTreeMarksDirectoryFilteredWhenOnlyMetadataEntriesRemain() async throws {
        let rootDirectory = try makeTemporaryDirectory()
        let workspaceDirectory = rootDirectory.appendingPathComponent("workspace", isDirectory: true)

        try FileManager.default.createDirectory(at: workspaceDirectory, withIntermediateDirectories: true)
        try Data().write(to: workspaceDirectory.appendingPathComponent(".DS_Store"))

        let workspace = makeTestWorkspace(autoStartSessions: false)
        let sessionID = try XCTUnwrap(workspace.activeSessionID)
        XCTAssertTrue(workspace.updateSessionContext(
            id: sessionID,
            workingDirectoryPath: workspaceDirectory.path,
            foregroundProcessName: "zsh"
        ))

        let controller = WorkspaceFileTreeController(workspace: workspace)
        await controller.syncFromWorkspace(forceRefresh: true)?.value

        XCTAssertTrue(controller.rootNodes.isEmpty)
        XCTAssertEqual(controller.rootEmptyState, .filtered)
    }

    func testFileTreeFiltersGitIgnoredPathsWhenRepositoryHasIgnoreRules() async throws {
        let repositoryRoot = try makeTemporaryDirectory()
        try runGit(in: repositoryRoot, arguments: ["init", "-q"])

        try "ignored.txt\nnode_modules/\n".write(
            to: repositoryRoot.appendingPathComponent(".gitignore"),
            atomically: true,
            encoding: .utf8
        )
        try Data().write(to: repositoryRoot.appendingPathComponent("README.md"))
        try Data().write(to: repositoryRoot.appendingPathComponent("ignored.txt"))
        let ignoredDirectory = repositoryRoot.appendingPathComponent("node_modules", isDirectory: true)
        try FileManager.default.createDirectory(at: ignoredDirectory, withIntermediateDirectories: true)
        try Data().write(to: ignoredDirectory.appendingPathComponent("package.json"))

        let workspace = makeTestWorkspace(autoStartSessions: false)
        let sessionID = try XCTUnwrap(workspace.activeSessionID)
        XCTAssertTrue(workspace.updateSessionContext(
            id: sessionID,
            workingDirectoryPath: repositoryRoot.path,
            foregroundProcessName: "zsh"
        ))

        let controller = WorkspaceFileTreeController(workspace: workspace)
        await controller.syncFromWorkspace(forceRefresh: true)?.value

        XCTAssertEqual(controller.rootNodes.map(\.name), [".gitignore", "README.md"])
        XCTAssertEqual(controller.rootEmptyState, .empty)
    }

    func testFileTreeMarksDirectoryFilteredWhenOnlyIgnoredEntriesRemain() async throws {
        let repositoryRoot = try makeTemporaryDirectory()
        try runGit(in: repositoryRoot, arguments: ["init", "-q"])

        try "ignored.txt\n".write(
            to: repositoryRoot
                .appendingPathComponent(".git", isDirectory: true)
                .appendingPathComponent("info", isDirectory: true)
                .appendingPathComponent("exclude"),
            atomically: true,
            encoding: .utf8
        )
        try Data().write(to: repositoryRoot.appendingPathComponent("ignored.txt"))

        let workspace = makeTestWorkspace(autoStartSessions: false)
        let sessionID = try XCTUnwrap(workspace.activeSessionID)
        XCTAssertTrue(workspace.updateSessionContext(
            id: sessionID,
            workingDirectoryPath: repositoryRoot.path,
            foregroundProcessName: "zsh"
        ))

        let controller = WorkspaceFileTreeController(workspace: workspace)
        await controller.syncFromWorkspace(forceRefresh: true)?.value

        XCTAssertTrue(controller.rootNodes.isEmpty)
        XCTAssertEqual(controller.rootEmptyState, .filtered)
    }

    func testFileTreeShowsPlaceholderWhenChildDirectoryReadFails() async throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let sessionID = try XCTUnwrap(workspace.activeSessionID)
        XCTAssertTrue(workspace.updateSessionContext(
            id: sessionID,
            workingDirectoryPath: "/tmp/project",
            foregroundProcessName: "zsh"
        ))

        let rootURL = URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        let childURL = rootURL.appendingPathComponent("Sources", isDirectory: true)
        let reader = WorkspaceFileTreeReader(
            rootResolver: { _ in rootURL },
            directoryLoader: { _, directoryURL in
                if directoryURL == rootURL {
                    return WorkspaceFileTreeLoadResult(
                        nodes: [.directory(url: childURL, name: "Sources")],
                        emptyState: .empty
                    )
                }

                struct LoadFailure: Error {}
                throw LoadFailure()
            }
        )

        let controller = WorkspaceFileTreeController(workspace: workspace, reader: reader)
        await controller.syncFromWorkspace(forceRefresh: true)?.value

        let sourcesNode = try XCTUnwrap(controller.rootNodes.first)
        await controller.toggleExpansion(for: sourcesNode.id)?.value

        let failedNode = try XCTUnwrap(controller.rootNodes.first)
        XCTAssertEqual(failedNode.children?.count, 1)
        XCTAssertEqual(failedNode.children?.first?.kind, .placeholder)
    }

    func testFileTreeMarksExpandedChildFolderFilteredWhenNoVisibleChildrenRemain() async throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let sessionID = try XCTUnwrap(workspace.activeSessionID)
        XCTAssertTrue(workspace.updateSessionContext(
            id: sessionID,
            workingDirectoryPath: "/tmp/project",
            foregroundProcessName: "zsh"
        ))

        let rootURL = URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        let childURL = rootURL.appendingPathComponent("Sources", isDirectory: true)
        let reader = WorkspaceFileTreeReader(
            rootResolver: { _ in rootURL },
            directoryLoader: { _, directoryURL in
                if directoryURL == rootURL {
                    return WorkspaceFileTreeLoadResult(
                        nodes: [.directory(url: childURL, name: "Sources")],
                        emptyState: .empty
                    )
                }

                return WorkspaceFileTreeLoadResult(
                    nodes: [],
                    emptyState: .filtered
                )
            }
        )

        let controller = WorkspaceFileTreeController(workspace: workspace, reader: reader)
        await controller.syncFromWorkspace(forceRefresh: true)?.value

        let sourcesNode = try XCTUnwrap(controller.rootNodes.first)
        await controller.toggleExpansion(for: sourcesNode.id)?.value

        let expandedSourcesNode = try XCTUnwrap(controller.rootNodes.first)
        XCTAssertEqual(expandedSourcesNode.children, [])
        XCTAssertEqual(expandedSourcesNode.childEmptyState, .filtered)
    }

    func testFileTreeMarksExpandedChildFolderEmptyWhenNoChildrenExist() async throws {
        let workspace = makeTestWorkspace(autoStartSessions: false)
        let sessionID = try XCTUnwrap(workspace.activeSessionID)
        XCTAssertTrue(workspace.updateSessionContext(
            id: sessionID,
            workingDirectoryPath: "/tmp/project",
            foregroundProcessName: "zsh"
        ))

        let rootURL = URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        let childURL = rootURL.appendingPathComponent("Sources", isDirectory: true)
        let reader = WorkspaceFileTreeReader(
            rootResolver: { _ in rootURL },
            directoryLoader: { _, directoryURL in
                if directoryURL == rootURL {
                    return WorkspaceFileTreeLoadResult(
                        nodes: [.directory(url: childURL, name: "Sources")],
                        emptyState: .empty
                    )
                }

                return WorkspaceFileTreeLoadResult(
                    nodes: [],
                    emptyState: .empty
                )
            }
        )

        let controller = WorkspaceFileTreeController(workspace: workspace, reader: reader)
        await controller.syncFromWorkspace(forceRefresh: true)?.value

        let sourcesNode = try XCTUnwrap(controller.rootNodes.first)
        await controller.toggleExpansion(for: sourcesNode.id)?.value

        let expandedSourcesNode = try XCTUnwrap(controller.rootNodes.first)
        XCTAssertEqual(expandedSourcesNode.children, [])
        XCTAssertEqual(expandedSourcesNode.childEmptyState, .empty)
    }

    func testFileTreeRootDisplayPathShortensHomeDirectoryPrefix() async throws {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let nestedDirectory = homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Developer", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let workspace = makeTestWorkspace(autoStartSessions: false)
        let sessionID = try XCTUnwrap(workspace.activeSessionID)
        XCTAssertTrue(workspace.updateSessionContext(
            id: sessionID,
            workingDirectoryPath: nestedDirectory.path,
            foregroundProcessName: "zsh"
        ))

        let reader = WorkspaceFileTreeReader(
            rootResolver: { _ in nestedDirectory },
            directoryLoader: { _, _ in
                WorkspaceFileTreeLoadResult(
                    nodes: [],
                    emptyState: .empty
                )
            }
        )

        let controller = WorkspaceFileTreeController(workspace: workspace, reader: reader)
        await controller.syncFromWorkspace(forceRefresh: true)?.value

        XCTAssertEqual(controller.rootPath, nestedDirectory.path)
        XCTAssertEqual(
            controller.rootDisplayPath,
            nestedDirectory.path.replacingOccurrences(
                of: homeDirectory.path,
                with: "~"
            )
        )
    }

    func testFileTreeLoadsVisibleEntriesWhenWorkingDirectoryPathUsesDifferentCasing() async throws {
        let rootDirectory = try makeTemporaryDirectory()
        try XCTSkipIf(
            isCaseSensitiveVolume(at: rootDirectory),
            "Requires a case-insensitive volume"
        )

        let workspaceDirectory = rootDirectory.appendingPathComponent("workspace", isDirectory: true)
        let sourcesDirectory = workspaceDirectory.appendingPathComponent("Sources", isDirectory: true)

        try FileManager.default.createDirectory(at: sourcesDirectory, withIntermediateDirectories: true)
        try Data().write(to: workspaceDirectory.appendingPathComponent("README.md"))

        let alternateCasedWorkspacePath = rootDirectory
            .appendingPathComponent("Workspace", isDirectory: true)
            .path
        XCTAssertNotEqual(alternateCasedWorkspacePath, workspaceDirectory.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: alternateCasedWorkspacePath))

        let workspace = makeTestWorkspace(autoStartSessions: false)
        let sessionID = try XCTUnwrap(workspace.activeSessionID)
        XCTAssertTrue(workspace.updateSessionContext(
            id: sessionID,
            workingDirectoryPath: alternateCasedWorkspacePath,
            foregroundProcessName: "zsh"
        ))

        let controller = WorkspaceFileTreeController(workspace: workspace)
        await controller.syncFromWorkspace(forceRefresh: true)?.value

        XCTAssertEqual(controller.rootNodes.map(\.name), ["Sources", "README.md"])
        XCTAssertEqual(controller.rootEmptyState, .empty)
    }

    func testPathResolverBuildsRelativePathWhenRootCasingDiffersFromChildPath() throws {
        let rootDirectory = try makeTemporaryDirectory()
        try XCTSkipIf(
            isCaseSensitiveVolume(at: rootDirectory),
            "Requires a case-insensitive volume"
        )

        let workspaceDirectory = rootDirectory.appendingPathComponent("workspace", isDirectory: true)
        let sourcesDirectory = workspaceDirectory.appendingPathComponent("Sources", isDirectory: true)
        let childFile = sourcesDirectory.appendingPathComponent("main.swift")

        try FileManager.default.createDirectory(at: sourcesDirectory, withIntermediateDirectories: true)
        try Data().write(to: childFile)

        let alternateRootURL = rootDirectory.appendingPathComponent("Workspace", isDirectory: true)

        XCTAssertEqual(
            WorkspaceFileTreePathResolver.relativePath(for: childFile, rootURL: alternateRootURL),
            "Sources/main.swift"
        )
    }

    func testFileTreeMarksTrueEmptyDirectoryAsEmpty() async throws {
        let rootDirectory = try makeTemporaryDirectory()
        let workspaceDirectory = rootDirectory.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceDirectory, withIntermediateDirectories: true)

        let workspace = makeTestWorkspace(autoStartSessions: false)
        let sessionID = try XCTUnwrap(workspace.activeSessionID)
        XCTAssertTrue(workspace.updateSessionContext(
            id: sessionID,
            workingDirectoryPath: workspaceDirectory.path,
            foregroundProcessName: "zsh"
        ))

        let controller = WorkspaceFileTreeController(workspace: workspace)
        await controller.syncFromWorkspace(forceRefresh: true)?.value

        XCTAssertTrue(controller.rootNodes.isEmpty)
        XCTAssertEqual(controller.rootEmptyState, .empty)
    }

    func testFileTreeRefreshesWhenActiveDirectoryChanges() async throws {
        let rootDirectory = try makeTemporaryDirectory()
        let firstDirectory = rootDirectory.appendingPathComponent("first", isDirectory: true)
        let secondDirectory = rootDirectory.appendingPathComponent("second", isDirectory: true)

        try FileManager.default.createDirectory(at: firstDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)

        let workspace = makeTestWorkspace(autoStartSessions: false)
        let sessionID = try XCTUnwrap(workspace.activeSessionID)
        let controller = WorkspaceFileTreeController(workspace: workspace)

        XCTAssertTrue(workspace.updateSessionContext(
            id: sessionID,
            workingDirectoryPath: firstDirectory.path,
            foregroundProcessName: "zsh"
        ))
        await controller.syncFromWorkspace(forceRefresh: true)?.value
        XCTAssertEqual(controller.rootPath, firstDirectory.path)

        XCTAssertTrue(workspace.updateSessionContext(
            id: sessionID,
            workingDirectoryPath: secondDirectory.path,
            foregroundProcessName: "zsh"
        ))
        await controller.syncFromWorkspace()?.value

        XCTAssertEqual(controller.rootPath, secondDirectory.path)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    private func runGit(in directory: URL, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "WorkspaceFileTreeTests",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "git \(arguments.joined(separator: " ")) failed"]
            )
        }
    }

    private func isCaseSensitiveVolume(at directory: URL) throws -> Bool {
        let values = try directory.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
        return values.volumeSupportsCaseSensitiveNames ?? true
    }
}
