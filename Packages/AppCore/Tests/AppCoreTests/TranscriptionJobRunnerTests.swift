import Foundation
import Testing
@testable import AppCore

struct TranscriptionJobRunnerTests {
    @Test
    func runsTranscriptionInIsolatedJobDirectoryAndPromotesValidatedTranscript() async throws {
        let context = try makeRunnerContext(
            behavior: .success(
                transcriptFileName: "utterance.txt",
                transcriptText: "job transcript",
                standardOutput: "ok",
                standardError: nil
            )
        )
        let staleTranscriptURL = context.paths.transcripts.appending(path: "stale.txt")
        try "stale transcript".write(to: staleTranscriptURL, atomically: true, encoding: .utf8)

        let outcome = try await context.runner.run(
            utteranceID: context.utteranceID,
            recordingArtifact: context.recordingArtifact
        )
        let result: TranscriptionJobRunResult
        switch outcome {
        case let .completed(completed):
            result = completed
        case .discarded:
            Issue.record("Expected successful transcript to complete, but it was discarded.")
            return
        }

        let jobs = try context.store.listTranscriptionJobs(utteranceID: context.utteranceID)
        let artifacts = try context.store.listTranscriptArtifacts(utteranceID: context.utteranceID)

        #expect(result.job.status == .completed)
        #expect(jobs.count == 1)
        #expect(jobs.first?.status == .completed)
        #expect(jobs.first?.outputFileNames == ["utterance.txt"])
        #expect(artifacts.count == 1)
        #expect(artifacts.first?.text == "job transcript")
        #expect(artifacts.first?.filePath != staleTranscriptURL.path(percentEncoded: false))
        #expect(FileManager.default.fileExists(atPath: artifacts[0].filePath))
        #expect(FileManager.default.fileExists(atPath: jobs[0].stdoutFilePath ?? ""))
        #expect(!FileManager.default.fileExists(atPath: context.paths.transcriptionJobDirectory(jobID: result.job.id).appending(path: "stale.txt").path(percentEncoded: false)))
    }

    @Test
    func discardsJobWhenProcessSucceedsButTranscriptOutputIsMissing() async throws {
        let context = try makeRunnerContext(
            behavior: .missingTranscript(
                createdFileName: "sidecar.log",
                standardOutput: "ok",
                standardError: nil
            )
        )

        let outcome = try await context.runner.run(
            utteranceID: context.utteranceID,
            recordingArtifact: context.recordingArtifact
        )
        let jobs = try context.store.listTranscriptionJobs(utteranceID: context.utteranceID)
        let artifacts = try context.store.listTranscriptArtifacts(utteranceID: context.utteranceID)

        switch outcome {
        case .completed:
            Issue.record("Expected missing transcript to be discarded.")
        case let .discarded(job, reason):
            #expect(job.status == .discarded)
            #expect(reason.contains("no transcript text file"))
        }

        #expect(jobs.count == 1)
        #expect(jobs.first?.status == .discarded)
        #expect(jobs.first?.outputFileNames == ["sidecar.log"])
        #expect(jobs.first?.failureMessage?.contains("no transcript text file") == true)
        #expect(artifacts.isEmpty)
    }

    @Test
    func discardsJobWhenTranscriptOutputIsEmpty() async throws {
        let context = try makeRunnerContext(
            behavior: .success(
                transcriptFileName: "utterance.txt",
                transcriptText: "   \n",
                standardOutput: "ok",
                standardError: nil
            )
        )

        let outcome = try await context.runner.run(
            utteranceID: context.utteranceID,
            recordingArtifact: context.recordingArtifact
        )
        let jobs = try context.store.listTranscriptionJobs(utteranceID: context.utteranceID)
        let artifacts = try context.store.listTranscriptArtifacts(utteranceID: context.utteranceID)

        switch outcome {
        case .completed:
            Issue.record("Expected empty transcript to be discarded.")
        case let .discarded(job, reason):
            #expect(job.status == .discarded)
            #expect(reason.contains("empty"))
        }

        #expect(jobs.count == 1)
        #expect(jobs.first?.status == .discarded)
        #expect(artifacts.isEmpty)
    }

    @Test
    func preservesProcessDiagnosticsWhenWhisperExitsNonZero() async throws {
        let context = try makeRunnerContext(
            behavior: .nonZeroExit(
                exitCode: 5,
                createdFileName: "failure.log",
                standardOutput: nil,
                standardError: "decoder failed"
            )
        )

        do {
            _ = try await context.runner.run(
                utteranceID: context.utteranceID,
                recordingArtifact: context.recordingArtifact
            )
            Issue.record("Expected nonzero Whisper exit to fail.")
        } catch {
            let jobs = try context.store.listTranscriptionJobs(utteranceID: context.utteranceID)

            #expect(jobs.count == 1)
            #expect(jobs.first?.status == .failed)
            #expect(jobs.first?.exitCode == 5)
            #expect(jobs.first?.outputFileNames == ["failure.log"])
            #expect(jobs.first?.failureMessage?.contains("decoder failed") == true)
            #expect(FileManager.default.fileExists(atPath: jobs[0].stderrFilePath ?? ""))
        }
    }
}

