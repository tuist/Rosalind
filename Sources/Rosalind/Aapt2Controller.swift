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
            let packageName = findProtobufString(after: "package", in: data)
            let versionName = findProtobufString(after: "versionName", in: data)

            guard let packageName else {
                throw Aapt2ControllerError.parsingFailed(manifestPath)
            }

            var appName: String?
            let resourcesPath = unzippedPath.appending(components: "base", "resources.pb")
            if try await fileSystem.exists(resourcesPath) {
                let resourcesData = try await fileSystem.readFile(at: resourcesPath)
                appName = findProtobufString(after: "app_name", in: resourcesData, preferLongest: true)
            }

            return AndroidBundleMetadata(
                packageName: packageName,
                versionName: versionName ?? "1.0",
                appName: appName ?? packageName
            )
        }
    }

    private func findProtobufString(after key: String, in data: Data, preferLongest: Bool = false) -> String? {
        guard let keyData = key.data(using: .utf8) else { return nil }
        let bytes = [UInt8](data)
        let keyBytes = [UInt8](keyData)

        for i in 0 ..< bytes.count - keyBytes.count {
            guard bytes[i ..< i + keyBytes.count].elementsEqual(keyBytes) else { continue }
            let afterKey = i + keyBytes.count
            var best: String?
            for j in afterKey ..< min(afterKey + 20, bytes.count) {
                let length = Int(bytes[j])
                if length > 0, length < 200, j + 1 + length <= bytes.count {
                    let candidate = Data(bytes[j + 1 ..< j + 1 + length])
                    if let str = String(data: candidate, encoding: .utf8),
                       str.allSatisfy({ $0.isASCII && !$0.isNewline && $0 != "\0" }),
                       str.count > 1
                    {
                        if !preferLongest { return str }
                        if str.count > (best?.count ?? 0) { best = str }
                    }
                }
            }
            if let best { return best }
        }
        return nil
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
