import XCTest
@testable import Mvx

final class TerminalInteractionTests: XCTestCase {
    func testTerminalKeyFallbackReturnsPrintableText() {
        XCTAssertEqual(TerminalKeyFallback.fallbackText(for: "a"), "a")
        XCTAssertEqual(TerminalKeyFallback.fallbackText(for: "hello"), "hello")
    }

    func testTerminalKeyFallbackRejectsFunctionKeyPrivateUseCharacters() {
        XCTAssertNil(TerminalKeyFallback.fallbackText(for: String(UnicodeScalar(0xF700)!)))
        XCTAssertNil(TerminalKeyFallback.fallbackText(for: String(UnicodeScalar(0xF701)!)))
    }

    func testTerminalKeyFallbackRejectsMixedTextContainingFunctionKeyPrivateUseCharacters() {
        let invalidText = "a" + String(UnicodeScalar(0xF702)!) + "b"
        XCTAssertNil(TerminalKeyFallback.fallbackText(for: invalidText))
    }

    func testTerminalKeyFallbackRejectsEmptyInput() {
        XCTAssertNil(TerminalKeyFallback.fallbackText(for: nil))
        XCTAssertNil(TerminalKeyFallback.fallbackText(for: ""))
    }

    func testTerminalKeyFallbackAllowsCommittedNonASCIIText() {
        XCTAssertEqual(TerminalKeyFallback.fallbackText(for: "おおおか"), "おおおか")
    }

    func testTerminalKeyEquivalentPolicyDefersPrintableOptionCharactersToTextInput() {
        let disposition = TerminalKeyEquivalentPolicy.disposition(
            modifiers: [.option],
            characters: "@",
            charactersIgnoringModifiers: "q"
        )

        XCTAssertEqual(disposition, .deferToTextInput)
    }

    func testTerminalKeyEquivalentPolicyKeepsControlChordsRaw() {
        let disposition = TerminalKeyEquivalentPolicy.disposition(
            modifiers: [.control],
            characters: "c",
            charactersIgnoringModifiers: "c"
        )

        XCTAssertEqual(disposition, .sendRawToTerminal)
    }

    func testTerminalKeyEquivalentPolicyLeavesCommandQToSystemHandling() {
        let disposition = TerminalKeyEquivalentPolicy.disposition(
            modifiers: [.command],
            characters: "q",
            charactersIgnoringModifiers: "q"
        )

        XCTAssertEqual(disposition, .allowSystemHandling)
    }

    func testTerminalKeyEquivalentPolicyKeepsNonPrintableOptionKeysRaw() {
        let disposition = TerminalKeyEquivalentPolicy.disposition(
            modifiers: [.option],
            characters: String(UnicodeScalar(0xF700)!),
            charactersIgnoringModifiers: String(UnicodeScalar(0xF700)!)
        )

        XCTAssertEqual(disposition, .sendRawToTerminal)
    }

    func testActivityObserversNotifyMultipleListeners() {
        let session = makeTestSession()
        var firstCount = 0
        var secondCount = 0

        _ = session.addActivityObserver { firstCount += 1 }
        _ = session.addActivityObserver { secondCount += 1 }

        _ = session.sendUserInput("echo hi\n")

        XCTAssertEqual(firstCount, 1)
        XCTAssertEqual(secondCount, 1)
    }

    func testClipboardAndOSC52() {
        let session = makeTestSession()

        session.start()
        _ = session.handleKeyboard(KeyboardCommand.commandC, selection: "copied selection")

        XCTAssertEqual(session.clipboardContents(), "copied selection")

        let remotePayload = Data("remote clipboard".utf8).base64EncodedString()
        let setResponse = session.processOSC52("\u{001B}]52;c;\(remotePayload)\u{0007}")
        XCTAssertTrue(setResponse.handled)
        XCTAssertEqual(setResponse.action, "set")
        XCTAssertEqual(session.clipboardContents(), "remote clipboard")

        let queryResponse = session.processOSC52("\u{001B}]52;c;?\u{0007}")
        XCTAssertEqual(queryResponse.action, "query")
        XCTAssertTrue(queryResponse.replySequence?.contains(remotePayload) == true)

        let pasted = session.handleKeyboard(KeyboardCommand.commandV)
        XCTAssertEqual(pasted, "remote clipboard")
    }

