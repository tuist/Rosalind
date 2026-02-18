#if os(macOS)
    import Command
    import Foundation
    import Mockable
    import Path

    enum AssetUtilControllerError: LocalizedError {
        case parsingFailed(AbsolutePath)
        case decodingFailed(path: AbsolutePath, jsonString: String, underlyingError: Error)

        var errorDescription: String? {
            switch self {
            case let .parsingFailed(path):
                return "Parsing of \(path.pathString) failed. Make sure the file is valid."
            case let .decodingFailed(path: path, jsonString: jsonString, underlyingError: error):
                return """
                Failed to decode asset info from \(path.pathString).
                Underlying error: \(error.localizedDescription)
                JSON excerpt: \(String(jsonString.prefix(200)))...
                """
            }
        }
    }

    struct AssetInfo: Decodable {
        enum CodingKeys: String, CodingKey {
            case sizeOnDisk = "SizeOnDisk"
            case sha1Digest = "SHA1Digest"
            case renditionName = "RenditionName"
        }

        let sizeOnDisk: Int?
        let sha1Digest: String?
        let renditionName: String?
    }

    @Mockable
    protocol AssetUtilControlling: Sendable {
        func info(at path: AbsolutePath) async throws -> [AssetInfo]
    }

    struct AssetUtilController: AssetUtilControlling {
        @TaskLocal static var poolLock: PoolLock = .init(capacity: 5)

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
            await Self.poolLock.acquire()

            let output = try await commandRunner.run(arguments: ["/usr/bin/xcrun", "assetutil", "--info", path.pathString])
                .concatenatedString()

            await Self.poolLock.release()

            guard let jsonStartIndex = output.firstIndex(of: "[") ?? output.firstIndex(of: "{") else {
                throw AssetUtilControllerError.parsingFailed(path)
            }

            let jsonString = String(output[jsonStartIndex...])

            guard let data = jsonString.data(using: .utf8) else {
                throw AssetUtilControllerError.parsingFailed(path)
            }

            do {
                let result = try jsonDecoder.decode([AssetInfo].self, from: data)
                return result
            } catch {
                throw AssetUtilControllerError.decodingFailed(
                    path: path,
                    jsonString: jsonString,
                    underlyingError: error
                )
            }
        }
    }
#endif
