import Foundation

public enum PreparingStep: Equatable, Sendable {
    case checkingPermission
    case checkingAssets
    case downloadingAssets(progress: Double?)
    case startingAudio
}

public enum CaptureEngineFailure: Equatable, Sendable {
    case microphonePermissionDenied
    case localeNotSupported(String)
    case assetInstallationFailed(String)
    case audioEngineFailed(String)
    case transcriberFailed(String)
}

public enum CaptureEngineState: Equatable, Sendable {
    case idle
    case preparing(PreparingStep)
    case listening
    case stopping
    case stopped
    case failed(CaptureEngineFailure)
}

public struct FinalizedUtteranceEvent: Equatable, Sendable {
    public let text: String
    public let startOffsetSeconds: Double
    public let endOffsetSeconds: Double

    public init(
        text: String,
        startOffsetSeconds: Double,
        endOffsetSeconds: Double
    ) {
        self.text = text
        self.startOffsetSeconds = startOffsetSeconds
        self.endOffsetSeconds = endOffsetSeconds
    }
}

public enum CaptureEngineEvent: Equatable, Sendable {
    case stateChanged(CaptureEngineState)
    case audioLevel(Float)
    case volatileTranscript(String)
    case finalizedUtterance(FinalizedUtteranceEvent)
}
