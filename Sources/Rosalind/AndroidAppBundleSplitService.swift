@preconcurrency import FileSystem
import Foundation
import Mockable
import Path
import ZIPFoundation

/// The entries of an `.aab` that a single device downloads, along with the size of that download.
struct AndroidAppBundleSplit: Equatable {
    /// Paths, relative to the root of the `.aab`, of the entries a single device downloads.
    let entryPaths: Set<String>
    /// The sum of the compressed sizes of `entryPaths`.
    let downloadSize: Int
}

@Mockable
protocol AndroidAppBundleSplitServicing: Sendable {
    func split(of path: AbsolutePath, unzippedAt unzippedPath: AbsolutePath) async throws -> AndroidAppBundleSplit
    func collect(
        _ split: AndroidAppBundleSplit,
        from unzippedPath: AbsolutePath,
        into contentPath: AbsolutePath
    ) async throws
}

/// An `.aab` is a publishing container that carries every ABI, screen density and language. The Play Store
/// splits it into per-device APKs, so the bytes a device downloads are a subset of the bundle. This service
/// resolves that subset the way `bundletool` does: entries that every device receives, plus the largest
/// variant of each split dimension.
struct AndroidAppBundleSplitService: AndroidAppBundleSplitServicing {
    private static let distributionNamespaceURI = "http://schemas.android.com/apk/distribution"
    private static let baseModule = "base"
    private static let bundleMetadataDirectory = "BUNDLE-METADATA"

    /// `anydpi` and `nodpi` resources are density-agnostic, so they are served to every device.
    private static let densityAgnosticDensities: Set<UInt32> = [65534, 65535]

    private enum SplitDimension: Hashable {
        case abi
        case density
        case locale
        /// Asset packs are targeted with `#key_value` directory suffixes, such as `#tcf_astc`.
        case asset(String)
    }

    private let fileSystem: FileSysteming

    init(fileSystem: FileSysteming = FileSystem()) {
        self.fileSystem = fileSystem
    }

    func split(of path: AbsolutePath, unzippedAt unzippedPath: AbsolutePath) async throws -> AndroidAppBundleSplit {
        let entries = try compressedSizes(of: path)
        let modules = try await installedModules(in: unzippedPath)
        let configurations = try await resourceConfigurations(in: unzippedPath, modules: modules)

        var common: [String: Int] = [:]
        var dimensions: [SplitDimension: [String: [String: Int]]] = [:]

        for (entryPath, compressedSize) in entries {
            guard let module = entryPath.split(separator: "/").first.map(String.init),
                  module != Self.bundleMetadataDirectory,
                  modules.contains(module)
            else { continue }

            if let (dimension, variant) = dimension(of: entryPath, configurations: configurations) {
                dimensions[dimension, default: [:]][variant, default: [:]][entryPath] = compressedSize
            } else {
                common[entryPath] = compressedSize
            }
        }

        var entryPaths = Set(common.keys)
        var downloadSize = common.values.reduce(0, +)

        for variants in dimensions.values {
            let totals = variants.mapValues { $0.values.reduce(0, +) }
            guard let largest = totals.max(by: { ($0.value, $0.key) < ($1.value, $1.key) })?.key,
                  let entries = variants[largest]
            else { continue }
            entryPaths.formUnion(entries.keys)
            downloadSize += totals[largest] ?? 0
        }

        return AndroidAppBundleSplit(entryPaths: entryPaths, downloadSize: downloadSize)
    }

    /// Gathers the entries a device downloads into a single tree rooted at `contentPath`, so that the install
    /// size and the artifact breakdown describe the same bytes as the download size. The base module is
    /// flattened into the root and every other installed module is nested under its own name.
    func collect(
        _ split: AndroidAppBundleSplit,
        from unzippedPath: AbsolutePath,
        into contentPath: AbsolutePath
    ) async throws {
        try await fileSystem.makeDirectory(at: contentPath)

        for entryPath in split.entryPaths.sorted() {
            let relativePath = try RelativePath(validating: entryPath)
            let source = unzippedPath.appending(relativePath)
            guard try await fileSystem.exists(source) else { continue }

            let components = relativePath.components.first == Self.baseModule
                ? Array(relativePath.components.dropFirst())
                : relativePath.components
            guard !components.isEmpty else { continue }

            let destination = contentPath.appending(try RelativePath(validating: components.joined(separator: "/")))
            try await fileSystem.makeDirectory(at: destination.parentDirectory)
            try await fileSystem.move(from: source, to: destination)
        }
    }

