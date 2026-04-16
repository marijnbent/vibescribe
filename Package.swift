// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Talkie",
    platforms: [
        .macOS(.v13),
    ],
    targets: [
        .target(
            name: "TalkieCore",
            resources: [
                .process("Resources"),
            ]
        ),
        .executableTarget(
            name: "Talkie",
            dependencies: ["TalkieCore"]
        ),
        .testTarget(
            name: "TalkieTests",
            dependencies: ["TalkieCore"]
        ),
    ]
)
