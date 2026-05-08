import Foundation

public struct TranscriptArtifactMetadata: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let utteranceID: UUID
    public let transcriptionJobID: UUID
    public let filePath: String
    public let text: String
    public let modelIdentifier: String
    public let language: String
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        utteranceID: UUID,
        transcriptionJobID: UUID,
        filePath: String,
        text: String,
        modelIdentifier: String,
        language: String,
        createdAt: Date
    ) {
        self.id = id
        self.utteranceID = utteranceID
        self.transcriptionJobID = transcriptionJobID
        self.filePath = filePath
        self.text = text
        self.modelIdentifier = modelIdentifier
        self.language = language
        self.createdAt = createdAt
    }
}
