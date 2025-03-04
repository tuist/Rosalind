// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Rosalind",
    platforms: [.macOS("14.0")],
    products: [
        .library(
            name: "Rosalind",
            type: .static,
            targets: ["Rosalind"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/tuist/Path.git", .upToNextMajor(from: "0.3.8")),
        .package(url: "https://github.com/tuist/FileSystem.git", .upToNextMajor(from: "0.7.7")),
        .package(url: "https://github.com/tuist/Command.git", .upToNextMajor(from: "0.13.0")),
        .package(url: "https://github.com/ajevans99/swift-json-schema", exact: "0.3.2"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", .upToNextMajor(from: "1.18.1")),
    ],
    targets: [
        .target(
            name: "Rosalind",
            dependencies: [
                .product(name: "JSONSchema", package: "swift-json-schema"),
                .product(name: "JSONSchemaBuilder", package: "swift-json-schema"),
                .product(name: "Path", package: "Path"),
                .product(name: "FileSystem", package: "FileSystem"),
                .product(name: "Command", package: "Command"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "RosalindTests",
            dependencies: [
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
                "Rosalind",
            ]
        ),
    ]
)
