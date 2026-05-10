import Foundation

public struct StaleSummaryRecoveryService: Sendable {
    public static let defaultRecoveryMessage =
        "Recovered stale running summary after previous app interruption."

    private let sessionStore: any SessionStore
    private let topicStore: any TopicStore

    public init(
        sessionStore: any SessionStore,
        topicStore: any TopicStore
    ) {
        self.sessionStore = sessionStore
        self.topicStore = topicStore
    }

    @discardableResult
    public func recover(
        recoveryMessage: String = defaultRecoveryMessage
    ) throws -> Int {
        let sessions = try sessionStore.listSessions()
        var recoveredCount = 0

        for session in sessions {
            let topics = try topicStore.listTopics(sessionID: session.id)
            for topic in topics where topic.summaryStatus == .running {
                try topicStore.updateTopic(
                    topic.withSummaryFailed(error: recoveryMessage)
                )
                recoveredCount += 1
            }
        }

        return recoveredCount
    }
}
