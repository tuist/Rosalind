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
        .package(url: "https://github.com/tuist/FileSystem.git", .upToNextMajor(from: "0.7.9")),
        .package(url: "https://github.com/tuist/Command.git", .upToNextMajor(from: "0.13.0")),
        .package(
            url: "https://github.com/pointfreeco/swift-snapshot-testing",
            .upToNextMajor(from: "1.18.2")
        ),
        // To our surprise (note the irony), CryptoSwift is an AppleOS-only framework, therefore
        // crypto capabilities need to be imported using a package.
        .package(url: "https://github.com/apple/swift-crypto.git", .upToNextMajor(from: "3.12.2")),
    ],
    targets: [
        .target(
            name: "Rosalind",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
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
