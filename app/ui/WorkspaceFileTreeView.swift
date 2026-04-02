import AppKit
import Foundation
import SwiftUI

enum WorkspaceFileTreeAction {
    case copyPath(URL)
    case copyRelativePath(URL)
    case revealInFinder(URL)
    case cdToDirectory(URL)
}

enum WorkspaceFileTreeEmptyState: Equatable, Sendable {
    case empty
    case filtered
}

struct WorkspaceFileTreeLoadResult: Equatable, Sendable {
    let nodes: [WorkspaceFileTreeNode]
    let emptyState: WorkspaceFileTreeEmptyState
}

struct WorkspaceFileTreeNode: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case directory
        case file
        case placeholder
    }

    let id: String
    let name: String
    let url: URL?
    let kind: Kind
    let isExpandable: Bool
    var isExpanded: Bool
    var isLoadingChildren: Bool
    var children: [WorkspaceFileTreeNode]?
    var childEmptyState: WorkspaceFileTreeEmptyState?

    static func directory(url: URL, name: String? = nil) -> WorkspaceFileTreeNode {
        WorkspaceFileTreeNode(
            id: url.standardizedFileURL.path,
            name: name ?? displayName(for: url),
            url: url.standardizedFileURL,
            kind: .directory,
            isExpandable: true,
            isExpanded: false,
            isLoadingChildren: false,
            children: nil,
            childEmptyState: nil
        )
    }

    static func file(url: URL, name: String? = nil) -> WorkspaceFileTreeNode {
        WorkspaceFileTreeNode(
            id: url.standardizedFileURL.path,
            name: name ?? displayName(for: url),
            url: url.standardizedFileURL,
            kind: .file,
            isExpandable: false,
            isExpanded: false,
            isLoadingChildren: false,
            children: nil,
            childEmptyState: nil
        )
    }

    static func placeholder(id: String, message: String) -> WorkspaceFileTreeNode {
        WorkspaceFileTreeNode(
            id: id,
            name: message,
            url: nil,
            kind: .placeholder,
            isExpandable: false,
            isExpanded: false,
            isLoadingChildren: false,
            children: nil,
            childEmptyState: nil
        )
    }

    private static func displayName(for url: URL) -> String {
        let standardized = url.standardizedFileURL
        return standardized.lastPathComponent.isEmpty ? standardized.path : standardized.lastPathComponent
    }
}

enum WorkspaceFileTreePathResolver {
    static func relativePath(for url: URL, rootURL: URL) -> String? {
        relativePath(
            for: url,
            rootURL: rootURL,
            volumeIsCaseSensitive: volumeSupportsCaseSensitiveNames(at: rootURL)
        )
    }

    static func relativePath(
        for url: URL,
        rootURL: URL,
        volumeIsCaseSensitive: Bool
    ) -> String? {
        let path = url.standardizedFileURL.path
        let rootPath = rootURL.standardizedFileURL.path
        let options: String.CompareOptions = volumeIsCaseSensitive ? [] : [.caseInsensitive]

        if path.compare(rootPath, options: options) == .orderedSame {
            return "."
        }

        let rootPrefix = rootPath + "/"
        guard path.range(of: rootPrefix, options: options.union(.anchored)) != nil else {
            return nil
        }

        return String(path.dropFirst(rootPrefix.count))
    }

    static func volumeSupportsCaseSensitiveNames(at rootURL: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.volumeSupportsCaseSensitiveNamesKey]
        let values = try? rootURL.resourceValues(forKeys: keys)
        return values?.volumeSupportsCaseSensitiveNames ?? true
    }
}

struct WorkspaceFileTreeReader: Sendable {
    let rootResolver: @Sendable (String) -> URL?
    let directoryLoader: @Sendable (URL, URL) throws -> WorkspaceFileTreeLoadResult

    static let live = WorkspaceFileTreeReader(
        rootResolver: { workingDirectoryPath in
            let normalized = workingDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else {
                return nil
            }

            if let gitRoot = WorkspaceMetadataSnapshot.gitRoot(for: normalized) {
                return URL(fileURLWithPath: gitRoot, isDirectory: true).standardizedFileURL
            }

            return URL(fileURLWithPath: normalized, isDirectory: true).standardizedFileURL
        },
        directoryLoader: { rootURL, directoryURL in
            try loadDirectory(rootURL: rootURL, directoryURL: directoryURL)
        }
    )

