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

    public func closeSession(_ session: Session) throws -> Session {
        let updatedSession = session.closed(endedAt: clock.now())
        try sessionStore.updateSession(updatedSession)
        return updatedSession
    }

    public func setStatus(_ status: Session.Status, for session: Session) throws -> Session {
        let updated = session.withStatus(status)
        try sessionStore.updateSession(updated)
        return updated
    }

}
