import Foundation

public struct CaptureStartRequest: Equatable, Sendable {
    public let localeIdentifier: String
    public let audioFileURL: URL

    public init(localeIdentifier: String, audioFileURL: URL) {
        self.localeIdentifier = localeIdentifier
        self.audioFileURL = audioFileURL
    }
}

public struct CaptureStopResult: Equatable, Sendable {
    public let audioFileURL: URL
    public let durationSeconds: Double

    public init(audioFileURL: URL, durationSeconds: Double) {
        self.audioFileURL = audioFileURL
        self.durationSeconds = durationSeconds
    }
}

@MainActor
public protocol MeetingCaptureEngine: AnyObject {
    var state: CaptureEngineState { get }
    func start(_ request: CaptureStartRequest) -> AsyncStream<CaptureEngineEvent>
    func stop() async throws -> CaptureStopResult
}
