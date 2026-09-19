// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ViKey",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "VietEngine",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "ViKey",
            dependencies: ["VietEngine"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "VietEngineTests",
            dependencies: ["VietEngine"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
