import Foundation

public struct TranscriptionJob: Identifiable, Equatable, Sendable {
    public enum Status: String, Codable, Equatable, Sendable {
        case queued
        case running
        case completed
        case discarded
        case failed
    }

    public let id: UUID
    public let utteranceID: UUID
    public let recordingArtifactID: UUID
    public let workingDirectoryPath: String
    public let command: String
    public let arguments: [String]
    public let modelIdentifier: String
    public let language: String
    public let status: Status
    public let createdAt: Date
    public let startedAt: Date?
    public let endedAt: Date?
    public let stdoutFilePath: String?
    public let stderrFilePath: String?
    public let exitCode: Int32?
    public let outputFileNames: [String]
    public let failureMessage: String?

    public init(
        id: UUID = UUID(),
        utteranceID: UUID,
        recordingArtifactID: UUID,
        workingDirectoryPath: String,
        command: String,
        arguments: [String],
        modelIdentifier: String,
        language: String,
        status: Status = .queued,
        createdAt: Date,
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        stdoutFilePath: String? = nil,
        stderrFilePath: String? = nil,
        exitCode: Int32? = nil,
        outputFileNames: [String] = [],
        failureMessage: String? = nil
    ) {
        self.id = id
        self.utteranceID = utteranceID
        self.recordingArtifactID = recordingArtifactID
        self.workingDirectoryPath = workingDirectoryPath
        self.command = command
        self.arguments = arguments
        self.modelIdentifier = modelIdentifier
        self.language = language
        self.status = status
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.stdoutFilePath = stdoutFilePath
        self.stderrFilePath = stderrFilePath
        self.exitCode = exitCode
        self.outputFileNames = outputFileNames
        self.failureMessage = failureMessage
    }

    public func started(at startedAt: Date) -> TranscriptionJob {
        TranscriptionJob(
            id: id,
            utteranceID: utteranceID,
            recordingArtifactID: recordingArtifactID,
            workingDirectoryPath: workingDirectoryPath,
            command: command,
            arguments: arguments,
            modelIdentifier: modelIdentifier,
            language: language,
            status: .running,
            createdAt: createdAt,
            startedAt: startedAt,
            endedAt: nil,
            stdoutFilePath: nil,
            stderrFilePath: nil,
            exitCode: nil,
            outputFileNames: [],
            failureMessage: nil
        )
    }

    public func completed(
        at endedAt: Date,
        stdoutFilePath: String?,
        stderrFilePath: String?,
        exitCode: Int32,
        outputFileNames: [String]
    ) -> TranscriptionJob {
        TranscriptionJob(
            id: id,
            utteranceID: utteranceID,
            recordingArtifactID: recordingArtifactID,
            workingDirectoryPath: workingDirectoryPath,
            command: command,
            arguments: arguments,
            modelIdentifier: modelIdentifier,
            language: language,
            status: .completed,
            createdAt: createdAt,
            startedAt: startedAt,
            endedAt: endedAt,
            stdoutFilePath: stdoutFilePath,
            stderrFilePath: stderrFilePath,
            exitCode: exitCode,
            outputFileNames: outputFileNames,
            failureMessage: nil
        )
    }

    public func failed(
        at endedAt: Date,
        stdoutFilePath: String?,
        stderrFilePath: String?,
        exitCode: Int32?,
        outputFileNames: [String],
        message: String
    ) -> TranscriptionJob {
        TranscriptionJob(
            id: id,
            utteranceID: utteranceID,
            recordingArtifactID: recordingArtifactID,
            workingDirectoryPath: workingDirectoryPath,
            command: command,
            arguments: arguments,
            modelIdentifier: modelIdentifier,
            language: language,
            status: .failed,
            createdAt: createdAt,
            startedAt: startedAt,
            endedAt: endedAt,
            stdoutFilePath: stdoutFilePath,
            stderrFilePath: stderrFilePath,
            exitCode: exitCode,
            outputFileNames: outputFileNames,
            failureMessage: message
        )
    }

    public func discarded(
        at endedAt: Date,
        stdoutFilePath: String?,
        stderrFilePath: String?,
        exitCode: Int32?,
        outputFileNames: [String],
        message: String
    ) -> TranscriptionJob {
        TranscriptionJob(
            id: id,
            utteranceID: utteranceID,
            recordingArtifactID: recordingArtifactID,
            workingDirectoryPath: workingDirectoryPath,
            command: command,
            arguments: arguments,
            modelIdentifier: modelIdentifier,
            language: language,
            status: .discarded,
            createdAt: createdAt,
            startedAt: startedAt,
            endedAt: endedAt,
            stdoutFilePath: stdoutFilePath,
            stderrFilePath: stderrFilePath,
            exitCode: exitCode,
            outputFileNames: outputFileNames,
            failureMessage: message
        )
    }
}
