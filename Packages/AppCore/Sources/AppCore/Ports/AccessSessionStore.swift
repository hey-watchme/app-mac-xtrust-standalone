import Foundation

public protocol AccessSessionStore: Sendable {
    func listAccessSessions() throws -> [AccessSession]
    func listAccessSessions(deviceID: UUID) throws -> [AccessSession]
    func insertAccessSession(_ session: AccessSession) throws
    func updateAccessSession(_ session: AccessSession) throws
}
