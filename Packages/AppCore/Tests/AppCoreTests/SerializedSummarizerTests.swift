import Foundation
import Testing
@testable import AppCore

struct SerializedSummarizerTests {
    @Test
    func serializesConcurrentSummarizationRequests() async throws {
        let metrics = SummarizerMetrics()
        let base = RecordingSummarizer(metrics: metrics)
        let summarizer = SerializedSummarizer(base: base)

        async let first = summarizer.summarize(
            request: SummarizationRequest(
                scope: .transcriptChunk,
                contextProfile: .general,
                transcripts: ["first"]
            )
        )
        async let second = summarizer.summarize(
            request: SummarizationRequest(
                scope: .meetingMinutes,
                contextProfile: .engineering,
                transcripts: ["second"]
            )
        )

        let results = try await [first, second]

        #expect(results == ["summary:first", "summary:second"])
        #expect(await metrics.maxConcurrentCalls == 1)
        #expect(await metrics.recordedInputs == ["first", "second"])
    }
}

private actor SummarizerMetrics {
    private(set) var currentConcurrentCalls = 0
    private(set) var maxConcurrentCalls = 0
    private(set) var recordedInputs: [String] = []

    func beginCall(input: String) {
        currentConcurrentCalls += 1
        if currentConcurrentCalls > maxConcurrentCalls {
            maxConcurrentCalls = currentConcurrentCalls
        }
        recordedInputs.append(input)
    }

    func endCall() {
        currentConcurrentCalls -= 1
    }
}

private struct RecordingSummarizer: Summarizer {
    let metrics: SummarizerMetrics

    var modelIdentifier: String { "recording" }

    func summarize(request: SummarizationRequest) async throws -> String {
        let input = request.transcripts.joined(separator: " ")
        await metrics.beginCall(input: input)
        try await Task.sleep(for: .milliseconds(50))
        await metrics.endCall()
        return "summary:\(input)"
    }
}
