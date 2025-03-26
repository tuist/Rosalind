import Command
@preconcurrency import FileSystem
import Foundation
import Path
import MachOKit

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
        let artifact: Artifact
        if path.extension == "xcarchive" {
            guard let appPath = try await fileSystem.glob(
                directory: path.appending(components: "Products", "Applications"),
                include: ["*.app"]
            )
            .collect()
            .first
            else { fatalError() }
            artifact = try await pathToArtifact(
                appPath
            )
        } else {
            artifact = try await pathToArtifact(path)
        }
        return try await traverse(
            artifact: artifact,
            baseArtifact: artifact
        )
    }

    private func traverse(artifact: Artifact, baseArtifact: Artifact) async throws -> RosalindReport {
        let children: [RosalindReport]? = if artifact.isDirectory {
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
        return RosalindReport(
            artifactType: artifactType,
            path: try RelativePath(validating: baseArtifact.path.basename)
                .appending(artifact.path.relative(to: baseArtifact.path)).pathString,
            size: size,
            shasum: shasum,
            children: children
        )
    }
    
    private func artifactType(for artifact: Artifact) throws -> RosalindReport.ArtifactType {
        switch artifact.path.extension {
        case "otf", "ttc", "ttf", "woff": return .font
        default:
            if artifact.isDirectory {
                return .directory
            } else {
                let fileHandle = try FileHandle(forReadingFrom: URL(fileURLWithPath: artifact.path.pathString))
                
                if
                    let magicRaw: UInt32 = fileHandle.read(offset: 0),
                    let magic = Magic(rawValue: magicRaw) {
                    return .binary
                } else {
                    return .file
                }
            }
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

extension FileHandle {
    @_spi(Support)
    public func read<Element>(
        offset: UInt64,
        swapHandler: ((inout Data) -> Void)? = nil
    ) -> Element? {
        seek(toFileOffset: offset)
        var data = readData(
            ofLength: MemoryLayout<Element>.size
        )
        guard data.count >= MemoryLayout<Element>.size else { return nil }
        if let swapHandler { swapHandler(&data) }
        return data.withUnsafeBytes {
            $0.load(as: Element.self)
        }
    }
}

