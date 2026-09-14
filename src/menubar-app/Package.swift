// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SparkdockManager",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "sparkdock-manager", targets: ["SparkdockManager"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "SparkdockManager",
            dependencies: [],
            // The binary is installed bare in /opt/homebrew/bin, without the
            // SwiftPM resource bundle. Embedding the resources in the executable
            // keeps it self-contained; a `Bundle.module` lookup would abort at
            // launch because the bundle is not next to the installed binary.
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
