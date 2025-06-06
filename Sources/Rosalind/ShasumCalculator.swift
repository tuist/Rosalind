import Command
import Crypto
@preconcurrency import FileSystem
import Foundation
import Mockable
import Path

@Mockable
protocol ShasumCalculating: Sendable {
    func calculate(childrenShasums: [String]) async throws -> String
    func calculate(filePath: AbsolutePath) async throws -> String
}

struct ShasumCalculator: ShasumCalculating {
    private let fileSystem: FileSysteming
    private let commandRunner: CommandRunning

    init(fileSystem: FileSysteming = FileSystem(), commandRunner: CommandRunning = CommandRunner()) {
        self.fileSystem = fileSystem
        self.commandRunner = commandRunner
    }

    func calculate(childrenShasums: [String]) async throws -> String {
        print("ShasumCalculator: Calculating directory shasum from \(childrenShasums.count) children")
        let digest = SHA256.hash(data: childrenShasums.joined().data(using: .utf8)!)
        let result = digest.compactMap { String(format: "%02x", $0) }.joined()
        print("ShasumCalculator: Directory shasum calculated: \(result)")
        return result
    }

    func calculate(filePath: Path.AbsolutePath) async throws -> String {
        print("ShasumCalculator: Starting file shasum calculation for: \(filePath.pathString)")
        
        let fileHandle = try FileHandle(forReadingFrom: URL(fileURLWithPath: filePath.pathString))
        defer { try? fileHandle.close() }

        var hasher = SHA256()
        let chunkSize = 1024 * 1024
        var totalBytesRead = 0
        var chunkCount = 0

        print("ShasumCalculator: Reading file in \(chunkSize) byte chunks")
        
        var shouldContinue = true
        while shouldContinue {
            print("ShasumCalculator: Starting read loop iteration")
            guard let data = try? fileHandle.read(upToCount: chunkSize), !data.isEmpty else {
                shouldContinue = false
                continue
            }
            hasher.update(data: data)
            totalBytesRead += data.count
            chunkCount += 1
            
            // Log progress every 10 chunks to avoid spam
            if chunkCount % 10 == 0 {
                print("ShasumCalculator: Processed \(chunkCount) chunks, \(totalBytesRead) bytes total")
            }
        }

        print("ShasumCalculator: Finished reading file, processed \(chunkCount) chunks (\(totalBytesRead) bytes)")
        print("ShasumCalculator: Finalizing hash calculation")
        
        let digest = hasher.finalize()
        let result = digest.compactMap { String(format: "%02x", $0) }.joined()
        
        print("ShasumCalculator: File shasum calculated: \(result)")
        return result
    }
}
