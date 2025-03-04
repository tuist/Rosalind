import JSONSchema
import JSONSchemaBuilder

@Schemable
public enum Report: Sendable, Codable {
    indirect case app(path: String, size: Int, children: [Report])
    indirect case unknown(path: String, size: Int, children: [Report])

    var size: Int {
        switch self {
        case let .app(_, size, _): return size
        case let .unknown(_, size, _): return size
        }
    }
}
