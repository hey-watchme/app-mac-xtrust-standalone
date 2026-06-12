import Foundation

public actor LiveMeetingRecorder {
    private let utteranceStore: any UtteranceStore
    private let clock: any Clock

    private var captureSessionID: UUID?
    private var sessionStartedAt: Date?
    private var locale: String = ""
    private var recordedCount = 0

    public init(utteranceStore: any UtteranceStore, clock: any Clock) {
        self.utteranceStore = utteranceStore
        self.clock = clock
    }

    public func begin(captureSessionID: UUID, sessionStartedAt: Date, locale: String) {
        self.captureSessionID = captureSessionID
        self.sessionStartedAt = sessionStartedAt
        self.locale = locale
        self.recordedCount = 0
    }

    @discardableResult
    public func record(_ event: FinalizedUtteranceEvent) throws -> Utterance {
        guard let captureSessionID, let sessionStartedAt else {
            throw LiveMeetingRecorderError.notRecording
        }

        let utterance = Utterance(
            captureSessionID: captureSessionID,
            startedAt: sessionStartedAt.addingTimeInterval(event.startOffsetSeconds),
            endedAt: sessionStartedAt.addingTimeInterval(event.endOffsetSeconds),
            startOffsetSeconds: event.startOffsetSeconds,
            endOffsetSeconds: event.endOffsetSeconds,
            text: event.text,
            locale: locale,
            createdAt: clock.now()
        )
        try utteranceStore.insertUtterance(utterance)
        recordedCount += 1
        return utterance
    }

    public func finish() -> Int {
        let count = recordedCount
        captureSessionID = nil
        sessionStartedAt = nil
        locale = ""
        recordedCount = 0
        return count
    }
}

public enum LiveMeetingRecorderError: Error, LocalizedError {
    case notRecording

    public var errorDescription: String? {
        switch self {
        case .notRecording:
            return "No capture session has been started for recording."
        }
    }
}
