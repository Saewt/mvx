import XCTest
@testable import Mvx

final class AppearanceConfigTests: XCTestCase {
    func testBuiltInThemePresetsIncludeRequiredThemes() {
        let names = Set(ThemePreset.allCases.map(\.displayName))

        XCTAssertEqual(names, ["Catppuccin", "Dracula", "Solarized", "Nord"])
    }

    func testInvalidAppearanceValuesFallBackSafely() {
        let preferences = AppPreferences(
            themeName: "unknown",
            fontFamily: "   ",
            fontSize: 2,
            colorOverrides: ["background": "not-a-color"]
        )

        let configuration = preferences.resolvedRenderConfiguration()

        XCTAssertEqual(configuration.themeName, "Catppuccin")
        XCTAssertEqual(configuration.fontFamily, RenderConfiguration.defaultFontFamily)
        XCTAssertEqual(configuration.fontSize, AppPreferences.minimumFontSize)
        XCTAssertEqual(configuration.colorPalette.backgroundHex, ThemePreset.catppuccin.colors.backgroundHex)
    }

    func testCustomFontAndColorOverridesTakePrecedence() {
        let preferences = AppPreferences(
            themeName: "Nord",
            fontFamily: "Menlo",
            fontSize: 15,
            colorOverrides: ["foreground": "#112233"]
        )

        let configuration = preferences.resolvedRenderConfiguration()

        XCTAssertEqual(configuration.themeName, "Nord")
        XCTAssertEqual(configuration.fontFamily, "Menlo")
        XCTAssertEqual(configuration.fontSize, 15)
        XCTAssertEqual(configuration.colorPalette.foregroundHex, "#112233")
        XCTAssertEqual(configuration.fallbackFonts.first, "Menlo")
    }

    func testConfigStoreRoundTripsPreferences() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("config.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ConfigStore(fileURL: fileURL)
        let preferences = AppPreferences(
            themeName: "Dracula",
            fontFamily: "Monaco",
            fontSize: 14,
            colorOverrides: ["cursor": "#ABCDEF"]
        )

        try store.save(preferences)
        let loaded = try store.loadValidated()

        XCTAssertEqual(loaded, preferences.validated())
    }
}
