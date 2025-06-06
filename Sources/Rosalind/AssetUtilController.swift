import Command
import Foundation
import Mockable
import Path

actor AssetUtilQueue {
    private let semaphore = AsyncSemaphore(value: 2)
    
    func execute<T>(_ operation: () async throws -> T) async throws -> T {
        await semaphore.wait()
        do {
            let result = try await operation()
            await semaphore.signal()
            return result
        } catch {
            await semaphore.signal()
            throw error
        }
    }
}

actor AsyncSemaphore {
    private var value: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []
    
    init(value: Int) {
        self.value = value
    }
    
    func wait() async {
        if value > 0 {
            value -= 1
        } else {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
    }
    
    func signal() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
        } else {
            value += 1
        }
    }
}

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
    private let queue = AssetUtilQueue()

    init(commandRunner: CommandRunning = CommandRunner()) {
        self.commandRunner = commandRunner
    }

    func info(at path: AbsolutePath) async throws -> [AssetInfo] {
        print("AssetUtilController: Queuing assetutil command for: \(path.pathString)")
        
        return try await queue.execute {
            print("AssetUtilController: Executing assetutil command for: \(path.pathString)")
            
            guard let data = try await commandRunner.run(arguments: ["/usr/bin/xcrun", "assetutil", "--info", path.pathString])
                .concatenatedString()
                .data(using: .utf8)
            else {
                print("AssetUtilController: Failed to get data from assetutil for: \(path.pathString)")
                throw AssetUtilControllerError.parsingFailed(path)
            }

            let result = try jsonDecoder.decode([AssetInfo].self, from: data)
            print("AssetUtilController: Completed assetutil command for: \(path.pathString), found \(result.count) assets")
            return result
        }
    }
}
