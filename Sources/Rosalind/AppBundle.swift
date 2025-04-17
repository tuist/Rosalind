import Path

struct AppBundle: Equatable {
    /// Path to the app bundle
    let path: AbsolutePath

    /// The app's Info.plist
    let infoPlist: InfoPlist

    struct InfoPlist: Decodable, Equatable {
        /// App version number (e.g. 10.3)
        let version: String

        /// Name of the app
        let name: String

        /// Bundle ID
        let bundleId: String

        /// Minimum OS version
        let minimumOSVersion: String

        /// Supported destination platforms.
        let supportedPlatforms: [String]

        init(
            version: String,
            name: String,
            bundleId: String,
            minimumOSVersion: String,
            supportedPlatforms: [String]
        ) {
            self.version = version
            self.name = name
            self.bundleId = bundleId
            self.minimumOSVersion = minimumOSVersion
            self.supportedPlatforms = supportedPlatforms
        }

        enum CodingKeys: String, CodingKey {
            case version = "CFBundleShortVersionString"
            case name = "CFBundleName"
            case bundleId = "CFBundleIdentifier"
            case minimumOSVersion = "MinimumOSVersion"
            case supportedPlatforms = "CFBundleSupportedPlatforms"
        }

        init(from decoder: any Decoder) throws {
            let container: KeyedDecodingContainer<AppBundle.InfoPlist.CodingKeys> = try decoder
                .container(keyedBy: AppBundle.InfoPlist.CodingKeys.self)
            version = try container.decode(String.self, forKey: AppBundle.InfoPlist.CodingKeys.version)
            name = try container.decode(String.self, forKey: AppBundle.InfoPlist.CodingKeys.name)
            bundleId = try container.decode(String.self, forKey: AppBundle.InfoPlist.CodingKeys.bundleId)
            minimumOSVersion = try container.decode(String.self, forKey: AppBundle.InfoPlist.CodingKeys.minimumOSVersion)
            supportedPlatforms = try container.decode([String].self, forKey: AppBundle.InfoPlist.CodingKeys.supportedPlatforms)
        }
    }
}