    private func compressedSizes(of path: AbsolutePath) throws -> [String: Int] {
        let archive = try Archive(url: URL(fileURLWithPath: path.pathString), accessMode: .read)
        return archive.reduce(into: [:]) { sizes, entry in
            guard entry.type == .file else { return }
            sizes[entry.path] = Int(entry.compressedSize)
        }
    }

    /// The modules a device downloads on the first install: the base module, plus every feature module that
    /// isn't delivered on demand.
    private func installedModules(in unzippedPath: AbsolutePath) async throws -> Set<String> {
        var modules: Set<String> = []

        for directory in try await fileSystem.glob(directory: unzippedPath, include: ["*"]).collect() {
            guard try await fileSystem.exists(directory, isDirectory: true) else { continue }
            let module = directory.basename
            guard module != Self.bundleMetadataDirectory else { continue }

            if module == Self.baseModule {
                modules.insert(module)
                continue
            }

            let manifestPath = directory.appending(components: "manifest", "AndroidManifest.xml")
            guard try await fileSystem.exists(manifestPath) else { continue }
            let manifest = try Aapt_Pb_XmlNode(serializedBytes: try await fileSystem.readFile(at: manifestPath))
            if isInstalledOnFirstDownload(manifest) {
                modules.insert(module)
            }
        }

        return modules
    }

    private func isInstalledOnFirstDownload(_ manifest: Aapt_Pb_XmlNode) -> Bool {
        guard let module = manifest.element.child
            .map(\.element)
            .first(where: { $0.name == "module" && $0.namespaceUri == Self.distributionNamespaceURI })
        else { return true }

        if module.attribute.contains(where: {
            $0.name == "onDemand" && $0.namespaceUri == Self.distributionNamespaceURI && $0.value == "true"
        }) {
            return false
        }

        guard let delivery = module.child
            .map(\.element)
            .first(where: { $0.name == "delivery" && $0.namespaceUri == Self.distributionNamespaceURI })
        else { return true }

        return delivery.child
            .map(\.element)
            .contains { $0.name == "install-time" && $0.namespaceUri == Self.distributionNamespaceURI }
    }

    /// The targeting of every file-backed resource, keyed by its path within the `.aab`. `resources.pb` records
    /// density and locale as structured fields, so the targeting doesn't have to be recovered from directory
    /// name qualifiers.
    private func resourceConfigurations(
        in unzippedPath: AbsolutePath,
        modules: Set<String>
    ) async throws -> [String: Aapt_Pb_Configuration] {
        var configurations: [String: Aapt_Pb_Configuration] = [:]

        for module in modules.sorted() {
            let resourcesPath = unzippedPath.appending(components: module, "resources.pb")
            guard try await fileSystem.exists(resourcesPath) else { continue }
            let resourceTable = try Aapt_Pb_ResourceTable(
                serializedBytes: try await fileSystem.readFile(at: resourcesPath)
            )

            for package in resourceTable.package {
                for type in package.type {
                    for entry in type.entry {
                        for configValue in entry.configValue {
                            guard case let .file(file) = configValue.value.item.value, !file.path.isEmpty
                            else { continue }
                            configurations["\(module)/\(file.path)"] = configValue.config
                        }
                    }
                }
            }
        }

        return configurations
    }

    private func dimension(
        of entryPath: String,
        configurations: [String: Aapt_Pb_Configuration]
    ) -> (SplitDimension, String)? {
        let components = entryPath.split(separator: "/").map(String.init)
        guard components.count > 2 else { return nil }

        switch components[1] {
        case "lib":
            return (.abi, components[2])
        case "res":
            guard let configuration = configurations[entryPath] else { return nil }
            if !configuration.locale.isEmpty {
                return (.locale, configuration.locale)
            }
            if configuration.density != 0, !Self.densityAgnosticDensities.contains(configuration.density) {
                return (.density, String(configuration.density))
            }
            return nil
        case "assets":
            for component in components.dropFirst(2) {
                guard let targeting = component.split(separator: "#").dropFirst().first,
                      let separator = targeting.firstIndex(of: "_")
                else { continue }
                return (
                    .asset(String(targeting[targeting.startIndex ..< separator])),
                    String(targeting[targeting.index(after: separator)...])
                )
            }
            return nil
        default:
            return nil
        }
    }
}
