import Foundation

public struct CreateSession: Sendable {
    private let clock: any Clock
    private let sessionStore: any SessionStore

    public init(clock: any Clock, sessionStore: any SessionStore) {
        self.clock = clock
        self.sessionStore = sessionStore
    }

    public func run() throws -> Session {
        let session = Session(startedAt: clock.now(), status: .draft)
        try sessionStore.insertSession(session)
        return session
    }
}
