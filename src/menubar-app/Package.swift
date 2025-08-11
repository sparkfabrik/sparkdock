// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SparkdockManager",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "sparkdock-manager",
            targets: ["SparkdockMenubar"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "SparkdockMenubar",
            dependencies: [],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "SparkdockMenubarTests",
            dependencies: ["SparkdockMenubar"]
        ),
    ]
)