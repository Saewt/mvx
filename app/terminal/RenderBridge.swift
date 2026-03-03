import Foundation

public struct TextFidelityCheck: Codable, Equatable {
    public let name: String
    public let passed: Bool
    public let detail: String

    public init(name: String, passed: Bool, detail: String) {
        self.name = name
        self.passed = passed
        self.detail = detail
    }
}

public struct TextFidelityReport: Codable, Equatable {
    public let fixturePath: String
    public let checks: [TextFidelityCheck]
    public let passed: Bool
    public let evaluatedAt: String

    public init(fixturePath: String, checks: [TextFidelityCheck], passed: Bool, evaluatedAt: String) {
        self.fixturePath = fixturePath
        self.checks = checks
        self.passed = passed
        self.evaluatedAt = evaluatedAt
    }

    public func check(named name: String) -> TextFidelityCheck? {
        checks.first { $0.name == name }
    }
}

public final class RenderBridge {
    public init() {}

    public func baselineConfiguration(scrollbackLimit: Int = 10_000) -> RenderConfiguration {
        RenderConfiguration(scrollbackLimit: scrollbackLimit)
    }

    public func applyBaseline(to adapter: TerminalAdapter, scrollbackLimit: Int = 10_000) {
        adapter.applyRenderConfiguration(baselineConfiguration(scrollbackLimit: scrollbackLimit))
    }

    public func analyzeFixture(
        _ text: String,
        fixturePath: String,
        configuration: RenderConfiguration
    ) -> TextFidelityReport {
        let trueColorPass = (text.contains("[38;2;") || text.contains("[48;2;")) && configuration.trueColorEnabled
        let emojiPass = (text.contains("👩‍💻") || text.contains("🧑🏽‍💻"))
        let graphemePass = configuration.preserveGraphemeClusters && text.contains("e\u{301}")
        let ligaturePass = configuration.ligaturesEnabled && text.contains("-> => !=")
        let fallbackPass = !configuration.fallbackFonts.isEmpty && text.contains("漢字")

        let checks = [
            TextFidelityCheck(name: "truecolor", passed: trueColorPass, detail: "Validates 24-bit SGR sequences"),
            TextFidelityCheck(name: "graphemes", passed: graphemePass, detail: "Checks combined scalar clusters remain intact"),
            TextFidelityCheck(name: "emoji", passed: emojiPass, detail: "Checks multi-codepoint emoji sequences are present"),
            TextFidelityCheck(name: "ligatures", passed: ligaturePass, detail: "Confirms ligature examples are captured in fixture"),
            TextFidelityCheck(name: "fallback-fonts", passed: fallbackPass, detail: "Confirms fallback glyph examples and configured font chain"),
        ]

        return TextFidelityReport(
            fixturePath: fixturePath,
            checks: checks,
            passed: checks.allSatisfy(\.passed),
            evaluatedAt: Self.timestamp()
        )
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date())
    }
}