    private static func loadDirectory(
        rootURL: URL,
        directoryURL: URL
    ) throws -> WorkspaceFileTreeLoadResult {
        let fileManager = FileManager.default
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isPackageKey,
            .isSymbolicLinkKey,
            .nameKey,
        ]
        let childURLs = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: []
        )
        let didFindRawEntries = !childURLs.isEmpty

        typealias ChildEntry = (
            url: URL,
            name: String,
            isDirectory: Bool,
            isPackage: Bool,
            isSymbolicLink: Bool
        )
        let childEntries: [ChildEntry] = try childURLs.compactMap { childURL in
            let values = try childURL.resourceValues(forKeys: keys)
            let name = values.name ?? childURL.lastPathComponent
            guard !isExcludedMetadataEntry(named: name) else {
                return nil
            }

            return (
                url: childURL.standardizedFileURL,
                name: name,
                isDirectory: values.isDirectory ?? false,
                isPackage: values.isPackage ?? false,
                isSymbolicLink: values.isSymbolicLink ?? false
            )
        }
        let volumeIsCaseSensitive = WorkspaceFileTreePathResolver.volumeSupportsCaseSensitiveNames(at: rootURL)
        let ignoredRelativePaths = gitIgnoredRelativePaths(
            childURLs: childEntries.map(\.url),
            rootURL: rootURL,
            volumeIsCaseSensitive: volumeIsCaseSensitive
        )

        let nodes = childEntries.compactMap { entry -> WorkspaceFileTreeNode? in
            guard let relativePath = WorkspaceFileTreePathResolver.relativePath(
                for: entry.url,
                rootURL: rootURL,
                volumeIsCaseSensitive: volumeIsCaseSensitive
            ),
                  !ignoredRelativePaths.contains(relativePath) else {
                return nil
            }

            if entry.isDirectory && !entry.isPackage && !entry.isSymbolicLink {
                return .directory(url: entry.url, name: entry.name)
            }

            return .file(url: entry.url, name: entry.name)
        }

        let emptyState: WorkspaceFileTreeEmptyState = (!didFindRawEntries || !nodes.isEmpty)
            ? .empty
            : .filtered

        return WorkspaceFileTreeLoadResult(
            nodes: sort(nodes: nodes),
            emptyState: emptyState
        )
    }

    private static func isExcludedMetadataEntry(named name: String) -> Bool {
        name == ".git" || name == ".DS_Store"
    }

    private static func gitIgnoredRelativePaths(
        childURLs: [URL],
        rootURL: URL,
        volumeIsCaseSensitive: Bool
    ) -> Set<String> {
        let relativePaths = childURLs.compactMap {
            WorkspaceFileTreePathResolver.relativePath(
                for: $0,
                rootURL: rootURL,
                volumeIsCaseSensitive: volumeIsCaseSensitive
            )
        }
        guard !relativePaths.isEmpty,
              FileManager.default.isExecutableFile(atPath: "/usr/bin/git") else {
            return []
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", rootURL.path, "check-ignore", "--stdin"]

        let standardOutput = Pipe()
        let standardInput = Pipe()
        process.standardOutput = standardOutput
        process.standardError = Pipe()
        process.standardInput = standardInput

        do {
            try process.run()

            let payload = relativePaths.joined(separator: "\n")
            if !payload.isEmpty {
                standardInput.fileHandleForWriting.write(Data(payload.utf8))
            }
            standardInput.fileHandleForWriting.closeFile()

            process.waitUntilExit()

            guard process.terminationStatus == 0 || process.terminationStatus == 1 else {
                return []
            }

            let output = standardOutput.fileHandleForReading.readDataToEndOfFile()
            guard let ignoredOutput = String(data: output, encoding: .utf8) else {
                return []
            }

            return Set(
                ignoredOutput
                    .split(whereSeparator: \.isNewline)
                    .map(String.init)
            )
        } catch {
            return []
        }
    }

    private static func sort(nodes: [WorkspaceFileTreeNode]) -> [WorkspaceFileTreeNode] {
        nodes.sorted { lhs, rhs in
            if lhs.isExpandable != rhs.isExpandable {
                return lhs.isExpandable && !rhs.isExpandable
            }

            let comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if comparison != .orderedSame {
                return comparison == .orderedAscending
            }

            return lhs.name < rhs.name
        }
    }
}

