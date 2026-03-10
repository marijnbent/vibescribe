// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "VibeScribe",
    platforms: [
        .macOS(.v13),
    ],
    targets: [
        .target(
            name: "VibeScribeCore",
            resources: [
                .process("Resources"),
            ]
        ),
        .executableTarget(
            name: "VibeScribe",
            dependencies: ["VibeScribeCore"]
        ),
        .testTarget(
            name: "VibeScribeTests",
            dependencies: ["VibeScribeCore"]
        ),
    ]
)
