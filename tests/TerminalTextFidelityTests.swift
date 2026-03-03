import XCTest
@testable import Mvx

final class TerminalTextFidelityTests: XCTestCase {
    func testTextFidelityProbeCoversTrueColorUnicodeAndLigatures() throws {
        let root = repositoryRoot()
        let outputPath = root.appendingPathComponent(".build/test-artifacts/text-fidelity.json").path
        let report = try TerminalProbeRunnerService.runTextFidelity(
            fixturePath: root.appendingPathComponent("app/diagnostics/fixtures/text-fidelity.ansi").path,
            outputPath: outputPath
        )

        XCTAssertTrue(report.passed)
        XCTAssertEqual(report.check(named: "truecolor")?.passed, true, "truecolor SGR coverage should pass")
        XCTAssertEqual(report.check(named: "graphemes")?.passed, true, "grapheme coverage should pass")
        XCTAssertEqual(report.check(named: "emoji")?.passed, true, "emoji coverage should pass")
        XCTAssertEqual(report.check(named: "ligatures")?.passed, true, "ligature coverage should pass")
        XCTAssertEqual(report.check(named: "fallback-fonts")?.passed, true, "fallback font coverage should pass")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath))
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
