import AppCore
import Foundation

@MainActor
struct AppRuntime {
    let paths: WorkspacePaths
    let sessionStore: SQLiteSessionStore
    let sessionService: SessionService
    let microphoneRecorder: MicrophoneRecorder
    let audioPlaybackController: AudioPlaybackController
    let whisperTranscriber: WhisperCLITranscriber
    let transcriptionJobRunner: TranscriptionJobRunner
    let captureRuntime: CaptureRuntime
    let initialSessions: [Session]
    let diagnostics: AppDiagnostics

    static func bootstrap() throws -> AppRuntime {
        let microphoneRecorder = MicrophoneRecorder()
        let audioPlaybackController = AudioPlaybackController()
        let root = try WorkspaceLocator.defaultRoot()
        let paths = WorkspacePaths(root: root)
        let bootstrap = BootstrapWorkspace(fileManager: LocalFileManager())
        _ = try bootstrap.run(paths: paths)
        let whisperTranscriber = WhisperCLITranscriber(
            configuration: .developmentDefault(modelsRootDirectory: paths.models.path(percentEncoded: false))
        )
        let sessionStore = SQLiteSessionStore(databaseURL: paths.database)
        let sessionService = SessionService(
            sessionStore: sessionStore,
            clock: SystemClock()
        )
        let transcriptionJobRunner = TranscriptionJobRunner(
            paths: paths,
            jobStore: sessionStore,
            transcriptArtifactStore: sessionStore,
            transcriber: whisperTranscriber,
            clock: SystemClock()
        )
        let topicAssignmentService = TopicAssignmentService(
            topicStore: sessionStore,
            utteranceStore: sessionStore
        )
        let captureRuntime = CaptureRuntime(
            captureController: AVAudioCaptureController(),
            utteranceStore: sessionStore,
            recordingArtifactStore: sessionStore,
            clock: SystemClock(),
            topicAssignmentService: topicAssignmentService
        )

        try sessionStore.initialize()
        let sessions = try sessionService.loadSessions()

        return AppRuntime(
            paths: paths,
            sessionStore: sessionStore,
            sessionService: sessionService,
            microphoneRecorder: microphoneRecorder,
            audioPlaybackController: audioPlaybackController,
            whisperTranscriber: whisperTranscriber,
            transcriptionJobRunner: transcriptionJobRunner,
            captureRuntime: captureRuntime,
            initialSessions: sessions,
            diagnostics: AppDiagnostics(
                paths: paths,
                recordingActive: microphoneRecorder.isRecording,
                whisperConfiguration: whisperTranscriber.configuration
            )
        )
    }
}
