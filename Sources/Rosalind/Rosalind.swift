import Command
import CryptoKit
@preconcurrency import FileSystem
import Foundation
import Path

enum RosalindError: LocalizedError {
    case notFound(AbsolutePath)

    var errorDescription: String? {
        switch self {
        case let .notFound(path):
            return "File not found at path \(path.pathString)"
        }
    }
}

public protocol Rosalindable: Sendable {
    func analyze(path: AbsolutePath) async throws -> RosalindReport
}

enum Artifact {
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
    private let commandRunner: CommandRunning
    private let shasumCalculator: ShasumCalculating

    /// The default constructor of Rosalind.
    public init() {
        self.init(fileSystem: FileSystem(), commandRunner: CommandRunner(), shasumCalculator: ShasumCalculator())
    }

    init(
        fileSystem: FileSysteming,
        commandRunner: CommandRunning,
        shasumCalculator: ShasumCalculating
    ) {
        self.fileSystem = fileSystem
        self.commandRunner = commandRunner
        self.shasumCalculator = shasumCalculator
    }

    /// Given the absolute path to an artifact that's result of a compilation, for example a .app bundle,
    /// Rosalind analyzes it and returns a report.
    /// - Parameter path: Absolute path to the artifact. If it doesn't exist, Rosalind throws.
    /// - Returns: A `RosalindReport` instance that captures the analysis.
    public func analyze(path: AbsolutePath) async throws -> RosalindReport {
        guard try await fileSystem.exists(path) else { throw RosalindError.notFound(path) }
        return try await traverse(artifact: pathToArtifact(path), baseArtifact: pathToArtifact(path))
    }

    private func traverse(artifact: Artifact, baseArtifact: Artifact) async throws -> RosalindReport {
        let children: [RosalindReport] = try await fileSystem.glob(directory: artifact.path, include: ["*"]).collect().sorted()
            .asyncMap {
                try await traverse(artifact: pathToArtifact($0), baseArtifact: baseArtifact)
            }
        let size = try await size(artifact: artifact, children: children)
        let shasum = try await shasum(artifact: artifact, children: children)
        if artifact.path.extension == "app" {
            return .app(
                path: artifact.path.relative(to: baseArtifact.path).pathString,
                size: size,
                shasum: shasum,
                children: children
            )
        } else if artifact.isDirectory {
            return .directory(
                path: artifact.path.relative(to: baseArtifact.path).pathString,
                size: size,
                shasum: shasum,
                children: children
            )
        } else {
            return .file(
                path: artifact.path.relative(to: baseArtifact.path).pathString,
                size: size,
                shasum: shasum,
                children: children
            )
        }
    }

    private func shasum(artifact: Artifact, children: [RosalindReport]) async throws -> String {
        if artifact.isDirectory {
            return try await shasumCalculator.calculate(childrenShasums: children.map(\.shasum).sorted())
        } else {
            return try await shasumCalculator.calculate(filePath: artifact.path)
        }
    }

    private func pathToArtifact(_ path: AbsolutePath) async throws -> Artifact {
        (try await fileSystem.exists(path, isDirectory: true)) ? .directory(path) : .file(path)
    }

    private func size(artifact: Artifact, children: [RosalindReport]) async throws -> Int {
        if artifact.isDirectory {
            return children.map(\.size).reduce(0, +)
        } else {
            return ((try FileManager.default.attributesOfItem(atPath: artifact.path.pathString))[.size] as? Int) ?? 0
        }
    }
}
