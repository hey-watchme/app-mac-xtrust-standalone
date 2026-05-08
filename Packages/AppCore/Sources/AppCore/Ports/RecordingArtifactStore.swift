import Foundation

public protocol RecordingArtifactStore: Sendable {
    func listRecordingArtifacts(utteranceID: UUID) throws -> [RecordingArtifactMetadata]
    func insertRecordingArtifact(_ artifact: RecordingArtifactMetadata) throws
    func updateRecordingArtifact(_ artifact: RecordingArtifactMetadata) throws
}
