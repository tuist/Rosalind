public struct AppReport: Sendable, Codable, Equatable {
    public let bundleId: String
    public let name: String
    public let size: Int
    public let platform: String
    public let appVersion: String
    public let artifacts: [Artifact]
}

public struct Artifact: Sendable, Codable, Equatable {
    public enum ArtifactType: String, Sendable, Codable, Equatable {
        case app
        case directory
        case file
        case font
        case binary
    }

    public let artifactType: ArtifactType
    public let path: String
    public let size: Int
    public let shasum: String
    public let children: [Artifact]?
}
