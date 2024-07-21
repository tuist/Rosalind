// swift-tools-version: 5.9
import PackageDescription

#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        // Customize the product types for specific package product
        // Default is .staticFramework
        // productTypes: ["Alamofire": .framework,] 
        productTypes: [:]
    )
#endif

let package = Package(
    name: "apple-bundle-size-analyzer",
    dependencies: [
        .package(url: "https://github.com/tuist/Path.git", .upToNextMajor(from: "0.3.0")),
        .package(url: "https://github.com/tuist/FileSystem.git", .upToNextMajor(from: "0.3.0")),
        .package(url: "https://github.com/tuist/Command.git", .upToNextMajor(from: "0.2.0"))
        // Add your own dependencies here:
        // .package(url: "https://github.com/Alamofire/Alamofire", from: "5.0.0"),
        // You can read more about dependencies here: https://docs.tuist.io/documentation/tuist/dependencies
    ]
)
