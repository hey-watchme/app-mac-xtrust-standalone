import Foundation

public struct Session: Identifiable, Equatable, Sendable {
    public enum MeetingContextProfile: String, Codable, Equatable, CaseIterable, Sendable {
        case general
        case engineering
        case product
        case recruitingHR = "recruiting_hr"
    }

    public enum Status: String, Codable, Equatable, Sendable {
        case draft
        case recording
        case completed
        case failed
        case closed
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
    public let meetingContextProfile: MeetingContextProfile
    public let transcriptionStatus: TranscriptionStatus
    public let transcriptionError: String?
    public let transcriptionDurationSeconds: Double?
    public let utteranceCount: Int
    public let topicCount: Int

    public init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date? = nil,
        status: Status = .draft,
        audioFilePath: String? = nil,
        durationSeconds: Double? = nil,
        transcriptText: String? = nil,
        transcriptFilePath: String? = nil,
        meetingContextProfile: MeetingContextProfile = .general,
        transcriptionStatus: TranscriptionStatus = .idle,
        transcriptionError: String? = nil,
        transcriptionDurationSeconds: Double? = nil,
        utteranceCount: Int = 0,
        topicCount: Int = 0
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.audioFilePath = audioFilePath
        self.durationSeconds = durationSeconds
        self.transcriptText = transcriptText
        self.transcriptFilePath = transcriptFilePath
        self.meetingContextProfile = meetingContextProfile
        self.transcriptionStatus = transcriptionStatus
        self.transcriptionError = transcriptionError
        self.transcriptionDurationSeconds = transcriptionDurationSeconds
        self.utteranceCount = utteranceCount
        self.topicCount = topicCount
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
            meetingContextProfile: meetingContextProfile,
            transcriptionStatus: .idle,
            transcriptionError: nil,
            transcriptionDurationSeconds: nil,
            utteranceCount: utteranceCount,
            topicCount: topicCount
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
            meetingContextProfile: meetingContextProfile,
            transcriptionStatus: transcriptionStatus,
            transcriptionError: transcriptionError,
            transcriptionDurationSeconds: transcriptionDurationSeconds,
            utteranceCount: utteranceCount,
            topicCount: topicCount
        )
    }

    public func withStatus(_ newStatus: Status) -> Session {
        Session(
            id: id,
            startedAt: startedAt,
            endedAt: endedAt,
            status: newStatus,
            audioFilePath: audioFilePath,
            durationSeconds: durationSeconds,
            transcriptText: transcriptText,
            transcriptFilePath: transcriptFilePath,
            meetingContextProfile: meetingContextProfile,
            transcriptionStatus: transcriptionStatus,
            transcriptionError: transcriptionError,
            transcriptionDurationSeconds: transcriptionDurationSeconds,
            utteranceCount: utteranceCount,
            topicCount: topicCount
        )
    }

    public func closed(endedAt: Date) -> Session {
        Session(
            id: id,
            startedAt: startedAt,
            endedAt: endedAt,
            status: .closed,
            audioFilePath: audioFilePath,
            durationSeconds: durationSeconds,
            transcriptText: transcriptText,
            transcriptFilePath: transcriptFilePath,
            meetingContextProfile: meetingContextProfile,
            transcriptionStatus: transcriptionStatus,
            transcriptionError: transcriptionError,
            transcriptionDurationSeconds: transcriptionDurationSeconds,
            utteranceCount: utteranceCount,
            topicCount: topicCount
        )
    }

    public func withMeetingContextProfile(_ profile: MeetingContextProfile) -> Session {
        Session(
            id: id,
            startedAt: startedAt,
            endedAt: endedAt,
            status: status,
            audioFilePath: audioFilePath,
            durationSeconds: durationSeconds,
            transcriptText: transcriptText,
            transcriptFilePath: transcriptFilePath,
            meetingContextProfile: profile,
            transcriptionStatus: transcriptionStatus,
            transcriptionError: transcriptionError,
            transcriptionDurationSeconds: transcriptionDurationSeconds,
            utteranceCount: utteranceCount,
            topicCount: topicCount
        )
    }

}
