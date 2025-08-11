// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SparkdockMenubar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "sparkdock-manager", targets: ["SparkdockMenubar"])
    ],
    dependencies: [],
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