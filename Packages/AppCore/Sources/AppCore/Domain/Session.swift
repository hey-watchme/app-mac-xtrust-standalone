import Foundation

public struct Session: Identifiable, Equatable, Sendable {
    public enum Status: String, Codable, Equatable, Sendable {
        case draft
        case recording
        case completed
        case failed
    }

    public enum TranscriptionStatus: String, Codable, Equatable, Sendable {
        case idle
        case running
        case completed
        case failed
    }

    public let id: UUID
    public let startedAt: Date
    public let endedAt: Date?
    public let status: Status
    public let audioFilePath: String?
    public let durationSeconds: Double?
    public let transcriptText: String?
    public let transcriptFilePath: String?
    public let transcriptionStatus: TranscriptionStatus
    public let transcriptionError: String?
    public let transcriptionDurationSeconds: Double?

    public init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date? = nil,
        status: Status = .draft,
        audioFilePath: String? = nil,
        durationSeconds: Double? = nil,
        transcriptText: String? = nil,
        transcriptFilePath: String? = nil,
        transcriptionStatus: TranscriptionStatus = .idle,
        transcriptionError: String? = nil,
        transcriptionDurationSeconds: Double? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.audioFilePath = audioFilePath
        self.durationSeconds = durationSeconds
        self.transcriptText = transcriptText
        self.transcriptFilePath = transcriptFilePath
        self.transcriptionStatus = transcriptionStatus
        self.transcriptionError = transcriptionError
        self.transcriptionDurationSeconds = transcriptionDurationSeconds
    }

    public func recordingStarted(audioFilePath: String) -> Session {
        Session(
            id: id,
            startedAt: startedAt,
            endedAt: nil,
            status: .recording,
            audioFilePath: audioFilePath,
            durationSeconds: nil,
            transcriptText: nil,
            transcriptFilePath: nil,
            transcriptionStatus: .idle,
            transcriptionError: nil,
            transcriptionDurationSeconds: nil
        )
    }

    public func recordingCompleted(
        endedAt: Date,
        audioFilePath: String,
        durationSeconds: Double
    ) -> Session {
        Session(
            id: id,
            startedAt: startedAt,
            endedAt: endedAt,
            status: .completed,
            audioFilePath: audioFilePath,
            durationSeconds: durationSeconds,
            transcriptText: transcriptText,
            transcriptFilePath: transcriptFilePath,
            transcriptionStatus: transcriptionStatus,
            transcriptionError: transcriptionError,
            transcriptionDurationSeconds: transcriptionDurationSeconds
        )
    }

    public func transcriptionStarted() -> Session {
        Session(
            id: id,
            startedAt: startedAt,
            endedAt: endedAt,
            status: status,
            audioFilePath: audioFilePath,
            durationSeconds: durationSeconds,
            transcriptText: transcriptText,
            transcriptFilePath: transcriptFilePath,
            transcriptionStatus: .running,
            transcriptionError: nil,
            transcriptionDurationSeconds: nil
        )
    }

    public func transcriptionCompleted(
        transcriptText: String,
        transcriptFilePath: String,
        durationSeconds: Double
    ) -> Session {
        Session(
            id: id,
            startedAt: startedAt,
            endedAt: endedAt,
            status: status,
            audioFilePath: audioFilePath,
            durationSeconds: self.durationSeconds,
            transcriptText: transcriptText,
            transcriptFilePath: transcriptFilePath,
            transcriptionStatus: .completed,
            transcriptionError: nil,
            transcriptionDurationSeconds: durationSeconds
        )
    }

    public func transcriptionFailed(message: String) -> Session {
        Session(
            id: id,
            startedAt: startedAt,
            endedAt: endedAt,
            status: status,
            audioFilePath: audioFilePath,
            durationSeconds: durationSeconds,
            transcriptText: transcriptText,
            transcriptFilePath: transcriptFilePath,
            transcriptionStatus: .failed,
            transcriptionError: message,
            transcriptionDurationSeconds: transcriptionDurationSeconds
        )
    }
}
