// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AppleArtifactAnalyzer",
    platforms: [.macOS("13.0")],
    products: [
        .library(
            name: "AppleArtifactAnalyzer",
            type: .static,
            targets: ["AppleArtifactAnalyzer"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/tuist/Path.git", .upToNextMajor(from: "0.3.4")),
        .package(url: "https://github.com/tuist/FileSystem.git", .upToNextMajor(from: "0.3.0")),
        .package(url: "https://github.com/tuist/Command.git", .upToNextMajor(from: "0.8.0")),
    ],
    targets: [
        .target(
            name: "AppleArtifactAnalyzer",
            dependencies: [
                .product(name: "Path", package: "Path"),
                .product(name: "FileSystem", package: "FileSystem"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "AppleArtifactAnalyzerTests",
            dependencies: [
                "AppleArtifactAnalyzer",
            ]
        ),
    ]
)
