import Foundation
import Testing
@testable import AppCore

struct CreateSessionTests {
    @Test
    func createsDraftSessionWithFixedClock() throws {
        let store = InMemorySessionStore()
        let clock = FixedClock(now: Date(timeIntervalSince1970: 1_700_000_123))
        let createSession = CreateSession(clock: clock, sessionStore: store)

        let session = try createSession.run()

        #expect(session.status == .draft)
        #expect(session.startedAt == clock.now())
        #expect(try store.listSessions() == [session])
    }
}

private final class InMemorySessionStore: SessionStore, @unchecked Sendable {
    private var sessions: [Session] = []

    func initialize() throws {}

    func listSessions() throws -> [Session] {
        sessions
    }

    func insertSession(_ session: Session) throws {
        sessions.append(session)
    }

    func updateSession(_ session: Session) throws {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[index] = session
    }
}

private struct FixedClock: Clock {
    let currentDate: Date

    init(now: Date) {
        self.currentDate = now
    }

    func now() -> Date {
        currentDate
    }
}
