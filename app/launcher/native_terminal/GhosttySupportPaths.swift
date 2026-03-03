import Foundation

struct GhosttySupportPaths {
    let resourcesRoot: URL
    let terminfoRoot: URL
    let shellIntegrationRoot: URL

    static func `default`(bundle: Bundle = .main) throws -> GhosttySupportPaths {
        for candidate in candidateSets(bundle: bundle) {
            if isDirectory(candidate.resourcesRoot),
               isDirectory(candidate.terminfoRoot),
               isDirectory(candidate.shellIntegrationRoot) {
                return GhosttySupportPaths(
                    resourcesRoot: candidate.resourcesRoot,
                    terminfoRoot: candidate.terminfoRoot,
                    shellIntegrationRoot: candidate.shellIntegrationRoot
                )
            }
        }

        throw ResolutionError.missing(paths: candidateSets(bundle: bundle).flatMap { candidate in
            [
                candidate.resourcesRoot.path,
                candidate.terminfoRoot.path,
                candidate.shellIntegrationRoot.path,
            ]
        })
    }

    private struct CandidateSet {
        let resourcesRoot: URL
        let terminfoRoot: URL
        let shellIntegrationRoot: URL
    }

    private enum ResolutionError: LocalizedError {
        case missing(paths: [String])

        var errorDescription: String? {
            switch self {
            case .missing(let paths):
                return "Missing Ghostty support resources. Checked: \(paths.joined(separator: ", "))"
            }
        }
    }

    private static func candidateSets(bundle: Bundle) -> [CandidateSet] {
        var candidates: [CandidateSet] = []

        if let resourceURL = bundle.resourceURL {
            candidates.append(
                CandidateSet(
                    resourcesRoot: resourceURL.appendingPathComponent("ghostty", isDirectory: true),
                    terminfoRoot: resourceURL.appendingPathComponent("terminfo", isDirectory: true),
                    shellIntegrationRoot: resourceURL.appendingPathComponent("shell-integration", isDirectory: true)
                )
            )
        }

        return candidates
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
