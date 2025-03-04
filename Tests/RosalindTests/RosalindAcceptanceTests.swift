import Command
import FileSystem
import Foundation
import Path
import Rosalind
import Testing

@Suite(.serialized) struct RosalindAcceptanceTests {
    private let commandRunner = CommandRunner()
    private let fileSystem = FileSystem()
    private let subject = Rosalind()

    #if os(macOS)
        @Test func apple_ios_app() async throws {
            try await withFixtureInTemporaryDirectory("apple/ios_app") { temporaryDirectory, fixtureDirectory in
                // Given
                let xcodeprojPath = fixtureDirectory.appending(component: "App.xcodeproj")
                let derivedDataDirectory = temporaryDirectory.appending(component: "derived-data")
                try await commandRunner.run(
                    arguments: [
                        "/usr/bin/xcrun", "xcodebuild",
                        "-project", xcodeprojPath.pathString,
                        "-scheme", "App",
                        "-derivedDataPath", derivedDataDirectory.pathString,
                        "-destination", "generic/platform=iOS",
                        "-config", "Debug",
                        "-sdk", "iphoneos",
                        "clean", "build",
                        "CODE_SIGN_IDENTITY=''", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_ENTITLEMENTS=''",
                        "CODE_SIGNING_ALLOWED=NO",
                    ]
                ).awaitCompletion()

                // When
                let got = try await subject
                    .analyze(
                        path: derivedDataDirectory
                            .appending(try RelativePath(validating: "Build/Products/Debug-iphoneos/App.app"))
                    )

                // Then
                #expect(got == Report())
            }
        }
    #endif

    private func withFixtureInTemporaryDirectory(
        _ fixturePath: String,
        callback: (AbsolutePath, AbsolutePath) async throws -> Void
    ) async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            let sourceFixtureDirectory = try AbsolutePath(validating: "\(#file)").parentDirectory.parentDirectory.parentDirectory
                .appending(component: "fixtures")
                .appending(try RelativePath(validating: fixturePath))
            let targetFixtureDirectory = temporaryDirectory.appending(component: sourceFixtureDirectory.basename)
            try await fileSystem.copy(sourceFixtureDirectory, to: targetFixtureDirectory)
            try await callback(temporaryDirectory, targetFixtureDirectory)
        }
    }
}
