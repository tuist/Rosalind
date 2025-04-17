// A Rosalind report of an app bundle such as `.ipa`.
public struct AppBundleReport: Sendable, Codable, Equatable {
    /// App's Bundle ID
    public let bundleId: String
    /// The app name
    public let name: String
    /// The app size in bytes
    public let size: Int
    /// List of supported platforms, such as `iPhoneSimulator`. List of possible values is the same as for `CFBundleSupportedPlatforms`.
    public let platforms: [String]
    /// The app version.
    public let version: String
    /// List of app-specific artifacts, such as fonts or binaries.
    public let artifacts: [AppBundleArtifact]
}

public struct AppBundleArtifact: Sendable, Codable, Equatable {
    public enum ArtifactType: String, Sendable, Codable, Equatable {
        /// A generic directory artifact type.
        case directory
        /// A generic file artifact type when the file is not recognized as something more specific, such as `.font`.
        case file
        /// A font artifact. A font is considered any file with one of the following extensions: `.otf`, `.ttc`, `.ttf`, `.woff`.
        case font
        /// A binary recognized by the file's header which has to be either `MH_*` or `FAT_*`.
        case binary
        /// A localization file is any file that has one of the following extensions: `.strings` or `.xcstrings`.
        case localization
    }

    /// The type of the artifact, such as `.font`.
    public let artifactType: ArtifactType
    public let path: String
    public let size: Int
    public let shasum: String
    public let children: [AppBundleArtifact]?
}
