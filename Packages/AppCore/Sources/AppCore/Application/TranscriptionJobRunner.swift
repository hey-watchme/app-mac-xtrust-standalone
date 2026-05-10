import Foundation

public struct TranscriptionJobRunResult: Sendable {
    public let job: TranscriptionJob
    public let transcriptArtifact: TranscriptArtifactMetadata

    public init(job: TranscriptionJob, transcriptArtifact: TranscriptArtifactMetadata) {
        self.job = job
        self.transcriptArtifact = transcriptArtifact
    }
}

public enum TranscriptionJobRunOutcome: Sendable {
    case completed(TranscriptionJobRunResult)
    case discarded(job: TranscriptionJob, reason: String)
}

public struct TranscriptionJobRunner: Sendable {
    private let paths: WorkspacePaths
    private let jobStore: any TranscriptionJobStore
    private let transcriptArtifactStore: any TranscriptArtifactStore
    private let transcriber: any Transcriber
    private let clock: any Clock

    public init(
        paths: WorkspacePaths,
        jobStore: any TranscriptionJobStore,
        transcriptArtifactStore: any TranscriptArtifactStore,
        transcriber: any Transcriber,
        clock: any Clock
    ) {
        self.paths = paths
        self.jobStore = jobStore
        self.transcriptArtifactStore = transcriptArtifactStore
        self.transcriber = transcriber
        self.clock = clock
    }

    @discardableResult
    public func run(
        utteranceID: UUID,
        recordingArtifact: RecordingArtifactMetadata
    ) async throws -> TranscriptionJobRunOutcome {
        let jobID = UUID()
        let workingDirectoryURL = paths.transcriptionJobDirectory(jobID: jobID)
        let invocation = transcriber.makeInvocation(
            audioFilePath: recordingArtifact.filePath,
            outputDirectory: workingDirectoryURL.path(percentEncoded: false)
        )

        let queuedJob = TranscriptionJob(
            id: jobID,
            utteranceID: utteranceID,
            recordingArtifactID: recordingArtifact.id,
            workingDirectoryPath: workingDirectoryURL.path(percentEncoded: false),
            command: invocation.command,
            arguments: invocation.arguments,
            modelIdentifier: transcriber.modelIdentifier,
            language: transcriber.language,
            createdAt: clock.now()
        )
        try jobStore.insertTranscriptionJob(queuedJob)

        try FileManager.default.createDirectory(at: workingDirectoryURL, withIntermediateDirectories: true)

        let runningJob = queuedJob.started(at: clock.now())
        try jobStore.updateTranscriptionJob(runningJob)

        let processResult: TranscriptionProcessResult
        do {
            processResult = try await transcriber.run(invocation: invocation)
        } catch {
            let outputFileNames = (try? listSidecarOutputFileNames(in: workingDirectoryURL)) ?? []
            let diagnostics = try writeErrorDiagnosticIfNeeded(
                error: error,
                workingDirectoryURL: workingDirectoryURL
            )

            let failedJob = runningJob.failed(
                at: clock.now(),
                stdoutFilePath: diagnostics.stdoutFilePath,
                stderrFilePath: diagnostics.stderrFilePath,
                exitCode: nil,
                outputFileNames: outputFileNames,
                message: error.localizedDescription
            )
            try jobStore.updateTranscriptionJob(failedJob)
            throw error
        }

        let outputFileNames = try listSidecarOutputFileNames(in: workingDirectoryURL)
        let diagnostics = try writeDiagnostics(
            processResult: processResult,
            workingDirectoryURL: workingDirectoryURL
        )

        guard processResult.exitCode == 0 else {
            let failedJob = runningJob.failed(
                at: clock.now(),
                stdoutFilePath: diagnostics.stdoutFilePath,
                stderrFilePath: diagnostics.stderrFilePath,
                exitCode: processResult.exitCode,
                outputFileNames: outputFileNames,
                message: processFailureMessage(for: processResult)
            )
            try jobStore.updateTranscriptionJob(failedJob)
            throw TranscriptionJobRunnerError.processFailed(
                exitCode: processResult.exitCode,
                message: failedJob.failureMessage ?? "Transcription process failed."
            )
        }

        do {
            let transcriptSourceURL = try validateTranscriptOutput(
                workingDirectoryURL: workingDirectoryURL,
                outputFileNames: outputFileNames
            )
            let transcriptText = try loadTranscriptText(from: transcriptSourceURL)
            let transcriptArtifact = try promoteTranscriptArtifact(
                transcriptSourceURL: transcriptSourceURL,
                utteranceID: utteranceID,
                transcriptionJobID: runningJob.id,
                transcriptText: transcriptText
            )

            try transcriptArtifactStore.insertTranscriptArtifact(transcriptArtifact)

            let completedJob = runningJob.completed(
                at: clock.now(),
                stdoutFilePath: diagnostics.stdoutFilePath,
                stderrFilePath: diagnostics.stderrFilePath,
                exitCode: processResult.exitCode,
                outputFileNames: outputFileNames
            )
            try jobStore.updateTranscriptionJob(completedJob)

            return .completed(
                TranscriptionJobRunResult(
                    job: completedJob,
                    transcriptArtifact: transcriptArtifact
                )
            )
        } catch {
            if isDiscardableValidationError(error) {
                let discardedJob = runningJob.discarded(
                    at: clock.now(),
                    stdoutFilePath: diagnostics.stdoutFilePath,
                    stderrFilePath: diagnostics.stderrFilePath,
                    exitCode: processResult.exitCode,
                    outputFileNames: outputFileNames,
                    message: error.localizedDescription
                )
                try jobStore.updateTranscriptionJob(discardedJob)
                return .discarded(job: discardedJob, reason: error.localizedDescription)
            }

            let failedJob = runningJob.failed(
                at: clock.now(),
                stdoutFilePath: diagnostics.stdoutFilePath,
                stderrFilePath: diagnostics.stderrFilePath,
                exitCode: processResult.exitCode,
                outputFileNames: outputFileNames,
                message: error.localizedDescription
            )
            try jobStore.updateTranscriptionJob(failedJob)
            throw error
        }
    }

