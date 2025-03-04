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

    public init() {
        self.init(fileSystem: FileSystem())
    }

    init(fileSystem: FileSysteming) {
        self.fileSystem = fileSystem
    }

    public func analyze(path _: AbsolutePath) async throws -> Report {
        Report()
    }
}