@MainActor
final class WorkspaceFileTreeController: ObservableObject {
    @Published private(set) var rootURL: URL?
    @Published private(set) var rootNodes: [WorkspaceFileTreeNode]
    @Published private(set) var isLoading = false
    @Published private(set) var rootEmptyState: WorkspaceFileTreeEmptyState = .empty
    @Published var isSectionExpanded = true

    private var workspace: SessionWorkspace
    private let reader: WorkspaceFileTreeReader
    private var rootLoadTask: Task<Void, Never>?
    private var childLoadTasks: [String: Task<Void, Never>] = [:]
    private var loadGeneration = 0

    init(
        workspace: SessionWorkspace,
        reader: WorkspaceFileTreeReader = .live
    ) {
        self.workspace = workspace
        self.reader = reader
        self.rootNodes = []
    }

    var rootDisplayName: String? {
        guard let rootURL else {
            return nil
        }

        return rootURL.lastPathComponent.isEmpty ? rootURL.path : rootURL.lastPathComponent
    }

    var rootPath: String? {
        rootURL?.path
    }

    var rootDisplayPath: String? {
        guard let rootPath else {
            return nil
        }

        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        guard rootPath == homePath || rootPath.hasPrefix(homePath + "/") else {
            return rootPath
        }

        if rootPath == homePath {
            return "~"
        }

        return "~" + rootPath.dropFirst(homePath.count)
    }

    func bind(to workspace: SessionWorkspace) {
        self.workspace = workspace
    }

    @discardableResult
    func syncFromWorkspace(forceRefresh: Bool = false) -> Task<Void, Never>? {
        let resolvedRootURL = workspace.activeDescriptor?.workingDirectoryPath.flatMap(reader.rootResolver)
        let standardizedRootURL = resolvedRootURL?.standardizedFileURL

        guard forceRefresh || standardizedRootURL != rootURL else {
            return nil
        }

        rootURL = standardizedRootURL
        rootNodes = []
        isLoading = false
        rootEmptyState = .empty
        cancelPendingLoads()

        guard let standardizedRootURL else {
            return nil
        }

        return loadRoot(at: standardizedRootURL)
    }

    @discardableResult
    func refresh() -> Task<Void, Never>? {
        syncFromWorkspace(forceRefresh: true)
    }

    @discardableResult
    func toggleExpansion(for nodeID: String) -> Task<Void, Never>? {
        guard let node = node(for: nodeID), node.isExpandable else {
            return nil
        }

        if node.isExpanded {
            childLoadTasks[nodeID]?.cancel()
            childLoadTasks.removeValue(forKey: nodeID)
            _ = updateNode(nodeID: nodeID) { node in
                node.isExpanded = false
                node.isLoadingChildren = false
                node.childEmptyState = nil
            }
            return nil
        }

        if node.children != nil {
            _ = updateNode(nodeID: nodeID) { node in
                node.isExpanded = true
            }
            return nil
        }

        _ = updateNode(nodeID: nodeID) { node in
            node.isExpanded = true
            node.isLoadingChildren = true
            node.childEmptyState = nil
        }

        return loadChildren(for: nodeID)
    }

    private func loadRoot(at rootURL: URL) -> Task<Void, Never> {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true

        let task = Task { [reader] in
            let result = await Task.detached(priority: .utility) {
                Result { try reader.directoryLoader(rootURL, rootURL) }
            }.value

            await MainActor.run {
                guard generation == self.loadGeneration,
                      self.rootURL == rootURL else {
                    return
                }

                self.isLoading = false
                switch result {
                case .success(let loadResult):
                    self.rootNodes = loadResult.nodes
                    self.rootEmptyState = loadResult.emptyState
                case .failure:
                    self.rootNodes = [
                        .placeholder(
                            id: "\(rootURL.path)#error",
                            message: "Unable to read this directory."
                        )
                    ]
                    self.rootEmptyState = .empty
                }

                self.rootLoadTask = nil
            }
        }

        rootLoadTask = task
        return task
    }

