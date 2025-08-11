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
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "SparkdockManagerTests",
            dependencies: ["SparkdockManager"]
        ),
    ]
)