    func testMouseProtocolMatrix() {
        let session = makeTestSession()
        let driver = session.backendObject as? InMemoryTestTerminalDriver

        session.enableMouseModes([.drag, .motion, .sgr])
        let sequence = session.handleMouse(MouseEvent(kind: .drag(.left), column: 12, row: 4))

        XCTAssertEqual(sequence, "\u{001B}[<32;12;4M")
        XCTAssertEqual(driver?.ptyBridge.protocolLog.last, sequence)
    }

    func testProtocolLogRetainsOnlyMostRecentEntries() {
        let bridge = PtyBridge()

        for index in 0..<600 {
            bridge.recordProtocolPacket(Array("pkt-\(index)".utf8))
        }

        XCTAssertEqual(bridge.protocolLog.count, 500)
        XCTAssertEqual(bridge.protocolLog.first, "pkt-100")
        XCTAssertEqual(bridge.protocolLog.last, "pkt-599")
    }

    func testResolveAgentHelpersDirectoryReturnsExistingDirectoryFromEnvironment() throws {
        let directory = try makeTemporaryDirectory()

        let resolved = PtyBridge.resolveAgentHelpersDirectory(
            environment: [PtyBridge.agentHelpersEnvironmentKey: directory.path]
        )

        XCTAssertEqual(resolved, directory.standardizedFileURL)
    }

    func testResolveAgentHelpersDirectoryIgnoresMissingDirectory() {
        let resolved = PtyBridge.resolveAgentHelpersDirectory(
            environment: [PtyBridge.agentHelpersEnvironmentKey: "/tmp/mvx-missing-\(UUID().uuidString)"]
        )

        XCTAssertNil(resolved)
    }

    func testBootstrapConfigurationPrependsCommandDirectoryToPath() {
        let configuration = PtyBridge.bootstrapConfiguration(
            prompt: "mvx% ",
            commandDirectory: URL(fileURLWithPath: "/tmp/mvx-runtime", isDirectory: true)
        )

        XCTAssertTrue(configuration.contains("PROMPT='mvx% '"))
        XCTAssertTrue(configuration.contains("export PATH='/tmp/mvx-runtime':\"$PATH\""))
    }

    func testInstallAgentHelperLaunchersCreatesExecutableShims() throws {
        let rootDirectory = try makeTemporaryDirectory()
        let runtimeDirectory = rootDirectory.appendingPathComponent("runtime", isDirectory: true)
        let helpersDirectory = rootDirectory.appendingPathComponent("helpers", isDirectory: true)
        try FileManager.default.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: helpersDirectory, withIntermediateDirectories: true)

        try Data().write(to: helpersDirectory.appendingPathComponent("mvx-agent-status"))
        try Data().write(to: helpersDirectory.appendingPathComponent("mvx-wrap-agent"))

        let launchers = try PtyBridge.installAgentHelperLaunchers(
            in: runtimeDirectory,
            agentHelpersDirectory: helpersDirectory
        )

        XCTAssertEqual(launchers.map(\.lastPathComponent).sorted(), ["mvx-agent-status", "mvx-wrap-agent"])

        let launcherURL = runtimeDirectory.appendingPathComponent("mvx-wrap-agent")
        let contents = try String(contentsOf: launcherURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("exec /bin/sh '\(helpersDirectory.path)/mvx-wrap-agent' \"$@\""))

        let attributes = try FileManager.default.attributesOfItem(atPath: launcherURL.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        XCTAssertEqual(permissions.intValue & 0o111, 0o111)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}
