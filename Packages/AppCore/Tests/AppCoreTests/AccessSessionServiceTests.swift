import Foundation
import Testing
@testable import AppCore

struct AccessSessionServiceTests {
    @Test
    func beginsActiveAccessSessionWhenNoneExists() throws {
        let store = InMemoryAccessSessionStore()
        let clock = AccessSessionFixedClock(now: Date(timeIntervalSince1970: 1_700_400_000))
        let service = AccessSessionService(accessSessionStore: store, clock: clock)
        let deviceID = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
        let accountID = UUID(uuidString: "00000000-0000-0000-0000-000000000302")!

        let session = try service.beginAccess(
            deviceID: deviceID,
            accountID: accountID,
            authenticationMethod: .localMock
        )

        #expect(session.deviceID == deviceID)
        #expect(session.accountID == accountID)
        #expect(session.status == .active)
        #expect(session.endedAt == nil)
        #expect(try store.listAccessSessions(deviceID: deviceID) == [session])
    }

    @Test
    func reusesExistingActiveAccessSessionForDevice() throws {
        let deviceID = UUID(uuidString: "00000000-0000-0000-0000-000000000311")!
        let accountID = UUID(uuidString: "00000000-0000-0000-0000-000000000312")!
        let existing = AccessSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000313")!,
            deviceID: deviceID,
            accountID: accountID,
            startedAt: Date(timeIntervalSince1970: 1_700_400_100),
            authenticationMethod: .localMock
        )
        let store = InMemoryAccessSessionStore(initialSessions: [existing])
        let service = AccessSessionService(
            accessSessionStore: store,
            clock: AccessSessionFixedClock(now: Date(timeIntervalSince1970: 1_700_400_200))
        )

        let resolved = try service.beginAccess(
            deviceID: deviceID,
            accountID: accountID,
            authenticationMethod: .badge
        )

        #expect(resolved == existing)
        #expect(try store.listAccessSessions(deviceID: deviceID).count == 1)
    }

    @Test
    func endsAccessSessionAsLoggedOut() throws {
        let session = AccessSession(
            deviceID: UUID(uuidString: "00000000-0000-0000-0000-000000000321")!,
            accountID: UUID(uuidString: "00000000-0000-0000-0000-000000000322")!,
            startedAt: Date(timeIntervalSince1970: 1_700_400_300),
            authenticationMethod: .localMock
        )
        let store = InMemoryAccessSessionStore(initialSessions: [session])
        let service = AccessSessionService(
            accessSessionStore: store,
            clock: AccessSessionFixedClock(now: Date(timeIntervalSince1970: 1_700_400_360))
        )

        let ended = try service.endAccess(session, status: .loggedOut)

        #expect(ended.status == .loggedOut)
        #expect(ended.endedAt == Date(timeIntervalSince1970: 1_700_400_360))
        #expect(try store.listAccessSessions(deviceID: session.deviceID).first == ended)
    }
}

private final class InMemoryAccessSessionStore: AccessSessionStore, @unchecked Sendable {
    private var sessions: [AccessSession]

    init(initialSessions: [AccessSession] = []) {
        self.sessions = initialSessions
    }

    func listAccessSessions() throws -> [AccessSession] {
        sessions.sorted { $0.startedAt > $1.startedAt }
    }

    func listAccessSessions(deviceID: UUID) throws -> [AccessSession] {
        sessions
            .filter { $0.deviceID == deviceID }
            .sorted { $0.startedAt > $1.startedAt }
    }

    func insertAccessSession(_ session: AccessSession) throws {
        sessions.append(session)
    }

    func updateAccessSession(_ session: AccessSession) throws {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[index] = session
    }
}

private struct AccessSessionFixedClock: Clock {
    let currentDate: Date

    init(now: Date) {
        self.currentDate = now
    }

    func now() -> Date {
        currentDate
    }
}