    private func loadChildren(for nodeID: String) -> Task<Void, Never>? {
        guard let node = node(for: nodeID),
              let url = node.url,
              let rootURL else {
            _ = updateNode(nodeID: nodeID) { node in
                node.isLoadingChildren = false
            }
            return nil
        }

        let task = Task { [reader] in
            let result = await Task.detached(priority: .utility) {
                Result { try reader.directoryLoader(rootURL, url) }
            }.value

            await MainActor.run {
                guard self.childLoadTasks[nodeID] != nil,
                      self.rootURL == rootURL else {
                    return
                }

                switch result {
                case .success(let loadResult):
                    _ = self.updateNode(nodeID: nodeID) { node in
                        node.children = loadResult.nodes
                        node.childEmptyState = loadResult.emptyState
                        node.isLoadingChildren = false
                    }
                case .failure:
                    _ = self.updateNode(nodeID: nodeID) { node in
                        node.children = [
                            .placeholder(
                                id: "\(nodeID)#error",
                            message: "Unable to read this directory."
                        )
                    ]
                    node.childEmptyState = nil
                    node.isLoadingChildren = false
                }
                }

                self.childLoadTasks.removeValue(forKey: nodeID)
            }
        }

        childLoadTasks[nodeID]?.cancel()
        childLoadTasks[nodeID] = task
        return task
    }

    private func cancelPendingLoads() {
        rootLoadTask?.cancel()
        rootLoadTask = nil

        for task in childLoadTasks.values {
            task.cancel()
        }
        childLoadTasks.removeAll()
    }

    private func node(for nodeID: String) -> WorkspaceFileTreeNode? {
        Self.findNode(in: rootNodes, nodeID: nodeID)
    }

    private static func findNode(
        in nodes: [WorkspaceFileTreeNode],
        nodeID: String
    ) -> WorkspaceFileTreeNode? {
        for node in nodes {
            if node.id == nodeID {
                return node
            }

            if let children = node.children,
               let match = findNode(in: children, nodeID: nodeID) {
                return match
            }
        }

        return nil
    }

    @discardableResult
    private func updateNode(
        nodeID: String,
        mutate: (inout WorkspaceFileTreeNode) -> Void
    ) -> Bool {
        Self.update(nodes: &rootNodes, nodeID: nodeID, mutate: mutate)
    }

    @discardableResult
    private static func update(
        nodes: inout [WorkspaceFileTreeNode],
        nodeID: String,
        mutate: (inout WorkspaceFileTreeNode) -> Void
    ) -> Bool {
        for index in nodes.indices {
            if nodes[index].id == nodeID {
                mutate(&nodes[index])
                return true
            }

            guard var children = nodes[index].children else {
                continue
            }

            if update(nodes: &children, nodeID: nodeID, mutate: mutate) {
                nodes[index].children = children
                return true
            }
        }

        return false
    }
}

