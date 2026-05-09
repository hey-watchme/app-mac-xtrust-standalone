import Foundation

public struct TopicSummaryRunner: Sendable {
    private let topicStore: any TopicStore
    private let utteranceStore: any UtteranceStore
    private let transcriptArtifactStore: any TranscriptArtifactStore
    private let summarizer: any Summarizer

    public init(
        topicStore: any TopicStore,
        utteranceStore: any UtteranceStore,
        transcriptArtifactStore: any TranscriptArtifactStore,
        summarizer: any Summarizer
    ) {
        self.topicStore = topicStore
        self.utteranceStore = utteranceStore
        self.transcriptArtifactStore = transcriptArtifactStore
        self.summarizer = summarizer
    }

    @discardableResult
    public func run(
        topic: Topic,
        contextProfile: Session.MeetingContextProfile = .general
    ) async throws -> Topic {
        let utterances = try utteranceStore.listUtterances(topicID: topic.id)

        var transcripts: [String] = []
        for utterance in utterances {
            let artifacts = try transcriptArtifactStore.listTranscriptArtifacts(utteranceID: utterance.id)
            if let latest = artifacts.last {
                transcripts.append(latest.text)
            }
        }

        guard !transcripts.isEmpty else {
            throw TopicSummaryRunnerError.noTranscriptsAvailable(topicID: topic.id)
        }

        let runningTopic = topic.withSummaryRunning()
        try topicStore.updateTopic(runningTopic)

        do {
            let request = SummarizationRequest(
                scope: .topic,
                contextProfile: contextProfile,
                transcripts: transcripts
            )
            let summaryText = try await summarizer.summarize(request: request)
            let completedTopic = runningTopic.withSummaryCompleted(text: summaryText)
            try topicStore.updateTopic(completedTopic)
            return completedTopic
        } catch {
            let failedTopic = runningTopic.withSummaryFailed(error: error.localizedDescription)
            try topicStore.updateTopic(failedTopic)
            throw error
        }
    }
}

public enum TopicSummaryRunnerError: LocalizedError {
    case noTranscriptsAvailable(topicID: UUID)

    public var errorDescription: String? {
        switch self {
        case let .noTranscriptsAvailable(topicID):
            return "No transcribed utterances for topic \(topicID.uuidString). Transcribe utterances before summarizing."
        }
    }
}
