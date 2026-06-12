import Foundation

public struct MeetingMinutesService: Sendable {
    private let minutesStore: any MeetingMinutesStore
    private let utteranceStore: any UtteranceStore
    private let summarizer: any Summarizer
    private let clock: any Clock
    private let maxPromptCharacters: Int

    public init(
        minutesStore: any MeetingMinutesStore,
        utteranceStore: any UtteranceStore,
        summarizer: any Summarizer,
        clock: any Clock,
        maxPromptCharacters: Int = 12_000
    ) {
        self.minutesStore = minutesStore
        self.utteranceStore = utteranceStore
        self.summarizer = summarizer
        self.clock = clock
        self.maxPromptCharacters = maxPromptCharacters
    }

    @discardableResult
    public func enqueue(captureSessionID: UUID) throws -> MeetingMinutes {
        if let existing = try minutesStore.getMeetingMinutes(captureSessionID: captureSessionID) {
            let reEnqueued = existing.reEnqueued()
            try minutesStore.updateMeetingMinutes(reEnqueued)
            return reEnqueued
        }

        let minutes = MeetingMinutes(
            captureSessionID: captureSessionID,
            createdAt: clock.now()
        )
        try minutesStore.insertMeetingMinutes(minutes)
        return minutes
    }

    @discardableResult
    public func run(
        _ minutes: MeetingMinutes,
        contextProfile: MeetingContextProfile
    ) async throws -> MeetingMinutes {
        let running = minutes.running(at: clock.now())
        try minutesStore.updateMeetingMinutes(running)

        do {
            let utterances = try utteranceStore.listUtterances(
                captureSessionID: minutes.captureSessionID
            )
            let lines = utterances.map(transcriptLine(for:))
            guard !lines.isEmpty else {
                throw MeetingMinutesServiceError.emptyTranscript
            }

            let transcript = lines.joined(separator: "\n")
            let markdownText: String
            if transcript.count > maxPromptCharacters {
                var chunkSummaries: [String] = []
                for chunk in chunked(lines: lines) {
                    let summary = try await summarizer.summarize(
                        request: SummarizationRequest(
                            scope: .transcriptChunk,
                            contextProfile: contextProfile,
                            transcripts: [chunk.joined(separator: "\n")]
                        )
                    )
                    chunkSummaries.append(summary)
                }
                markdownText = try await summarizer.summarize(
                    request: SummarizationRequest(
                        scope: .meetingMinutes,
                        contextProfile: contextProfile,
                        transcripts: chunkSummaries
                    )
                )
            } else {
                markdownText = try await summarizer.summarize(
                    request: SummarizationRequest(
                        scope: .meetingMinutes,
                        contextProfile: contextProfile,
                        transcripts: [transcript]
                    )
                )
            }

            let completed = running.completed(
                markdownText: markdownText,
                modelIdentifier: summarizer.modelIdentifier,
                at: clock.now()
            )
            try minutesStore.updateMeetingMinutes(completed)
            return completed
        } catch {
            let failed = running.failed(
                errorMessage: failureMessage(for: error),
                at: clock.now()
            )
            try? minutesStore.updateMeetingMinutes(failed)
            throw error
        }
    }

    private func transcriptLine(for utterance: Utterance) -> String {
        "[\(timestamp(fromSeconds: utterance.startOffsetSeconds))] \(utterance.text)"
    }

    private func timestamp(fromSeconds seconds: Double) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%02d:%02d:%02d", total / 3_600, (total % 3_600) / 60, total % 60)
    }

    private func chunked(lines: [String]) -> [[String]] {
        var chunks: [[String]] = []
        var current: [String] = []
        var currentCount = 0

        for line in lines {
            let lineCount = line.count + 1
            if !current.isEmpty, currentCount + lineCount > maxPromptCharacters {
                chunks.append(current)
                current = []
                currentCount = 0
            }
            current.append(line)
            currentCount += lineCount
        }

        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks
    }

    private func failureMessage(for error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }
        return String(describing: error)
    }
}

public enum MeetingMinutesServiceError: Error, LocalizedError, Equatable {
    case emptyTranscript

    public var errorDescription: String? {
        switch self {
        case .emptyTranscript:
            return "Cannot generate meeting minutes because the transcript is empty."
        }
    }
}
