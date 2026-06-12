import Foundation

public struct Utterance: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let captureSessionID: UUID
    public let startedAt: Date
    public let endedAt: Date
    public let startOffsetSeconds: Double
    public let endOffsetSeconds: Double
    public let text: String
    public let locale: String
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        captureSessionID: UUID,
        startedAt: Date,
        endedAt: Date,
        startOffsetSeconds: Double,
        endOffsetSeconds: Double,
        text: String,
        locale: String,
        createdAt: Date
    ) {
        self.id = id
        self.captureSessionID = captureSessionID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.startOffsetSeconds = startOffsetSeconds
        self.endOffsetSeconds = endOffsetSeconds
        self.text = text
        self.locale = locale
        self.createdAt = createdAt
    }
}
