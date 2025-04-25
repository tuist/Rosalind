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
    private let commandRunner: CommandRunning
    private let jsonDecoder = JSONDecoder()

    init(commandRunner: CommandRunning = CommandRunner()) {
        self.commandRunner = commandRunner
    }

    func info(at path: AbsolutePath) async throws -> [AssetInfo] {
        guard let data = try await commandRunner.run(arguments: ["/usr/bin/xcrun", "assetutil", "--info", path.pathString])
            .concatenatedString()
            .data(using: .utf8)
        else {
            throw AssetUtilControllerError.parsingFailed(path)
        }

        return try jsonDecoder.decode([AssetInfo].self, from: data)
    }
}
