public struct RosalindReport: Sendable, Codable, Equatable {
    public enum ArtifactType: String, Sendable, Codable, Equatable {
        case app
        case directory
        case file
        case font
    }

    public let artifactType: ArtifactType
    public let path: String
    public let size: Int
    public let shasum: String
    public let children: [RosalindReport]?
}
