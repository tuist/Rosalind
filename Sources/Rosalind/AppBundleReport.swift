// A Rosalind report of an app bundle such as `.ipa`.
public struct AppBundleReport: Sendable, Codable, Equatable {
    public enum BundleType: String, Sendable, Codable, Equatable {
        case app
        case ipa
        case xcarchive
    }

    /// App's Bundle ID
    public let bundleId: String
    /// The app name
    public let name: String
    /// The type of the bundle
    public let type: BundleType
    /// The app install size in bytes. This is the size of the `.app` bundle and represents the value that will be installed on
    /// the device.
    public let installSize: Int
    /// The app download size in bytes. Only available for `.ipa`. It represents the compressed size that the users will end up
    /// downloading over the network.
    public let downloadSize: Int?
    /// List of supported platforms, such as `iPhoneSimulator`. List of possible values is the same as for
    /// `CFBundleSupportedPlatforms`.
    public let platforms: [String]
    /// The app version.
    public let version: String
    /// List of app-specific artifacts, such as fonts or binaries.
    public let artifacts: [AppBundleArtifact]

    public init(
        bundleId: String,
        name: String,
        type: BundleType,
        installSize: Int,
        downloadSize: Int?,
        platforms: [String],
        version: String,
        artifacts: [AppBundleArtifact]
    ) {
        self.bundleId = bundleId
        self.name = name
        self.type = type
        self.installSize = installSize
        self.downloadSize = downloadSize
        self.platforms = platforms
        self.version = version
        self.artifacts = artifacts
    }
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
        /// An asset – either a `.car` file or a file inside the `.car` obtained using the `assetutils`.
        case asset
    }

    /// The type of the artifact, such as `.font`.
    public let artifactType: ArtifactType
    public let path: String
    public let size: Int
    public let shasum: String
    public let children: [AppBundleArtifact]?
}
