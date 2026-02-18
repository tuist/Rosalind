import Command
import FileSystem
import Foundation
import Mockable
import Path
import Testing

@testable import Rosalind

struct Aapt2ControllerTests {
    // MARK: - APK Metadata

    @Test func apkMetadata_parsesAllFields() async throws {
        let commandRunner = MockCommandRunning()
        let subject = Aapt2Controller(commandRunner: commandRunner)
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
        let subject = Aapt2Controller(commandRunner: commandRunner)
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
        let subject = Aapt2Controller(commandRunner: commandRunner)
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
            if let e = error as? Aapt2ControllerError, case .parsingFailed = e { return true }
            return false
        }
    }

    // MARK: - AAB Metadata

    @Test func aabMetadata_parsesManifestAndResources() async throws {
        let fileSystem = FileSystem()
        let subject = Aapt2Controller(fileSystem: fileSystem)

        try await fileSystem.runInTemporaryDirectory(prefix: "test") { temporaryDirectory in
            let aabPath = try await createTestAAB(
                in: temporaryDirectory,
                fileSystem: fileSystem,
                packageName: "com.test.app",
                versionName: "2.0",
                appName: "Test App"
            )

            let metadata = try await subject.aabMetadata(at: aabPath)

            #expect(metadata.packageName == "com.test.app")
            #expect(metadata.versionName == "2.0")
            #expect(metadata.appName == "Test App")
        }
    }

    @Test func aabMetadata_throws_whenManifestNotFound() async throws {
        let fileSystem = FileSystem()
        let subject = Aapt2Controller(fileSystem: fileSystem)

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
                if let e = error as? Aapt2ControllerError, case .manifestNotFound = e { return true }
                return false
            }
        }
    }

    @Test func aabMetadata_usesPackageName_whenResourcesMissing() async throws {
        let fileSystem = FileSystem()
        let subject = Aapt2Controller(fileSystem: fileSystem)

        try await fileSystem.runInTemporaryDirectory(prefix: "test") { temporaryDirectory in
            let aabPath = try await createTestAAB(
                in: temporaryDirectory,
                fileSystem: fileSystem,
                packageName: "com.test.app",
                versionName: "1.0",
                appName: nil
            )

            let metadata = try await subject.aabMetadata(at: aabPath)

            #expect(metadata.packageName == "com.test.app")
            #expect(metadata.versionName == "1.0")
            #expect(metadata.appName == "com.test.app")
        }
    }

    // MARK: - Helpers

    private func createTestAAB(
        in temporaryDirectory: AbsolutePath,
        fileSystem: FileSysteming,
        packageName: String,
        versionName: String,
        appName: String?
    ) async throws -> AbsolutePath {
        let aabContentsPath = temporaryDirectory.appending(component: "aab-contents")
        let basePath = aabContentsPath.appending(component: "base")
        let manifestDir = basePath.appending(component: "manifest")
        try await fileSystem.makeDirectory(at: manifestDir)

        var element = AaptXmlElement()
        element.name = "manifest"
        var packageAttr = AaptXmlAttribute()
        packageAttr.name = "package"
        packageAttr.value = packageName
        var versionAttr = AaptXmlAttribute()
        versionAttr.name = "versionName"
        versionAttr.value = versionName
        element.attributes = [packageAttr, versionAttr]
        var xmlNode = AaptXmlNode()
        xmlNode.element = element

        let manifestData: Data = try xmlNode.serializedBytes()
        try manifestData.write(
            to: URL(fileURLWithPath: manifestDir.appending(component: "AndroidManifest.xml").pathString)
        )

        if let appName {
            var resourcesData = Data()
            resourcesData.append(0x0A)
            resourcesData.append(contentsOf: "app_name".utf8)
            resourcesData.append(0x00)
            resourcesData.append(UInt8(appName.utf8.count))
            resourcesData.append(contentsOf: appName.utf8)
            try resourcesData.write(
                to: URL(fileURLWithPath: basePath.appending(component: "resources.pb").pathString)
            )
        }

        let aabPath = temporaryDirectory.appending(component: "app.aab")
        try await fileSystem.zipFileOrDirectoryContent(at: aabContentsPath, to: aabPath)
        return aabPath
    }

}
