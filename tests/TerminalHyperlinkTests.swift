import XCTest
@testable import Mvx

final class TerminalHyperlinkTests: XCTestCase {
    func testInvalidHyperlinksFallBackToPlainVisibleText() {
        let parsed = TerminalLinkParser.parse("\u{001B}]8;;file:///tmp/demo\u{0007}Docs\u{001B}]8;;\u{0007}")

        XCTAssertEqual(parsed.visibleText, "Docs")
        XCTAssertTrue(parsed.links.isEmpty)
    }

    func testOsc8HyperlinksPreserveVisibleTextAndOpenUrl() {
        let parsed = TerminalLinkParser.parse("\u{001B}]8;;https://openai.com\u{0007}Docs\u{001B}]8;;\u{0007}")

        XCTAssertEqual(parsed.visibleText, "Docs")
        XCTAssertEqual(parsed.links.first?.url.absoluteString, "https://openai.com")
        XCTAssertEqual(parsed.links.first?.text, "Docs")
    }

    func testVisibleTextStripsEscapeSequences() {
        let parsed = TerminalLinkParser.parse("\u{001B}]8;;https://openai.com\u{0007}Docs\u{001B}]8;;\u{0007}")

        XCTAssertEqual(parsed.visibleText, "Docs")
        XCTAssertFalse(parsed.visibleText.contains("\u{001B}]8"))
    }
}
