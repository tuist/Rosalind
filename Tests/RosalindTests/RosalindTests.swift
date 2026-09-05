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
    private let androidAppBundleSplitService = MockAndroidAppBundleSplitServicing()
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
                androidAppBundleSplitService: androidAppBundleSplitService,
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
                androidAppBundleSplitService: androidAppBundleSplitService
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
            // Given
            let aabPath = temporaryDirectory.appending(component: "app.aab")
            try await fileSystem.writeText("bundle", at: aabPath)

            // bundletool hands back the splits the reference device installs.
            let splitsPath = temporaryDirectory.appending(component: "splits")
            try await fileSystem.makeDirectory(at: splitsPath)
            try await makeSplit(
                named: "base-master",
                in: splitsPath,
                files: ["classes.dex": "dex-bytecode", "resources.arsc": "resources"]
            )
            try await makeSplit(
                named: "base-arm64_v8a",
                in: splitsPath,
                files: ["lib/arm64-v8a/libapp.so": "native-lib"]
            )

            given(androidBundleMetadataService)
                .aabMetadata(at: .any)
                .willReturn(AndroidBundleMetadata(
                    packageName: "com.test.app",
                    versionName: "2.0",
                    appName: "Test App"
                ))
            given(androidAppBundleSplitService)
                .split(of: .any, in: .any)
                .willReturn(AndroidAppBundleSplit(splitsPath: splitsPath, downloadSize: 1234))

            // When
            let got = try await subject.analyzeAppBundle(at: aabPath)

            // Then
            #expect(got.bundleId == "com.test.app")
            #expect(got.name == "Test App")
            #expect(got.type == .aab)
            #expect(got.version == "2.0")
            #expect(got.platforms == ["android"])

            // The download size is bundletool's, and the install size covers the same splits.
            #expect(got.downloadSize == 1234)
            #expect(got.installSize == 31)

            // Each split stays distinguishable in the breakdown.
            let artifactPaths = got.artifacts.map(\.path)
            #expect(artifactPaths.sorted() == ["com.test.app/base-arm64_v8a", "com.test.app/base-master"])

            let dexArtifact = got.artifacts
                .first(where: { $0.path == "com.test.app/base-master" })?
                .children?
                .first(where: { $0.path == "com.test.app/base-master/classes.dex" })
            #expect(dexArtifact?.artifactType == .binary)

            let arscArtifact = got.artifacts
                .first(where: { $0.path == "com.test.app/base-master" })?
                .children?
                .first(where: { $0.path == "com.test.app/base-master/resources.arsc" })
            #expect(arscArtifact?.artifactType == .asset)
        }
    }

    private func makeSplit(
        named name: String,
        in splitsPath: AbsolutePath,
        files: [String: String]
    ) async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: name) { contentsPath in
            for (path, contents) in files {
                let filePath = contentsPath.appending(try RelativePath(validating: path))
                try await fileSystem.makeDirectory(at: filePath.parentDirectory)
                try await fileSystem.writeText(contents, at: filePath)
            }
            try await fileSystem.zipFileOrDirectoryContent(
                at: contentsPath,
                to: splitsPath.appending(component: "\(name).apk")
            )
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
