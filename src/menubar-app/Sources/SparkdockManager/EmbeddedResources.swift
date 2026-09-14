import Foundation

/// Fallback resources for unbundled SwiftPM test and development executables.
enum EmbeddedResources {
    /// The menu definition, `Resources/menu.json`.
    static var menuConfigData: Data { Data(PackageResources.menu_json) }

    /// The SparkFabrik logo, `Resources/sparkfabrik-logo.png`.
    static var logoData: Data { Data(PackageResources.sparkfabrik_logo_png) }
}
