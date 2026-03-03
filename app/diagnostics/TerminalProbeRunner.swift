import Foundation

public enum TerminalProbeRunnerService {
    @discardableResult
    public static func runTextFidelity(fixturePath: String, outputPath: String) throws -> TextFidelityReport {
        let fixture = try String(contentsOfFile: fixturePath, encoding: .utf8)
        let renderBridge = RenderBridge()
        let configuration = RenderConfiguration()
        let report = renderBridge.analyzeFixture(
            fixture,
            fixturePath: fixturePath,
            configuration: configuration
        )
        try writeJSON(report, to: outputPath)
        return report
    }

    private static func writeJSON<T: Encodable>(_ value: T, to outputPath: String) throws {
        let url = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }
}