private struct RunnerContext {
    let paths: WorkspacePaths
    let store: SQLiteSessionStore
    let runner: TranscriptionJobRunner
    let utteranceID: UUID
    let recordingArtifact: RecordingArtifactMetadata
}

private func makeRunnerContext(
    behavior: FakeTranscriber.Behavior
) throws -> RunnerContext {
    let root = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let paths = WorkspacePaths(root: root)
    _ = try BootstrapWorkspace(fileManager: LocalFileManager()).run(paths: paths)

    let audioURL = paths.audio.appending(path: "input.wav")
    try Data("fake wav".utf8).write(to: audioURL)

    let store = SQLiteSessionStore(databaseURL: paths.database)
    try store.initialize()

    let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000001100")!
    let utteranceID = UUID(uuidString: "00000000-0000-0000-0000-000000001101")!
    let recordingArtifactID = UUID(uuidString: "00000000-0000-0000-0000-000000001102")!

    try store.insertSession(
        Session(
            id: sessionID,
            startedAt: Date(timeIntervalSince1970: 1_700_010_000),
            status: .completed
        )
    )
    try store.insertUtterance(
        Utterance(
            id: utteranceID,
            sessionID: sessionID,
            startedAt: Date(timeIntervalSince1970: 1_700_010_001),
            endedAt: Date(timeIntervalSince1970: 1_700_010_005),
            durationSeconds: 4,
            audioFilePath: audioURL.path(percentEncoded: false)
        )
    )

    let recordingArtifact = RecordingArtifactMetadata(
        id: recordingArtifactID,
        utteranceID: utteranceID,
        filePath: audioURL.path(percentEncoded: false),
        byteSize: 8,
        durationSeconds: 4,
        sampleRate: 16_000,
        channelCount: 1,
        createdAt: Date(timeIntervalSince1970: 1_700_010_006)
    )
    try store.insertRecordingArtifact(recordingArtifact)

    let runner = TranscriptionJobRunner(
        paths: paths,
        jobStore: store,
        transcriptArtifactStore: store,
        transcriber: FakeTranscriber(behavior: behavior),
        clock: SystemClock()
    )

    return RunnerContext(
        paths: paths,
        store: store,
        runner: runner,
        utteranceID: utteranceID,
        recordingArtifact: recordingArtifact
    )
}

private struct FakeTranscriber: Transcriber {
    enum Behavior: Sendable {
        case success(
            transcriptFileName: String,
            transcriptText: String,
            standardOutput: String?,
            standardError: String?
        )
        case missingTranscript(
            createdFileName: String,
            standardOutput: String?,
            standardError: String?
        )
        case nonZeroExit(
            exitCode: Int32,
            createdFileName: String,
            standardOutput: String?,
            standardError: String?
        )
    }

    let behavior: Behavior

    var modelIdentifier: String { "fake-small" }
    var language: String { "ja" }

    func makeInvocation(
        audioFilePath: String,
        outputDirectory: String
    ) -> TranscriptionInvocation {
        TranscriptionInvocation(
            command: "fake-whisper",
            arguments: [
                audioFilePath,
                "--output_dir", outputDirectory
            ]
        )
    }

    func run(invocation: TranscriptionInvocation) async throws -> TranscriptionProcessResult {
        let outputDirectory = try outputDirectory(from: invocation)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        switch behavior {
        case let .success(transcriptFileName, transcriptText, standardOutput, standardError):
            try transcriptText.write(
                to: outputDirectory.appending(path: transcriptFileName),
                atomically: true,
                encoding: .utf8
            )
            return TranscriptionProcessResult(
                exitCode: 0,
                standardOutput: standardOutput,
                standardError: standardError
            )
        case let .missingTranscript(createdFileName, standardOutput, standardError):
            try "log".write(
                to: outputDirectory.appending(path: createdFileName),
                atomically: true,
                encoding: .utf8
            )
            return TranscriptionProcessResult(
                exitCode: 0,
                standardOutput: standardOutput,
                standardError: standardError
            )
        case let .nonZeroExit(exitCode, createdFileName, standardOutput, standardError):
            try "log".write(
                to: outputDirectory.appending(path: createdFileName),
                atomically: true,
                encoding: .utf8
            )
            return TranscriptionProcessResult(
                exitCode: exitCode,
                standardOutput: standardOutput,
                standardError: standardError
            )
        }
    }

    private func outputDirectory(from invocation: TranscriptionInvocation) throws -> URL {
        guard let outputDirectoryIndex = invocation.arguments.firstIndex(of: "--output_dir"),
              invocation.arguments.indices.contains(outputDirectoryIndex + 1) else {
            throw FakeTranscriberError.outputDirectoryMissing
        }

        return URL(fileURLWithPath: invocation.arguments[outputDirectoryIndex + 1], isDirectory: true)
    }
}

private enum FakeTranscriberError: Error {
    case outputDirectoryMissing
}
