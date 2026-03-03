import Foundation

public enum SessionNaming {
    public static func automaticTitle(
        terminalTitle: String? = nil,
        workingDirectoryPath: String?,
        foregroundProcessName: String?,
        fallbackOrdinal: Int
    ) -> String {
        if let terminal = normalizedValue(terminalTitle) {
            return terminal
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

        if let process = normalizedValue(foregroundProcessName) {
            let component = URL(fileURLWithPath: process).lastPathComponent
            return component.isEmpty ? process : component
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
}
