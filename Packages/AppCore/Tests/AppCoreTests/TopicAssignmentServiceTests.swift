import Foundation
import Testing
@testable import AppCore

struct TopicAssignmentServiceTests {
    private let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000100")!

    @Test
    func firstUtteranceCreatesNewTopic() throws {
        let topicStore = InMemoryTopicStore()
        let utteranceStore = InMemoryUtteranceStore()
        let service = TopicAssignmentService(topicStore: topicStore, utteranceStore: utteranceStore)

        let utterance = makeUtterance(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_000_010)
        )
        try utteranceStore.insertUtterance(utterance)

        let topic = try service.assignTopic(to: utterance)

        #expect(topic.sessionID == sessionID)
        #expect(topic.status == .active)
        #expect(topicStore.topics.count == 1)

        let updated = try utteranceStore.listUtterances(sessionID: sessionID).first!
        #expect(updated.topicID == topic.id)
    }

    @Test
    func utteranceWithin60sStaysInSameTopic() throws {
        let topicStore = InMemoryTopicStore()
        let utteranceStore = InMemoryUtteranceStore()
        let service = TopicAssignmentService(topicStore: topicStore, utteranceStore: utteranceStore)

        let first = makeUtterance(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_000_010)
        )
        try utteranceStore.insertUtterance(first)
        let firstTopic = try service.assignTopic(to: first)

        let second = makeUtterance(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
            startedAt: Date(timeIntervalSince1970: 1_700_000_040),
            endedAt: Date(timeIntervalSince1970: 1_700_000_050)
        )
        try utteranceStore.insertUtterance(second)
        let secondTopic = try service.assignTopic(to: second)

        #expect(secondTopic.id == firstTopic.id)
        #expect(topicStore.topics.count == 1)
        #expect(topicStore.topics[0].status == .active)
    }

    @Test
    func utteranceAfter60sGapCreatesNewTopicAndClosesPrior() throws {
        let topicStore = InMemoryTopicStore()
        let utteranceStore = InMemoryUtteranceStore()
        let service = TopicAssignmentService(topicStore: topicStore, utteranceStore: utteranceStore)

        let first = makeUtterance(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000103")!,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_000_010)
        )
        try utteranceStore.insertUtterance(first)
        let firstTopic = try service.assignTopic(to: first)

        // Gap = 1_700_000_080 - 1_700_000_010 = 70s >= 60s
        let second = makeUtterance(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000104")!,
            startedAt: Date(timeIntervalSince1970: 1_700_000_080),
            endedAt: Date(timeIntervalSince1970: 1_700_000_090)
        )
        try utteranceStore.insertUtterance(second)
        let secondTopic = try service.assignTopic(to: second)

        #expect(secondTopic.id != firstTopic.id)
        #expect(topicStore.topics.count == 2)

        let closedTopic = topicStore.topics.first(where: { $0.id == firstTopic.id })!
        #expect(closedTopic.status == .completed)
        #expect(closedTopic.endedAt == Date(timeIntervalSince1970: 1_700_000_010))

        #expect(secondTopic.status == .active)
    }

    private func makeUtterance(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date
    ) -> Utterance {
        Utterance(
            id: id,
            sessionID: sessionID,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: endedAt.timeIntervalSince(startedAt),
            audioFilePath: "/tmp/test.wav"
        )
    }
}

private final class InMemoryTopicStore: TopicStore, @unchecked Sendable {
    var topics: [Topic] = []

    func listTopics(sessionID: UUID) throws -> [Topic] {
        topics.filter { $0.sessionID == sessionID }.sorted { $0.startedAt < $1.startedAt }
    }

    func insertTopic(_ topic: Topic) throws {
        topics.append(topic)
    }

    func updateTopic(_ topic: Topic) throws {
        guard let index = topics.firstIndex(where: { $0.id == topic.id }) else { return }
        topics[index] = topic
    }
}

private final class InMemoryUtteranceStore: UtteranceStore, @unchecked Sendable {
    var utterances: [Utterance] = []

    func listUtterances(sessionID: UUID) throws -> [Utterance] {
        utterances.filter { $0.sessionID == sessionID }.sorted { $0.startedAt < $1.startedAt }
    }

    func listUtterances(topicID: UUID) throws -> [Utterance] {
        utterances.filter { $0.topicID == topicID }.sorted { $0.startedAt < $1.startedAt }
    }

    func insertUtterance(_ utterance: Utterance) throws {
        utterances.append(utterance)
    }

    func updateUtterance(_ utterance: Utterance) throws {
        guard let index = utterances.firstIndex(where: { $0.id == utterance.id }) else { return }
        utterances[index] = utterance
    }
}
