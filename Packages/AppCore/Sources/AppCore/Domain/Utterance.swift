import Foundation

public struct Utterance: Identifiable, Equatable, Sendable {
    public enum TranscriptionStatus: String, Codable, Equatable, Sendable {
        case idle
        case running
        case completed
        case failed
    }

    public let id: UUID
    public let sessionID: UUID
    public let topicID: UUID?
    public let startedAt: Date
    public let endedAt: Date?
    public let durationSeconds: Double?
    public let audioFilePath: String?
    public let transcriptText: String?
    public let transcriptFilePath: String?
    public let transcriptionStatus: TranscriptionStatus
    public let transcriptionError: String?
    public let transcriptionDurationSeconds: Double?

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        topicID: UUID? = nil,
        startedAt: Date,
        endedAt: Date? = nil,
        durationSeconds: Double? = nil,
        audioFilePath: String? = nil,
        transcriptText: String? = nil,
        transcriptFilePath: String? = nil,
        transcriptionStatus: TranscriptionStatus = .idle,
        transcriptionError: String? = nil,
        transcriptionDurationSeconds: Double? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.topicID = topicID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.audioFilePath = audioFilePath
        self.transcriptText = transcriptText
        self.transcriptFilePath = transcriptFilePath
        self.transcriptionStatus = transcriptionStatus
        self.transcriptionError = transcriptionError
        self.transcriptionDurationSeconds = transcriptionDurationSeconds
    }

    public func assigned(to topicID: UUID) -> Utterance {
        Utterance(
            id: id,
            sessionID: sessionID,
            topicID: topicID,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: durationSeconds,
            audioFilePath: audioFilePath,
            transcriptText: transcriptText,
            transcriptFilePath: transcriptFilePath,
            transcriptionStatus: transcriptionStatus,
            transcriptionError: transcriptionError,
            transcriptionDurationSeconds: transcriptionDurationSeconds
        )
    }

    public func transcriptionStarted() -> Utterance {
        Utterance(
            id: id,
            sessionID: sessionID,
            topicID: topicID,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: durationSeconds,
            audioFilePath: audioFilePath,
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
    ) -> Utterance {
        Utterance(
            id: id,
            sessionID: sessionID,
            topicID: topicID,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: self.durationSeconds,
            audioFilePath: audioFilePath,
            transcriptText: transcriptText,
            transcriptFilePath: transcriptFilePath,
            transcriptionStatus: .completed,
            transcriptionError: nil,
            transcriptionDurationSeconds: durationSeconds
        )
    }

    public func transcriptionFailed(message: String) -> Utterance {
        Utterance(
            id: id,
            sessionID: sessionID,
            topicID: topicID,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: durationSeconds,
            audioFilePath: audioFilePath,
            transcriptText: transcriptText,
            transcriptFilePath: transcriptFilePath,
            transcriptionStatus: .failed,
            transcriptionError: message,
            transcriptionDurationSeconds: transcriptionDurationSeconds
        )
    }
}
