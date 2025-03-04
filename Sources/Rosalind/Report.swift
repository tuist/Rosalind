import JSONSchema
import JSONSchemaBuilder

@Schemable
public enum Report: Sendable, Codable {
    indirect case app(path: String, size: Int, shasum: String, children: [Report])
    indirect case unknown(path: String, size: Int, shasum: String, children: [Report])

    var size: Int {
        switch self {
        case let .app(_, size, _, _): return size
        case let .unknown(_, size, _, _): return size
        }
    }

    var shasum: String {
        switch self {
        case let .app(_, _, shasum, _): return shasum
        case let .unknown(_, _, shasum, _): return shasum
        }
    }
}
