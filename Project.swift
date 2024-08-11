import ProjectDescription

let project = Project(
    name: "AppleBundleSizeAnalyzer",
    targets: [
        .target(
            name: "AppleBundleSizeAnalyzer",
            destinations: .macOS,
            product: .framework,
            bundleId: "io.tuist.AppleBundleSizeAnalyzer",
            sources: ["Sources/AppleBundleSizeAnalyzer/**"],
            dependencies: [
                .external(name: "Path"),
                .external(name: "FileSystem"),
                .external(name: "Command")
            ]
        ),
        .target(
            name: "AppleBundleSizeAnalyzerTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "io.tuist.AppleBundleSizeAnalyzerTests",
            infoPlist: .default,
            sources: ["Tests/AppleBundleSizeAnalyzerTests/**"],
            resources: [],
            dependencies: [.target(name: "AppleBundleSizeAnalyzer")]
        ),
    ]
)
