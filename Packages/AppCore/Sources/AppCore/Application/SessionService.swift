import Foundation

public struct SessionService: Sendable {
    private let sessionStore: any SessionStore
    private let clock: any Clock

    public init(sessionStore: any SessionStore, clock: any Clock) {
        self.sessionStore = sessionStore
        self.clock = clock
    }

    public func loadSessions() throws -> [Session] {
        try sessionStore.listSessions()
    }

    public func createSession() throws -> Session {
        try CreateSession(clock: clock, sessionStore: sessionStore).run()
    }

    public func ensureDraftSession(
        selectedSessionID: Session.ID?,
        sessions: [Session]
    ) throws -> Session {
        if let selectedSessionID,
           let selectedSession = sessions.first(where: { $0.id == selectedSessionID }),
           selectedSession.status == .draft {
            return selectedSession
        }

        return try createSession()
    }

    public func markRecordingStarted(
        session: Session,
        audioFilePath: String
    ) throws -> Session {
        let updatedSession = session.recordingStarted(audioFilePath: audioFilePath)
        try sessionStore.updateSession(updatedSession)
        return updatedSession
    }

    public func markRecordingCompleted(
        session: Session,
        audioFilePath: String,
        durationSeconds: Double
    ) throws -> Session {
        let updatedSession = session.recordingCompleted(
            endedAt: clock.now(),
            audioFilePath: audioFilePath,
            durationSeconds: durationSeconds
        )
        try sessionStore.updateSession(updatedSession)
        return updatedSession
    }

    public func markTranscriptionStarted(session: Session) throws -> Session {
        let updatedSession = session.transcriptionStarted()
        try sessionStore.updateSession(updatedSession)
        return updatedSession
    }

    public func markTranscriptionCompleted(
        session: Session,
        transcriptText: String,
        transcriptFilePath: String,
        durationSeconds: Double
    ) throws -> Session {
        let updatedSession = session.transcriptionCompleted(
            transcriptText: transcriptText,
            transcriptFilePath: transcriptFilePath,
            durationSeconds: durationSeconds
        )
        try sessionStore.updateSession(updatedSession)
        return updatedSession
    }

    public func markTranscriptionFailed(
        session: Session,
        message: String
    ) throws -> Session {
        let updatedSession = session.transcriptionFailed(message: message)
        try sessionStore.updateSession(updatedSession)
        return updatedSession
    }
}
