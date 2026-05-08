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
    let initialErrorMessage: String?

    static func bootstrap() -> AppRuntime {
        let microphoneRecorder = MicrophoneRecorder()
        let audioPlaybackController = AudioPlaybackController()

        do {
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
                    usingFallbackWorkspace: false,
                    usingUnavailableServices: false,
                    recordingActive: microphoneRecorder.isRecording,
                    whisperConfiguration: whisperTranscriber.configuration
                ),
                initialErrorMessage: nil
            )
        } catch {
            let fallbackRoot = FileManager.default.temporaryDirectory
                .appending(path: "xtrust-mac-local-first-fallback", directoryHint: .isDirectory)
            let fallbackPaths = WorkspacePaths(root: fallbackRoot)
            let whisperTranscriber = WhisperTranscriber(
                configuration: .developmentDefault(modelsRootDirectory: fallbackPaths.models.path(percentEncoded: false))
            )

            return AppRuntime(
                paths: fallbackPaths,
                sessionService: SessionService(
                    sessionStore: UnavailableSessionStore(),
                    clock: SystemClock()
                ),
                microphoneRecorder: microphoneRecorder,
                audioPlaybackController: audioPlaybackController,
                whisperTranscriber: whisperTranscriber,
                initialSessions: [],
                diagnostics: AppDiagnostics(
                    paths: fallbackPaths,
                    usingFallbackWorkspace: true,
                    usingUnavailableServices: true,
                    recordingActive: microphoneRecorder.isRecording,
                    whisperConfiguration: whisperTranscriber.configuration
                ),
                initialErrorMessage: error.localizedDescription
            )
        }
    }
}

private struct UnavailableSessionStore: SessionStore {
    func initialize() throws {}

    func listSessions() throws -> [Session] {
        []
    }

    func insertSession(_ session: Session) throws {
        throw AppRuntimeError.unavailable
    }

    func updateSession(_ session: Session) throws {
        throw AppRuntimeError.unavailable
    }
}

private enum AppRuntimeError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "Session store is unavailable."
    }
}
