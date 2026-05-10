import Foundation

public struct AccessSessionService: Sendable {
    private let accessSessionStore: any AccessSessionStore
    private let clock: any Clock

    public init(
        accessSessionStore: any AccessSessionStore,
        clock: any Clock
    ) {
        self.accessSessionStore = accessSessionStore
        self.clock = clock
    }

    public func loadAccessSessions(deviceID: UUID) throws -> [AccessSession] {
        try accessSessionStore.listAccessSessions(deviceID: deviceID)
    }

    public func activeAccessSession(deviceID: UUID) throws -> AccessSession? {
        try accessSessionStore
            .listAccessSessions(deviceID: deviceID)
            .first(where: { $0.status == .active && $0.endedAt == nil })
    }

    public func beginAccess(
        deviceID: UUID,
        accountID: UUID,
        authenticationMethod: AccessSession.AuthenticationMethod
    ) throws -> AccessSession {
        if let existing = try activeAccessSession(deviceID: deviceID) {
            return existing
        }

        let session = AccessSession(
            deviceID: deviceID,
            accountID: accountID,
            startedAt: clock.now(),
            authenticationMethod: authenticationMethod
        )
        try accessSessionStore.insertAccessSession(session)
        return session
    }

    public func endAccess(
        _ session: AccessSession,
        status: AccessSession.Status
    ) throws -> AccessSession {
        precondition(status != .active, "Active status cannot be used to end an access session.")
        let updated = session.ended(at: clock.now(), status: status)
        try accessSessionStore.updateAccessSession(updated)
        return updated
    }
}
