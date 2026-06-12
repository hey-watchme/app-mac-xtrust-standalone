import Foundation

public enum MeetingContextProfile: String, Codable, Equatable, CaseIterable, Sendable {
    case general
    case engineering
    case product
    case recruitingHR = "recruiting_hr"
}

public struct CaptureSession: Identifiable, Equatable, Sendable {
    public enum Status: String, Codable, Equatable, Sendable {
        case open
        case recording
        case closed
    }

    public let id: UUID
    public let organizationID: UUID
    public let workspaceID: UUID
    public let deviceID: UUID
    public let startedByAccountID: UUID
    public let accessSessionID: UUID?
    public let startedAt: Date
    public let endedAt: Date?
    public let status: Status
    public let meetingContextProfile: MeetingContextProfile
    public let audioFilePath: String?
    public let audioDurationSeconds: Double?
    public let utteranceCount: Int

    public init(
        id: UUID = UUID(),
        organizationID: UUID,
        workspaceID: UUID,
        deviceID: UUID,
        startedByAccountID: UUID,
        accessSessionID: UUID? = nil,
        startedAt: Date,
        endedAt: Date? = nil,
        status: Status = .open,
        meetingContextProfile: MeetingContextProfile = .general,
        audioFilePath: String? = nil,
        audioDurationSeconds: Double? = nil,
        utteranceCount: Int = 0
    ) {
        self.id = id
        self.organizationID = organizationID
        self.workspaceID = workspaceID
        self.deviceID = deviceID
        self.startedByAccountID = startedByAccountID
        self.accessSessionID = accessSessionID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.meetingContextProfile = meetingContextProfile
        self.audioFilePath = audioFilePath
        self.audioDurationSeconds = audioDurationSeconds
        self.utteranceCount = utteranceCount
    }

    public func recordingStarted(audioFilePath: String) -> CaptureSession {
        CaptureSession(
            id: id,
            organizationID: organizationID,
            workspaceID: workspaceID,
            deviceID: deviceID,
            startedByAccountID: startedByAccountID,
            accessSessionID: accessSessionID,
            startedAt: startedAt,
            endedAt: nil,
            status: .recording,
            meetingContextProfile: meetingContextProfile,
            audioFilePath: audioFilePath,
            audioDurationSeconds: nil,
            utteranceCount: utteranceCount
        )
    }

    public func closed(
        endedAt: Date,
        audioDurationSeconds: Double?,
        utteranceCount: Int
    ) -> CaptureSession {
        CaptureSession(
            id: id,
            organizationID: organizationID,
            workspaceID: workspaceID,
            deviceID: deviceID,
            startedByAccountID: startedByAccountID,
            accessSessionID: accessSessionID,
            startedAt: startedAt,
            endedAt: endedAt,
            status: .closed,
            meetingContextProfile: meetingContextProfile,
            audioFilePath: audioFilePath,
            audioDurationSeconds: audioDurationSeconds,
            utteranceCount: utteranceCount
        )
    }

    public func withMeetingContextProfile(_ profile: MeetingContextProfile) -> CaptureSession {
        CaptureSession(
            id: id,
            organizationID: organizationID,
            workspaceID: workspaceID,
            deviceID: deviceID,
            startedByAccountID: startedByAccountID,
            accessSessionID: accessSessionID,
            startedAt: startedAt,
            endedAt: endedAt,
            status: status,
            meetingContextProfile: profile,
            audioFilePath: audioFilePath,
            audioDurationSeconds: audioDurationSeconds,
            utteranceCount: utteranceCount
        )
    }
}
