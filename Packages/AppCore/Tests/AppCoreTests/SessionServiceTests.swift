import Foundation
import Testing
@testable import AppCore

struct SessionServiceTests {
    @Test
    func reusesSelectedDraftSessionForRecording() throws {
        let session = Session(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            status: .draft
        )
        let store = SessionServiceInMemoryStore(initialSessions: [session])
        let service = SessionService(sessionStore: store, clock: SessionServiceFixedClock(now: session.startedAt))

        let resolved = try service.ensureDraftSession(
            selectedSessionID: session.id,
            sessions: [session]
        )

        #expect(resolved.id == session.id)
        #expect(try store.listSessions().count == 1)
    }

    @Test
    func createsDraftSessionWhenSelectedSessionIsNotDraft() throws {
        let completed = Session(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_000_120),
            status: .completed,
            audioFilePath: "/tmp/test.wav",
            durationSeconds: 12
        )
        let store = SessionServiceInMemoryStore(initialSessions: [completed])
        let fixedClock = SessionServiceFixedClock(now: Date(timeIntervalSince1970: 1_700_000_200))
        let service = SessionService(sessionStore: store, clock: fixedClock)

        let resolved = try service.ensureDraftSession(
            selectedSessionID: completed.id,
            sessions: [completed]
        )

        #expect(resolved.id != completed.id)
        #expect(resolved.status == .draft)
        #expect(resolved.startedAt == fixedClock.now())
        #expect(try store.listSessions().count == 2)
    }

    @Test
    func marksTranscriptionLifecycle() throws {
        let session = Session(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_000_005),
            status: .completed,
            audioFilePath: "/tmp/test.wav",
            durationSeconds: 5
        )
        let store = SessionServiceInMemoryStore(initialSessions: [session])
        let service = SessionService(
            sessionStore: store,
            clock: SessionServiceFixedClock(now: Date(timeIntervalSince1970: 1_700_000_123))
        )

        let running = try service.markTranscriptionStarted(session: session)
        let completed = try service.markTranscriptionCompleted(
            session: running,
            transcriptText: "こんにちは",
            transcriptFilePath: "/tmp/test.txt",
            durationSeconds: 2.4
        )

        #expect(running.transcriptionStatus == .running)
        #expect(completed.transcriptionStatus == .completed)
        #expect(completed.transcriptText == "こんにちは")
        #expect(completed.transcriptFilePath == "/tmp/test.txt")
        #expect(completed.transcriptionDurationSeconds == 2.4)
    }
}

private final class SessionServiceInMemoryStore: SessionStore, @unchecked Sendable {
    private var sessions: [Session]

    init(initialSessions: [Session] = []) {
        self.sessions = initialSessions
    }

    func initialize() throws {}

    func listSessions() throws -> [Session] {
        sessions.sorted { $0.startedAt > $1.startedAt }
    }

    func insertSession(_ session: Session) throws {
        sessions.append(session)
    }

    func updateSession(_ session: Session) throws {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[index] = session
    }
}

private struct SessionServiceFixedClock: Clock {
    let currentDate: Date

    init(now: Date) {
        self.currentDate = now
    }

    func now() -> Date {
        currentDate
    }
}
