import FileSystem
import Foundation
import Path
import Testing
import ZIPFoundation

@testable import Rosalind

struct AndroidAppBundleSplitServiceTests {
    private let fileSystem = FileSystem()
    private let subject = AndroidAppBundleSplitService()

    @Test func split_keepsOnlyTheLargestABI() async throws {
        try await withAppBundle([
            "base/dex/classes.dex": .content(size: 100),
            "base/lib/arm64-v8a/libapp.so": .content(size: 4000),
            "base/lib/armeabi-v7a/libapp.so": .content(size: 3000),
            "base/lib/x86_64/libapp.so": .content(size: 2000),
        ]) { path, unzippedPath in
            let got = try await subject.split(of: path, unzippedAt: unzippedPath)

            #expect(got.entryPaths == [
                "base/dex/classes.dex",
                "base/lib/arm64-v8a/libapp.so",
            ])
        }
    }

    @Test func split_keepsOnlyTheLargestDensity() async throws {
        try await withAppBundle([
            "base/res/drawable-xxhdpi/icon.png": .content(size: 4000),
            "base/res/drawable-hdpi/icon.png": .content(size: 1000),
            "base/res/drawable-nodpi/shape.xml": .content(size: 500),
            "base/resources.pb": .resourceTable([
                ("res/drawable-xxhdpi/icon.png", 480, ""),
                ("res/drawable-hdpi/icon.png", 240, ""),
                ("res/drawable-nodpi/shape.xml", 65535, ""),
            ]),
        ]) { path, unzippedPath in
            let got = try await subject.split(of: path, unzippedAt: unzippedPath)

            #expect(got.entryPaths == [
                "base/res/drawable-xxhdpi/icon.png",
                "base/res/drawable-nodpi/shape.xml",
                "base/resources.pb",
            ])
        }
    }

    @Test func split_keepsOnlyTheLargestLocale() async throws {
        try await withAppBundle([
            "base/res/raw/terms.txt": .content(size: 100),
            "base/res/raw-fr/terms.txt": .content(size: 3000),
            "base/res/raw-de/terms.txt": .content(size: 2000),
            "base/resources.pb": .resourceTable([
                ("res/raw/terms.txt", 0, ""),
                ("res/raw-fr/terms.txt", 0, "fr"),
                ("res/raw-de/terms.txt", 0, "de"),
            ]),
        ]) { path, unzippedPath in
            let got = try await subject.split(of: path, unzippedAt: unzippedPath)

            #expect(got.entryPaths == [
                "base/res/raw/terms.txt",
                "base/res/raw-fr/terms.txt",
                "base/resources.pb",
            ])
        }
    }

    @Test func split_excludesEntriesThatAreNeverServedToADevice() async throws {
        try await withAppBundle([
            "BundleConfig.pb": .content(size: 200),
            "BUNDLE-METADATA/com.android.tools.build.libraries/dependencies.pb": .content(size: 300),
            "base/dex/classes.dex": .content(size: 100),
        ]) { path, unzippedPath in
            let got = try await subject.split(of: path, unzippedAt: unzippedPath)

            #expect(got.entryPaths == ["base/dex/classes.dex"])
        }
    }

    @Test func split_excludesOnDemandModules() async throws {
        try await withAppBundle([
            "base/dex/classes.dex": .content(size: 100),
            "payments/manifest/AndroidManifest.xml": .manifest(delivery: "install-time"),
            "payments/dex/classes.dex": .content(size: 200),
            "onboarding/manifest/AndroidManifest.xml": .manifest(delivery: "on-demand"),
            "onboarding/dex/classes.dex": .content(size: 300),
        ]) { path, unzippedPath in
            let got = try await subject.split(of: path, unzippedAt: unzippedPath)

            #expect(got.entryPaths == [
                "base/dex/classes.dex",
                "payments/manifest/AndroidManifest.xml",
                "payments/dex/classes.dex",
            ])
        }
    }

    @Test func split_keepsOnlyTheLargestAssetTargeting() async throws {
        try await withAppBundle([
            "base/assets/textures#tcf_astc/level.ktx": .content(size: 3000),
            "base/assets/textures#tcf_etc2/level.ktx": .content(size: 1000),
            "base/assets/shared/config.json": .content(size: 100),
        ]) { path, unzippedPath in
            let got = try await subject.split(of: path, unzippedAt: unzippedPath)

            #expect(got.entryPaths == [
                "base/assets/textures#tcf_astc/level.ktx",
                "base/assets/shared/config.json",
            ])
        }
    }

    @Test func split_downloadSizeIsTheCompressedSizeOfTheSelectedEntries() async throws {
        try await withAppBundle([
            "base/dex/classes.dex": .content(size: 10000),
            "base/lib/arm64-v8a/libapp.so": .content(size: 40000),
            "base/lib/armeabi-v7a/libapp.so": .content(size: 30000),
        ]) { path, unzippedPath in
            let got = try await subject.split(of: path, unzippedAt: unzippedPath)

            let archive = try Archive(url: URL(fileURLWithPath: path.pathString), accessMode: .read)
            let expected = archive
                .filter { got.entryPaths.contains($0.path) }
                .reduce(0) { $0 + Int($1.compressedSize) }

            #expect(got.downloadSize == expected)
            #expect(got.downloadSize < (try fileSize(at: path)))
        }
    }
}