@MainActor
struct WorkspaceFileTreeSectionView: View {
    @ObservedObject var controller: WorkspaceFileTreeController
    let workspace: SessionWorkspace

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if controller.isSectionExpanded {
                content
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .contextMenu {
            if controller.rootURL != nil {
                Button("Refresh") {
                    _ = controller.refresh()
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    controller.isSectionExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: controller.isSectionExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text("Files")
                        .font(.system(.headline, design: .rounded))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let rootDisplayName = controller.rootDisplayName,
           let rootDisplayPath = controller.rootDisplayPath {
            VStack(alignment: .leading, spacing: 2) {
                Text(rootDisplayName)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .lineLimit(1)

                Text(rootDisplayPath)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if controller.isLoading && controller.rootNodes.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)

                    Text("Loading files…")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            } else if controller.rootNodes.isEmpty {
                Text(rootEmptyMessage)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .italic()
                    .padding(.vertical, 6)
            } else {
                ScrollView {
                    WorkspaceFileTreeNodeList(
                        nodes: controller.rootNodes,
                        depth: 0,
                        onToggle: { nodeID in
                            _ = controller.toggleExpansion(for: nodeID)
                        },
                        onAction: handle,
                        onRefresh: {
                            _ = controller.refresh()
                        },
                        rootURL: controller.rootURL
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: min(320, max(120, CGFloat(controller.rootNodes.count) * 22)))
                .scrollIndicators(.never)
            }
        } else {
            Text("No working directory captured yet.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
        }
    }

    private var rootEmptyMessage: String {
        switch controller.rootEmptyState {
        case .empty:
            return "This directory is empty."
        case .filtered:
            return "No visible files. Hidden by .gitignore or sidebar filters."
        }
    }

    private func handle(_ action: WorkspaceFileTreeAction) {
        switch action {
        case .copyPath(let url):
            copyToPasteboard(url.path)
        case .copyRelativePath(let url):
            guard let rootURL = controller.rootURL,
                  let relativePath = WorkspaceFileTreePathResolver.relativePath(for: url, rootURL: rootURL) else {
                return
            }
            copyToPasteboard(relativePath)
        case .revealInFinder(let url):
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case .cdToDirectory(let url):
            workspace.sendInputToActiveSession("cd -- \(shellEscaped(url.path))", appendNewline: true)
        }
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func shellEscaped(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

private struct WorkspaceFileTreeNodeList: View {
    let nodes: [WorkspaceFileTreeNode]
    let depth: Int
    let onToggle: (String) -> Void
    let onAction: (WorkspaceFileTreeAction) -> Void
    let onRefresh: (() -> Void)?
    let rootURL: URL?

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 1) {
            ForEach(nodes) { node in
                WorkspaceFileTreeRow(
                    node: node,
                    depth: depth,
                    onToggle: onToggle,
                    onAction: onAction,
                    onRefresh: onRefresh,
                    rootURL: rootURL
                )

                if node.isExpanded {
                    if node.isLoadingChildren {
                        statusRow("Loading…", depth: depth + 1)
                    } else if let children = node.children {
                        if children.isEmpty {
                            statusRow(emptyMessage(for: node), depth: depth + 1)
                        } else {
                            WorkspaceFileTreeNodeList(
                                nodes: children,
                                depth: depth + 1,
                                onToggle: onToggle,
                                onAction: onAction,
                                onRefresh: onRefresh,
                                rootURL: rootURL
                            )
                        }
                    }
                }
            }
        }
    }

    private func statusRow(_ label: String, depth: Int) -> some View {
        Text(label)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.tertiary)
            .italic()
            .padding(.leading, CGFloat(depth) * 12 + 18)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func emptyMessage(for node: WorkspaceFileTreeNode) -> String {
        switch node.childEmptyState ?? .empty {
        case .empty:
            return "Empty folder"
        case .filtered:
            return "No visible files"
        }
    }
}

private struct WorkspaceFileTreeRow: View {
    private struct IconDescriptor {
        let symbolName: String
        let color: Color
    }

    let node: WorkspaceFileTreeNode
    let depth: Int
    let onToggle: (String) -> Void
    let onAction: (WorkspaceFileTreeAction) -> Void
    let onRefresh: (() -> Void)?
    let rootURL: URL?

    @State private var isHovered = false

    var body: some View {
        content
            .padding(.leading, CGFloat(depth) * 12)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(isHovered ? 0.06 : 0))
            )
            .contentShape(Rectangle())
            .onTapGesture {
                guard node.isExpandable else {
                    return
                }

                withAnimation(.easeInOut(duration: 0.16)) {
                    onToggle(node.id)
                }
            }
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) {
                    isHovered = hovering
                }
            }
            .contextMenu {
                contextMenuContent
            }
    }

    private var content: some View {
        let iconDescriptor = Self.iconDescriptor(for: node.url, kind: node.kind)

        return HStack(spacing: 5) {
            if node.isExpandable {
                Image(systemName: node.isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 8)
            }

            Image(systemName: iconDescriptor.symbolName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(iconDescriptor.color)
                .frame(width: 12)

            Text(node.name)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .italic(node.kind == .placeholder)

            if let childCount = folderChildCount {
                Text("\(childCount)")
                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, node.isExpandable ? 0 : 13)
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        if let url = node.url {
            Button("Copy Path") {
                onAction(.copyPath(url))
            }

            Button("Copy Relative Path") {
                onAction(.copyRelativePath(url))
            }
            .disabled(rootURL == nil)

            Button("Reveal in Finder") {
                onAction(.revealInFinder(url))
            }

            if node.kind == .directory {
                Button("Open in Terminal") {
                    onAction(.cdToDirectory(url))
                }
            }
        }

        if let onRefresh {
            if node.url != nil {
                Divider()
            }

            Button("Refresh") {
                onRefresh()
            }
        }
    }

    private var folderChildCount: Int? {
        guard node.kind == .directory,
              node.isExpanded,
              !node.isLoadingChildren,
              let children = node.children else {
            return nil
        }

        if children.count == 1, children.first?.kind == .placeholder {
            return nil
        }

        return children.count
    }

    private var textColor: Color {
        switch node.kind {
        case .placeholder:
            return .secondary.opacity(0.78)
        default:
            return .primary
        }
    }

    private static func iconDescriptor(
        for url: URL?,
        kind: WorkspaceFileTreeNode.Kind
    ) -> IconDescriptor {
        switch kind {
        case .directory:
            return IconDescriptor(
                symbolName: "folder.fill",
                color: Color(red: 0.88, green: 0.71, blue: 0.33)
            )
        case .placeholder:
            return IconDescriptor(
                symbolName: "exclamationmark.triangle.fill",
                color: .orange
            )
        case .file:
            let `extension` = url?.pathExtension.lowercased() ?? ""
            switch `extension` {
            case "swift":
                return IconDescriptor(symbolName: "swift", color: .orange.opacity(0.85))
            case "js", "jsx":
                return IconDescriptor(
                    symbolName: "doc.text",
                    color: Color(red: 0.92, green: 0.79, blue: 0.31).opacity(0.85)
                )
            case "ts", "tsx":
                return IconDescriptor(
                    symbolName: "doc.text",
                    color: Color(red: 0.31, green: 0.57, blue: 0.96).opacity(0.85)
                )
            case "json":
                return IconDescriptor(
                    symbolName: "curlybraces",
                    color: Color(red: 0.44, green: 0.70, blue: 0.98).opacity(0.85)
                )
            case "sh", "bash", "zsh", "fish":
                return IconDescriptor(symbolName: "terminal", color: .green.opacity(0.85))
            case "png", "jpg", "jpeg", "gif", "webp", "heic", "svg":
                return IconDescriptor(
                    symbolName: "photo",
                    color: Color(red: 0.54, green: 0.73, blue: 0.96).opacity(0.85)
                )
            case "md", "markdown":
                return IconDescriptor(
                    symbolName: "text.document",
                    color: Color(red: 0.61, green: 0.76, blue: 0.92).opacity(0.85)
                )
            case "html", "htm":
                return IconDescriptor(
                    symbolName: "chevron.left.forwardslash.chevron.right",
                    color: Color(red: 0.95, green: 0.55, blue: 0.31).opacity(0.85)
                )
            case "css", "scss", "sass":
                return IconDescriptor(
                    symbolName: "paintbrush",
                    color: Color(red: 0.48, green: 0.74, blue: 0.96).opacity(0.85)
                )
            case "zip", "gz", "tgz", "tar", "xz":
                return IconDescriptor(
                    symbolName: "doc.zipper",
                    color: Color(red: 0.73, green: 0.61, blue: 0.40).opacity(0.85)
                )
            case "lock":
                return IconDescriptor(symbolName: "lock.fill", color: .secondary.opacity(0.85))
            default:
                return IconDescriptor(symbolName: "doc", color: .secondary.opacity(0.85))
            }
        }
    }
}
