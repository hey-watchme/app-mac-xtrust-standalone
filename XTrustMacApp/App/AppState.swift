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
    let gemmaSummarizer: MLXSummarizer
    let transcriptionJobRunner: TranscriptionJobRunner
    let topicSummaryRunner: TopicSummaryRunner
    let captureRuntime: CaptureRuntime
    private var transcriptionRefreshTask: Task<Void, Never>?
    private var summaryRefreshTask: Task<Void, Never>?
    @Published var selectedSessionID: Session.ID?
    @Published var activePlaybackFilePath: String?
    @Published var sessions: [Session]
    @Published var selectedSessionDetail: SessionDetailSnapshot?
    @Published var diagnostics: AppDiagnostics
    @Published var errorMessage: String?
    @Published var audioLevel: Float = 0
    @Published var isSpeechActive: Bool = false
    @Published var meetingSummaryText: String?
    @Published var isSummarizingMeeting: Bool = false

    static func bootstrap() throws -> AppState {
        let runtime = try AppRuntime.bootstrap()
        return AppState(
            paths: runtime.paths,
            sessionService: runtime.sessionService,
            persistenceStore: runtime.sessionStore,
            microphoneRecorder: runtime.microphoneRecorder,
            audioPlaybackController: runtime.audioPlaybackController,
            whisperTranscriber: runtime.whisperTranscriber,
            gemmaSummarizer: runtime.gemmaSummarizer,
            transcriptionJobRunner: runtime.transcriptionJobRunner,
            topicSummaryRunner: runtime.topicSummaryRunner,
            captureRuntime: runtime.captureRuntime,
            selectedSessionID: runtime.initialSessions.first?.id,
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
        gemmaSummarizer: MLXSummarizer,
        transcriptionJobRunner: TranscriptionJobRunner,
        topicSummaryRunner: TopicSummaryRunner,
        captureRuntime: CaptureRuntime,
        selectedSessionID: Session.ID?,
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
        self.gemmaSummarizer = gemmaSummarizer
        self.transcriptionJobRunner = transcriptionJobRunner
        self.topicSummaryRunner = topicSummaryRunner
        self.captureRuntime = captureRuntime
        self.selectedSessionID = selectedSessionID
        self.activePlaybackFilePath = activePlaybackFilePath
        self.sessions = sessions
        self.selectedSessionDetail = selectedSessionDetail
        self.diagnostics = diagnostics
        self.errorMessage = errorMessage
        self.audioPlaybackController.onPlaybackStopped = { [weak self] in
            self?.activePlaybackFilePath = nil
        }
        captureRuntime.onUtteranceCreated = { [weak self] utterance, artifact in
            self?.refreshSelectedSessionDetail()
            self?.autoTranscribeUtterance(utterance, artifact: artifact)
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

    private func autoTranscribeUtterance(_ utterance: Utterance, artifact: RecordingArtifactMetadata) {
        guard let sessionID = selectedSessionID else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                startTranscriptionRefreshLoop(selecting: sessionID)
                defer { stopTranscriptionRefreshLoop() }
                try await transcriptionJobRunner.run(
                    utteranceID: utterance.id,
                    recordingArtifact: artifact
                )
                try reloadSessions(selecting: sessionID)
            } catch {
                try? reloadSessions(selecting: sessionID)
                errorMessage = error.localizedDescription
            }
        }
    }

    private func reloadSessions(selecting sessionID: Session.ID?) throws {
        sessions = try sessionService.loadSessions()
        selectedSessionID = sessionID ?? sessions.first?.id
        refreshSelectedSessionDetail()
    }

    private func refreshDiagnostics() {
        diagnostics = AppDiagnostics(
            paths: paths,
            recordingActive: captureRuntime.isCapturing,
            whisperConfiguration: whisperTranscriber.configuration,
            mlxConfiguration: gemmaSummarizer.configuration
        )
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

    func summarizeTopic(topicID: UUID) async {
        guard let sessionID = selectedSessionID,
              let detail = selectedSessionDetail,
              let topic = detail.topics.first(where: { $0.id == topicID }) else {
            errorMessage = "Topic not found."
            return
        }
        do {
            errorMessage = nil
            startSummaryRefreshLoop(selecting: sessionID)
            defer { stopSummaryRefreshLoop() }
            try await topicSummaryRunner.run(
                topic: topic,
                contextProfile: detail.session.meetingContextProfile
            )
            try reloadSessions(selecting: sessionID)
        } catch {
            try? reloadSessions(selecting: sessionID)
            errorMessage = error.localizedDescription
        }
    }

    func setSessionStatus(_ status: Session.Status) {
        guard let session = selectedSession else { return }
        if status == .closed, isListening { stopListening() }
        do {
            let updated = try sessionService.setStatus(status, for: session)
            if let index = sessions.firstIndex(where: { $0.id == updated.id }) {
                sessions[index] = updated
            }
            refreshSelectedSessionDetail()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setMeetingContextProfile(_ profile: Session.MeetingContextProfile) {
        guard let session = selectedSession else { return }
        do {
            let updated = try sessionService.setMeetingContextProfile(profile, for: session)
            if let index = sessions.firstIndex(where: { $0.id == updated.id }) {
                sessions[index] = updated
            }
            refreshSelectedSessionDetail()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func wrapUpText(for detail: SessionDetailSnapshot) -> String {
        var lines: [String] = []
        let startStr = detail.session.startedAt.formatted(.dateTime.year().month().day().hour().minute())
        lines.append("# Session — \(startStr)")
        lines.append("Context Profile: \(detail.session.meetingContextProfile.rawValue)")
        lines.append("")

        for (index, topic) in detail.topics.enumerated() {
            let topicTime = topic.startedAt.formatted(.dateTime.hour().minute().second())
            lines.append("## Topic \(index + 1) — \(topicTime)")
            lines.append("")
            if let summaryText = topic.summaryText {
                lines.append("### Summary")
                lines.append(summaryText)
                lines.append("")
            }
            let topicUtterances = detail.utterances.filter { $0.utterance.topicID == topic.id }
            if !topicUtterances.isEmpty {
                lines.append("### Utterances")
                for ud in topicUtterances {
                    let t = ud.utterance.startedAt.formatted(.dateTime.hour().minute().second())
                    let text = ud.latestTranscriptArtifact?.text ?? "(not transcribed)"
                    lines.append("- [\(t)] \(text)")
                }
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func startSummaryRefreshLoop(selecting sessionID: Session.ID) {
        stopSummaryRefreshLoop()
        summaryRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(500)) } catch { break }
                guard let self else { return }
                try? self.reloadSessions(selecting: sessionID)
            }
        }
    }

    private func stopSummaryRefreshLoop() {
        summaryRefreshTask?.cancel()
        summaryRefreshTask = nil
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
        meetingSummaryText = nil
        refreshSelectedSessionDetail()
    }

    func summarizeMeeting() async {
        guard let detail = selectedSessionDetail else { return }
        let topicSummaries = detail.topics.compactMap(\.summaryText)
        guard !topicSummaries.isEmpty else {
            errorMessage = "要約できるトピックがありません。先にトピックの要約を実行してください。"
            return
        }
        isSummarizingMeeting = true
        errorMessage = nil
        do {
            let request = SummarizationRequest(
                scope: .meeting,
                contextProfile: detail.session.meetingContextProfile,
                transcripts: topicSummaries
            )
            meetingSummaryText = try await gemmaSummarizer.summarize(request: request)
        } catch {
            errorMessage = error.localizedDescription
        }
        isSummarizingMeeting = false
    }
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
