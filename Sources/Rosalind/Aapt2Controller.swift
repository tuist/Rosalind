import Command
@preconcurrency import FileSystem
import Foundation
import Mockable
import Path

enum Aapt2ControllerError: LocalizedError {
    case parsingFailed(AbsolutePath)
    case aapt2NotFound
    case manifestNotFound(AbsolutePath)

    var errorDescription: String? {
        switch self {
        case let .parsingFailed(path):
            return "Failed to parse Android bundle metadata from \(path.pathString)."
        case .aapt2NotFound:
            return "Couldn't locate the executable 'aapt2' in the environment."
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
protocol Aapt2Controlling: Sendable {
    func apkMetadata(at path: AbsolutePath) async throws -> AndroidBundleMetadata
    func aabMetadata(at path: AbsolutePath) async throws -> AndroidBundleMetadata
}

struct Aapt2Controller: Aapt2Controlling {
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
        await Self.poolLock.acquire()

        let output: String
        do {
            output = try await commandRunner.run(arguments: ["aapt2", "dump", "badging", path.pathString])
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
            throw Aapt2ControllerError.parsingFailed(path)
        }

        return AndroidBundleMetadata(
            packageName: packageName,
            versionName: versionName ?? "1.0",
            appName: appName ?? packageName
        )
    }

    func aabMetadata(at path: AbsolutePath) async throws -> AndroidBundleMetadata {
        return try await fileSystem.runInTemporaryDirectory(prefix: "aab-metadata") { temporaryDirectory in
            let unzippedPath = temporaryDirectory.appending(component: path.basename)
            try await fileSystem.unzip(path, to: unzippedPath)

            let manifestPath = unzippedPath.appending(components: "base", "manifest", "AndroidManifest.xml")
            guard try await fileSystem.exists(manifestPath) else {
                throw Aapt2ControllerError.manifestNotFound(path)
            }

            let data = try await fileSystem.readFile(at: manifestPath)
            let xmlNode = try Aapt_Pb_XmlNode(serializedBytes: data)
            let attributes = xmlNode.element.attribute
            let packageName = attributes.first(where: { $0.name == "package" })?.value
            let versionName = attributes.first(where: { $0.name == "versionName" })?.value

            guard let packageName, !packageName.isEmpty else {
                throw Aapt2ControllerError.parsingFailed(manifestPath)
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

    private func parseValue(from output: String, pattern: String) -> String? {
        guard let regex = try? Regex(pattern),
              let match = try? regex.firstMatch(in: output),
              match.output.count > 1,
              let capture = match.output[1].substring
        else { return nil }
        return String(capture)
    }
}
