import AppCore
import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    let paths: WorkspacePaths
    let sessionService: SessionService
    let microphoneRecorder: MicrophoneRecorder
    let audioPlaybackController: AudioPlaybackController
    let whisperTranscriber: WhisperTranscriber
    @Published var selectedSessionID: Session.ID?
    @Published var activeRecordingSessionID: Session.ID?
    @Published var activePlaybackFilePath: String?
    @Published var sessions: [Session]
    @Published var diagnostics: AppDiagnostics
    @Published var errorMessage: String?

    static func bootstrap() throws -> AppState {
        let runtime = try AppRuntime.bootstrap()
        return AppState(
            paths: runtime.paths,
            sessionService: runtime.sessionService,
            microphoneRecorder: runtime.microphoneRecorder,
            audioPlaybackController: runtime.audioPlaybackController,
            whisperTranscriber: runtime.whisperTranscriber,
            selectedSessionID: runtime.initialSessions.first?.id,
            activeRecordingSessionID: nil,
            activePlaybackFilePath: nil,
            sessions: runtime.initialSessions,
            diagnostics: runtime.diagnostics,
            errorMessage: nil
        )
    }

    init(
        paths: WorkspacePaths,
        sessionService: SessionService,
        microphoneRecorder: MicrophoneRecorder,
        audioPlaybackController: AudioPlaybackController,
        whisperTranscriber: WhisperTranscriber,
        selectedSessionID: Session.ID?,
        activeRecordingSessionID: Session.ID?,
        activePlaybackFilePath: String?,
        sessions: [Session],
        diagnostics: AppDiagnostics,
        errorMessage: String?
    ) {
        self.paths = paths
        self.sessionService = sessionService
        self.microphoneRecorder = microphoneRecorder
        self.audioPlaybackController = audioPlaybackController
        self.whisperTranscriber = whisperTranscriber
        self.selectedSessionID = selectedSessionID
        self.activeRecordingSessionID = activeRecordingSessionID
        self.activePlaybackFilePath = activePlaybackFilePath
        self.sessions = sessions
        self.diagnostics = diagnostics
        self.errorMessage = errorMessage
        self.audioPlaybackController.onPlaybackStopped = { [weak self] in
            self?.activePlaybackFilePath = nil
        }
    }

    var selectedSession: Session? {
        guard let selectedSessionID else { return nil }
        return sessions.first { $0.id == selectedSessionID }
    }

    func createSession() {
        do {
            let session = try sessionService.createSession()
            sessions.insert(session, at: 0)
            selectedSessionID = session.id
            errorMessage = nil
            refreshDiagnostics()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startRecording() async {
        do {
            guard await microphoneRecorder.requestPermission() else {
                throw MicrophoneRecorderError.permissionDenied
            }

            let session = try draftSessionForRecording()
            let outputURL = paths.audio.appending(path: "\(session.id.uuidString).wav")
            try microphoneRecorder.startRecording(to: outputURL)

            let updatedSession = try sessionService.markRecordingStarted(
                session: session,
                audioFilePath: outputURL.path(percentEncoded: false)
            )
            try reloadSessions(selecting: updatedSession.id)
            activeRecordingSessionID = updatedSession.id
            errorMessage = nil
            refreshDiagnostics()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopRecording() async {
        do {
            guard let activeRecordingSessionID,
                  let session = sessions.first(where: { $0.id == activeRecordingSessionID }) else {
                throw MicrophoneRecorderError.notRecording
            }

            let artifact = try await microphoneRecorder.stopRecording()
            let completedSession = try sessionService.markRecordingCompleted(
                session: session,
                audioFilePath: artifact.fileURL.path(percentEncoded: false),
                durationSeconds: artifact.durationSeconds
            )
            try reloadSessions(selecting: completedSession.id)
            self.activeRecordingSessionID = nil
            errorMessage = nil
            refreshDiagnostics()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var isRecording: Bool {
        microphoneRecorder.isRecording
    }

    func togglePlaybackForSelectedSession() {
        do {
            guard let filePath = selectedSession?.audioFilePath else { return }
            try audioPlaybackController.play(filePath: filePath)
            activePlaybackFilePath = audioPlaybackController.isPlaying ? filePath : nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopPlayback() {
        audioPlaybackController.stop()
        activePlaybackFilePath = nil
    }

    var isPlayingSelectedSession: Bool {
        guard let filePath = selectedSession?.audioFilePath else { return false }
        return activePlaybackFilePath == filePath && audioPlaybackController.isPlaying
    }

    func transcribeSelectedSession() async {
        do {
            guard let session = selectedSession, let audioFilePath = session.audioFilePath else { return }

            let runningSession = try sessionService.markTranscriptionStarted(session: session)
            try reloadSessions(selecting: session.id)
            errorMessage = nil

            let artifact = try await whisperTranscriber.transcribe(
                audioFilePath: audioFilePath,
                outputDirectory: paths.transcripts.path(percentEncoded: false)
            )

            let completedSession = try sessionService.markTranscriptionCompleted(
                session: runningSession,
                transcriptText: artifact.transcriptText,
                transcriptFilePath: artifact.transcriptFilePath,
                durationSeconds: artifact.durationSeconds
            )
            try reloadSessions(selecting: completedSession.id)
        } catch {
            do {
                if let session = selectedSession {
                    let failedSession = try sessionService.markTranscriptionFailed(
                        session: session,
                        message: error.localizedDescription
                    )
                    try reloadSessions(selecting: failedSession.id)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            errorMessage = error.localizedDescription
        }
    }

    private func reloadSessions(selecting sessionID: Session.ID?) throws {
        sessions = try sessionService.loadSessions()
        selectedSessionID = sessionID ?? sessions.first?.id
    }

    private func draftSessionForRecording() throws -> Session {
        let session = try sessionService.ensureDraftSession(
            selectedSessionID: selectedSessionID,
            sessions: sessions
        )
        if !sessions.contains(where: { $0.id == session.id }) {
            sessions.insert(session, at: 0)
        }
        selectedSessionID = session.id
        return session
    }

    private func refreshDiagnostics() {
        diagnostics = AppDiagnostics(
            paths: paths,
            recordingActive: microphoneRecorder.isRecording,
            whisperConfiguration: whisperTranscriber.configuration
        )
    }
}
