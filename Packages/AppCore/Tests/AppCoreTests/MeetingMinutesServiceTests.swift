import Foundation
import Testing
@testable import AppCore

struct MeetingMinutesServiceTests {
    @Test
    func enqueueInsertsPendingMinutes() throws {
        let minutesStore = InMemoryMeetingMinutesStore()
        let service = makeService(minutesStore: minutesStore)
        let captureSessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000701")!

        let minutes = try service.enqueue(captureSessionID: captureSessionID)

        #expect(minutes.captureSessionID == captureSessionID)
        #expect(minutes.status == .pending)
        #expect(try minutesStore.getMeetingMinutes(captureSessionID: captureSessionID) == minutes)
    }

    @Test
    func enqueueReEnqueuesExistingFailedMinutes() throws {
        let captureSessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000702")!
        let existing = MeetingMinutes(
            captureSessionID: captureSessionID,
            status: .failed,
            errorMessage: "boom",
            createdAt: Date(timeIntervalSince1970: 1_700_700_000),
            startedAt: Date(timeIntervalSince1970: 1_700_700_001),
            completedAt: Date(timeIntervalSince1970: 1_700_700_002)
        )
        let minutesStore = InMemoryMeetingMinutesStore(initialMinutes: [existing])
        let service = makeService(minutesStore: minutesStore)

        let reEnqueued = try service.enqueue(captureSessionID: captureSessionID)

        #expect(reEnqueued.id == existing.id)
        #expect(reEnqueued.status == .pending)
        #expect(reEnqueued.errorMessage == nil)
        #expect(reEnqueued.startedAt == nil)
        #expect(reEnqueued.completedAt == nil)
        #expect(try minutesStore.getMeetingMinutes(captureSessionID: captureSessionID) == reEnqueued)
    }

    @Test
    func runSummarizesShortTranscriptInSingleRequest() async throws {
        let captureSessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000711")!
        let minutesStore = InMemoryMeetingMinutesStore()
        let summarizer = RecordingMinutesSummarizer(results: ["# Minutes"])
        let utteranceStore = InMemoryMinutesUtteranceStore(
            utterances: [
                makeUtterance(captureSessionID: captureSessionID, startOffset: 0, text: "はじめます"),
                makeUtterance(captureSessionID: captureSessionID, startOffset: 65, text: "次の議題です"),
                makeUtterance(captureSessionID: captureSessionID, startOffset: 3_661, text: "終わります"),
            ]
        )
        let service = makeService(
            minutesStore: minutesStore,
            utteranceStore: utteranceStore,
            summarizer: summarizer
        )
        let minutes = try service.enqueue(captureSessionID: captureSessionID)

        let completed = try await service.run(minutes, contextProfile: .product)

        #expect(completed.status == .completed)
        #expect(completed.markdownText == "# Minutes")
        #expect(completed.modelIdentifier == "recording-minutes")
        #expect(completed.startedAt != nil)
        #expect(completed.completedAt != nil)

        let requests = await summarizer.requests()
        #expect(requests.count == 1)
        #expect(requests[0].scope == .meetingMinutes)
        #expect(requests[0].contextProfile == .product)
        #expect(requests[0].transcripts == [
            "[00:00:00] はじめます\n[00:01:05] 次の議題です\n[01:01:01] 終わります"
        ])
        #expect(try minutesStore.getMeetingMinutes(captureSessionID: captureSessionID) == completed)
    }

    @Test
    func runChunksLongTranscriptAtUtteranceBoundaries() async throws {
        let captureSessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000712")!
        let minutesStore = InMemoryMeetingMinutesStore()
        let summarizer = RecordingMinutesSummarizer(
            results: ["chunk-1", "chunk-2", "chunk-3", "# Combined"]
        )
        let utteranceStore = InMemoryMinutesUtteranceStore(
            utterances: [
                makeUtterance(captureSessionID: captureSessionID, startOffset: 0, text: "first utterance"),
                makeUtterance(captureSessionID: captureSessionID, startOffset: 10, text: "second utterance"),
                makeUtterance(captureSessionID: captureSessionID, startOffset: 20, text: "third utterance"),
            ]
        )
        let service = makeService(
            minutesStore: minutesStore,
            utteranceStore: utteranceStore,
            summarizer: summarizer,
            maxPromptCharacters: 10
        )
        let minutes = try service.enqueue(captureSessionID: captureSessionID)

        let completed = try await service.run(minutes, contextProfile: .general)

        #expect(completed.status == .completed)
        #expect(completed.markdownText == "# Combined")

        let requests = await summarizer.requests()
        #expect(requests.count == 4)
        #expect(requests[0].scope == .transcriptChunk)
        #expect(requests[0].transcripts == ["[00:00:00] first utterance"])
        #expect(requests[1].scope == .transcriptChunk)
        #expect(requests[1].transcripts == ["[00:00:10] second utterance"])
        #expect(requests[2].scope == .transcriptChunk)
        #expect(requests[2].transcripts == ["[00:00:20] third utterance"])
        #expect(requests[3].scope == .meetingMinutes)
        #expect(requests[3].transcripts == ["chunk-1", "chunk-2", "chunk-3"])
    }

    @Test
    func runPersistsFailureAndRethrowsWhenSummarizerFails() async throws {
        let captureSessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000713")!
        let minutesStore = InMemoryMeetingMinutesStore()
        let utteranceStore = InMemoryMinutesUtteranceStore(
            utterances: [
                makeUtterance(captureSessionID: captureSessionID, startOffset: 0, text: "hello")
            ]
        )
        let service = makeService(
            minutesStore: minutesStore,
            utteranceStore: utteranceStore,
            summarizer: FailingMinutesSummarizer()
        )
        let minutes = try service.enqueue(captureSessionID: captureSessionID)

        await #expect(throws: MinutesSummarizerError.self) {
            try await service.run(minutes, contextProfile: .general)
        }

        let persisted = try minutesStore.getMeetingMinutes(captureSessionID: captureSessionID)
        #expect(persisted?.status == .failed)
        #expect(persisted?.errorMessage == "summarizer exploded")
    }

    @Test
    func runFailsOnEmptyTranscript() async throws {
        let captureSessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000714")!
        let minutesStore = InMemoryMeetingMinutesStore()
        let service = makeService(minutesStore: minutesStore)
        let minutes = try service.enqueue(captureSessionID: captureSessionID)

        await #expect(throws: MeetingMinutesServiceError.emptyTranscript) {
            try await service.run(minutes, contextProfile: .general)
        }

        let persisted = try minutesStore.getMeetingMinutes(captureSessionID: captureSessionID)
        #expect(persisted?.status == .failed)
        #expect(persisted?.errorMessage?.isEmpty == false)
    }
}

