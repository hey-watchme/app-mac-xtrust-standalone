import Foundation

public protocol TopicStore: Sendable {
    func listTopics(sessionID: UUID) throws -> [Topic]
    func insertTopic(_ topic: Topic) throws
    func updateTopic(_ topic: Topic) throws
}
