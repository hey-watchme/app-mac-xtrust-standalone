import Foundation

public protocol TranscriptionJobStore: Sendable {
    func listTranscriptionJobs(utteranceID: UUID) throws -> [TranscriptionJob]
    func insertTranscriptionJob(_ job: TranscriptionJob) throws
    func updateTranscriptionJob(_ job: TranscriptionJob) throws
}
