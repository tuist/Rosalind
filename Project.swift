import ProjectDescription

let project = Project(
    name: "apple-bundle-size-analyzer",
    targets: [
        .target(
            name: "apple-bundle-size-analyzer",
            destinations: .iOS,
            product: .app,
            bundleId: "io.tuist.apple-bundle-size-analyzer",
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchScreen": [
                        "UIColorName": "",
                        "UIImageName": "",
                    ],
                ]
            ),
            sources: ["apple-bundle-size-analyzer/Sources/**"],
            resources: ["apple-bundle-size-analyzer/Resources/**"],
            dependencies: []
        ),
        .target(
            name: "apple-bundle-size-analyzerTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.apple-bundle-size-analyzerTests",
            infoPlist: .default,
            sources: ["apple-bundle-size-analyzer/Tests/**"],
            resources: [],
            dependencies: [.target(name: "apple-bundle-size-analyzer")]
        ),
    ]
)
