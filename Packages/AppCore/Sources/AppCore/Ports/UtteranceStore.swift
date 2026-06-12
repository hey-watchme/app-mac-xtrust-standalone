import Foundation

public protocol UtteranceStore: Sendable {
    func insertUtterance(_ utterance: Utterance) throws
    func listUtterances(captureSessionID: UUID) throws -> [Utterance]
}
