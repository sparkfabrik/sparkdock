import AppKit

/// Bundle identifiers define instance identity, independent of the installation path.
enum AppInstance {
    static func otherInstances(bundleIdentifier: String? = AppBundle.current.bundleIdentifier) -> [NSRunningApplication] {
        guard let bundleIdentifier = bundleIdentifier else { return [] }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != currentPID && !$0.isTerminated }
    }
}
