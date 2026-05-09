import Foundation

public struct SummarizationRequest: Sendable {
    public enum Scope: String, Sendable {
        case topic
        case meeting
    }

    public let scope: Scope
    public let contextProfile: Session.MeetingContextProfile
    public let transcripts: [String]

    public init(
        scope: Scope,
        contextProfile: Session.MeetingContextProfile,
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
