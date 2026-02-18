import Command
import FileSystem
import Foundation
import Mockable
import Path
import Testing

@testable import Rosalind

struct AndroidBundleMetadataServiceTests {
    // MARK: - APK Metadata

    @Test func apkMetadata_parsesAllFields() async throws {
        let commandRunner = MockCommandRunning()
        let subject = AndroidBundleMetadataService(commandRunner: commandRunner)
        let path = try AbsolutePath(validating: "/path/to/app.apk")

        let output = """
        package: name='com.example.app' versionCode='1' versionName='1.0.0'
        sdkVersion:'21'
        targetSdkVersion:'34'
        application-label:'My App'
        application-label-en:'My App'
        """

        given(commandRunner)
            .run(
                arguments: .value(["aapt2", "dump", "badging", path.pathString]),
                environment: .any,
                workingDirectory: .any
            )
            .willReturn(
                AsyncThrowingStream { continuation in
                    continuation.yield(CommandEvent.standardOutput(Array(output.utf8)))
                    continuation.finish()
                }
            )

        let metadata = try await subject.apkMetadata(at: path)

        #expect(metadata.packageName == "com.example.app")
        #expect(metadata.versionName == "1.0.0")
        #expect(metadata.appName == "My App")
    }

    @Test func apkMetadata_usesDefaults_whenOptionalFieldsMissing() async throws {
        let commandRunner = MockCommandRunning()
        let subject = AndroidBundleMetadataService(commandRunner: commandRunner)
        let path = try AbsolutePath(validating: "/path/to/app.apk")

        let output = "package: name='com.example.app' versionCode='1'\n"

        given(commandRunner)
            .run(
                arguments: .value(["aapt2", "dump", "badging", path.pathString]),
                environment: .any,
                workingDirectory: .any
            )
            .willReturn(
                AsyncThrowingStream { continuation in
                    continuation.yield(CommandEvent.standardOutput(Array(output.utf8)))
                    continuation.finish()
                }
            )

        let metadata = try await subject.apkMetadata(at: path)

        #expect(metadata.packageName == "com.example.app")
        #expect(metadata.versionName == "1.0")
        #expect(metadata.appName == "com.example.app")
    }

    @Test func apkMetadata_throws_whenPackageNameMissing() async throws {
        let commandRunner = MockCommandRunning()
        let subject = AndroidBundleMetadataService(commandRunner: commandRunner)
        let path = try AbsolutePath(validating: "/path/to/app.apk")

        let output = "sdkVersion:'21'\ntargetSdkVersion:'34'\n"

        given(commandRunner)
            .run(
                arguments: .value(["aapt2", "dump", "badging", path.pathString]),
                environment: .any,
                workingDirectory: .any
            )
            .willReturn(
                AsyncThrowingStream { continuation in
                    continuation.yield(CommandEvent.standardOutput(Array(output.utf8)))
                    continuation.finish()
                }
            )

        await #expect {
            try await subject.apkMetadata(at: path)
        } throws: { error in
            if let e = error as? AndroidBundleMetadataServiceError, case .parsingFailed = e { return true }
            return false
        }
    }

    // MARK: - AAB Metadata

    @Test func aabMetadata_parsesManifestAndResources() async throws {
        let fileSystem = FileSystem()
        let subject = AndroidBundleMetadataService(fileSystem: fileSystem)
        let aabPath = try fixturePath("android_app/app.aab")

        let metadata = try await subject.aabMetadata(at: aabPath)

        #expect(metadata.packageName == "dev.tuist.example")
        #expect(metadata.versionName == "1.0")
        #expect(metadata.appName == "Simple Android App")
    }

    @Test func aabMetadata_throws_whenManifestNotFound() async throws {
        let fileSystem = FileSystem()
        let subject = AndroidBundleMetadataService(fileSystem: fileSystem)

        try await fileSystem.runInTemporaryDirectory(prefix: "test") { temporaryDirectory in
            let aabContentsPath = temporaryDirectory.appending(component: "aab-contents")
            let basePath = aabContentsPath.appending(component: "base")
            try await fileSystem.makeDirectory(at: basePath)
            try await fileSystem.writeText("content", at: basePath.appending(component: "dummy.txt"))

            let aabPath = temporaryDirectory.appending(component: "app.aab")
            try await fileSystem.zipFileOrDirectoryContent(at: aabContentsPath, to: aabPath)

            await #expect {
                try await subject.aabMetadata(at: aabPath)
            } throws: { error in
                if let e = error as? AndroidBundleMetadataServiceError, case .manifestNotFound = e { return true }
                return false
            }
        }
    }

    // MARK: - Helpers

    private func fixturePath(_ relativePath: String) throws -> AbsolutePath {
        try AbsolutePath(validating: "\(#filePath)")
            .parentDirectory.parentDirectory.parentDirectory
            .appending(component: "fixtures")
            .appending(try RelativePath(validating: relativePath))
    }
}
