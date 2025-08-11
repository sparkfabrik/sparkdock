// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SparkdockMenubar",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "sparkdock-menubar",
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