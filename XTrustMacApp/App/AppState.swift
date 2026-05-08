import AppCore
import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    typealias SessionPersistenceStore =
        RecordingArtifactStore &
        TopicStore &
        UtteranceStore &
        TranscriptionJobStore &
        TranscriptArtifactStore

    let paths: WorkspacePaths
    let sessionService: SessionService
    let persistenceStore: any SessionPersistenceStore
    let microphoneRecorder: MicrophoneRecorder
    let audioPlaybackController: AudioPlaybackController
    let whisperTranscriber: WhisperCLITranscriber
    let transcriptionJobRunner: TranscriptionJobRunner
    let captureRuntime: CaptureRuntime
    private var transcriptionRefreshTask: Task<Void, Never>?
    @Published var selectedSessionID: Session.ID?
    @Published var activeRecordingSessionID: Session.ID?
    @Published var activePlaybackFilePath: String?
    @Published var sessions: [Session]
    @Published var selectedSessionDetail: SessionDetailSnapshot?
    @Published var diagnostics: AppDiagnostics
    @Published var errorMessage: String?
    @Published var audioLevel: Float = 0
    @Published var isSpeechActive: Bool = false

    static func bootstrap() throws -> AppState {
        let runtime = try AppRuntime.bootstrap()
        return AppState(
            paths: runtime.paths,
            sessionService: runtime.sessionService,
            persistenceStore: runtime.sessionStore,
            microphoneRecorder: runtime.microphoneRecorder,
            audioPlaybackController: runtime.audioPlaybackController,
            whisperTranscriber: runtime.whisperTranscriber,
            transcriptionJobRunner: runtime.transcriptionJobRunner,
            captureRuntime: runtime.captureRuntime,
            selectedSessionID: runtime.initialSessions.first?.id,
            activeRecordingSessionID: nil,
            activePlaybackFilePath: nil,
            sessions: runtime.initialSessions,
            selectedSessionDetail: nil,
            diagnostics: runtime.diagnostics,
            errorMessage: nil
        )
    }

    init(
        paths: WorkspacePaths,
        sessionService: SessionService,
        persistenceStore: any SessionPersistenceStore,
        microphoneRecorder: MicrophoneRecorder,
        audioPlaybackController: AudioPlaybackController,
        whisperTranscriber: WhisperCLITranscriber,
        transcriptionJobRunner: TranscriptionJobRunner,
        captureRuntime: CaptureRuntime,
        selectedSessionID: Session.ID?,
        activeRecordingSessionID: Session.ID?,
        activePlaybackFilePath: String?,
        sessions: [Session],
        selectedSessionDetail: SessionDetailSnapshot?,
        diagnostics: AppDiagnostics,
        errorMessage: String?
    ) {
        self.paths = paths
        self.sessionService = sessionService
        self.persistenceStore = persistenceStore
        self.microphoneRecorder = microphoneRecorder
        self.audioPlaybackController = audioPlaybackController
        self.whisperTranscriber = whisperTranscriber
        self.transcriptionJobRunner = transcriptionJobRunner
        self.captureRuntime = captureRuntime
        self.selectedSessionID = selectedSessionID
        self.activeRecordingSessionID = activeRecordingSessionID
        self.activePlaybackFilePath = activePlaybackFilePath
        self.sessions = sessions
        self.selectedSessionDetail = selectedSessionDetail
        self.diagnostics = diagnostics
        self.errorMessage = errorMessage
        self.audioPlaybackController.onPlaybackStopped = { [weak self] in
            self?.activePlaybackFilePath = nil
        }
        captureRuntime.onUtteranceCreated = { [weak self] _, _ in
            self?.refreshSelectedSessionDetail()
        }
        captureRuntime.onSpeechStateChanged = { [weak self] active in
            self?.isSpeechActive = active
        }
        captureRuntime.onLevelUpdated = { [weak self] level in
            self?.audioLevel = level
        }
        captureRuntime.onError = { [weak self] error in
            self?.errorMessage = error.localizedDescription
        }
        refreshSelectedSessionDetail()
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
            refreshSelectedSessionDetail()
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

    var isListening: Bool { captureRuntime.isCapturing }

    func startListening() async {
        do {
            guard let sessionID = selectedSessionID else { return }
            guard await microphoneRecorder.requestPermission() else {
                throw MicrophoneRecorderError.permissionDenied
            }
            try captureRuntime.startCapture(
                sessionID: sessionID,
                utteranceOutputDirectory: paths.audio
            )
            errorMessage = nil
            refreshDiagnostics()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopListening() {
        captureRuntime.stopCapture()
        audioLevel = 0
        isSpeechActive = false
        refreshDiagnostics()
    }

    func transcribeUtterance(utteranceID: UUID) async {
        guard let sessionID = selectedSessionID,
              let utteranceDetail = selectedSessionDetail?.utterances.first(where: { $0.utterance.id == utteranceID }),
              let artifact = utteranceDetail.latestRecordingArtifact else {
            errorMessage = "No recording artifact found for this utterance."
            return
        }
        do {
            errorMessage = nil
            startTranscriptionRefreshLoop(selecting: sessionID)
            defer { stopTranscriptionRefreshLoop() }
            try await transcriptionJobRunner.run(
                utteranceID: utteranceID,
                recordingArtifact: artifact
            )
            try reloadSessions(selecting: sessionID)
        } catch {
            try? reloadSessions(selecting: sessionID)
            errorMessage = error.localizedDescription
        }
    }

    func transcribeSelectedSession() async {
        do {
            guard let session = selectedSession, let audioFilePath = session.audioFilePath else { return }
            let utteranceContext = try ensureTranscriptionContext(for: session, audioFilePath: audioFilePath)

            errorMessage = nil
            startTranscriptionRefreshLoop(selecting: session.id)
            defer { stopTranscriptionRefreshLoop() }

            try await transcriptionJobRunner.run(
                utteranceID: utteranceContext.utterance.id,
                recordingArtifact: utteranceContext.recordingArtifact
            )

            try reloadSessions(selecting: session.id)
        } catch {
            if let session = selectedSession {
                try? reloadSessions(selecting: session.id)
            }
            errorMessage = error.localizedDescription
        }
    }

    private func reloadSessions(selecting sessionID: Session.ID?) throws {
        sessions = try sessionService.loadSessions()
        selectedSessionID = sessionID ?? sessions.first?.id
        refreshSelectedSessionDetail()
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
        refreshSelectedSessionDetail()
        return session
    }

    private func refreshDiagnostics() {
        diagnostics = AppDiagnostics(
            paths: paths,
            recordingActive: microphoneRecorder.isRecording,
            whisperConfiguration: whisperTranscriber.configuration
        )
    }

    private func ensureTranscriptionContext(
        for session: Session,
        audioFilePath: String
    ) throws -> SessionTranscriptionContext {
        guard let durationSeconds = session.durationSeconds else {
            throw SessionTranscriptionContextError.sessionDurationMissing
        }

        let audioURL = URL(fileURLWithPath: audioFilePath)
        let standardizedAudioPath = audioURL.standardizedFileURL.path(percentEncoded: false)
        let workspaceAudioRoot = paths.audio.standardizedFileURL
            .path(percentEncoded: false)
            .replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        let audioParentDirectory = audioURL.deletingLastPathComponent().standardizedFileURL
            .path(percentEncoded: false)
            .replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        guard audioParentDirectory == workspaceAudioRoot else {
            throw SessionTranscriptionContextError.audioOutsideWorkspace(path: standardizedAudioPath)
        }

        guard FileManager.default.fileExists(atPath: standardizedAudioPath) else {
            throw SessionTranscriptionContextError.audioMissing(path: standardizedAudioPath)
        }

        let utterances = try persistenceStore.listUtterances(sessionID: session.id)
        let utterance = try existingOrNewUtterance(
            session: session,
            audioFilePath: standardizedAudioPath,
            durationSeconds: durationSeconds,
            utterances: utterances
        )

        let artifacts = try persistenceStore.listRecordingArtifacts(utteranceID: utterance.id)
        if let artifact = artifacts.first(where: { $0.filePath == standardizedAudioPath }) {
            return SessionTranscriptionContext(
                utterance: utterance,
                recordingArtifact: artifact
            )
        }

        let fileAttributes = try FileManager.default.attributesOfItem(atPath: standardizedAudioPath)
        let fileSize = (fileAttributes[.size] as? NSNumber)?.int64Value ?? 0
        guard fileSize > 0 else {
            throw SessionTranscriptionContextError.audioEmpty(path: standardizedAudioPath)
        }

        let artifact = RecordingArtifactMetadata(
            utteranceID: utterance.id,
            filePath: standardizedAudioPath,
            byteSize: fileSize,
            durationSeconds: durationSeconds,
            sampleRate: 16_000,
            channelCount: 1,
            createdAt: session.endedAt ?? session.startedAt
        )
        try persistenceStore.insertRecordingArtifact(artifact)

        return SessionTranscriptionContext(
            utterance: utterance,
            recordingArtifact: artifact
        )
    }

    private func existingOrNewUtterance(
        session: Session,
        audioFilePath: String,
        durationSeconds: Double,
        utterances: [Utterance]
    ) throws -> Utterance {
        if let existing = utterances.first(where: { $0.audioFilePath == audioFilePath }) {
            return existing
        }

        let utterance = Utterance(
            sessionID: session.id,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            durationSeconds: durationSeconds,
            audioFilePath: audioFilePath
        )
        try persistenceStore.insertUtterance(utterance)
        return utterance
    }

    private func startTranscriptionRefreshLoop(selecting sessionID: Session.ID) {
        stopTranscriptionRefreshLoop()
        transcriptionRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(350))
                } catch {
                    break
                }

                guard let self else { return }
                await self.refreshTranscriptionState(selecting: sessionID)
            }
        }
    }

    private func stopTranscriptionRefreshLoop() {
        transcriptionRefreshTask?.cancel()
        transcriptionRefreshTask = nil
    }

    private func refreshTranscriptionState(selecting sessionID: Session.ID) async {
        do {
            try reloadSessions(selecting: sessionID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshSelectedSessionDetail() {
        guard let session = selectedSession else {
            selectedSessionDetail = nil
            return
        }

        do {
            let topics = try persistenceStore.listTopics(sessionID: session.id)
            let utterances = try persistenceStore.listUtterances(sessionID: session.id)
            let utteranceDetails = try utterances.map { utterance in
                let recordingArtifacts = try persistenceStore.listRecordingArtifacts(utteranceID: utterance.id)
                let transcriptionJobs = try persistenceStore.listTranscriptionJobs(utteranceID: utterance.id)
                let transcriptArtifacts = try persistenceStore.listTranscriptArtifacts(utteranceID: utterance.id)

                return UtteranceDetailSnapshot(
                    utterance: utterance,
                    recordingArtifacts: recordingArtifacts,
                    transcriptionJobs: transcriptionJobs,
                    latestTranscriptionJob: transcriptionJobs.last,
                    transcriptArtifacts: transcriptArtifacts
                )
            }

            selectedSessionDetail = SessionDetailSnapshot(
                session: session,
                topics: topics,
                utterances: utteranceDetails.sorted { $0.utterance.startedAt < $1.utterance.startedAt }
            )
        } catch {
            selectedSessionDetail = nil
            errorMessage = error.localizedDescription
        }
    }

    var latestSelectedSessionJob: TranscriptionJob? {
        selectedSessionDetail?.utterances
            .compactMap(\.latestTranscriptionJob)
            .max { lhs, rhs in lhs.createdAt < rhs.createdAt }
    }

    func selectSession(_ sessionID: Session.ID?) {
        selectedSessionID = sessionID
        refreshSelectedSessionDetail()
    }
}

private struct SessionTranscriptionContext {
    let utterance: Utterance
    let recordingArtifact: RecordingArtifactMetadata
}

struct SessionDetailSnapshot {
    let session: Session
    let topics: [Topic]
    let utterances: [UtteranceDetailSnapshot]
}

struct UtteranceDetailSnapshot: Identifiable {
    let utterance: Utterance
    let recordingArtifacts: [RecordingArtifactMetadata]
    let transcriptionJobs: [TranscriptionJob]
    let latestTranscriptionJob: TranscriptionJob?
    let transcriptArtifacts: [TranscriptArtifactMetadata]

    var id: UUID {
        utterance.id
    }

    var latestRecordingArtifact: RecordingArtifactMetadata? {
        recordingArtifacts.last
    }

    var latestTranscriptArtifact: TranscriptArtifactMetadata? {
        transcriptArtifacts.last
    }
}

private enum SessionTranscriptionContextError: LocalizedError {
    case sessionDurationMissing
    case audioMissing(path: String)
    case audioEmpty(path: String)
    case audioOutsideWorkspace(path: String)

    var errorDescription: String? {
        switch self {
        case .sessionDurationMissing:
            return "Recording duration is missing for this session."
        case let .audioMissing(path):
            return "Recorded audio file was not found. Expected: \(path)"
        case let .audioEmpty(path):
            return "Recorded audio file is empty and cannot be transcribed. File: \(path)"
        case let .audioOutsideWorkspace(path):
            return "Recorded audio must remain inside the app workspace. File: \(path)"
        }
    }
}
