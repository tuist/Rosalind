import Command
import Foundation
import Mockable
import Path

enum AssetUtilControllerError: LocalizedError {
    case parsingFailed(AbsolutePath)

    var errorDescription: String? {
        switch self {
        case let .parsingFailed(path):
            return "Parsing of \(path.pathString) failed. Make sure the file is valid."
        }
    }
}

struct AssetInfo: Decodable {
    enum CodingKeys: String, CodingKey {
        case sizeOnDisk = "SizeOnDisk"
        case sha1Digest = "SHA1Digest"
        case renditionName = "RenditionName"
    }

    // All properties are optional because [AssetInfo] is a hetergoneous array
    let sizeOnDisk: Int?
    let sha1Digest: String?
    let renditionName: String?
}

@Mockable
protocol AssetUtilControlling: Sendable {
    func info(at path: AbsolutePath) async throws -> [AssetInfo]
}

struct AssetUtilController: AssetUtilControlling {
    @TaskLocal static var poolLock: PoolLock = .init(capacity: 10)

    static func acquiringPoolLock(_ closure: () async throws -> Void) async throws {
        await poolLock.acquire()
        do {
            try await closure()
        } catch {
            await poolLock.release()
            throw error
        }
        await poolLock.release()
    }

    private let commandRunner: CommandRunning
    private let jsonDecoder = JSONDecoder()

    init(commandRunner: CommandRunning = CommandRunner()) {
        self.commandRunner = commandRunner
    }

    func info(at path: AbsolutePath) async throws -> [AssetInfo] {
        print("AssetUtilController: Queuing assetutil command for: \(path.pathString)")

        await Self.poolLock.acquire()

        guard let data = try await commandRunner.run(arguments: ["/usr/bin/xcrun", "assetutil", "--info", path.pathString])
            .concatenatedString()
            .data(using: .utf8)
        else {
            throw AssetUtilControllerError.parsingFailed(path)
        }

        await Self.poolLock.release()

        let result = try jsonDecoder.decode([AssetInfo].self, from: data)
        return result
    }
}
