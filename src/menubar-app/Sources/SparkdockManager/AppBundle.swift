import Foundation

/// Resolve the CLI symlink before locating its enclosing application bundle.
enum AppBundle {
    static let current: Bundle = {
        let main = Bundle.main
        guard main.bundleURL.pathExtension != "app", let executable = main.executableURL else { return main }
        let url = executable.resolvingSymlinksInPath()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard url.pathExtension == "app", let bundle = Bundle(url: url) else { return main }
        return bundle
    }()
}
