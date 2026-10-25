import Foundation

/// Environment for `sparkdock-check-updates`, which the app runs from its LaunchAgent.
enum CheckUpdatesEnvironment {
    /// launchd's PATH carries neither Homebrew nor the python3 and git the checks use.
    static let path = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    /// Leaves Homebrew auto-update on, so the `brew` check refreshes stale formula
    /// and cask data first instead of comparing against whatever is on disk.
    static func make(base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var environment = base
        environment["PATH"] = path
        return environment
    }
}
