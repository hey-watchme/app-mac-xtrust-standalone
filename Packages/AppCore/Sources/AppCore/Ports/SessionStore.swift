import Foundation

public protocol SessionStore: Sendable {
    func initialize() throws
    func listSessions() throws -> [Session]
    func insertSession(_ session: Session) throws
    func updateSession(_ session: Session) throws
}
