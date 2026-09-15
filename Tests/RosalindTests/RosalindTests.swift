import FileSystem
import Foundation
import Mockable
import Path
import Testing

@testable import Rosalind

struct RosalindTests {
    private let fileSystem = FileSystem()
    private let appBundleLoader = MockAppBundleLoading()
    private let shasumCalculator = MockShasumCalculating()
    private let androidBundleMetadataService = MockAndroidBundleMetadataServicing()
    /// The stream analyzer has no external dependencies (it inflates ZIP entries via
    /// ZIPFoundation and hashes bytes with swift-crypto), so tests exercise the real
    /// implementation against fixture ZIPs built at runtime with `zipFileOrDirectoryContent`.
    private let androidBundleStreamAnalyzer: AndroidBundleStreamAnalyzing = AndroidBundleStreamAnalyzer()
    #if os(macOS)
        private let assetUtilController = MockAssetUtilControlling()
    #endif
    private let subject: Rosalind

    #if os(macOS)
        init() {
            given(shasumCalculator)
                .calculate(filePath: .any)
                .willProduce { $0.basename }
            given(shasumCalculator)
                .calculate(childrenShasums: .any)
                .willProduce { $0.joined(separator: "-") }
            subject = Rosalind(
                fileSystem: fileSystem,
                appBundleLoader: appBundleLoader,
                shasumCalculator: shasumCalculator,
                androidBundleMetadataService: androidBundleMetadataService,
                androidBundleStreamAnalyzer: androidBundleStreamAnalyzer,
                assetUtilController: assetUtilController
            )
        }
    #else
        init() {
            given(shasumCalculator)
                .calculate(filePath: .any)
                .willProduce { $0.basename }
            given(shasumCalculator)
                .calculate(childrenShasums: .any)
                .willProduce { $0.joined(separator: "-") }
            subject = Rosalind(
                fileSystem: fileSystem,
                appBundleLoader: appBundleLoader,
                shasumCalculator: shasumCalculator,
                androidBundleMetadataService: androidBundleMetadataService,
                androidBundleStreamAnalyzer: androidBundleStreamAnalyzer
            )
        }
    #endif

