import Command
import FileSystem
import Foundation
import Path
import Rosalind
import SnapshotTesting
import Testing

struct RosalindAcceptanceTests {
    private let fileSystem = FileSystem()
    private let subject = Rosalind()

    // We run `assetutils` as part of these acceptance tests, so these won't run on Linux
    #if os(macOS)
        @Test func macos_app() async throws {
            try await withFixtureInTemporaryDirectory("macos_app") { _, fixtureDirectory in
                // When
                let got = try await subject
                    .analyzeAppBundle(
                        at: fixtureDirectory.appending(component: "App.app")
                    )

                // Then
                assertSnapshot(
                    of: got,
                    as: .rosalind()
                )
            }
        }

        @Test func ios_app() async throws {
            try await withFixtureInTemporaryDirectory("ios_app") { _, fixtureDirectory in
                // When
                let got = try await subject
                    .analyzeAppBundle(
                        at: fixtureDirectory.appending(component: "App.app")
                    )

                // Then
                assertSnapshot(
                    of: got,
                    as: .rosalind()
                )
            }
        }

        @Test func ios_app_xcarchive() async throws {
            try await withFixtureInTemporaryDirectory("ios_app") { _, fixtureDirectory in
                // When
                let got = try await subject
                    .analyzeAppBundle(
                        at: fixtureDirectory.appending(component: "App.xcarchive")
                    )

                // Then
                assertSnapshot(
                    of: got,
                    as: .rosalind()
                )
            }
        }

        @Test func ios_app_ipa() async throws {
            try await withFixtureInTemporaryDirectory("ios_app") { _, fixtureDirectory in
                // When
                let got = try await subject
                    .analyzeAppBundle(
                        at: fixtureDirectory.appending(component: "App.ipa")
                    )

                // Then
                assertSnapshot(
                    of: got,
                    as: .rosalind()
                )
            }
        }
    #endif

    @Test func android_aab() async throws {
        try await withFixtureInTemporaryDirectory("android_app") { _, fixtureDirectory in
            // When
            let got = try await subject
                .analyzeAppBundle(
                    at: fixtureDirectory.appending(component: "app.aab")
                )

            // Then
            // bundletool signs the splits it builds, and the signature it produces depends on the keystore of
            // the machine running it. On a fixture this small the signature outweighs the content, so no exact
            // size is portable across environments. `RosalindTests.aabBundle` covers that the reported size is
            // the one bundletool measured rather than the size of the `.aab` on disk.
            #expect(try #require(got.downloadSize) > 0)

            assertSnapshot(
                of: AppBundleReport(
                    bundleId: got.bundleId,
                    name: got.name,
                    type: got.type,
                    installSize: got.installSize,
                    downloadSize: nil,
                    platforms: got.platforms,
                    version: got.version,
                    artifacts: got.artifacts
                ),
                as: .rosalind()
            )
        }
    }

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
