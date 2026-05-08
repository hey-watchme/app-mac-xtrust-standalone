import Foundation

public struct RecordingArtifactMetadata: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let utteranceID: UUID
    public let filePath: String
    public let byteSize: Int64
    public let durationSeconds: Double
    public let sampleRate: Int
    public let channelCount: Int
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        utteranceID: UUID,
        filePath: String,
        byteSize: Int64,
        durationSeconds: Double,
        sampleRate: Int,
        channelCount: Int,
        createdAt: Date
    ) {
        self.id = id
        self.utteranceID = utteranceID
        self.filePath = filePath
        self.byteSize = byteSize
        self.durationSeconds = durationSeconds
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.createdAt = createdAt
    }
}
