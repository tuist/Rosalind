import ProjectDescription

let project = Project(
    name: "AppleArtifactAnalyzer",
    targets: [
        .target(
            name: "AppleArtifactAnalyzer",
            destinations: .macOS,
            product: .framework,
            bundleId: "io.tuist.AppleArtifactAnalyzer",
            sources: ["Sources/AppleArtifactAnalyzer/**"],
            dependencies: [
                .external(name: "Path"),
                .external(name: "FileSystem"),
                .external(name: "Command"),
            ]
        ),
        .target(
            name: "AppleArtifactAnalyzerTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "io.tuist.AppleArtifactAnalyzerTests",
            infoPlist: .default,
            sources: ["Tests/AppleArtifactAnalyzerTests/**"],
            resources: [],
            dependencies: [.target(name: "AppleArtifactAnalyzer")]
        ),
    ]
)
