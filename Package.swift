// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Rosalind",
    platforms: [.macOS("13.0")],
    products: [
        .library(
            name: "Rosalind",
            type: .static,
            targets: ["Rosalind"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/tuist/Path.git", .upToNextMajor(from: "0.3.4")),
        .package(url: "https://github.com/tuist/FileSystem.git", .upToNextMajor(from: "0.3.0")),
        .package(url: "https://github.com/tuist/Command.git", .upToNextMajor(from: "0.9.32")),
    ],
    targets: [
        .target(
            name: "Rosalind",
            dependencies: [
                .product(name: "Path", package: "Path"),
                .product(name: "FileSystem", package: "FileSystem"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "RosalindTests",
            dependencies: [
                "Rosalind"
            ]
        ),
    ]
)
