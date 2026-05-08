import Foundation

public protocol TranscriptArtifactStore: Sendable {
    func listTranscriptArtifacts(utteranceID: UUID) throws -> [TranscriptArtifactMetadata]
    func insertTranscriptArtifact(_ artifact: TranscriptArtifactMetadata) throws
    func updateTranscriptArtifact(_ artifact: TranscriptArtifactMetadata) throws
}
