import Foundation

public protocol Summarizer: Sendable {
    var modelIdentifier: String { get }
    func summarize(transcripts: [String]) async throws -> String
}
