import ProjectDescription

let project = Project(
    name: "Rosalind",
    settings: .settings(base: ["SWIFT_STRICT_CONCURRENCY": "complete"]),
    targets: [
        .target(
            name: "Rosalind",
            destinations: .macOS,
            product: .framework,
            bundleId: "io.tuist.Rosalind",
            sources: ["Sources/Rosalind/**"],
            dependencies: [
                .external(name: "Path"),
                .external(name: "FileSystem"),
                .external(name: "Command"),
            ]
        ),
        .target(
            name: "RosalindTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "io.tuist.RosalindTests",
            infoPlist: .default,
            sources: ["Tests/RosalindTests/**"],
            resources: [],
            dependencies: [.target(name: "Rosalind")]
        ),
    ]
)
