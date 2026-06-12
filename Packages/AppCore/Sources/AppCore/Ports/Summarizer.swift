import Foundation

public struct SummarizationRequest: Sendable {
    public enum Scope: String, Sendable {
        case transcriptChunk
        case meetingMinutes
    }

    public let scope: Scope
    public let contextProfile: MeetingContextProfile
    public let transcripts: [String]

    public init(
        scope: Scope,
        contextProfile: MeetingContextProfile,
        transcripts: [String]
    ) {
        self.scope = scope
        self.contextProfile = contextProfile
        self.transcripts = transcripts
    }
}

public protocol Summarizer: Sendable {
    var modelIdentifier: String { get }
    func summarize(request: SummarizationRequest) async throws -> String
}
