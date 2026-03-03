import Foundation

public struct TerminalPixelSize: Codable, Equatable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = max(width, 0)
        self.height = max(height, 0)
    }
}

public struct RenderConfiguration: Codable, Equatable {
    public static let defaultFontFamily = "SF Mono"

    public var trueColorEnabled: Bool
    public var preserveGraphemeClusters: Bool
    public var ligaturesEnabled: Bool
    public var fallbackFonts: [String]
    public var scrollbackLimit: Int
    public var allowOSC52Read: Bool
    public var allowOSC52Write: Bool
    public var themeName: String
    public var fontFamily: String
    public var fontSize: Double
    public var colorPalette: TerminalThemeColors

    public init(
        trueColorEnabled: Bool = true,
        preserveGraphemeClusters: Bool = true,
        ligaturesEnabled: Bool = true,
        fallbackFonts: [String] = ["SF Mono", "Apple Symbols", "Apple Color Emoji"],
        scrollbackLimit: Int = 10_000,
        allowOSC52Read: Bool = true,
        allowOSC52Write: Bool = true,
        themeName: String = ThemePreset.catppuccin.displayName,
        fontFamily: String = RenderConfiguration.defaultFontFamily,
        fontSize: Double = 13,
        colorPalette: TerminalThemeColors = ThemePreset.catppuccin.colors
    ) {
        self.trueColorEnabled = trueColorEnabled
        self.preserveGraphemeClusters = preserveGraphemeClusters
        self.ligaturesEnabled = ligaturesEnabled
        self.fallbackFonts = fallbackFonts
        self.scrollbackLimit = max(scrollbackLimit, 1)
        self.allowOSC52Read = allowOSC52Read
        self.allowOSC52Write = allowOSC52Write
        self.themeName = themeName
        self.fontFamily = fontFamily
        self.fontSize = min(max(fontSize, AppPreferences.minimumFontSize), AppPreferences.maximumFontSize)
        self.colorPalette = colorPalette
    }
}

public final class TerminalAdapter {
    private(set) public var renderConfiguration: RenderConfiguration

    public init(renderConfiguration: RenderConfiguration = RenderConfiguration()) {
        self.renderConfiguration = renderConfiguration
    }

    public func applyRenderConfiguration(_ configuration: RenderConfiguration) {
        renderConfiguration = configuration
    }
}
