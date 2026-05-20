import Foundation

@MainActor
public enum AppUpdateHelper {
    public static var helperScriptPath: String {
        #if canImport(AppKit)
        if let resourceURL = Bundle.main.resourceURL {
            let path = resourceURL.appendingPathComponent("update-helpers/mvx-update-helper.sh").path
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        #endif
        return "/usr/local/lib/mvx/mvx-update-helper.sh"
    }

    public static func extractVersion(from bundle: Bundle) -> String? {
        bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    public static func extractBuild(from bundle: Bundle) -> String? {
        bundle.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String
    }
}