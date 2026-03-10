import Foundation

public struct AppPreferences: Codable, Equatable {
    public static let minimumFontSize = 8.0
    public static let maximumFontSize = 32.0

    public var themeName: String
    public var fontFamily: String?
    public var fontSize: Double
    public var colorOverrides: [String: String]

    public init(
        themeName: String = ThemePreset.catppuccin.displayName,
        fontFamily: String? = nil,
        fontSize: Double = 13,
        colorOverrides: [String: String] = [:]
    ) {
        self.themeName = themeName
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.colorOverrides = colorOverrides
    }

    public static var `default`: AppPreferences {
        AppPreferences()
    }

    public func validated() -> AppPreferences {
        let resolvedTheme = ThemePreset.resolve(named: themeName)?.displayName ?? ThemePreset.catppuccin.displayName
        let trimmedFontFamily = fontFamily?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedFontFamily = trimmedFontFamily?.isEmpty == false ? trimmedFontFamily : nil
        let boundedFontSize = min(max(fontSize, Self.minimumFontSize), Self.maximumFontSize)

        return AppPreferences(
            themeName: resolvedTheme,
            fontFamily: normalizedFontFamily,
            fontSize: boundedFontSize,
            colorOverrides: colorOverrides
        )
    }

    public var resolvedThemePreset: ThemePreset {
        ThemePreset.resolve(named: themeName) ?? .catppuccin
    }

    public var resolvedThemeColors: TerminalThemeColors {
        resolvedThemePreset.colors.applying(overrides: colorOverrides)
    }

    public func resolvedRenderConfiguration(base: RenderConfiguration = RenderConfiguration()) -> RenderConfiguration {
        let normalized = validated()
        var configuration = base
        configuration.themeName = normalized.resolvedThemePreset.displayName
        configuration.fontFamily = normalized.fontFamily ?? RenderConfiguration.defaultFontFamily
        configuration.fontSize = normalized.fontSize
        configuration.colorPalette = normalized.resolvedThemeColors

        var fallbackFonts = configuration.fallbackFonts
        if let fontFamily = normalized.fontFamily {
            fallbackFonts.removeAll { $0.caseInsensitiveCompare(fontFamily) == .orderedSame }
            fallbackFonts.insert(fontFamily, at: 0)
        }
        configuration.fallbackFonts = fallbackFonts

        return configuration
    }

    enum CodingKeys: String, CodingKey {
        case themeName
        case fontFamily
        case fontSize
        case colorOverrides
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.themeName = try container.decodeIfPresent(String.self, forKey: .themeName) ?? ThemePreset.catppuccin.displayName
        self.fontFamily = try container.decodeIfPresent(String.self, forKey: .fontFamily)
        self.fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? 13
        self.colorOverrides = try container.decodeIfPresent([String: String].self, forKey: .colorOverrides) ?? [:]
    }
}
