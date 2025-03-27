import Command
@preconcurrency import FileSystem
import Foundation
import MachOKit
import Path

enum RosalindError: LocalizedError, Equatable {
    case notFound(AbsolutePath)
    case appNotFound(AbsolutePath)
    case notSupported(AbsolutePath)

    var errorDescription: String? {
        switch self {
        case let .notFound(path):
            return "File not found at path \(path.pathString)"
        case let .appNotFound(path):
            return "No app found at \(path). Make sure the passed app bundle is valid."
        case let .notSupported(path):
            return "The app bundle \(path) is not supported. Only `.xcarchive`, `.ipa`, and `.app` bundles are supported."
        }
    }
}

public protocol Rosalindable: Sendable {
    func analyzeAppBundle(at path: AbsolutePath) async throws -> AppBundleReport
}

enum FileSystemArtifact {
    case file(AbsolutePath)
    case directory(AbsolutePath)

    var path: AbsolutePath {
        switch self {
        case let .file(path): return path
        case let .directory(path): return path
        }
    }

    var isFile: Bool {
        switch self {
        case .file:
            return true
        case .directory:
            return false
        }
    }

    var isDirectory: Bool {
        switch self {
        case .file:
            return false
        case .directory:
            return true
        }
    }
}

/// Rosalind is the main interface to analyzing app artifacts.
/// Once instantiated, you can invoke the function `analyze` passing an absolute path to the artifact,
/// and you'll get a `Codable` report back.
public struct Rosalind: Rosalindable {
    private let fileSystem: FileSysteming
    private let appBundleLoader: AppBundleLoading
    private let shasumCalculator: ShasumCalculating

    /// The default constructor of Rosalind.
    public init() {
        self.init(
            fileSystem: FileSystem(),
            appBundleLoader: AppBundleLoader(),
            shasumCalculator: ShasumCalculator()
        )
    }

    init(
        fileSystem: FileSysteming,
        appBundleLoader: AppBundleLoading,
        shasumCalculator: ShasumCalculating
    ) {
        self.fileSystem = fileSystem
        self.appBundleLoader = appBundleLoader
        self.shasumCalculator = shasumCalculator
    }

    /// Given the absolute path to an artifact that's result of a compilation, for example a .app bundle,
    /// Rosalind analyzes it and returns a report.
    /// - Parameter path: Absolute path to the artifact. If it doesn't exist, Rosalind throws.
    /// - Returns: A `RosalindReport` instance that captures the analysis.
    public func analyzeAppBundle(at path: AbsolutePath) async throws -> AppBundleReport {
        guard try await fileSystem.exists(path) else { throw RosalindError.notFound(path) }
        return try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            let appBundlePath = try await appBundlePath(path, temporaryDirectory: temporaryDirectory)
            let artifactPath = try await pathToArtifact(appBundlePath)
            let artifact = try await traverse(
                artifact: artifactPath,
                baseArtifact: artifactPath
            )
            let appBundle = try await appBundleLoader.load(appBundlePath)

            return AppBundleReport(
                bundleId: appBundle.infoPlist.bundleId,
                name: appBundle.infoPlist.name,
                size: artifact.size,
                platforms: appBundle.infoPlist.supportedPlatforms,
                version: appBundle.infoPlist.version,
                artifacts: artifact.children ?? []
            )
        }
    }

    private func appBundlePath(
        _ path: AbsolutePath,
        temporaryDirectory: AbsolutePath
    ) async throws -> AbsolutePath {
        switch path.extension {
        case "xcarchive":
            guard let appPath = try await fileSystem.glob(
                directory: path.appending(components: "Products", "Applications"),
                include: ["*.app"]
            )
            .collect()
            .first else {
                throw RosalindError.appNotFound(path)
            }
            return appPath
        case "ipa":
            let unzippedPath = temporaryDirectory.appending(component: "App")
            try await fileSystem.unzip(path, to: unzippedPath)
            guard let appPath = try await fileSystem.glob(
                directory: unzippedPath.appending(component: "Payload"),
                include: ["*.app"]
            )
            .collect()
            .first else {
                throw RosalindError.appNotFound(path)
            }
            return appPath
        case "app":
            return path
        default:
            throw RosalindError.notSupported(path)
        }
    }

    private func traverse(artifact: FileSystemArtifact, baseArtifact: FileSystemArtifact) async throws -> AppBundleArtifact {
        let children: [AppBundleArtifact]? = if artifact.isDirectory {
            try await fileSystem.glob(directory: artifact.path, include: ["*"]).collect().sorted()
                .asyncMap {
                    try await traverse(artifact: pathToArtifact($0), baseArtifact: baseArtifact)
                }
        } else {
            nil
        }

        let size = try await size(artifact: artifact, children: children ?? [])
        let shasum = try await shasum(artifact: artifact, children: children ?? [])
        let artifactType = try artifactType(for: artifact)
        return AppBundleArtifact(
            artifactType: artifactType,
            path: try RelativePath(validating: baseArtifact.path.basename)
                .appending(artifact.path.relative(to: baseArtifact.path)).pathString,
            size: size,
            shasum: shasum,
            children: children
        )
    }

    private func artifactType(for artifact: FileSystemArtifact) throws -> AppBundleArtifact.ArtifactType {
        switch artifact.path.extension {
        case "otf", "ttc", "ttf", "woff": return .font
        case "strings", "xcstrings": return .localization
        default:
            if artifact.isDirectory {
                return .directory
            } else {
                let fileURL = URL(fileURLWithPath: artifact.path.pathString)
                let fileHandle = try FileHandle(forReadingFrom: fileURL)

                if let magicRaw: UInt32 = fileHandle.read(offset: 0),
                   Magic(rawValue: magicRaw) != nil
                {
                    return .binary
                } else {
                    return .file
                }
            }
        }
    }

    private func shasum(artifact: FileSystemArtifact, children: [AppBundleArtifact]) async throws -> String {
        if artifact.isDirectory {
            return try await shasumCalculator.calculate(childrenShasums: children.map(\.shasum).sorted())
        } else {
            return try await shasumCalculator.calculate(filePath: artifact.path)
        }
    }

    private func pathToArtifact(_ path: AbsolutePath) async throws -> FileSystemArtifact {
        (try await fileSystem.exists(path, isDirectory: true)) ? .directory(path) : .file(path)
    }

    private func size(artifact: FileSystemArtifact, children: [AppBundleArtifact]) async throws -> Int {
        if artifact.isDirectory {
            return children.map(\.size).reduce(0, +)
        } else {
            return ((try FileManager.default.attributesOfItem(atPath: artifact.path.pathString))[.size] as? Int) ?? 0
        }
    }
}
