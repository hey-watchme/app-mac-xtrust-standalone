import Foundation

public final class TopicAssignmentService {
    private let topicStore: any TopicStore
    private let utteranceStore: any UtteranceStore

    public init(
        topicStore: any TopicStore,
        utteranceStore: any UtteranceStore
    ) {
        self.topicStore = topicStore
        self.utteranceStore = utteranceStore
    }

    // Finds or creates a topic for the utterance, updates the utterance in the store with the
    // assigned topicID, and returns the topic.
    // Rule: if utterance.startedAt - previousUtterance.endedAt >= 60s, close the active topic
    // and open a new one.
    @discardableResult
    public func assignTopic(to utterance: Utterance) throws -> Topic {
        let existingTopics = try topicStore.listTopics(sessionID: utterance.sessionID)
        let activeTopic = existingTopics.first(where: { $0.status == .active })

        let allUtterances = try utteranceStore.listUtterances(sessionID: utterance.sessionID)
        let previousUtterance = allUtterances
            .filter { $0.id != utterance.id && $0.startedAt < utterance.startedAt }
            .max(by: { $0.startedAt < $1.startedAt })

        let needsNewTopic: Bool
        if let previous = previousUtterance, let prevEndedAt = previous.endedAt {
            needsNewTopic = utterance.startedAt.timeIntervalSince(prevEndedAt) >= 60
        } else {
            needsNewTopic = activeTopic == nil
        }

        let assignedTopic: Topic
        if needsNewTopic {
            if let active = activeTopic {
                let closeAt = previousUtterance?.endedAt ?? utterance.startedAt
                try topicStore.updateTopic(Topic(
                    id: active.id,
                    sessionID: active.sessionID,
                    startedAt: active.startedAt,
                    endedAt: closeAt,
                    status: .completed,
                    summaryText: active.summaryText,
                    summaryStatus: active.summaryStatus,
                    summaryError: active.summaryError
                ))
            }
            let newTopic = Topic(sessionID: utterance.sessionID, startedAt: utterance.startedAt)
            try topicStore.insertTopic(newTopic)
            assignedTopic = newTopic
        } else if let active = activeTopic {
            assignedTopic = active
        } else {
            // Defensive fallback: no active topic but gap < 60s (e.g. topic was manually closed)
            let newTopic = Topic(sessionID: utterance.sessionID, startedAt: utterance.startedAt)
            try topicStore.insertTopic(newTopic)
            assignedTopic = newTopic
        }

        try utteranceStore.updateUtterance(utterance.assigned(to: assignedTopic.id))
        return assignedTopic
    }
}
