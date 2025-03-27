import FileSystem
import Foundation
import Mockable
import Testing

@testable import Rosalind

struct RosalindTests {
    private let fileSystem = FileSystem()
    private let appBundleLoader = MockAppBundleLoading()
    private let shasumCalculator = MockShasumCalculating()
    private let subject: Rosalind

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
            shasumCalculator: shasumCalculator
        )
    }

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
                    size: 21,
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
            let apkPath = temporaryDirectory.appending(component: "App.apk")
            try await fileSystem.makeDirectory(at: apkPath)
            // When / Then
            await #expect(
                throws: RosalindError.notSupported(apkPath)
            ) {
                try await subject.analyzeAppBundle(at: apkPath)
            }
        }
    }
}
