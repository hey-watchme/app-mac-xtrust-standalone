import Foundation

public struct Topic: Identifiable, Equatable, Sendable {
    public enum Status: String, Codable, Equatable, Sendable {
        case active
        case completed
    }

    public enum SummaryStatus: String, Codable, Equatable, Sendable {
        case idle
        case running
        case completed
        case failed
    }

    public let id: UUID
    public let sessionID: UUID
    public let startedAt: Date
    public let endedAt: Date?
    public let status: Status
    public let summaryText: String?
    public let summaryStatus: SummaryStatus
    public let summaryError: String?

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        startedAt: Date,
        endedAt: Date? = nil,
        status: Status = .active,
        summaryText: String? = nil,
        summaryStatus: SummaryStatus = .idle,
        summaryError: String? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.summaryText = summaryText
        self.summaryStatus = summaryStatus
        self.summaryError = summaryError
    }
}
