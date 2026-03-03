import Foundation

public struct TerminalThemeColors: Codable, Equatable {
    public var foregroundHex: String
    public var backgroundHex: String
    public var cursorHex: String
    public var selectionHex: String

    public init(
        foregroundHex: String,
        backgroundHex: String,
        cursorHex: String,
        selectionHex: String
    ) {
        self.foregroundHex = Self.normalizedHex(foregroundHex, fallback: "#CDD6F4")
        self.backgroundHex = Self.normalizedHex(backgroundHex, fallback: "#1E1E2E")
        self.cursorHex = Self.normalizedHex(cursorHex, fallback: "#F5E0DC")
        self.selectionHex = Self.normalizedHex(selectionHex, fallback: "#45475A")
    }

    public func applying(overrides: [String: String]) -> TerminalThemeColors {
        TerminalThemeColors(
            foregroundHex: overrides["foreground"] ?? foregroundHex,
            backgroundHex: overrides["background"] ?? backgroundHex,
            cursorHex: overrides["cursor"] ?? cursorHex,
            selectionHex: overrides["selection"] ?? selectionHex
        )
    }

    private static func normalizedHex(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard trimmed.hasPrefix("#"), trimmed.count == 7 else {
            return fallback
        }

        let scalars = trimmed.dropFirst().unicodeScalars
        let isValid = scalars.allSatisfy { scalar in
            switch scalar.value {
            case 48...57, 65...70:
                return true
            default:
                return false
            }
        }

        return isValid ? trimmed : fallback
    }
}

public enum ThemePreset: String, Codable, CaseIterable {
    case catppuccin
    case dracula
    case solarized
    case nord

    public var displayName: String {
        switch self {
        case .catppuccin:
            return "Catppuccin"
        case .dracula:
            return "Dracula"
        case .solarized:
            return "Solarized"
        case .nord:
            return "Nord"
        }
    }

    public var colors: TerminalThemeColors {
        switch self {
        case .catppuccin:
            return TerminalThemeColors(
                foregroundHex: "#CDD6F4",
                backgroundHex: "#1E1E2E",
                cursorHex: "#F5E0DC",
                selectionHex: "#45475A"
            )
        case .dracula:
            return TerminalThemeColors(
                foregroundHex: "#F8F8F2",
                backgroundHex: "#282A36",
                cursorHex: "#F8F8F2",
                selectionHex: "#44475A"
            )
        case .solarized:
            return TerminalThemeColors(
                foregroundHex: "#839496",
                backgroundHex: "#002B36",
                cursorHex: "#93A1A1",
                selectionHex: "#073642"
            )
        case .nord:
            return TerminalThemeColors(
                foregroundHex: "#D8DEE9",
                backgroundHex: "#2E3440",
                cursorHex: "#ECEFF4",
                selectionHex: "#4C566A"
            )
        }
    }

    public static func resolve(named name: String?) -> ThemePreset? {
        let normalized = name?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")

        guard let normalized, !normalized.isEmpty else {
            return nil
        }

        return allCases.first { preset in
            preset.rawValue == normalized || preset.displayName.lowercased() == normalized
        }
    }
}
