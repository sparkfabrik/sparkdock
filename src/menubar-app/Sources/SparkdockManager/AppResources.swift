import Foundation

/// Application bundles must carry their own resources; raw SwiftPM tools use embedded bytes.
enum AppResources {
    static func data(named name: String, extension fileExtension: String, in bundle: Bundle = AppBundle.current) throws -> Data {
        if bundle.bundleURL.pathExtension == "app" {
            guard let url = bundle.url(forResource: name, withExtension: fileExtension) else {
                throw CocoaError(.fileNoSuchFile)
            }
            return try Data(contentsOf: url)
        }
        switch (name, fileExtension) {
        case ("menu", "json"):
            return EmbeddedResources.menuConfigData
        case ("sparkfabrik-logo", "png"):
            return EmbeddedResources.logoData
        default:
            throw CocoaError(.fileNoSuchFile)
        }
    }
}
