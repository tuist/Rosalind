import Command
import FileSystem
import Foundation
import Mockable
import Path
import Testing

@testable import Rosalind

struct AndroidAppBundleSplitServiceTests {
    private let fileSystem = FileSystem()
    private let commandRunner = MockCommandRunning()

    @Test func split_throwsBundletoolNotFound_whenBundletoolIsNotInstalled() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: "aab-split") { temporaryDirectory in
            let subject = AndroidAppBundleSplitService(
                commandRunner: commandRunner,
                fileSystem: fileSystem,
                environment: [:]
            )
            stub { _ in "" }

            await #expect(throws: AndroidAppBundleSplitServiceError.bundletoolNotFound) {
                try await subject.split(
                    of: try AbsolutePath(validating: "/path/to/app.aab"),
                    in: temporaryDirectory
                )
            }
        }
    }

    @Test func split_returnsTheDownloadSizeReportedByBundletool() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: "aab-split") { temporaryDirectory in
            let subject = AndroidAppBundleSplitService(
                commandRunner: commandRunner,
                fileSystem: fileSystem,
                environment: ["BUNDLETOOL_PATH": "/opt/bundletool.jar"]
            )
            // bundletool writes CRLF line endings.
            stub { arguments in
                arguments.contains("get-size") ? "MIN,MAX\r\n98219538,98219538\r\n" : ""
            }

            let got = try await subject.split(
                of: try AbsolutePath(validating: "/path/to/app.aab"),
                in: temporaryDirectory
            )

            #expect(got.downloadSize == 98_219_538)
            #expect(got.splitsPath == temporaryDirectory.appending(component: "splits"))
        }
    }

    @Test func split_measuresTheSplitsOfASingleReferenceDevice() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: "aab-split") { temporaryDirectory in
            let subject = AndroidAppBundleSplitService(
                commandRunner: commandRunner,
                fileSystem: fileSystem,
                environment: ["BUNDLETOOL_PATH": "/opt/bundletool.jar"]
            )
            let invocations = Invocations()
            stub { arguments in
                await invocations.record(arguments)
                return arguments.contains("get-size") ? "MIN,MAX\n1000,1000\n" : ""
            }

            _ = try await subject.split(
                of: try AbsolutePath(validating: "/path/to/app.aab"),
                in: temporaryDirectory
            )

            let deviceSpecPath = temporaryDirectory.appending(component: "device-spec.json")
            let deviceSpec = try await fileSystem.readTextFile(at: deviceSpecPath)
            #expect(deviceSpec.contains("arm64-v8a"))
            #expect(deviceSpec.contains("\"en\""))
            #expect(deviceSpec.contains("440"))

            // Every bundletool call is scoped to that one device, so the sizes describe a single install.
            let recorded = await invocations.arguments
            #expect(recorded.count == 3)
            for arguments in recorded {
                #expect(arguments.first == "java")
                #expect(arguments.contains("--device-spec=\(deviceSpecPath.pathString)"))
            }
            #expect(recorded.contains { $0.contains("build-apks") })
            #expect(recorded.contains { $0.contains("get-size") })
            #expect(recorded.contains { $0.contains("extract-apks") })
        }
    }

    @Test func split_throwsWhenTheDownloadSizeCannotBeRead() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: "aab-split") { temporaryDirectory in
            let subject = AndroidAppBundleSplitService(
                commandRunner: commandRunner,
                fileSystem: fileSystem,
                environment: ["BUNDLETOOL_PATH": "/opt/bundletool.jar"]
            )
            stub { _ in "no sizes here\n" }

            await #expect(throws: AndroidAppBundleSplitServiceError.downloadSizeParsingFailed("no sizes here\n")) {
                try await subject.split(
                    of: try AbsolutePath(validating: "/path/to/app.aab"),
                    in: temporaryDirectory
                )
            }
        }
    }

    private func stub(_ output: @escaping @Sendable ([String]) async -> String) {
        given(commandRunner)
            .run(arguments: .any, environment: .any, workingDirectory: .any)
            .willProduce { arguments, _, _ in
                AsyncThrowingStream { continuation in
                    Task {
                        continuation.yield(CommandEvent.standardOutput(Array(await output(arguments).utf8)))
                        continuation.finish()
                    }
                }
            }
    }
}

private actor Invocations {
    private(set) var arguments: [[String]] = []

    func record(_ arguments: [String]) {
        self.arguments.append(arguments)
    }
}
