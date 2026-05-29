import SwiftUI

// MARK: - MvxSurface (Backgrounds & Overlays)

public enum MvxSurface {
    // #121316
    public static let base = Color(red: 0.071, green: 0.075, blue: 0.086)
    // #17191E
    public static let sidebar = Color(red: 0.090, green: 0.098, blue: 0.118)
    // #1B1E24
    public static let toolbar = Color(red: 0.106, green: 0.118, blue: 0.141)
    // #202329
    public static let raised = Color(red: 0.125, green: 0.137, blue: 0.161)
    // #24272E
    public static let overlay = Color(red: 0.141, green: 0.153, blue: 0.180)

    // white @ 0.08
    public static let hairline = Color.white.opacity(0.08)
    // white @ 0.12
    public static let hairlineStrong = Color.white.opacity(0.12)
    // white @ 0.04
    public static let cardTint = Color.white.opacity(0.04)
    // white @ 0.06
    public static let cardTintHover = Color.white.opacity(0.06)
    // accentColor @ 0.14
    public static var selectionTint: Color {
        Color.accentColor.opacity(0.14)
    }
    // accentColor @ 0.20
    public static var selectedRow: Color {
        Color.accentColor.opacity(0.20)
    }
}

// MARK: - MvxSpacing

public enum MvxSpacing {
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 24
}

// MARK: - MvxRadius

public enum MvxRadius {
    public static let control: CGFloat = 8
    public static let card: CGFloat = 12
    public static let container: CGFloat = 16
}

// MARK: - MvxMotion (Animation Presets)

public enum MvxMotion {
    public static let standard = Animation.easeInOut(duration: 0.18)
    public static let emphasized = Animation.spring(response: 0.32, dampingFraction: 0.82)
    public static let pulse = Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true)
}

// MARK: - MvxText

public enum MvxText {
    public static let sectionHeader = Font.system(size: 10.5, weight: .semibold, design: .rounded)
    public static let rowTitle = Font.system(size: 12.5, weight: .medium, design: .rounded)
    public static let rowContext = Font.system(size: 10.5, weight: .regular, design: .monospaced)
    public static let meta = Font.system(size: 9.5, weight: .regular, design: .rounded)
    public static let metaMono = Font.system(size: 9.5, weight: .medium, design: .monospaced)
    public static let cardTitle = Font.system(size: 12, weight: .semibold, design: .rounded)
    public static let wordmark = Font.system(size: 10.5, weight: .heavy, design: .monospaced)
}

// MARK: - MvxIcon

public enum MvxIcon {
    public static let statusDot: CGFloat = 8
    public static let glyph: CGFloat = 10.5
    public static let controlButtonSize: CGFloat = 22
    public static let controlSymbolSize: CGFloat = 11
    public static let paneHeaderButtonSize: CGFloat = 18
}

// MARK: - MvxLayout

public enum MvxLayout {
    public static let topChromeInset: CGFloat = 30
    public static let indicatorLane: CGFloat = 16
    public static let indicatorGap: CGFloat = 6
    public static let selectionBarWidth: CGFloat = 3

    public static var titleLeadingInset: CGFloat {
        MvxSpacing.md + indicatorLane + indicatorGap
    }
}

public enum MvxStatusStyle {
    /// Canonical agent status → color name (for use with color-name-based APIs).
    public static func colorName(for status: SessionAgentStatus) -> String? {
        switch status {
        case .none:
            return nil
        case .running:
            return "green"
        case .waiting:
            return "orange"
        case .done:
            return "teal"
        case .error:
            return "red"
        }
    }

    /// Direct mapping from SessionAgentStatus enum to Color.
    public static func color(for status: SessionAgentStatus) -> Color {
        switch status {
        case .none:
            return .clear
        case .running:
            return .green
        case .waiting:
            return .orange
        case .done:
            return .teal
        case .error:
            return .red
        }
    }

    public static func symbolName(for status: SessionAgentStatus) -> String? {
        switch status {
        case .none:
            return nil
        case .running:
            return "circle.fill"
        case .waiting:
            return "hourglass"
        case .done:
            return "checkmark"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    /// Resolves agent role color-name strings (used by the row).
    /// "green"/"orange"/"teal"/"red" map to themselves.
    /// "blue" maps to teal (legacy done compat).
    /// Everything else returns .secondary.
    public static func color(forLegacyAgentColorName name: String?) -> Color {
        guard let name else {
            return .secondary
        }
        switch name {
        case "green":
            return .green
        case "orange":
            return .orange
        case "teal":
            return .teal
        case "red":
            return .red
        case "blue":
            return .teal
        default:
            return .secondary
        }
    }

    /// Group color tags — blue stays blue.
    /// SessionGroupColor is a different domain than agent status; blue is never remapped here.
    public static func color(for groupColor: SessionGroupColor) -> Color {
        switch groupColor {
        case .blue:
            return .blue
        case .green:
            return .green
        case .orange:
            return .orange
        case .red:
            return .red
        case .purple:
            return .purple
        case .teal:
            return .teal
        }
    }
}