    private func isDiscardableValidationError(_ error: any Error) -> Bool {
        guard let runnerError = error as? TranscriptionJobRunnerError else {
            return false
        }

        switch runnerError {
        case .transcriptMissing, .transcriptEmpty:
            return true
        case .processFailed, .transcriptAmbiguous, .transcriptOutsideJobDirectory:
            return false
        }
    }

    private func listSidecarOutputFileNames(in directoryURL: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )
        .map(\.lastPathComponent)
        .filter { $0 != "stdout.txt" && $0 != "stderr.txt" }
        .sorted()
    }

    private func writeDiagnostics(
        processResult: TranscriptionProcessResult,
        workingDirectoryURL: URL
    ) throws -> JobDiagnostics {
        let stdoutFilePath = try writeDiagnostic(
            named: "stdout.txt",
            text: processResult.standardOutput,
            workingDirectoryURL: workingDirectoryURL
        )
        let stderrFilePath = try writeDiagnostic(
            named: "stderr.txt",
            text: processResult.standardError,
            workingDirectoryURL: workingDirectoryURL
        )
        return JobDiagnostics(
            stdoutFilePath: stdoutFilePath,
            stderrFilePath: stderrFilePath
        )
    }

    private func writeErrorDiagnosticIfNeeded(
        error: any Error,
        workingDirectoryURL: URL
    ) throws -> JobDiagnostics {
        let stderrFilePath = try writeDiagnostic(
            named: "stderr.txt",
            text: error.localizedDescription,
            workingDirectoryURL: workingDirectoryURL
        )
        return JobDiagnostics(
            stdoutFilePath: nil,
            stderrFilePath: stderrFilePath
        )
    }

    private func writeDiagnostic(
        named fileName: String,
        text: String?,
        workingDirectoryURL: URL
    ) throws -> String? {
        guard let text, !text.isEmpty else {
            return nil
        }

        let fileURL = workingDirectoryURL.appending(path: fileName)
        try text.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL.path(percentEncoded: false)
    }

    private func validateTranscriptOutput(
        workingDirectoryURL: URL,
        outputFileNames: [String]
    ) throws -> URL {
        let transcriptFileNames = outputFileNames
            .filter { URL(fileURLWithPath: $0).pathExtension == "txt" }

        guard !transcriptFileNames.isEmpty else {
            throw TranscriptionJobRunnerError.transcriptMissing(
                workingDirectoryPath: workingDirectoryURL.path(percentEncoded: false),
                outputFileNames: outputFileNames
            )
        }

        guard transcriptFileNames.count == 1 else {
            throw TranscriptionJobRunnerError.transcriptAmbiguous(
                workingDirectoryPath: workingDirectoryURL.path(percentEncoded: false),
                outputFileNames: outputFileNames
            )
        }

        let transcriptURL = workingDirectoryURL.appending(path: transcriptFileNames[0])
        let standardizedJobDirectory = workingDirectoryURL.standardizedFileURL
            .path(percentEncoded: false)
            .replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        let standardizedTranscriptPath = transcriptURL.standardizedFileURL.path(percentEncoded: false)

        guard standardizedTranscriptPath.hasPrefix(standardizedJobDirectory + "/") else {
            throw TranscriptionJobRunnerError.transcriptOutsideJobDirectory(
                transcriptPath: standardizedTranscriptPath,
                workingDirectoryPath: standardizedJobDirectory
            )
        }

        guard FileManager.default.fileExists(atPath: standardizedTranscriptPath) else {
            throw TranscriptionJobRunnerError.transcriptMissing(
                workingDirectoryPath: standardizedJobDirectory,
                outputFileNames: outputFileNames
            )
        }

        return transcriptURL
    }

    private func loadTranscriptText(from transcriptURL: URL) throws -> String {
        let text = try String(contentsOf: transcriptURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw TranscriptionJobRunnerError.transcriptEmpty(
                transcriptPath: transcriptURL.path(percentEncoded: false)
            )
        }
        return text
    }

    private func promoteTranscriptArtifact(
        transcriptSourceURL: URL,
        utteranceID: UUID,
        transcriptionJobID: UUID,
        transcriptText: String
    ) throws -> TranscriptArtifactMetadata {
        let artifactID = UUID()
        let destinationURL = paths.transcripts.appending(path: "\(artifactID.uuidString).txt")
        try FileManager.default.createDirectory(at: paths.transcripts, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: transcriptSourceURL, to: destinationURL)

        return TranscriptArtifactMetadata(
            id: artifactID,
            utteranceID: utteranceID,
            transcriptionJobID: transcriptionJobID,
            filePath: destinationURL.path(percentEncoded: false),
            text: transcriptText,
            modelIdentifier: transcriber.modelIdentifier,
            language: transcriber.language,
            createdAt: clock.now()
        )
    }

    private func processFailureMessage(for processResult: TranscriptionProcessResult) -> String {
        if let standardError = processResult.standardError, !standardError.isEmpty {
            return "Transcription process failed (\(processResult.exitCode)): \(standardError)"
        }
        if let standardOutput = processResult.standardOutput, !standardOutput.isEmpty {
            return "Transcription process failed (\(processResult.exitCode)): \(standardOutput)"
        }
        return "Transcription process failed with exit code \(processResult.exitCode)."
    }
}

