import Foundation
import Testing
@testable import AppCore

struct TranscriptionJobTests {
    @Test
    func transitionsFromQueuedToCompleted() {
        let createdAt = Date(timeIntervalSince1970: 1_700_001_000)
        let startedAt = Date(timeIntervalSince1970: 1_700_001_005)
        let endedAt = Date(timeIntervalSince1970: 1_700_001_020)
        let job = TranscriptionJob(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000501")!,
            utteranceID: UUID(uuidString: "00000000-0000-0000-0000-000000000502")!,
            recordingArtifactID: UUID(uuidString: "00000000-0000-0000-0000-000000000503")!,
            workingDirectoryPath: "/tmp/jobs/501",
            command: "whisper",
            arguments: ["input.wav", "--output_format", "txt"],
            modelIdentifier: "small",
            language: "ja",
            createdAt: createdAt
        )

        let running = job.started(at: startedAt)
        let completed = running.completed(
            at: endedAt,
            stdoutFilePath: "/tmp/jobs/501/stdout.txt",
            stderrFilePath: "/tmp/jobs/501/stderr.txt",
            exitCode: 0,
            outputFileNames: ["output.txt"]
        )

        #expect(running.status == .running)
        #expect(running.startedAt == startedAt)
        #expect(completed.status == .completed)
        #expect(completed.exitCode == 0)
        #expect(completed.outputFileNames == ["output.txt"])
    }

    @Test
    func transitionsToFailedWithDiagnostics() {
        let createdAt = Date(timeIntervalSince1970: 1_700_002_000)
        let startedAt = Date(timeIntervalSince1970: 1_700_002_003)
        let endedAt = Date(timeIntervalSince1970: 1_700_002_010)
        let job = TranscriptionJob(
            utteranceID: UUID(uuidString: "00000000-0000-0000-0000-000000000504")!,
            recordingArtifactID: UUID(uuidString: "00000000-0000-0000-0000-000000000505")!,
            workingDirectoryPath: "/tmp/jobs/502",
            command: "whisper",
            arguments: ["input.wav"],
            modelIdentifier: "small",
            language: "ja",
            createdAt: createdAt
        )

        let failed = job
            .started(at: startedAt)
            .failed(
                at: endedAt,
                stdoutFilePath: "/tmp/jobs/502/stdout.txt",
                stderrFilePath: "/tmp/jobs/502/stderr.txt",
                exitCode: 1,
                outputFileNames: [],
                message: "txt output was not produced"
            )

        #expect(failed.status == .failed)
        #expect(failed.stderrFilePath == "/tmp/jobs/502/stderr.txt")
        #expect(failed.failureMessage == "txt output was not produced")
    }

    @Test
    func transitionsToDiscardedWithDiagnostics() {
        let createdAt = Date(timeIntervalSince1970: 1_700_003_000)
        let startedAt = Date(timeIntervalSince1970: 1_700_003_003)
        let endedAt = Date(timeIntervalSince1970: 1_700_003_010)
        let job = TranscriptionJob(
            utteranceID: UUID(uuidString: "00000000-0000-0000-0000-000000000506")!,
            recordingArtifactID: UUID(uuidString: "00000000-0000-0000-0000-000000000507")!,
            workingDirectoryPath: "/tmp/jobs/503",
            command: "whisper",
            arguments: ["input.wav"],
            modelIdentifier: "small",
            language: "ja",
            createdAt: createdAt
        )

        let discarded = job
            .started(at: startedAt)
            .discarded(
                at: endedAt,
                stdoutFilePath: "/tmp/jobs/503/stdout.txt",
                stderrFilePath: "/tmp/jobs/503/stderr.txt",
                exitCode: 0,
                outputFileNames: [],
                message: "Transcript file was empty after validation."
            )

        #expect(discarded.status == .discarded)
        #expect(discarded.stderrFilePath == "/tmp/jobs/503/stderr.txt")
        #expect(discarded.failureMessage == "Transcript file was empty after validation.")
    }
}
