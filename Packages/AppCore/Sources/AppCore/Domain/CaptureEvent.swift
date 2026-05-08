import Foundation

public enum CaptureEvent: Sendable {
    case utteranceFinalized(
        audioFileURL: URL,
        startedAt: Date,
        endedAt: Date,
        durationSeconds: Double
    )
    case levelUpdated(rmsLevel: Float)
    case speechStarted
    case speechStopped
}
