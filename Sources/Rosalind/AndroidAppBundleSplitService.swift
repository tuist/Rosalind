import Command
@preconcurrency import FileSystem
import Foundation
import Mockable
import Path

enum AndroidAppBundleSplitServiceError: LocalizedError, Equatable {
    case bundletoolNotFound
    case downloadSizeParsingFailed(String)

    var errorDescription: String? {
        switch self {
        case .bundletoolNotFound:
            return """
            bundletool is required to measure the size of an .aab. Install it with `brew install bundletool`, or \
            download bundletool-all.jar from https://github.com/google/bundletool/releases and point \
            BUNDLETOOL_PATH at it.
            """
        case let .downloadSizeParsingFailed(output):
            return "Failed to read the download size from bundletool's output: \(output)"
        }
    }
}

/// The split APKs a device installs, and the size of that download.
struct AndroidAppBundleSplit: Equatable {
    /// Directory holding the split APKs the reference device installs.
    let splitsPath: AbsolutePath
    /// bundletool's estimate of the bytes the reference device downloads.
    let downloadSize: Int
}

@Mockable
protocol AndroidAppBundleSplitServicing: Sendable {
    func split(of path: AbsolutePath, in temporaryDirectory: AbsolutePath) async throws -> AndroidAppBundleSplit
}

/// An `.aab` is a publishing container that carries every ABI, screen density and language. The Play Store
/// splits it into per-device APKs, so the bytes a device downloads are a subset of the bundle. This service
/// asks bundletool, the tool the Play Store itself uses, for the splits a reference device installs.
struct AndroidAppBundleSplitService: AndroidAppBundleSplitServicing {
    /// Sizes are reported for one reference device so that they are comparable across builds and to the size
    /// the Play Store lists. It stands in for a mid-range phone: 64-bit Arm, xxhdpi, English.
    private static let referenceDeviceSpec = """
    {
      "supportedAbis": ["arm64-v8a", "armeabi-v7a"],
      "supportedLocales": ["en"],
      "screenDensity": 440,
      "sdkVersion": 30
    }
    """

    private let commandRunner: CommandRunning
    private let fileSystem: FileSysteming
    private let environment: [String: String]

    init(
        commandRunner: CommandRunning = CommandRunner(),
        fileSystem: FileSysteming = FileSystem(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.commandRunner = commandRunner
        self.fileSystem = fileSystem
        self.environment = environment
    }

    func split(of path: AbsolutePath, in temporaryDirectory: AbsolutePath) async throws -> AndroidAppBundleSplit {
        let bundletool = try await resolveBundletool()

        let deviceSpecPath = temporaryDirectory.appending(component: "device-spec.json")
        try await fileSystem.writeText(Self.referenceDeviceSpec, at: deviceSpecPath)

        let apksPath = temporaryDirectory.appending(component: "device.apks")
        _ = try await commandRunner.run(
            arguments: bundletool + [
                "build-apks",
                "--bundle=\(path.pathString)",
                "--output=\(apksPath.pathString)",
                "--device-spec=\(deviceSpecPath.pathString)",
            ]
        )
        .concatenatedString()

        let sizeOutput = try await commandRunner.run(
            arguments: bundletool + [
                "get-size", "total",
                "--apks=\(apksPath.pathString)",
                "--device-spec=\(deviceSpecPath.pathString)",
            ]
        )
        .concatenatedString()

        let splitsPath = temporaryDirectory.appending(component: "splits")
        try await fileSystem.makeDirectory(at: splitsPath)
        _ = try await commandRunner.run(
            arguments: bundletool + [
                "extract-apks",
                "--apks=\(apksPath.pathString)",
                "--output-dir=\(splitsPath.pathString)",
                "--device-spec=\(deviceSpecPath.pathString)",
            ]
        )
        .concatenatedString()

        return AndroidAppBundleSplit(
            splitsPath: splitsPath,
            downloadSize: try downloadSize(from: sizeOutput)
        )
    }

    /// `get-size total` writes a `MIN,MAX` header followed by the sizes. Both columns hold the same value when
    /// the sizes are measured against a single device.
    private func downloadSize(from output: String) throws -> Int {
        for line in output.split(whereSeparator: \.isNewline).reversed() {
            guard let size = line
                .split(separator: ",")
                .last
                .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
                .flatMap(Int.init)
            else { continue }
            return size
        }
        throw AndroidAppBundleSplitServiceError.downloadSizeParsingFailed(output)
    }

    private func resolveBundletool() async throws -> [String] {
        if let path = environment["BUNDLETOOL_PATH"], !path.isEmpty {
            return path.hasSuffix(".jar") ? ["java", "-jar", path] : [path]
        }

        if let path = try? await commandRunner
            .run(arguments: ["/usr/bin/env", "which", "bundletool"])
            .concatenatedString()
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !path.isEmpty
        {
            return [path]
        }

        throw AndroidAppBundleSplitServiceError.bundletoolNotFound
    }
}
