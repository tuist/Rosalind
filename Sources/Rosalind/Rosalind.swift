import Command
import CryptoKit
import FileSystem
import Foundation
import Path

enum RosalindError: LocalizedError {
    case notFound(AbsolutePath)

    var errorDescription: String? {
        switch self {
        case let .notFound(path):
            return "File not found at path \(path.pathString)"
        }
    }
}

public protocol Rosalindable {
    func analyze(path: AbsolutePath) async throws -> Report
}

public struct Rosalind: Rosalindable {
    let fileSystem: FileSysteming
    let commandRunner: CommandRunning

    public init() {
        self.init(fileSystem: FileSystem(), commandRunner: CommandRunner())
    }

    init(
        fileSystem: FileSysteming,
        commandRunner: CommandRunning
    ) {
        self.fileSystem = fileSystem
        self.commandRunner = commandRunner
    }

    public func analyze(path: AbsolutePath) async throws -> Report {
        if !(try await fileSystem.exists(path)) { throw RosalindError.notFound(path) }
        return try await traverse(path: path, normalizingPath: path)
    }

    public func traverse(path: AbsolutePath, normalizingPath: AbsolutePath) async throws -> Report {
        let children: [Report] = try await (try await fileSystem.glob(directory: path, include: ["*"]).collect()).sorted()
            .asyncMap { try await traverse(path: $0, normalizingPath: normalizingPath) }
        let size = try await size(path: path, children: children)
        let shasum = try await shasum(path: path, children: children)
        if path.extension == "app" {
            return .app(path: path.relative(to: normalizingPath).pathString, size: size, shasum: shasum, children: children)
        } else {
            return .unknown(path: path.relative(to: normalizingPath).pathString, size: size, shasum: shasum, children: children)
        }
    }

    private func shasum(path: AbsolutePath, children: [Report]) async throws -> String {
        if try await fileSystem.exists(path, isDirectory: true) { // Directory
            let sortedHashes = children.map(\.shasum).sorted()
            let combinedString = sortedHashes.joined()
            guard let data = combinedString.data(using: .utf8) else {
                return ""
            }
            let digest = SHA256.hash(data: data)
            return digest.compactMap { String(format: "%02x", $0) }.joined()
        } else {
            return String(
                (
                    try await commandRunner.run(arguments: ["/usr/bin/shasum", "-a", "256", path.pathString])
                        .concatenatedString(including: Set([.standardOutput]))
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                    .split(separator: " ")[0]
            )
        }
    }

    private func size(path: AbsolutePath, children: [Report]) async throws -> Int {
        var size = 0
        if try await fileSystem.exists(path, isDirectory: true) { // Directory
            size = children.reduce(Int(0)) { acc, next in
                var acc = acc
                acc += next.size
                return acc
            }
        } else {
            size = ((try FileManager.default.attributesOfItem(atPath: path.pathString))[.size] as? Int) ?? 0
        }
        return size
    }
}
