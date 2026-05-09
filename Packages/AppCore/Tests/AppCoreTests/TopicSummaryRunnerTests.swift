import Foundation
import Testing
@testable import AppCore

struct TopicSummaryRunnerTests {
    private var sessionID: UUID {
        UUID(uuidString: "00000000-0000-0000-0000-000000000200")!
    }

    private var topicID: UUID {
        UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
    }

    @Test
    func runsSuccessfulSummary() async throws {
        let topicStore = InMemoryTopicStore()
        let utteranceStore = InMemoryUtteranceStore()
        let artifactStore = InMemoryTranscriptArtifactStore()
        let recorder = SummarizationRequestRecorder()

        let topic = makeTopic()
        try topicStore.insertTopic(topic)

        let utterance = makeUtterance()
        try utteranceStore.insertUtterance(utterance)
        try artifactStore.insertTranscriptArtifact(makeTranscriptArtifact(utteranceID: utterance.id, text: "会議の内容です"))

        let runner = makeRunner(
            topicStore: topicStore,
            utteranceStore: utteranceStore,
            artifactStore: artifactStore,
            result: .success("会議の要約テキスト"),
            recorder: recorder
        )
        let result = try await runner.run(topic: topic, contextProfile: .engineering)

        #expect(result.summaryStatus == .completed)
        #expect(result.summaryText == "会議の要約テキスト")
        #expect(result.summaryError == nil)

        let request = recorder.lastRequest
        #expect(request?.scope == .topic)
        #expect(request?.contextProfile == .engineering)
        #expect(request?.transcripts == ["会議の内容です"])

        let stored = try topicStore.listTopics(sessionID: sessionID).first!
        #expect(stored.summaryStatus == .completed)
        #expect(stored.summaryText == "会議の要約テキスト")
    }

    @Test
    func failsWhenNoTranscriptsAvailable() async throws {
        let topicStore = InMemoryTopicStore()
        let utteranceStore = InMemoryUtteranceStore()
        let artifactStore = InMemoryTranscriptArtifactStore()

        let topic = makeTopic()
        try topicStore.insertTopic(topic)

        let utterance = makeUtterance()
        try utteranceStore.insertUtterance(utterance)

        let runner = makeRunner(
            topicStore: topicStore,
            utteranceStore: utteranceStore,
            artifactStore: artifactStore,
            result: .success("should not run"),
            recorder: nil
        )

        do {
            _ = try await runner.run(topic: topic)
            Issue.record("Expected noTranscriptsAvailable error.")
        } catch TopicSummaryRunnerError.noTranscriptsAvailable {
            // expected — topic must not be updated to running
        }

        let stored = try topicStore.listTopics(sessionID: sessionID).first!
        #expect(stored.summaryStatus == .idle)
    }

    @Test
    func summaryFailureUpdatesTopicWithError() async throws {
        let topicStore = InMemoryTopicStore()
        let utteranceStore = InMemoryUtteranceStore()
        let artifactStore = InMemoryTranscriptArtifactStore()

        let topic = makeTopic()
        try topicStore.insertTopic(topic)

        let utterance = makeUtterance()
        try utteranceStore.insertUtterance(utterance)
        try artifactStore.insertTranscriptArtifact(makeTranscriptArtifact(utteranceID: utterance.id, text: "test"))

        let runner = makeRunner(
            topicStore: topicStore,
            utteranceStore: utteranceStore,
            artifactStore: artifactStore,
            result: .failure(FakeSummarizerError.modelFailed),
            recorder: nil
        )

        do {
            _ = try await runner.run(topic: topic)
            Issue.record("Expected summarizer failure.")
        } catch {
            let stored = try topicStore.listTopics(sessionID: sessionID).first!
            #expect(stored.summaryStatus == .failed)
            #expect(stored.summaryError != nil)
            #expect(stored.summaryText == nil)
        }
    }

    private func makeTopic() -> Topic {
        Topic(id: topicID, sessionID: sessionID, startedAt: Date(timeIntervalSince1970: 1_700_000_000))
    }

    private func makeUtterance() -> Utterance {
        Utterance(
            id: UUID(),
            sessionID: sessionID,
            topicID: topicID,
            startedAt: Date(timeIntervalSince1970: 1_700_000_010),
            endedAt: Date(timeIntervalSince1970: 1_700_000_020),
            durationSeconds: 10,
            audioFilePath: "/tmp/test.wav"
        )
    }

    private func makeTranscriptArtifact(utteranceID: UUID, text: String) -> TranscriptArtifactMetadata {
        TranscriptArtifactMetadata(
            id: UUID(),
            utteranceID: utteranceID,
            transcriptionJobID: UUID(),
            filePath: "/tmp/\(UUID().uuidString).txt",
            text: text,
            modelIdentifier: "fake",
            language: "ja",
            createdAt: Date(timeIntervalSince1970: 1_700_000_030)
        )
    }

    private func makeRunner(
        topicStore: InMemoryTopicStore,
        utteranceStore: InMemoryUtteranceStore,
        artifactStore: InMemoryTranscriptArtifactStore,
        result: Result<String, Error>,
        recorder: SummarizationRequestRecorder?
    ) -> TopicSummaryRunner {
        TopicSummaryRunner(
            topicStore: topicStore,
            utteranceStore: utteranceStore,
            transcriptArtifactStore: artifactStore,
            summarizer: FakeSummarizer(result: result, recorder: recorder)
        )
    }
}

private final class InMemoryTopicStore: TopicStore, @unchecked Sendable {
    var topics: [Topic] = []

    func listTopics(sessionID: UUID) throws -> [Topic] {
        topics.filter { $0.sessionID == sessionID }.sorted { $0.startedAt < $1.startedAt }
    }

    func insertTopic(_ topic: Topic) throws { topics.append(topic) }

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

    func insertUtterance(_ utterance: Utterance) throws { utterances.append(utterance) }

    func updateUtterance(_ utterance: Utterance) throws {
        guard let index = utterances.firstIndex(where: { $0.id == utterance.id }) else { return }
        utterances[index] = utterance
    }
}

private final class InMemoryTranscriptArtifactStore: TranscriptArtifactStore, @unchecked Sendable {
    var artifacts: [TranscriptArtifactMetadata] = []

    func listTranscriptArtifacts(utteranceID: UUID) throws -> [TranscriptArtifactMetadata] {
        artifacts.filter { $0.utteranceID == utteranceID }.sorted { $0.createdAt < $1.createdAt }
    }

    func insertTranscriptArtifact(_ artifact: TranscriptArtifactMetadata) throws {
        artifacts.append(artifact)
    }

    func updateTranscriptArtifact(_ artifact: TranscriptArtifactMetadata) throws {
        guard let index = artifacts.firstIndex(where: { $0.id == artifact.id }) else { return }
        artifacts[index] = artifact
    }
}

private final class SummarizationRequestRecorder: @unchecked Sendable {
    var lastRequest: SummarizationRequest?
}

private struct FakeSummarizer: Summarizer, @unchecked Sendable {
    var modelIdentifier: String { "fake-summarizer" }
    let result: Result<String, Error>
    let recorder: SummarizationRequestRecorder?

    func summarize(request: SummarizationRequest) async throws -> String {
        recorder?.lastRequest = request
        return try result.get()
    }
}

private enum FakeSummarizerError: LocalizedError {
    case modelFailed

    var errorDescription: String? {
        "Fake summarizer failed."
    }
}