private func makeService(
    minutesStore: InMemoryMeetingMinutesStore,
    utteranceStore: InMemoryMinutesUtteranceStore = InMemoryMinutesUtteranceStore(utterances: []),
    summarizer: any Summarizer = RecordingMinutesSummarizer(results: []),
    maxPromptCharacters: Int = 12_000
) -> MeetingMinutesService {
    MeetingMinutesService(
        minutesStore: minutesStore,
        utteranceStore: utteranceStore,
        summarizer: summarizer,
        clock: MinutesFixedClock(now: Date(timeIntervalSince1970: 1_700_700_100)),
        maxPromptCharacters: maxPromptCharacters
    )
}

private func makeUtterance(
    captureSessionID: UUID,
    startOffset: Double,
    text: String
) -> Utterance {
    let sessionStartedAt = Date(timeIntervalSince1970: 1_700_700_000)
    return Utterance(
        captureSessionID: captureSessionID,
        startedAt: sessionStartedAt.addingTimeInterval(startOffset),
        endedAt: sessionStartedAt.addingTimeInterval(startOffset + 2),
        startOffsetSeconds: startOffset,
        endOffsetSeconds: startOffset + 2,
        text: text,
        locale: "ja-JP",
        createdAt: sessionStartedAt.addingTimeInterval(startOffset + 2)
    )
}

private final class InMemoryMeetingMinutesStore: MeetingMinutesStore, @unchecked Sendable {
    private var minutes: [MeetingMinutes]

    init(initialMinutes: [MeetingMinutes] = []) {
        self.minutes = initialMinutes
    }

    func insertMeetingMinutes(_ newMinutes: MeetingMinutes) throws {
        minutes.append(newMinutes)
    }

    func updateMeetingMinutes(_ updatedMinutes: MeetingMinutes) throws {
        guard let index = minutes.firstIndex(where: { $0.id == updatedMinutes.id }) else { return }
        minutes[index] = updatedMinutes
    }

    func getMeetingMinutes(captureSessionID: UUID) throws -> MeetingMinutes? {
        minutes.first { $0.captureSessionID == captureSessionID }
    }

    func listMeetingMinutes(statuses: [MeetingMinutes.Status]) throws -> [MeetingMinutes] {
        minutes
            .filter { statuses.contains($0.status) }
            .sorted { $0.createdAt < $1.createdAt }
    }
}

private final class InMemoryMinutesUtteranceStore: UtteranceStore, @unchecked Sendable {
    private var utterances: [Utterance]

    init(utterances: [Utterance]) {
        self.utterances = utterances
    }

    func insertUtterance(_ utterance: Utterance) throws {
        utterances.append(utterance)
    }

    func listUtterances(captureSessionID: UUID) throws -> [Utterance] {
        utterances
            .filter { $0.captureSessionID == captureSessionID }
            .sorted { $0.startedAt < $1.startedAt }
    }
}

private actor MinutesRequestLog {
    private(set) var recorded: [SummarizationRequest] = []

    func append(_ request: SummarizationRequest) -> Int {
        recorded.append(request)
        return recorded.count - 1
    }
}

private struct RecordingMinutesSummarizer: Summarizer {
    let results: [String]
    private let log = MinutesRequestLog()

    var modelIdentifier: String { "recording-minutes" }

    func summarize(request: SummarizationRequest) async throws -> String {
        let index = await log.append(request)
        guard index < results.count else {
            return "summary-\(index)"
        }
        return results[index]
    }

    func requests() async -> [SummarizationRequest] {
        await log.recorded
    }
}

private struct FailingMinutesSummarizer: Summarizer {
    var modelIdentifier: String { "failing-minutes" }

    func summarize(request: SummarizationRequest) async throws -> String {
        throw MinutesSummarizerError.exploded
    }
}

private enum MinutesSummarizerError: Error, LocalizedError {
    case exploded

    var errorDescription: String? {
        "summarizer exploded"
    }
}

private struct MinutesFixedClock: Clock {
    let currentDate: Date

    init(now: Date) {
        self.currentDate = now
    }

    func now() -> Date {
        currentDate
    }
}
