import Foundation

/// Result of `brew outdated --quiet`, which prints one package per line.
enum BrewOutdatedCount {
    /// Returns nil when the command failed, so a failure never reads as up to date.
    static func from(exitCode: Int32, output: String) -> Int? {
        guard exitCode == 0 else { return nil }
        return output.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }
}
