import JSONSchema
import JSONSchemaBuilder

@Schemable
public enum RosalindReport: Sendable, Codable, Equatable {
    indirect case app(path: String, size: Int, shasum: String, children: [RosalindReport])
    indirect case directory(path: String, size: Int, shasum: String, children: [RosalindReport])
    indirect case file(path: String, size: Int, shasum: String, children: [RosalindReport])

    var size: Int {
        switch self {
        case let .app(_, size, _, _): return size
        case let .directory(_, size, _, _): return size
        case let .file(_, size, _, _): return size
        }
    }

    var shasum: String {
        switch self {
        case let .app(_, _, shasum, _): return shasum
        case let .directory(_, _, shasum, _): return shasum
        case let .file(_, _, shasum, _): return shasum
        }
    }
}