public enum TranscriptionJobRunnerError: LocalizedError {
    case processFailed(exitCode: Int32, message: String)
    case transcriptMissing(workingDirectoryPath: String, outputFileNames: [String])
    case transcriptAmbiguous(workingDirectoryPath: String, outputFileNames: [String])
    case transcriptOutsideJobDirectory(transcriptPath: String, workingDirectoryPath: String)
    case transcriptEmpty(transcriptPath: String)

    public var errorDescription: String? {
        switch self {
        case let .processFailed(_, message):
            return message
        case let .transcriptMissing(workingDirectoryPath, outputFileNames):
            let fileList = outputFileNames.isEmpty ? "(none)" : outputFileNames.joined(separator: ", ")
            return "Transcription finished but no transcript text file was found in job directory. Directory: \(workingDirectoryPath). Files: \(fileList)"
        case let .transcriptAmbiguous(workingDirectoryPath, outputFileNames):
            return "Transcription produced multiple transcript candidates. Directory: \(workingDirectoryPath). Files: \(outputFileNames.joined(separator: ", "))"
        case let .transcriptOutsideJobDirectory(transcriptPath, workingDirectoryPath):
            return "Transcript output must remain inside the job directory. Transcript: \(transcriptPath). Job directory: \(workingDirectoryPath)"
        case let .transcriptEmpty(transcriptPath):
            return "Transcript file was empty after validation. File: \(transcriptPath)"
        }
    }
}

private struct JobDiagnostics {
    let stdoutFilePath: String?
    let stderrFilePath: String?
}
