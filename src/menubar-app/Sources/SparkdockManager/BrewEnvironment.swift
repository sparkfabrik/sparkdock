import Foundation

/// Environment for the Homebrew commands the app runs from its LaunchAgent.
enum BrewEnvironment {
    /// launchd's PATH does not carry Homebrew.
    static let path = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    /// Leaves Homebrew auto-update on, so `brew outdated` refreshes stale formula
    /// and cask data first instead of comparing against whatever is on disk.
    static func make(base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var environment = base
        environment["PATH"] = path
        return environment
    }
}
