import Foundation

public struct MeetingMinutes: Identifiable, Equatable, Sendable {
    public enum Status: String, Codable, Equatable, Sendable {
        case pending
        case running
        case completed
        case failed
    }

    public let id: UUID
    public let captureSessionID: UUID
    public let status: Status
    public let markdownText: String?
    public let errorMessage: String?
    public let modelIdentifier: String?
    public let createdAt: Date
    public let startedAt: Date?
    public let completedAt: Date?

    public init(
        id: UUID = UUID(),
        captureSessionID: UUID,
        status: Status = .pending,
        markdownText: String? = nil,
        errorMessage: String? = nil,
        modelIdentifier: String? = nil,
        createdAt: Date,
        startedAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.captureSessionID = captureSessionID
        self.status = status
        self.markdownText = markdownText
        self.errorMessage = errorMessage
        self.modelIdentifier = modelIdentifier
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.completedAt = completedAt
    }

    public func running(at date: Date) -> MeetingMinutes {
        MeetingMinutes(
            id: id,
            captureSessionID: captureSessionID,
            status: .running,
            markdownText: markdownText,
            errorMessage: nil,
            modelIdentifier: modelIdentifier,
            createdAt: createdAt,
            startedAt: date,
            completedAt: nil
        )
    }

    public func completed(
        markdownText: String,
        modelIdentifier: String,
        at date: Date
    ) -> MeetingMinutes {
        MeetingMinutes(
            id: id,
            captureSessionID: captureSessionID,
            status: .completed,
            markdownText: markdownText,
            errorMessage: nil,
            modelIdentifier: modelIdentifier,
            createdAt: createdAt,
            startedAt: startedAt,
            completedAt: date
        )
    }

    public func failed(errorMessage: String, at date: Date) -> MeetingMinutes {
        MeetingMinutes(
            id: id,
            captureSessionID: captureSessionID,
            status: .failed,
            markdownText: markdownText,
            errorMessage: errorMessage,
            modelIdentifier: modelIdentifier,
            createdAt: createdAt,
            startedAt: startedAt,
            completedAt: date
        )
    }

    public func reEnqueued() -> MeetingMinutes {
        MeetingMinutes(
            id: id,
            captureSessionID: captureSessionID,
            status: .pending,
            markdownText: markdownText,
            errorMessage: nil,
            modelIdentifier: modelIdentifier,
            createdAt: createdAt,
            startedAt: nil,
            completedAt: nil
        )
    }
}
