import Foundation

public protocol UtteranceStore: Sendable {
    func listUtterances(sessionID: UUID) throws -> [Utterance]
    func listUtterances(topicID: UUID) throws -> [Utterance]
    func insertUtterance(_ utterance: Utterance) throws
    func updateUtterance(_ utterance: Utterance) throws
}
