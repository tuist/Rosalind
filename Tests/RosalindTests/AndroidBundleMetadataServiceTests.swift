import Command
import FileSystem
import Foundation
import Mockable
import Path
import SwiftProtobuf
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
                arguments: .any,
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
                arguments: .any,
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
                arguments: .any,
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

    /// With pool capacity 1, a leaked lock after `dump badging` fails would block the next `apkMetadata` on `acquire`.
    @Test func apkMetadata_returnsMetadataForSecondPath_afterFirstPathCommandFails_whenPoolCapacityIsOne() async throws {
        let failingPath = try AbsolutePath(validating: "/path/to/failing.apk")
        let okPath = try AbsolutePath(validating: "/path/to/ok.apk")
        let commandError = CommandError.terminated(1, stderr: "badging failed")
        let commandRunner = MockCommandRunning()
        let subject = AndroidBundleMetadataService(
            commandRunner: commandRunner
        )
        let isolatedLock = PoolLock(capacity: 1)

        let okOutput = """
        package: name='com.example.app' versionCode='1' versionName='1.0.0'
        sdkVersion:'21'
        application-label:'My App'
        """

        try await AndroidBundleMetadataService.$poolLock.withValue(isolatedLock) {
            given(commandRunner)
                .run(
                    arguments: .any,
                    environment: .any,
                    workingDirectory: .any
                )
                .willReturn(
                    AsyncThrowingStream { continuation in
                        continuation.finish(throwing: commandError)
                    }
                )

            given(commandRunner)
                .run(
                    arguments: .any,
                    environment: .any,
                    workingDirectory: .any
                )
                .willReturn(
                    AsyncThrowingStream { continuation in
                        continuation.yield(CommandEvent.standardOutput(Array(okOutput.utf8)))
                        continuation.finish()
                    }
                )

            await #expect {
                try await subject.apkMetadata(at: failingPath)
            } throws: { error in
                if let commandError = error as? CommandError,
                   case let .terminated(code, stderr) = commandError
                {
                    return code == 1 && stderr == "badging failed"
                }
                return false
            }

            let metadata = try await subject.apkMetadata(at: okPath)

            #expect(metadata.packageName == "com.example.app")
            #expect(metadata.versionName == "1.0.0")
            #expect(metadata.appName == "My App")
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

    @Test func aabMetadata_resolvesLabelReference_whenADependencyShipsItsOwnAppNameString() async throws {
        let fileSystem = FileSystem()
        let subject = AndroidBundleMetadataService(fileSystem: fileSystem)

        try await fileSystem.runInTemporaryDirectory(prefix: "test") { temporaryDirectory in
            let aabPath = try await makeBundle(
                manifest: manifest(label: labelAttribute(resourceID: 0x7F09_0001)),
                resourceTable: resourceTable(stringEntries: [
                    stringEntry(entryID: 1, name: "brand_name", values: [(locale: "", value: "Example App")]),
                    stringEntry(entryID: 2, name: "app_name", values: [(locale: "", value: "Dependency Default")]),
                ]),
                in: temporaryDirectory,
                fileSystem: fileSystem
            )

            let metadata = try await subject.aabMetadata(at: aabPath)

            #expect(metadata.packageName == "dev.tuist.example")
            #expect(metadata.versionName == "1.0")
            #expect(metadata.appName == "Example App")
        }
    }

    @Test func aabMetadata_usesLiteralLabel_whenLabelIsNotAResourceReference() async throws {
        let fileSystem = FileSystem()
        let subject = AndroidBundleMetadataService(fileSystem: fileSystem)

        try await fileSystem.runInTemporaryDirectory(prefix: "test") { temporaryDirectory in
            let aabPath = try await makeBundle(
                manifest: manifest(label: labelAttribute(literal: "Example App")),
                resourceTable: resourceTable(stringEntries: [
                    stringEntry(entryID: 1, name: "app_name", values: [(locale: "", value: "Dependency Default")]),
                ]),
                in: temporaryDirectory,
                fileSystem: fileSystem
            )

            let metadata = try await subject.aabMetadata(at: aabPath)

            #expect(metadata.appName == "Example App")
        }
    }

    @Test func aabMetadata_usesDefaultConfigurationValue_whenLabelIsLocalized() async throws {
        let fileSystem = FileSystem()
        let subject = AndroidBundleMetadataService(fileSystem: fileSystem)

        try await fileSystem.runInTemporaryDirectory(prefix: "test") { temporaryDirectory in
            let aabPath = try await makeBundle(
                manifest: manifest(label: labelAttribute(resourceID: 0x7F09_0001)),
                resourceTable: resourceTable(stringEntries: [
                    stringEntry(
                        entryID: 1,
                        name: "brand_name",
                        values: [(locale: "fr", value: "Exemple"), (locale: "", value: "Example App")]
                    ),
                ]),
                in: temporaryDirectory,
                fileSystem: fileSystem
            )

            let metadata = try await subject.aabMetadata(at: aabPath)

            #expect(metadata.appName == "Example App")
        }
    }

    @Test func aabMetadata_fallsBackToPackageName_whenLabelIsMissing() async throws {
        let fileSystem = FileSystem()
        let subject = AndroidBundleMetadataService(fileSystem: fileSystem)

        try await fileSystem.runInTemporaryDirectory(prefix: "test") { temporaryDirectory in
            let aabPath = try await makeBundle(
                manifest: manifest(label: nil),
                resourceTable: nil,
                in: temporaryDirectory,
                fileSystem: fileSystem
            )

            let metadata = try await subject.aabMetadata(at: aabPath)

            #expect(metadata.appName == "dev.tuist.example")
        }
    }

    // MARK: - Helpers

    private func makeBundle(
        manifest: Aapt_Pb_XmlNode,
        resourceTable: Aapt_Pb_ResourceTable?,
        in temporaryDirectory: AbsolutePath,
        fileSystem: FileSysteming
    ) async throws -> AbsolutePath {
        let basePath = temporaryDirectory.appending(components: "aab-contents", "base")
        try await fileSystem.makeDirectory(at: basePath.appending(component: "manifest"))
        try manifest.serializedData()
            .write(to: URL(fileURLWithPath: basePath.appending(components: "manifest", "AndroidManifest.xml").pathString))
        if let resourceTable {
            try resourceTable.serializedData()
                .write(to: URL(fileURLWithPath: basePath.appending(component: "resources.pb").pathString))
        }

        let aabPath = temporaryDirectory.appending(component: "app.aab")
        try await fileSystem.zipFileOrDirectoryContent(at: basePath.parentDirectory, to: aabPath)
        return aabPath
    }

    private func manifest(label: Aapt_Pb_XmlAttribute?) -> Aapt_Pb_XmlNode {
        var application = Aapt_Pb_XmlElement()
        application.name = "application"
        application.attribute = [label].compactMap { $0 }

        var applicationNode = Aapt_Pb_XmlNode()
        applicationNode.element = application

        var packageAttribute = Aapt_Pb_XmlAttribute()
        packageAttribute.name = "package"
        packageAttribute.value = "dev.tuist.example"

        var versionNameAttribute = Aapt_Pb_XmlAttribute()
        versionNameAttribute.name = "versionName"
        versionNameAttribute.value = "1.0"

        var element = Aapt_Pb_XmlElement()
        element.name = "manifest"
        element.attribute = [packageAttribute, versionNameAttribute]
        element.child = [applicationNode]

        var node = Aapt_Pb_XmlNode()
        node.element = element
        return node
    }

    private func labelAttribute(resourceID: UInt32) -> Aapt_Pb_XmlAttribute {
        var reference = Aapt_Pb_Reference()
        reference.id = resourceID

        var item = Aapt_Pb_Item()
        item.ref = reference

        var attribute = labelAttribute(literal: "@string/brand_name")
        attribute.compiledItem = item
        return attribute
    }

    private func labelAttribute(literal value: String) -> Aapt_Pb_XmlAttribute {
        var attribute = Aapt_Pb_XmlAttribute()
        attribute.namespaceUri = "http://schemas.android.com/apk/res/android"
        attribute.name = "label"
        attribute.value = value
        return attribute
    }

    private func stringEntry(
        entryID: UInt32,
        name: String,
        values: [(locale: String, value: String)]
    ) -> Aapt_Pb_Entry {
        var identifier = Aapt_Pb_EntryId()
        identifier.id = entryID

        var entry = Aapt_Pb_Entry()
        entry.entryID = identifier
        entry.name = name
        entry.configValue = values.map { locale, value in
            var string = Aapt_Pb_String()
            string.value = value

            var item = Aapt_Pb_Item()
            item.str = string

            var entryValue = Aapt_Pb_Value()
            entryValue.item = item

            var configuration = Aapt_Pb_Configuration()
            configuration.locale = locale

            var configValue = Aapt_Pb_ConfigValue()
            configValue.config = configuration
            configValue.value = entryValue
            return configValue
        }
        return entry
    }

    private func resourceTable(stringEntries: [Aapt_Pb_Entry]) -> Aapt_Pb_ResourceTable {
        var typeIdentifier = Aapt_Pb_TypeId()
        typeIdentifier.id = 9

        var type = Aapt_Pb_Type()
        type.typeID = typeIdentifier
        type.name = "string"
        type.entry = stringEntries

        var packageIdentifier = Aapt_Pb_PackageId()
        packageIdentifier.id = 127

        var package = Aapt_Pb_Package()
        package.packageID = packageIdentifier
        package.packageName = "dev.tuist.example"
        package.type = [type]

        var resourceTable = Aapt_Pb_ResourceTable()
        resourceTable.package = [package]
        return resourceTable
    }

    private func fixturePath(_ relativePath: String) throws -> AbsolutePath {
        try AbsolutePath(validating: "\(#filePath)")
            .parentDirectory.parentDirectory.parentDirectory
            .appending(component: "fixtures")
            .appending(try RelativePath(validating: relativePath))
    }
}
