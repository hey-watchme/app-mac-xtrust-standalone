import Foundation
import Testing
@testable import AppCore

struct StaleSummaryRecoveryServiceTests {
    @Test
    func recoversOnlyTopicsLeftRunning() throws {
        let sessionStore = InMemorySessionStore()
        let topicStore = InMemoryRecoveryTopicStore()
        let service = StaleSummaryRecoveryService(
            sessionStore: sessionStore,
            topicStore: topicStore
        )

        let firstSession = Session(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000401")!,
            startedAt: Date(timeIntervalSince1970: 1_700_400_000)
        )
        let secondSession = Session(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000402")!,
            startedAt: Date(timeIntervalSince1970: 1_700_400_100)
        )
        try sessionStore.insertSession(firstSession)
        try sessionStore.insertSession(secondSession)

        let runningTopic = Topic(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000411")!,
            sessionID: firstSession.id,
            startedAt: Date(timeIntervalSince1970: 1_700_400_010),
            summaryStatus: .running
        )
        let completedTopic = Topic(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000412")!,
            sessionID: firstSession.id,
            startedAt: Date(timeIntervalSince1970: 1_700_400_020),
            summaryText: "done",
            summaryStatus: .completed
        )
        let anotherRunningTopic = Topic(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000413")!,
            sessionID: secondSession.id,
            startedAt: Date(timeIntervalSince1970: 1_700_400_030),
            summaryStatus: .running
        )

        try topicStore.insertTopic(runningTopic)
        try topicStore.insertTopic(completedTopic)
        try topicStore.insertTopic(anotherRunningTopic)

        let recoveredCount = try service.recover()

        #expect(recoveredCount == 2)

        let firstSessionTopics = try topicStore.listTopics(sessionID: firstSession.id)
        #expect(firstSessionTopics[0].summaryStatus == .failed)
        #expect(firstSessionTopics[0].summaryError == StaleSummaryRecoveryService.defaultRecoveryMessage)
        #expect(firstSessionTopics[1].summaryStatus == .completed)

        let secondSessionTopics = try topicStore.listTopics(sessionID: secondSession.id)
        #expect(secondSessionTopics[0].summaryStatus == .failed)
        #expect(secondSessionTopics[0].summaryError == StaleSummaryRecoveryService.defaultRecoveryMessage)
    }

    @Test
    func returnsZeroWhenNothingNeedsRecovery() throws {
        let sessionStore = InMemorySessionStore()
        let topicStore = InMemoryRecoveryTopicStore()
        let service = StaleSummaryRecoveryService(
            sessionStore: sessionStore,
            topicStore: topicStore
        )

        let session = Session(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000421")!,
            startedAt: Date(timeIntervalSince1970: 1_700_401_000)
        )
        try sessionStore.insertSession(session)
        try topicStore.insertTopic(
            Topic(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000422")!,
                sessionID: session.id,
                startedAt: Date(timeIntervalSince1970: 1_700_401_010),
                summaryStatus: .idle
            )
        )

        #expect(try service.recover() == 0)
    }
}

private final class InMemorySessionStore: SessionStore, @unchecked Sendable {
    var sessions: [Session] = []

    func initialize() throws {}

    func listSessions() throws -> [Session] {
        sessions.sorted { $0.startedAt > $1.startedAt }
    }

    func insertSession(_ session: Session) throws {
        sessions.append(session)
    }

    func updateSession(_ session: Session) throws {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[index] = session
    }
}

private final class InMemoryRecoveryTopicStore: TopicStore, @unchecked Sendable {
    var topics: [Topic] = []

    func listTopics(sessionID: UUID) throws -> [Topic] {
        topics
            .filter { $0.sessionID == sessionID }
            .sorted { $0.startedAt < $1.startedAt }
    }

    func insertTopic(_ topic: Topic) throws {
        topics.append(topic)
    }

    func updateTopic(_ topic: Topic) throws {
        guard let index = topics.firstIndex(where: { $0.id == topic.id }) else { return }
        topics[index] = topic
    }
}
