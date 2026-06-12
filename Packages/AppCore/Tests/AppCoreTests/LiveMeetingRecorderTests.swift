import Foundation
import Testing
@testable import AppCore

struct LiveMeetingRecorderTests {
    @Test
    func recordsFinalizedUtterancesWithWallClockMapping() async throws {
        let store = InMemoryUtteranceStore()
        let createdAt = Date(timeIntervalSince1970: 1_700_600_500)
        let recorder = LiveMeetingRecorder(
            utteranceStore: store,
            clock: RecorderFixedClock(now: createdAt)
        )
        let captureSessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000601")!
        let sessionStartedAt = Date(timeIntervalSince1970: 1_700_600_000)

        await recorder.begin(
            captureSessionID: captureSessionID,
            sessionStartedAt: sessionStartedAt,
            locale: "ja-JP"
        )

        let first = try await recorder.record(
            FinalizedUtteranceEvent(text: "こんにちは", startOffsetSeconds: 1.5, endOffsetSeconds: 3.0)
        )
        let second = try await recorder.record(
            FinalizedUtteranceEvent(text: "次の議題です", startOffsetSeconds: 10.0, endOffsetSeconds: 14.5)
        )

        #expect(first.captureSessionID == captureSessionID)
        #expect(first.startedAt == sessionStartedAt.addingTimeInterval(1.5))
        #expect(first.endedAt == sessionStartedAt.addingTimeInterval(3.0))
        #expect(first.startOffsetSeconds == 1.5)
        #expect(first.endOffsetSeconds == 3.0)
        #expect(first.text == "こんにちは")
        #expect(first.locale == "ja-JP")
        #expect(first.createdAt == createdAt)

        #expect(second.startedAt == sessionStartedAt.addingTimeInterval(10.0))
        #expect(second.endedAt == sessionStartedAt.addingTimeInterval(14.5))

        let inserted = try store.listUtterances(captureSessionID: captureSessionID)
        #expect(inserted == [first, second])
    }

    @Test
    func finishReturnsRecordedCountAndResets() async throws {
        let store = InMemoryUtteranceStore()
        let recorder = LiveMeetingRecorder(
            utteranceStore: store,
            clock: RecorderFixedClock(now: Date(timeIntervalSince1970: 1_700_600_500))
        )
        await recorder.begin(
            captureSessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000611")!,
            sessionStartedAt: Date(timeIntervalSince1970: 1_700_600_000),
            locale: "ja-JP"
        )
        try await recorder.record(
            FinalizedUtteranceEvent(text: "a", startOffsetSeconds: 0, endOffsetSeconds: 1)
        )
        try await recorder.record(
            FinalizedUtteranceEvent(text: "b", startOffsetSeconds: 2, endOffsetSeconds: 3)
        )

        let count = await recorder.finish()

        #expect(count == 2)

        await #expect(throws: LiveMeetingRecorderError.self) {
            try await recorder.record(
                FinalizedUtteranceEvent(text: "c", startOffsetSeconds: 4, endOffsetSeconds: 5)
            )
        }
    }

    @Test
    func recordThrowsBeforeBegin() async {
        let recorder = LiveMeetingRecorder(
            utteranceStore: InMemoryUtteranceStore(),
            clock: RecorderFixedClock(now: Date(timeIntervalSince1970: 1_700_600_500))
        )

        await #expect(throws: LiveMeetingRecorderError.self) {
            try await recorder.record(
                FinalizedUtteranceEvent(text: "x", startOffsetSeconds: 0, endOffsetSeconds: 1)
            )
        }
    }
}

private final class InMemoryUtteranceStore: UtteranceStore, @unchecked Sendable {
    private var utterances: [Utterance] = []

    func insertUtterance(_ utterance: Utterance) throws {
        utterances.append(utterance)
    }

    func listUtterances(captureSessionID: UUID) throws -> [Utterance] {
        utterances
            .filter { $0.captureSessionID == captureSessionID }
            .sorted { $0.startedAt < $1.startedAt }
    }
}

private struct RecorderFixedClock: Clock {
    let currentDate: Date

    init(now: Date) {
        self.currentDate = now
    }

    func now() -> Date {
        currentDate
    }
}
