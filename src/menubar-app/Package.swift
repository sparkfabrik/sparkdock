// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SparkdockManager",
    platforms: [
        .macOS("15.0")
    ],
    products: [
        .executable(name: "sparkdock-manager", targets: ["SparkdockManager"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "SparkdockManager",
            dependencies: [],
            // Embedded bytes support raw SwiftPM test and development executables.
            resources: [
                .embedInCode("Resources/menu.json"),
                .embedInCode("Resources/sparkfabrik-logo.png"),
            ]
        ),
        .testTarget(
            name: "SparkdockManagerTests",
            dependencies: ["SparkdockManager"]
        ),
    ]
)
