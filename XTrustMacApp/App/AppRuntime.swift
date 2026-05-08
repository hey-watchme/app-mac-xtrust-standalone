import AppCore
import Foundation

@MainActor
struct AppRuntime {
    let paths: WorkspacePaths
    let sessionService: SessionService
    let microphoneRecorder: MicrophoneRecorder
    let audioPlaybackController: AudioPlaybackController
    let whisperTranscriber: WhisperTranscriber
    let initialSessions: [Session]
    let diagnostics: AppDiagnostics

    static func bootstrap() throws -> AppRuntime {
        let microphoneRecorder = MicrophoneRecorder()
        let audioPlaybackController = AudioPlaybackController()
        let root = try WorkspaceLocator.defaultRoot()
        let paths = WorkspacePaths(root: root)
        let bootstrap = BootstrapWorkspace(fileManager: LocalFileManager())
        _ = try bootstrap.run(paths: paths)
        let whisperTranscriber = WhisperTranscriber(
            configuration: .developmentDefault(modelsRootDirectory: paths.models.path(percentEncoded: false))
        )
        let sessionStore = SQLiteSessionStore(databaseURL: paths.database)
        let sessionService = SessionService(
            sessionStore: sessionStore,
            clock: SystemClock()
        )

        try sessionStore.initialize()
        let sessions = try sessionService.loadSessions()

        return AppRuntime(
            paths: paths,
            sessionService: sessionService,
            microphoneRecorder: microphoneRecorder,
            audioPlaybackController: audioPlaybackController,
            whisperTranscriber: whisperTranscriber,
            initialSessions: sessions,
            diagnostics: AppDiagnostics(
                paths: paths,
                recordingActive: microphoneRecorder.isRecording,
                whisperConfiguration: whisperTranscriber.configuration
            )
        )
    }
}
