import Foundation

/// Resources compiled into the executable through `.embedInCode` in `Package.swift`.
///
/// The binary is installed as a bare file in `/opt/homebrew/bin`, without the
/// SwiftPM resource bundle next to it. A `Bundle.module` lookup would abort the
/// process at launch under the `swiftbuild` build system, whose accessor only
/// searches the executable's own directory. Embedding the bytes removes the
/// runtime lookup entirely.
enum EmbeddedResources {
    /// The menu definition, `Resources/menu.json`.
    static var menuConfigData: Data { Data(PackageResources.menu_json) }

    /// The SparkFabrik logo, `Resources/sparkfabrik-logo.png`.
    static var logoData: Data { Data(PackageResources.sparkfabrik_logo_png) }
}
