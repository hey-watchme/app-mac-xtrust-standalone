import Foundation

public struct CaptureSessionService: Sendable {
    private let captureSessionStore: any CaptureSessionStore
    private let clock: any Clock

    public init(captureSessionStore: any CaptureSessionStore, clock: any Clock) {
        self.captureSessionStore = captureSessionStore
        self.clock = clock
    }

    public func createCaptureSession(
        context: SharedDeviceContext,
        accessSessionID: UUID?
    ) throws -> CaptureSession {
        let session = CaptureSession(
            organizationID: context.organization.id,
            workspaceID: context.workspace.id,
            deviceID: context.device.id,
            startedByAccountID: context.bootstrapAccount.id,
            accessSessionID: accessSessionID,
            startedAt: clock.now(),
            status: .open
        )
        try captureSessionStore.insertCaptureSession(session)
        return session
    }

    public func markRecordingStarted(
        _ session: CaptureSession,
        audioFilePath: String
    ) throws -> CaptureSession {
        let updated = session.recordingStarted(audioFilePath: audioFilePath)
        try captureSessionStore.updateCaptureSession(updated)
        return updated
    }

    public func close(
        _ session: CaptureSession,
        endedAt: Date,
        audioDurationSeconds: Double?,
        utteranceCount: Int
    ) throws -> CaptureSession {
        let updated = session.closed(
            endedAt: endedAt,
            audioDurationSeconds: audioDurationSeconds,
            utteranceCount: utteranceCount
        )
        try captureSessionStore.updateCaptureSession(updated)
        return updated
    }

    public func setMeetingContextProfile(
        _ session: CaptureSession,
        profile: MeetingContextProfile
    ) throws -> CaptureSession {
        let updated = session.withMeetingContextProfile(profile)
        try captureSessionStore.updateCaptureSession(updated)
        return updated
    }
}