    @Test func appBundleDoesNotExist() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            // Given
            let appBundlePath = temporaryDirectory.appending(component: "App.app")
            // When / Then
            await #expect(
                throws: RosalindError.notFound(appBundlePath)
            ) {
                try await subject.analyzeAppBundle(at: appBundlePath)
            }
        }
    }

    @Test func appBundle() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            // Given
            let appBundlePath = temporaryDirectory.appending(component: "App.app")
            try await fileSystem.makeDirectory(at: appBundlePath)
            try await fileSystem.writeText("font-binary", at: appBundlePath.appending(component: "Font.ttf"))
            given(appBundleLoader)
                .load(.any)
                .willReturn(
                    .test(
                        infoPlist: .test(
                            name: "App",
                            bundleId: "com.App",
                            supportedPlatforms: ["iPhoneOS"]
                        )
                    )
                )
            try await fileSystem.makeDirectory(at: appBundlePath.appending(component: "en.lproj"))
            try await fileSystem.writeText("app = App;", at: appBundlePath.appending(components: "en.lproj", "App.strings"))

            // When
            let got = try await subject.analyzeAppBundle(at: appBundlePath)

            // Then
            #expect(
                got == AppBundleReport(
                    bundleId: "com.App",
                    name: "App",
                    type: .app,
                    installSize: 21,
                    downloadSize: nil,
                    platforms: ["iPhoneOS"],
                    version: "1.0",
                    artifacts: [
                        AppBundleArtifact(
                            artifactType: .font,
                            path: "App.app/Font.ttf",
                            size: 11,
                            shasum: "Font.ttf",
                            children: nil
                        ),
                        AppBundleArtifact(
                            artifactType: .directory,
                            path: "App.app/en.lproj",
                            size: 10,
                            shasum: "App.strings",
                            children: [
                                AppBundleArtifact(
                                    artifactType: .localization,
                                    path: "App.app/en.lproj/App.strings",
                                    size: 10,
                                    shasum: "App.strings",
                                    children: nil
                                ),
                            ]
                        ),
                    ]
                )
            )
        }
    }

    @Test func appInXCArchiveDoesNotExist() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            // Given
            let xcarchivePath = temporaryDirectory.appending(component: "App.xcarchive")
            try await fileSystem.makeDirectory(at: xcarchivePath)
            // When / Then
            await #expect(
                throws: RosalindError.appNotFound(xcarchivePath)
            ) {
                try await subject.analyzeAppBundle(at: xcarchivePath)
            }
        }
    }

    @Test func appInIPADoesNotExist() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            // Given
            try await fileSystem.makeDirectory(at: temporaryDirectory.appending(component: "Payload"))
            let ipaPath = temporaryDirectory.appending(component: "App.ipa")
            try await fileSystem.zipFileOrDirectoryContent(at: temporaryDirectory.appending(component: "Payload"), to: ipaPath)
            // When / Then
            await #expect(
                throws: RosalindError.appNotFound(ipaPath)
            ) {
                try await subject.analyzeAppBundle(at: ipaPath)
            }
        }
    }

    @Test func appBundleNotSupported() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            // Given
            let dmgPath = temporaryDirectory.appending(component: "App.dmg")
            try await fileSystem.makeDirectory(at: dmgPath)
            // When / Then
            await #expect(
                throws: RosalindError.notSupported(dmgPath)
            ) {
                try await subject.analyzeAppBundle(at: dmgPath)
            }
        }
    }

    @Test func xcarchiveBundle() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            // Given
            let xcarchivePath = temporaryDirectory.appending(component: "App.xcarchive")
            let appBundlePath = xcarchivePath.appending(components: "Products", "Applications", "App.app")
            try await fileSystem.makeDirectory(at: appBundlePath)
            try await fileSystem.writeText("binary-content", at: appBundlePath.appending(component: "App"))
            try await fileSystem.writeText("config-content", at: appBundlePath.appending(component: "Info.plist"))

            given(appBundleLoader)
                .load(.any)
                .willReturn(
                    .test(
                        infoPlist: .test(
                            name: "App",
                            bundleId: "com.App",
                            supportedPlatforms: ["iPhoneOS"]
                        )
                    )
                )

            // When
            let got = try await subject.analyzeAppBundle(at: xcarchivePath)

            // Then
            #expect(
                got == AppBundleReport(
                    bundleId: "com.App",
                    name: "App",
                    type: .xcarchive,
                    installSize: 28,
                    downloadSize: nil,
                    platforms: ["iPhoneOS"],
                    version: "1.0",
                    artifacts: [
                        AppBundleArtifact(
                            artifactType: .file,
                            path: "App.app/App",
                            size: 14,
                            shasum: "App",
                            children: nil
                        ),
                        AppBundleArtifact(
                            artifactType: .file,
                            path: "App.app/Info.plist",
                            size: 14,
                            shasum: "Info.plist",
                            children: nil
                        ),
                    ]
                )
            )
            #expect(got.downloadSize == nil)
        }
    }

    @Test func ipaBundle() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            // Given
            let payloadPath = temporaryDirectory.appending(component: "ipa-contents").appending(component: "Payload")
            let appBundlePath = payloadPath.appending(component: "App.app")
            try await fileSystem.makeDirectory(at: appBundlePath)
            try await fileSystem.writeText("binary-content", at: appBundlePath.appending(component: "App"))
            try await fileSystem.writeText("font-binary", at: appBundlePath.appending(component: "Font.ttf"))

            given(appBundleLoader)
                .load(.any)
                .willReturn(
                    .test(
                        infoPlist: .test(
                            name: "App",
                            bundleId: "com.App",
                            supportedPlatforms: ["iPhoneOS"]
                        )
                    )
                )

            // Create IPA file
            let ipaPath = temporaryDirectory.appending(component: "App.ipa")
            try await fileSystem.zipFileOrDirectoryContent(
                at: temporaryDirectory.appending(component: "ipa-contents"),
                to: ipaPath
            )

            // When
            let got = try await subject.analyzeAppBundle(at: ipaPath)

            // Then
            #expect(
                got == AppBundleReport(
                    bundleId: "com.App",
                    name: "App",
                    type: .ipa,
                    installSize: 25,
                    downloadSize: got.downloadSize,
                    platforms: ["iPhoneOS"],
                    version: "1.0",
                    artifacts: [
                        AppBundleArtifact(
                            artifactType: .file,
                            path: "App.app/App",
                            size: 14,
                            shasum: "App",
                            children: nil
                        ),
                        AppBundleArtifact(
                            artifactType: .font,
                            path: "App.app/Font.ttf",
                            size: 11,
                            shasum: "Font.ttf",
                            children: nil
                        ),
                    ]
                )
            )
        }
    }

    @Test func aabBundle() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            // Given: a real AAB-shaped ZIP with a `base/` subtree. The streaming analyzer reads
            // entries straight out of it, so tests need to give it a real archive rather than a
            // stub tree on disk.
            let aabContentsPath = temporaryDirectory.appending(component: "aab-contents")
            try await fileSystem.makeDirectory(at: aabContentsPath.appending(components: "base", "dex"))
            try await fileSystem.makeDirectory(at: aabContentsPath.appending(components: "base", "res"))
            try await fileSystem.makeDirectory(at: aabContentsPath.appending(components: "base", "lib", "arm64-v8a"))
            try await fileSystem.writeText(
                "dex-bytecode",
                at: aabContentsPath.appending(components: "base", "dex", "classes.dex")
            )
            try await fileSystem.writeText(
                "resources",
                at: aabContentsPath.appending(components: "base", "res", "resources.arsc")
            )
            try await fileSystem.writeText(
                "native-lib",
                at: aabContentsPath.appending(components: "base", "lib", "arm64-v8a", "libapp.so")
            )
            // Non-`base/` entries mimic packaging metadata that must be excluded from the report.
            try await fileSystem.writeText(
                "packaging-metadata",
                at: aabContentsPath.appending(components: "BundleConfig.pb")
            )

            let aabPath = temporaryDirectory.appending(component: "app.aab")
            try await fileSystem.zipFileOrDirectoryContent(at: aabContentsPath, to: aabPath)

            given(androidBundleMetadataService)
                .aabMetadata(at: .any)
                .willReturn(AndroidBundleMetadata(
                    packageName: "com.test.app",
                    versionName: "2.0",
                    appName: "Test App"
                ))

            // When
            let got = try await subject.analyzeAppBundle(at: aabPath)

            // Then
            #expect(got.bundleId == "com.test.app")
            #expect(got.name == "Test App")
            #expect(got.type == .aab)
            #expect(got.version == "2.0")
            #expect(got.platforms == ["android"])

            // installSize is the decompressed byte total of every entry under base/, download
            // size falls back to the compressed AAB file size on disk (no bundletool).
            #expect(got.installSize == "dex-bytecode".utf8.count + "resources".utf8.count + "native-lib".utf8.count)
            #expect(got.downloadSize != nil)

            // The tree is rooted at the package name, and the `base/` prefix is stripped so the
            // report doesn't leak the AAB packaging shape.
            let artifactPaths = got.artifacts.map(\.path)
            #expect(artifactPaths.sorted() == ["com.test.app/dex", "com.test.app/lib", "com.test.app/res"])

            let dexArtifact = got.artifacts
                .first(where: { $0.path == "com.test.app/dex" })?
                .children?
                .first(where: { $0.path == "com.test.app/dex/classes.dex" })
            #expect(dexArtifact?.artifactType == .binary)

            let arscArtifact = got.artifacts
                .first(where: { $0.path == "com.test.app/res" })?
                .children?
                .first(where: { $0.path == "com.test.app/res/resources.arsc" })
            #expect(arscArtifact?.artifactType == .asset)

            // Nothing under `BundleConfig.pb` (non-base entry) should show up in the report.
            #expect(!artifactPaths.contains(where: { $0.contains("BundleConfig") }))
        }
    }

    @Test func apkBundle() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            // Given
            let apkContentsPath = temporaryDirectory.appending(component: "apk-contents")
            try await fileSystem.makeDirectory(at: apkContentsPath)
            try await fileSystem.writeText("dex-bytecode", at: apkContentsPath.appending(component: "classes.dex"))
            try await fileSystem.writeText("resources", at: apkContentsPath.appending(component: "resources.arsc"))

            let apkPath = temporaryDirectory.appending(component: "app.apk")
            try await fileSystem.zipFileOrDirectoryContent(at: apkContentsPath, to: apkPath)

            given(androidBundleMetadataService)
                .apkMetadata(at: .any)
                .willReturn(AndroidBundleMetadata(
                    packageName: "com.test.app",
                    versionName: "1.0",
                    appName: "Test App"
                ))

            // When
            let got = try await subject.analyzeAppBundle(at: apkPath)

            // Then
            #expect(got.bundleId == "com.test.app")
            #expect(got.name == "Test App")
            #expect(got.type == .apk)
            #expect(got.version == "1.0")
            #expect(got.platforms == ["android"])
            #expect(got.downloadSize != nil)

            let arscArtifact = got.artifacts
                .first(where: { $0.path.hasSuffix("resources.arsc") })
            #expect(arscArtifact?.artifactType == .asset)
        }
    }
}
