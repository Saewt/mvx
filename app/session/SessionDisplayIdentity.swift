import Foundation

public struct SessionDisplayIdentity: Equatable {
    public let title: String
    public let contextLine: String?
}

public enum SessionDisplayIdentityResolver {
    public static func resolve(
        descriptor: SessionDescriptor,
        visibleDescriptors: [SessionDescriptor],
        branchName: String? = nil,
        gitChangeSummary: WorkspaceGitChangeSummary? = nil
    ) -> SessionDisplayIdentity {
        let title = resolvedTitles(for: visibleDescriptors)[descriptor.id] ?? descriptor.displayTitle
        let contextLine = contextLine(
            for: descriptor,
            branchName: branchName,
            gitChangeSummary: gitChangeSummary
        )

        return SessionDisplayIdentity(title: title, contextLine: contextLine)
    }

    public static func resolvedTitles(for descriptors: [SessionDescriptor]) -> [UUID: String] {
        let titleCounts = descriptors.reduce(into: [String: Int]()) { counts, descriptor in
            counts[descriptor.displayTitle, default: 0] += 1
        }

        let groupedDescriptors = Dictionary(grouping: descriptors, by: \.displayTitle)
        var titles: [UUID: String] = [:]

        for descriptor in descriptors {
            guard (titleCounts[descriptor.displayTitle] ?? 0) > 1,
                  let duplicates = groupedDescriptors[descriptor.displayTitle] else {
                titles[descriptor.id] = descriptor.displayTitle
                continue
            }

            titles[descriptor.id] = disambiguatedTitle(for: descriptor, among: duplicates)
        }

        return titles
    }

    public static func contextLine(
        for descriptor: SessionDescriptor,
        branchName: String? = nil,
        gitChangeSummary: WorkspaceGitChangeSummary? = nil
    ) -> String? {
        var parts: [String] = []

        if let repositoryName = repositoryName(for: descriptor.workingDirectoryPath),
           repositoryName != descriptor.displayTitle {
            parts.append(repositoryName)
        }

        if let branchName = normalizedValue(branchName), branchName != "No Branch" {
            parts.append(branchName)
        }

        if let gitChangeSummary {
            parts.append("+\(gitChangeSummary.addedCount) -\(gitChangeSummary.removedCount)")
        }

        if let process = processName(for: descriptor.foregroundProcessName),
           !shellProcessNames.contains(process.lowercased()),
           process != descriptor.displayTitle,
           !parts.contains(process) {
            parts.append(process)
        }

        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }

    public static func processName(for foregroundProcessName: String?) -> String? {
        guard let process = normalizedValue(foregroundProcessName) else {
            return nil
        }

        let component = URL(fileURLWithPath: process).lastPathComponent
        return component.isEmpty ? process : component
    }

    public static func repositoryName(for workingDirectoryPath: String?) -> String? {
        guard let workingDirectoryPath = normalizedValue(workingDirectoryPath) else {
            return nil
        }

        if workingDirectoryPath == "/" {
            return workingDirectoryPath
        }

        let component = URL(fileURLWithPath: workingDirectoryPath).lastPathComponent
        return component.isEmpty ? workingDirectoryPath : component
    }

    private static func disambiguatedTitle(
        for descriptor: SessionDescriptor,
        among duplicates: [SessionDescriptor]
    ) -> String {
        if let branch = uniqueDifferentiator(
            for: descriptor,
            among: duplicates,
            value: { branchHeuristic(from: $0.workingDirectoryPath) }
        ) {
            return "\(descriptor.displayTitle) · \(branch)"
        }

        if let process = uniqueDifferentiator(
            for: descriptor,
            among: duplicates,
            value: { processName(for: $0.foregroundProcessName) }
        ) {
            return "\(descriptor.displayTitle) · \(process)"
        }

        let rankedDuplicates = duplicates.sorted {
            if $0.ordinal == $1.ordinal {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.ordinal < $1.ordinal
        }
        let rank = (rankedDuplicates.firstIndex(where: { $0.id == descriptor.id }) ?? 0) + 1
        guard rank > 1 else {
            return descriptor.displayTitle
        }

        return "\(descriptor.displayTitle) \(rank)"
    }

    private static func uniqueDifferentiator(
        for descriptor: SessionDescriptor,
        among duplicates: [SessionDescriptor],
        value: (SessionDescriptor) -> String?
    ) -> String? {
        guard let descriptorValue = value(descriptor),
              descriptorValue != descriptor.displayTitle else {
            return nil
        }

        let values = duplicates.compactMap(value)
        guard Set(values).count > 1 else {
            return nil
        }

        return descriptorValue
    }

    private static func branchHeuristic(from workingDirectoryPath: String?) -> String? {
        guard let workingDirectoryPath = normalizedValue(workingDirectoryPath) else {
            return nil
        }

        let components = workingDirectoryPath.split(separator: "/").map(String.init)
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

    private static func normalizedValue(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }

    private static let shellProcessNames: Set<String> = [
        "bash",
        "fish",
        "login",
        "sh",
        "tcsh",
        "zsh",
    ]
}
