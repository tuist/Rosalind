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
    private let assetUtilController: AssetUtilControlling

    /// The default constructor of Rosalind.
    public init() {
        self.init(
            fileSystem: FileSystem(),
            appBundleLoader: AppBundleLoader(),
            shasumCalculator: ShasumCalculator(),
            assetUtilController: AssetUtilController()
        )
    }

    init(
        fileSystem: FileSysteming,
        appBundleLoader: AppBundleLoading,
        shasumCalculator: ShasumCalculating,
        assetUtilController: AssetUtilControlling
    ) {
        self.fileSystem = fileSystem
        self.appBundleLoader = appBundleLoader
        self.shasumCalculator = shasumCalculator
        self.assetUtilController = assetUtilController
    }

    /// Given the absolute path to an artifact that's result of a compilation, for example a .app bundle,
    /// Rosalind analyzes it and returns a report.
    /// - Parameter path: Absolute path to the artifact. If it doesn't exist, Rosalind throws.
    /// - Returns: A `RosalindReport` instance that captures the analysis.
    public func analyzeAppBundle(at path: AbsolutePath) async throws -> AppBundleReport {
        print("Starting to analyze the app bundle at path: \(path.pathString)")
        
        print("Checking if file exists at path: \(path.pathString)")
        guard try await fileSystem.exists(path) else { 
            print("File not found at path: \(path.pathString)")
            throw RosalindError.notFound(path) 
        }
        print("File exists, proceeding with analysis")
        
        return try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            print("Created temporary directory: \(temporaryDirectory.pathString)")
            
            print("Extracting app bundle path from: \(path.pathString)")
            let appBundlePath = try await appBundlePath(path, temporaryDirectory: temporaryDirectory)
            print("App bundle path extracted: \(appBundlePath.pathString)")
            
            print("Converting app bundle path to artifact")
            let artifactPath = try await pathToArtifact(appBundlePath)
            print("Artifact path created: \(artifactPath.path.pathString)")
            
            print("Starting traversal of artifact tree")
            let artifact = try await traverse(
                artifact: artifactPath,
                baseArtifact: artifactPath
            )
            print("Artifact traversal completed. Total size: \(artifact.size) bytes")
            
            print("Loading app bundle metadata")
            let appBundle = try await appBundleLoader.load(appBundlePath)
            print("App bundle loaded successfully")

            print("Calculating download size")
            let downloadSize: Int?
            switch path.extension {
            case "ipa":
                downloadSize = try fileSize(at: path)
                print("Download size for IPA: \(downloadSize ?? 0) bytes")
            default:
                downloadSize = nil
                print("No download size calculated for extension: \(path.extension ?? "none")")
            }

            print("Creating final report")
            let report = AppBundleReport(
                bundleId: appBundle.infoPlist.bundleId,
                name: appBundle.infoPlist.name,
                installSize: artifact.size,
                downloadSize: downloadSize,
                platforms: appBundle.infoPlist.supportedPlatforms,
                version: appBundle.infoPlist.version,
                artifacts: artifact.children ?? []
            )
            print("Analysis completed successfully for bundle: \(appBundle.infoPlist.name)")
            return report
        }
    }

    private func appBundlePath(
        _ path: AbsolutePath,
        temporaryDirectory: AbsolutePath
    ) async throws -> AbsolutePath {
        print("Processing app bundle path for extension: \(path.extension ?? "none")")
        
        switch path.extension {
        case "xcarchive":
            print("Processing xcarchive bundle")
            let searchPath = path.appending(components: "Products", "Applications")
            print("Searching for .app files in: \(searchPath.pathString)")
            
            guard let appPath = try await fileSystem.glob(
                directory: searchPath,
                include: ["*.app"]
            )
            .collect()
            .first else {
                print("No .app file found in xcarchive at: \(searchPath.pathString)")
                throw RosalindError.appNotFound(path)
            }
            print("Found .app file in xcarchive: \(appPath.pathString)")
            return appPath
            
        case "ipa":
            print("Processing IPA bundle")
            let unzippedPath = temporaryDirectory.appending(component: "App")
            print("Unzipping IPA to: \(unzippedPath.pathString)")
            
            try await fileSystem.unzip(path, to: unzippedPath)
            print("IPA unzipped successfully")
            
            let payloadPath = unzippedPath.appending(component: "Payload")
            print("Searching for .app files in: \(payloadPath.pathString)")
            
            guard let appPath = try await fileSystem.glob(
                directory: payloadPath,
                include: ["*.app"]
            )
            .collect()
            .first else {
                print("No .app file found in IPA payload at: \(payloadPath.pathString)")
                throw RosalindError.appNotFound(path)
            }
            print("Found .app file in IPA: \(appPath.pathString)")
            return appPath
            
        case "app":
            print("Processing .app bundle directly")
            return path
            
        default:
            print("Unsupported bundle extension: \(path.extension ?? "none")")
            throw RosalindError.notSupported(path)
        }
    }

    private func traverse(artifact: FileSystemArtifact, baseArtifact: FileSystemArtifact) async throws -> AppBundleArtifact {
        print("Traversing artifact: \(artifact.path.pathString)")
        
        let children: [AppBundleArtifact]?
        let artifactType = try artifactType(for: artifact)
        print("Artifact type determined: \(artifactType)")
        
        switch artifactType {
        case .asset:
            print("Processing asset file: \(artifact.path.pathString)")
            let infos = try await assetUtilController.info(at: artifact.path)
            print("Asset info retrieved, processing \(infos.count) items")
            
            children = try infos.compactMap { info -> AppBundleArtifact? in
                guard let sizeOnDisk = info.sizeOnDisk,
                      let sha1Digest = info.sha1Digest,
                      let renditionName = info.renditionName
                else { return nil }

                return AppBundleArtifact(
                    artifactType: .asset,
                    path: try RelativePath(validating: baseArtifact.path.basename)
                        .appending(artifact.path.appending(component: renditionName).relative(to: baseArtifact.path)).pathString,
                    size: sizeOnDisk,
                    shasum: sha1Digest.lowercased(),
                    children: nil
                )
            }
            print("Asset processing completed, found \(children?.count ?? 0) valid assets")
            
        case .directory:
            print("Processing directory: \(artifact.path.pathString)")
            let globResults = try await fileSystem.glob(directory: artifact.path, include: ["*"]).collect().sorted()
            print("Found \(globResults.count) items in directory")
            
            children = try await globResults.asyncMap { childPath in
                print("Processing child: \(childPath.pathString)")
                return try await traverse(artifact: pathToArtifact(childPath), baseArtifact: baseArtifact)
            }
            print("Directory processing completed for: \(artifact.path.pathString)")
            
        case .file, .binary, .localization, .font:
            print("Processing leaf artifact: \(artifact.path.pathString)")
            children = nil
        }

        print("Calculating size for artifact: \(artifact.path.pathString)")
        let size = try await size(artifact: artifact, children: children ?? [])
        print("Size calculated: \(size) bytes")
        
        print("Calculating shasum for artifact: \(artifact.path.pathString)")
        let shasum = try await shasum(artifact: artifact, children: children ?? [])
        print("Shasum calculated: \(shasum)")
        
        let bundleArtifact = AppBundleArtifact(
            artifactType: artifactType,
            path: try RelativePath(validating: baseArtifact.path.basename)
                .appending(artifact.path.relative(to: baseArtifact.path)).pathString,
            size: size,
            shasum: shasum,
            children: children
        )
        
        print("Completed traversal for artifact: \(artifact.path.pathString)")
        return bundleArtifact
    }

    private func artifactType(for artifact: FileSystemArtifact) throws -> AppBundleArtifact.ArtifactType {
        print("Determining artifact type for: \(artifact.path.pathString), extension: \(artifact.path.extension ?? "none")")
        
        switch artifact.path.extension {
        case "otf", "ttc", "ttf", "woff": 
            print("Identified as font file")
            return .font
        case "strings", "xcstrings": 
            print("Identified as localization file")
            return .localization
        case "car": 
            print("Identified as asset catalog")
            return .asset
        default:
            if artifact.isDirectory {
                print("Identified as directory")
                return .directory
            } else {
                print("Analyzing file magic bytes")
                let fileURL = URL(fileURLWithPath: artifact.path.pathString)
                let fileHandle = try FileHandle(forReadingFrom: fileURL)
                defer { try? fileHandle.close() }

                if let magicRaw: UInt32 = fileHandle.read(offset: 0),
                   Magic(rawValue: magicRaw) != nil
                {
                    print("Identified as binary file")
                    return .binary
                } else {
                    print("Identified as regular file")
                    return .file
                }
            }
        }
    }

    private func shasum(artifact: FileSystemArtifact, children: [AppBundleArtifact]) async throws -> String {
        if artifact.isDirectory {
            print("Calculating directory shasum from \(children.count) children")
            let result = try await shasumCalculator.calculate(childrenShasums: children.map(\.shasum).sorted())
            print("Directory shasum calculated: \(result)")
            return result
        } else {
            print("Calculating file shasum for: \(artifact.path.pathString)")
            let result = try await shasumCalculator.calculate(filePath: artifact.path)
            print("File shasum calculated: \(result)")
            return result
        }
    }

    private func pathToArtifact(_ path: AbsolutePath) async throws -> FileSystemArtifact {
        print("Converting path to artifact: \(path.pathString)")
        let isDirectory = try await fileSystem.exists(path, isDirectory: true)
        let artifact: FileSystemArtifact = isDirectory ? .directory(path) : .file(path)
        print("Path converted to artifact type: \(isDirectory ? "directory" : "file")")
        return artifact
    }

    private func size(artifact: FileSystemArtifact, children: [AppBundleArtifact]) async throws -> Int {
        if artifact.isDirectory {
            let totalSize = children.map(\.size).reduce(0, +)
            print("Directory size calculated from children: \(totalSize) bytes")
            return totalSize
        } else {
            let fileSize = try fileSize(at: artifact.path)
            print("File size calculated: \(fileSize) bytes for \(artifact.path.pathString)")
            return fileSize
        }
    }

    private func fileSize(at path: AbsolutePath) throws -> Int {
        print("Getting file size for: \(path.pathString)")
        let size = ((try FileManager.default.attributesOfItem(atPath: path.pathString))[.size] as? Int) ?? 0
        print("File size retrieved: \(size) bytes")
        return size
    }
}
