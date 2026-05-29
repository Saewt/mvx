import Foundation

public enum SessionNaming {
    public static func automaticTitle(
        terminalTitle: String? = nil,
        workingDirectoryPath: String?,
        foregroundProcessName: String?,
        fallbackOrdinal: Int
    ) -> String {
        if let terminal = normalizedValue(terminalTitle) {
            return displayTitle(fromTerminalTitle: terminal)
        }

        if let process = meaningfulProcessTitle(foregroundProcessName) {
            return process
        }

        if let directory = normalizedValue(workingDirectoryPath) {
            if directory == "/" {
                return directory
            }

            let component = URL(fileURLWithPath: directory).lastPathComponent
            if !component.isEmpty {
                return component
            }

            return directory
        }

        if let process = processTitle(foregroundProcessName) {
            return process
        }

        return "Session \(max(fallbackOrdinal, 1))"
    }

    public static func normalizedCustomTitle(_ title: String?) -> String? {
        normalizedValue(title)
    }

    private static func normalizedValue(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }

    private static func meaningfulProcessTitle(_ processName: String?) -> String? {
        guard let process = processTitle(processName),
              !shellProcessNames.contains(process.lowercased()) else {
            return nil
        }

        return process
    }

    private static func processTitle(_ processName: String?) -> String? {
        guard let process = normalizedValue(processName) else {
            return nil
        }

        let component = URL(fileURLWithPath: process).lastPathComponent
        return component.isEmpty ? process : component
    }

    private static func displayTitle(fromTerminalTitle title: String) -> String {
        guard title.contains("/") else {
            return title
        }

        let normalized = title.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !normalized.isEmpty else {
            return title
        }

        let component = normalized.split(separator: "/").last.map(String.init)
        return component?.isEmpty == false ? component! : title
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
