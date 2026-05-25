// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FigBridge",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "FigBridgeCore",
            targets: ["FigBridgeCore"]
        ),
        .executable(
            name: "FigBridge",
            targets: ["FigBridgeApp"]
        ),
    ],
    targets: [
        .target(
            name: "FigBridgeCore"
        ),
        .executableTarget(
            name: "FigBridgeApp",
            dependencies: ["FigBridgeCore"],
            resources: [
                .copy("Resources")
            ],
            swiftSettings: [
                .unsafeFlags(["-Xfrontend", "-enable-actor-data-race-checks"], .when(configuration: .debug))
            ]
        ),
        .testTarget(
            name: "FigBridgeTests",
            dependencies: ["FigBridgeCore", "FigBridgeApp"],
            exclude: ["Fixtures"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