// MARK: - Helpers

private enum AppBundleEntry {
    /// Compressible content of the given size.
    case content(size: Int)
    /// A `resources.pb` describing file-backed resources as `(path, density, locale)`.
    case resourceTable([(String, UInt32, String)])
    /// A module `AndroidManifest.xml` declaring the given delivery mode.
    case manifest(delivery: String)

    func data() throws -> Data {
        switch self {
        case let .content(size):
            return Data(repeating: 0xAB, count: size)
        case let .resourceTable(files):
            var entry = Aapt_Pb_Entry()
            entry.configValue = files.map { path, density, locale in
                var fileReference = Aapt_Pb_FileReference()
                fileReference.path = path
                var item = Aapt_Pb_Item()
                item.value = .file(fileReference)
                var value = Aapt_Pb_Value()
                value.value = .item(item)
                var configuration = Aapt_Pb_Configuration()
                configuration.density = density
                configuration.locale = locale
                var configValue = Aapt_Pb_ConfigValue()
                configValue.config = configuration
                configValue.value = value
                return configValue
            }
            var type = Aapt_Pb_Type()
            type.entry = [entry]
            var package = Aapt_Pb_Package()
            package.type = [type]
            var resourceTable = Aapt_Pb_ResourceTable()
            resourceTable.package = [package]
            return try resourceTable.serializedData()
        case let .manifest(delivery):
            let namespace = "http://schemas.android.com/apk/distribution"

            var deliveryMode = Aapt_Pb_XmlElement()
            deliveryMode.name = delivery
            deliveryMode.namespaceUri = namespace
            var deliveryModeNode = Aapt_Pb_XmlNode()
            deliveryModeNode.node = .element(deliveryMode)

            var deliveryElement = Aapt_Pb_XmlElement()
            deliveryElement.name = "delivery"
            deliveryElement.namespaceUri = namespace
            deliveryElement.child = [deliveryModeNode]
            var deliveryNode = Aapt_Pb_XmlNode()
            deliveryNode.node = .element(deliveryElement)

            var module = Aapt_Pb_XmlElement()
            module.name = "module"
            module.namespaceUri = namespace
            module.child = [deliveryNode]
            var moduleNode = Aapt_Pb_XmlNode()
            moduleNode.node = .element(module)

            var manifest = Aapt_Pb_XmlElement()
            manifest.name = "manifest"
            manifest.child = [moduleNode]
            var manifestNode = Aapt_Pb_XmlNode()
            manifestNode.node = .element(manifest)

            return try manifestNode.serializedData()
        }
    }
}

private func withAppBundle(
    _ entries: [String: AppBundleEntry],
    _ test: (AbsolutePath, AbsolutePath) async throws -> Void
) async throws {
    let fileSystem = FileSystem()

    try await fileSystem.runInTemporaryDirectory(prefix: "android-app-bundle-split") { temporaryDirectory in
        let contentPath = temporaryDirectory.appending(component: "content")
        for (entryPath, entry) in entries {
            let filePath = contentPath.appending(try RelativePath(validating: entryPath))
            try await fileSystem.makeDirectory(at: filePath.parentDirectory)
            try entry.data().write(to: URL(fileURLWithPath: filePath.pathString))
        }

        let path = temporaryDirectory.appending(component: "app.aab")
        let archive = try Archive(url: URL(fileURLWithPath: path.pathString), accessMode: .create)
        for entryPath in entries.keys.sorted() {
            try archive.addEntry(
                with: entryPath,
                relativeTo: URL(fileURLWithPath: contentPath.pathString),
                compressionMethod: .deflate
            )
        }

        let unzippedPath = temporaryDirectory.appending(component: "unzipped")
        try await fileSystem.unzip(path, to: unzippedPath)

        try await test(path, unzippedPath)
    }
}

private func fileSize(at path: AbsolutePath) throws -> Int {
    ((try FileManager.default.attributesOfItem(atPath: path.pathString))[.size] as? Int) ?? 0
}
