import Foundation

public actor SerializedSummarizer: Summarizer {
    private let base: any Summarizer
    private var tailTask: Task<Void, Never>?

    public nonisolated var modelIdentifier: String {
        base.modelIdentifier
    }

    public init(base: any Summarizer) {
        self.base = base
    }

    public func summarize(request: SummarizationRequest) async throws -> String {
        let previousTask = tailTask

        return try await withCheckedThrowingContinuation { continuation in
            let task = Task { [base] in
                _ = await previousTask?.result

                do {
                    let result = try await base.summarize(request: request)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            tailTask = task
        }
    }
}
