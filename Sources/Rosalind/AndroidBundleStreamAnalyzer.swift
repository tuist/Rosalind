import Crypto
import Foundation
import Mockable
import Path
import ZIPFoundation

/// Result of analyzing an Android bundle (`.aab` / `.apk`) directly from its ZIP archive without
/// extracting it to disk.
struct AndroidBundleStreamAnalysis: Equatable {
    let installSize: Int
    let artifact: AppBundleArtifact
}

@Mockable
protocol AndroidBundleStreamAnalyzing: Sendable {
    func analyzeAab(at path: AbsolutePath, rootName: String) async throws -> AndroidBundleStreamAnalysis
    func analyzeApk(at path: AbsolutePath, rootName: String) async throws -> AndroidBundleStreamAnalysis
}

/// Reads an Android bundle by iterating the ZIP central directory and hashing each entry's
/// decompressed bytes as they stream by. Nothing is written to disk. On Linux this avoids the
/// 6,000+ per-file writes that dominate `FileManager.unzipItem` wall-clock; on macOS it also
/// beats disk extraction because it skips the write path entirely.
struct AndroidBundleStreamAnalyzer: AndroidBundleStreamAnalyzing {
    /// 1 MB per inflate call. ZIPFoundation on Linux allocates a fresh `Data(count:)` per output
    /// chunk, so a larger chunk amortises the allocation cost across a much bigger inflate step.
    /// 1 MB is well below the working set of realistic entries (dex, so, arsc) so the compiler
    /// keeps this on the fast path.
    private static let inflateBufferSize = 1024 * 1024

    /// AAB analysis: only entries under `base/` count towards the install artifact tree. That
    /// mirrors what Pedro's `fix/aab-double-unzip` branch chose after removing bundletool: the
    /// device-installed contents live under `base/`, everything else (`BUNDLE-METADATA/`,
    /// `META-INF/`, `BundleConfig.pb`, split-config modules) is packaging metadata that a user
    /// never sees.
    func analyzeAab(at path: AbsolutePath, rootName: String) async throws -> AndroidBundleStreamAnalysis {
        try await stream(archiveAt: path, prefix: "base/", rootName: rootName)
    }

    /// APK analysis: everything in the archive is part of the install, so no prefix filter.
    func analyzeApk(at path: AbsolutePath, rootName: String) async throws -> AndroidBundleStreamAnalysis {
        try await stream(archiveAt: path, prefix: nil, rootName: rootName)
    }

    private func stream(
        archiveAt path: AbsolutePath,
        prefix: String?,
        rootName: String
    ) async throws -> AndroidBundleStreamAnalysis {
        try await Task.detached(priority: .userInitiated) {
            let archive = try Archive(url: URL(fileURLWithPath: path.pathString), accessMode: .read)
            let root = TreeNode(name: rootName)
            var installSize = 0
            for entry in archive where entry.type == .file {
                let entryPath: String
                if let prefix {
                    guard entry.path.hasPrefix(prefix), entry.path.count > prefix.count else { continue }
                    entryPath = String(entry.path.dropFirst(prefix.count))
                } else {
                    entryPath = entry.path
                }
                let components = entryPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
                guard !components.isEmpty else { continue }

                var hasher = SHA256()
                var bytes = 0
                _ = try archive.extract(entry, bufferSize: Self.inflateBufferSize, skipCRC32: true) { data in
                    hasher.update(data: data)
                    bytes += data.count
                }
                let digest = hasher.finalize()
                let shasum = Self.hex(digest)
                installSize += bytes
                root.insert(components: components, size: bytes, shasum: shasum, type: Self.classify(components.last!))
            }
            let artifact = root.render(pathPrefix: rootName)
            return AndroidBundleStreamAnalysis(installSize: installSize, artifact: artifact)
        }.value
    }

    /// Matches `Rosalind.artifactType(for:isAndroid:)` for the Android branch. Kept in sync by
    /// hand rather than shared: this analyzer is the only Android caller now, and hoisting a
    /// helper into `Rosalind` would create an import cycle with `AppBundleArtifact`.
    private static func classify(_ filename: String) -> AppBundleArtifact.ArtifactType {
        guard let dot = filename.lastIndex(of: "."), dot != filename.startIndex else { return .file }
        let ext = String(filename[filename.index(after: dot)...])
        switch ext {
        case "otf", "ttc", "ttf", "woff": return .font
        case "strings", "xcstrings": return .localization
        case "dex", "so": return .binary
        case "arsc": return .asset
        default: return .file
        }
    }

    private static func hex(_ digest: SHA256Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// In-memory tree accumulator that mirrors what `Rosalind.traverse` used to build against a
/// directory on disk. Directory shasums combine children shasums the way `ShasumCalculator`
/// already did: SHA-256 of the sorted-shasum concatenation.
private final class TreeNode {
    let name: String
    var children: [String: TreeNode] = [:]
    var isFile: Bool = false
    var fileSize: Int = 0
    var fileShasum: String = ""
    var fileType: AppBundleArtifact.ArtifactType = .file

    init(name: String) {
        self.name = name
    }

    func insert(components: [String], size: Int, shasum: String, type: AppBundleArtifact.ArtifactType) {
        var cursor = self
        for (index, component) in components.enumerated() {
            if index == components.count - 1 {
                let leaf = TreeNode(name: component)
                leaf.isFile = true
                leaf.fileSize = size
                leaf.fileShasum = shasum
                leaf.fileType = type
                cursor.children[component] = leaf
            } else {
                if let existing = cursor.children[component] {
                    cursor = existing
                } else {
                    let node = TreeNode(name: component)
                    cursor.children[component] = node
                    cursor = node
                }
            }
        }
    }

    func render(pathPrefix: String) -> AppBundleArtifact {
        if isFile {
            return AppBundleArtifact(
                artifactType: fileType,
                path: pathPrefix,
                size: fileSize,
                shasum: fileShasum,
                children: nil
            )
        }
        let childNodes = children.keys.sorted().map { key -> AppBundleArtifact in
            children[key]!.render(pathPrefix: "\(pathPrefix)/\(key)")
        }
        let totalSize = childNodes.reduce(0) { $0 + $1.size }
        let combined = childNodes.map(\.shasum).sorted().joined()
        let digest = SHA256.hash(data: Data(combined.utf8))
        return AppBundleArtifact(
            artifactType: .directory,
            path: pathPrefix,
            size: totalSize,
            shasum: digest.map { String(format: "%02x", $0) }.joined(),
            children: childNodes
        )
    }
}
