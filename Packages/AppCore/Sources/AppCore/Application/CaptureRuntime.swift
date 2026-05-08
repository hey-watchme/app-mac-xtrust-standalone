import Foundation

@MainActor
public final class CaptureRuntime {
    private let captureController: any CaptureController
    private let utteranceStore: any UtteranceStore
    private let recordingArtifactStore: any RecordingArtifactStore
    private let clock: any Clock
    private let topicAssignmentService: TopicAssignmentService

    public private(set) var isCapturing = false
    public private(set) var isSpeechActive = false
    public var onUtteranceCreated: (@MainActor (Utterance, RecordingArtifactMetadata) -> Void)?
    public var onSpeechStateChanged: (@MainActor (Bool) -> Void)?
    public var onLevelUpdated: (@MainActor (Float) -> Void)?
    public var onError: (@MainActor (Error) -> Void)?

    public init(
        captureController: any CaptureController,
        utteranceStore: any UtteranceStore,
        recordingArtifactStore: any RecordingArtifactStore,
        clock: any Clock,
        topicAssignmentService: TopicAssignmentService
    ) {
        self.captureController = captureController
        self.utteranceStore = utteranceStore
        self.recordingArtifactStore = recordingArtifactStore
        self.clock = clock
        self.topicAssignmentService = topicAssignmentService
    }

    public func startCapture(sessionID: UUID, utteranceOutputDirectory: URL) throws {
        guard !isCapturing else { return }
        try FileManager.default.createDirectory(
            at: utteranceOutputDirectory,
            withIntermediateDirectories: true
        )
        try captureController.startCapture(utteranceOutputDirectory: utteranceOutputDirectory) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleEvent(event, sessionID: sessionID)
            }
        }
        isCapturing = true
    }

    public func stopCapture() {
        captureController.stopCapture()
        isCapturing = false
        isSpeechActive = false
    }

    private func handleEvent(_ event: CaptureEvent, sessionID: UUID) {
        switch event {
        case let .utteranceFinalized(audioFileURL, startedAt, endedAt, durationSeconds):
            do {
                let (utterance, artifact) = try persistUtterance(
                    sessionID: sessionID,
                    audioFileURL: audioFileURL,
                    startedAt: startedAt,
                    endedAt: endedAt,
                    durationSeconds: durationSeconds
                )
                do {
                    try topicAssignmentService.assignTopic(to: utterance)
                } catch {
                    onError?(error)
                }
                onUtteranceCreated?(utterance, artifact)
            } catch {
                onError?(error)
            }
        case let .levelUpdated(rmsLevel):
            onLevelUpdated?(rmsLevel)
        case .speechStarted:
            isSpeechActive = true
            onSpeechStateChanged?(true)
        case .speechStopped:
            isSpeechActive = false
            onSpeechStateChanged?(false)
        }
    }

    private func persistUtterance(
        sessionID: UUID,
        audioFileURL: URL,
        startedAt: Date,
        endedAt: Date,
        durationSeconds: Double
    ) throws -> (Utterance, RecordingArtifactMetadata) {
        let audioFilePath = audioFileURL.path(percentEncoded: false)
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: audioFilePath)
        let byteSize = (fileAttributes[.size] as? NSNumber)?.int64Value ?? 0

        let utterance = Utterance(
            sessionID: sessionID,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: durationSeconds,
            audioFilePath: audioFilePath
        )
        try utteranceStore.insertUtterance(utterance)

        let artifact = RecordingArtifactMetadata(
            utteranceID: utterance.id,
            filePath: audioFilePath,
            byteSize: byteSize,
            durationSeconds: durationSeconds,
            sampleRate: 16_000,
            channelCount: 1,
            createdAt: clock.now()
        )
        try recordingArtifactStore.insertRecordingArtifact(artifact)

        return (utterance, artifact)
    }
}
