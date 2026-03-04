import Command
@preconcurrency import FileSystem
import Foundation
import Mockable
import Path

enum AndroidBundleMetadataServiceError: LocalizedError {
    case aapt2NotFound
    case parsingFailed(AbsolutePath)
    case manifestNotFound(AbsolutePath)

    var errorDescription: String? {
        switch self {
        case .aapt2NotFound:
            return
                "aapt2 is required to read APK metadata. Install it via the Android SDK (build-tools) and ensure ANDROID_HOME or ANDROID_SDK_ROOT is set, or that aapt2 is in your PATH."
        case let .parsingFailed(path):
            return "Failed to parse Android bundle metadata from \(path.pathString)."
        case let .manifestNotFound(path):
            return "AndroidManifest.xml not found in the extracted bundle at \(path.pathString)."
        }
    }
}

struct AndroidBundleMetadata: Equatable {
    let packageName: String
    let versionName: String
    let appName: String
}

@Mockable
protocol AndroidBundleMetadataServicing: Sendable {
    func apkMetadata(at path: AbsolutePath) async throws -> AndroidBundleMetadata
    func aabMetadata(at path: AbsolutePath) async throws -> AndroidBundleMetadata
}

struct AndroidBundleMetadataService: AndroidBundleMetadataServicing {
    @TaskLocal static var poolLock: PoolLock = .init(capacity: 5)

    private let commandRunner: CommandRunning
    private let fileSystem: FileSysteming

    init(
        commandRunner: CommandRunning = CommandRunner(),
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.commandRunner = commandRunner
        self.fileSystem = fileSystem
    }

    func apkMetadata(at path: AbsolutePath) async throws -> AndroidBundleMetadata {
        let aapt2 = try await resolveAapt2Path()

        await Self.poolLock.acquire()

        let output: String
        do {
            output = try await commandRunner.run(arguments: [aapt2, "dump", "badging", path.pathString])
                .concatenatedString()
        } catch {
            await Self.poolLock.release()
            throw error
        }

        await Self.poolLock.release()

        let packageName = parseValue(from: output, pattern: "package: name='([^']+)'")
        let versionName = parseValue(from: output, pattern: "versionName='([^']+)'")
        let appName = parseValue(from: output, pattern: "application-label:'([^']+)'")

        guard let packageName else {
            throw AndroidBundleMetadataServiceError.parsingFailed(path)
        }

        return AndroidBundleMetadata(
            packageName: packageName,
            versionName: versionName ?? "1.0",
            appName: appName ?? packageName
        )
    }

    func aabMetadata(at path: AbsolutePath) async throws -> AndroidBundleMetadata {
        try await fileSystem.runInTemporaryDirectory(prefix: "aab-metadata") { temporaryDirectory in
            let unzippedPath = temporaryDirectory.appending(component: path.basename)
            try await fileSystem.unzip(path, to: unzippedPath)

            let manifestPath = unzippedPath.appending(components: "base", "manifest", "AndroidManifest.xml")
            guard try await fileSystem.exists(manifestPath) else {
                throw AndroidBundleMetadataServiceError.manifestNotFound(path)
            }

            let data = try await fileSystem.readFile(at: manifestPath)
            let xmlNode = try Aapt_Pb_XmlNode(serializedBytes: data)
            let attributes = xmlNode.element.attribute
            let packageName = attributes.first(where: { $0.name == "package" })?.value
            let versionName = attributes.first(where: { $0.name == "versionName" })?.value

            guard let packageName, !packageName.isEmpty else {
                throw AndroidBundleMetadataServiceError.parsingFailed(manifestPath)
            }

            var appName: String?
            let resourcesPath = unzippedPath.appending(components: "base", "resources.pb")
            if try await fileSystem.exists(resourcesPath) {
                let resourcesData = try await fileSystem.readFile(at: resourcesPath)
                let resourceTable = try Aapt_Pb_ResourceTable(serializedBytes: resourcesData)
                appName = resourceTable.package
                    .flatMap(\.type)
                    .flatMap(\.entry)
                    .first(where: { $0.name == "app_name" })?
                    .configValue.first?
                    .value.item.str.value
            }

            return AndroidBundleMetadata(
                packageName: packageName,
                versionName: versionName ?? "1.0",
                appName: appName ?? packageName
            )
        }
    }

    private func resolveAapt2Path() async throws -> String {
        let environment = ProcessInfo.processInfo.environment
        for envVar in ["ANDROID_HOME", "ANDROID_SDK_ROOT"] {
            guard let value = environment[envVar], !value.isEmpty else { continue }
            let buildToolsDir: AbsolutePath
            do {
                buildToolsDir = try AbsolutePath(validating: value).appending(component: "build-tools")
            } catch { continue }
            guard try await fileSystem.exists(buildToolsDir) else { continue }
            let aapt2Paths = try await fileSystem.glob(directory: buildToolsDir, include: ["*/aapt2"]).collect()
            if let aapt2 = aapt2Paths.sorted(by: { $0.pathString > $1.pathString }).first {
                return aapt2.pathString
            }
        }
        if let path = try? await commandRunner
            .run(arguments: ["/usr/bin/env", "which", "aapt2"])
            .concatenatedString()
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !path.isEmpty
        {
            return path
        }
        throw AndroidBundleMetadataServiceError.aapt2NotFound
    }

    private func parseValue(from output: String, pattern: String) -> String? {
        guard let regex = try? Regex(pattern),
              let match = try? regex.firstMatch(in: output),
              match.output.count > 1,
              let capture = match.output[1].substring
        else { return nil }
        return String(capture)
    }
}
