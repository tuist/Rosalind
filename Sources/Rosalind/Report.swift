import JSONSchema
import JSONSchemaBuilder

@Schemable
public enum Report: Sendable, Codable {
    indirect case app(path: String, children: [Report])
    indirect case unknown(path: String, children: [Report])
}
