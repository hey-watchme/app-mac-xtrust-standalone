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
    let sharedDeviceContext: SharedDeviceContext
    let accessSessionService: AccessSessionService
    let staleSummaryRecoveryService: StaleSummaryRecoveryService
    let sessionService: SessionService
    let persistenceStore: any SessionPersistenceStore
    let microphoneRecorder: MicrophoneRecorder
    let audioPlaybackController: AudioPlaybackController
    let moonshineTranscriber: MoonshineSherpaTranscriber
    let gemmaSummarizer: MLXSummarizer
    let summarySummarizer: any Summarizer
    let transcriptionJobRunner: TranscriptionJobRunner
    let topicSummaryRunner: TopicSummaryRunner
    let captureRuntime: CaptureRuntime
    let mlxChatRunner: MLXChatRunner
    private var transcriptionRefreshTask: Task<Void, Never>?
    private var summaryRefreshTask: Task<Void, Never>?
    private var summaryQueueTailTask: Task<Void, Never>?
    private var summaryQueueTailToken: UUID?
    private var recoveredStaleSummaryCount: Int
    private var visibleSessionIDs: Set<UUID>
    @Published var activeAccessSession: AccessSession?
    @Published var isShowingSettings: Bool
    @Published var isShowingChat: Bool
    @Published var isMeetingsSectionExpanded: Bool
    @Published var chatMessages: [ChatMessage]
    @Published var isChatLoading: Bool
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
    @Published var isSummaryQueueBusy: Bool = false
    @Published var maintenanceMessage: String?

    static func bootstrap() throws -> AppState {
        let runtime = try AppRuntime.bootstrap()
        return AppState(
            paths: runtime.paths,
            sharedDeviceContext: runtime.sharedDeviceContext,
            accessSessionService: runtime.accessSessionService,
            staleSummaryRecoveryService: runtime.staleSummaryRecoveryService,
            sessionService: runtime.sessionService,
            persistenceStore: runtime.sessionStore,
            microphoneRecorder: runtime.microphoneRecorder,
            audioPlaybackController: runtime.audioPlaybackController,
            moonshineTranscriber: runtime.moonshineTranscriber,
            gemmaSummarizer: runtime.gemmaSummarizer,
            summarySummarizer: runtime.summarySummarizer,
            transcriptionJobRunner: runtime.transcriptionJobRunner,
            topicSummaryRunner: runtime.topicSummaryRunner,
            captureRuntime: runtime.captureRuntime,
            mlxChatRunner: runtime.mlxChatRunner,
            activeAccessSession: runtime.initialAccessSession,
            isShowingSettings: false,
            isShowingChat: false,
            isMeetingsSectionExpanded: true,
            chatMessages: [],
            isChatLoading: false,
            selectedSessionID: runtime.initialSessions.first?.id,
            activePlaybackFilePath: nil,
            recoveredStaleSummaryCount: runtime.initialRecoveredStaleSummaryCount,
            visibleSessionIDs: Set(runtime.initialSessions.map(\.id)),
            sessions: runtime.initialSessions,
            selectedSessionDetail: nil,
            diagnostics: runtime.diagnostics,
            errorMessage: nil,
            maintenanceMessage: runtime.initialRecoveredStaleSummaryCount > 0
                ? "前回中断された要約を \(runtime.initialRecoveredStaleSummaryCount) 件回復しました。"
                : nil
        )
    }

    init(
        paths: WorkspacePaths,
        sharedDeviceContext: SharedDeviceContext,
        accessSessionService: AccessSessionService,
        staleSummaryRecoveryService: StaleSummaryRecoveryService,
        sessionService: SessionService,
        persistenceStore: any SessionPersistenceStore,
        microphoneRecorder: MicrophoneRecorder,
        audioPlaybackController: AudioPlaybackController,
        moonshineTranscriber: MoonshineSherpaTranscriber,
        gemmaSummarizer: MLXSummarizer,
        summarySummarizer: any Summarizer,
        transcriptionJobRunner: TranscriptionJobRunner,
        topicSummaryRunner: TopicSummaryRunner,
        captureRuntime: CaptureRuntime,
        mlxChatRunner: MLXChatRunner,
        activeAccessSession: AccessSession?,
        isShowingSettings: Bool,
        isShowingChat: Bool,
        isMeetingsSectionExpanded: Bool,
        chatMessages: [ChatMessage],
        isChatLoading: Bool,
        selectedSessionID: Session.ID?,
        activePlaybackFilePath: String?,
        recoveredStaleSummaryCount: Int,
        visibleSessionIDs: Set<UUID>,
        sessions: [Session],
        selectedSessionDetail: SessionDetailSnapshot?,
        diagnostics: AppDiagnostics,
        errorMessage: String?,
        maintenanceMessage: String?
    ) {
        self.paths = paths
        self.sharedDeviceContext = sharedDeviceContext
        self.accessSessionService = accessSessionService
        self.staleSummaryRecoveryService = staleSummaryRecoveryService
        self.sessionService = sessionService
        self.persistenceStore = persistenceStore
        self.microphoneRecorder = microphoneRecorder
        self.audioPlaybackController = audioPlaybackController
        self.moonshineTranscriber = moonshineTranscriber
        self.gemmaSummarizer = gemmaSummarizer
        self.summarySummarizer = summarySummarizer
        self.transcriptionJobRunner = transcriptionJobRunner
        self.topicSummaryRunner = topicSummaryRunner
        self.captureRuntime = captureRuntime
        self.mlxChatRunner = mlxChatRunner
        self.activeAccessSession = activeAccessSession
        self.isShowingSettings = isShowingSettings
        self.isShowingChat = isShowingChat
        self.isMeetingsSectionExpanded = isMeetingsSectionExpanded
        self.chatMessages = chatMessages
        self.isChatLoading = isChatLoading
        self.selectedSessionID = selectedSessionID
        self.activePlaybackFilePath = activePlaybackFilePath
        self.recoveredStaleSummaryCount = recoveredStaleSummaryCount
        self.visibleSessionIDs = visibleSessionIDs
        self.sessions = sessions
        self.selectedSessionDetail = selectedSessionDetail
        self.diagnostics = diagnostics
        self.errorMessage = errorMessage
        self.maintenanceMessage = maintenanceMessage
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
        guard activeAccessSession != nil else {
            errorMessage = "利用開始後にセッションを作成してください。"
            return
        }
        if isListening { stopListening() }
        do {
            let session = try sessionService.createSession()
            visibleSessionIDs.insert(session.id)
            sessions.insert(session, at: 0)
            isShowingSettings = false
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
            guard activeAccessSession != nil else {
                throw AppStateAccessError.accessRequired
            }
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
            _ = try await transcriptionJobRunner.run(
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
                _ = try await transcriptionJobRunner.run(
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
        sessions = try sessionService
            .loadSessions()
            .filter { visibleSessionIDs.contains($0.id) }
        selectedSessionID = sessionID ?? sessions.first?.id
        refreshSelectedSessionDetail()
    }

    private func refreshDiagnostics() {
        diagnostics = AppDiagnostics(
            paths: paths,
            sharedDeviceContext: sharedDeviceContext,
            accessActive: activeAccessSession != nil,
            activeAccessAccountDisplayName: activeAccessAccountDisplayName,
            recoveredStaleSummaryCount: recoveredStaleSummaryCount,
            recordingActive: captureRuntime.isCapturing,
            moonshineConfiguration: moonshineTranscriber.configuration,
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

    func requestTopicSummary(topicID: UUID) {
        guard let sessionID = selectedSessionID,
              let detail = selectedSessionDetail,
              let topic = detail.topics.first(where: { $0.id == topicID }) else {
            errorMessage = "Topic not found."
            return
        }
        enqueueSummaryJob {
            await self.performTopicSummary(
                sessionID: sessionID,
                topic: topic,
                contextProfile: detail.session.meetingContextProfile
            )
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
            .filter { !$0.isDiscardedNoise }

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

    var activeAccessAccountDisplayName: String? {
        guard let activeAccessSession else { return nil }
        if activeAccessSession.accountID == sharedDeviceContext.bootstrapAccount.id {
            return sharedDeviceContext.bootstrapAccount.displayName
        }
        return nil
    }

    func beginLocalAccess() {
        do {
            let session = try accessSessionService.beginAccess(
                deviceID: sharedDeviceContext.device.id,
                accountID: sharedDeviceContext.bootstrapAccount.id,
                authenticationMethod: .guest
            )
            activeAccessSession = session
            isShowingSettings = false
            isShowingChat = false
            visibleSessionIDs = []
            sessions = []
            selectedSessionID = nil
            selectedSessionDetail = nil
            meetingSummaryText = nil
            isSummarizingMeeting = false
            errorMessage = nil
            refreshDiagnostics()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func logoutActiveAccess() {
        guard let activeAccessSession else { return }
        if isListening { stopListening() }
        stopPlayback()
        do {
            _ = try accessSessionService.endAccess(activeAccessSession, status: .loggedOut)
            self.activeAccessSession = nil
            isShowingSettings = false
            isShowingChat = false
            visibleSessionIDs = []
            sessions = []
            selectedSessionID = nil
            selectedSessionDetail = nil
            meetingSummaryText = nil
            isSummarizingMeeting = false
            errorMessage = nil
            maintenanceMessage = nil
            refreshDiagnostics()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectSession(_ sessionID: Session.ID?) {
        isShowingSettings = false
        isShowingChat = false
        selectedSessionID = sessionID
        meetingSummaryText = nil
        refreshSelectedSessionDetail()
    }

    func showSettings() {
        isShowingSettings = true
        isShowingChat = false
        selectedSessionID = nil
        meetingSummaryText = nil
        refreshSelectedSessionDetail()
    }

    func showChat() {
        isShowingSettings = false
        isShowingChat = true
        selectedSessionID = nil
        meetingSummaryText = nil
        refreshSelectedSessionDetail()
    }

    func sendChatMessage(_ text: String) {
        let userMessage = ChatMessage(role: .user, text: text)
        chatMessages.append(userMessage)
        isChatLoading = true
        let snapshot = chatMessages
        Task { [weak self] in
            guard let self else { return }
            do {
                let reply = try await mlxChatRunner.chat(messages: snapshot)
                self.chatMessages.append(ChatMessage(role: .assistant, text: reply))
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isChatLoading = false
        }
    }

    func recoverStaleSummaries() {
        guard !isSummaryQueueBusy else {
            errorMessage = "要約処理中は stuck summary を解除できません。完了後に再実行してください。"
            return
        }

        do {
            let recoveredCount = try staleSummaryRecoveryService.recover()
            recoveredStaleSummaryCount += recoveredCount
            maintenanceMessage = recoveredCount == 0
                ? "解除対象の stuck summary はありません。"
                : "stuck summary を \(recoveredCount) 件解除しました。"
            errorMessage = nil
            refreshDiagnostics()
            refreshSelectedSessionDetail()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func enqueueSummaryJob(
        _ operation: @escaping @MainActor () async -> Void
    ) {
        errorMessage = nil
        isSummaryQueueBusy = true

        let previousTask = summaryQueueTailTask
        let token = UUID()
        summaryQueueTailToken = token
        summaryQueueTailTask = Task { @MainActor [weak self] in
            _ = await previousTask?.result
            guard let self else { return }
            await operation()
            self.finishSummaryJob(token: token)
        }
    }

    private func finishSummaryJob(token: UUID) {
        guard summaryQueueTailToken == token else { return }
        summaryQueueTailToken = nil
        summaryQueueTailTask = nil
        isSummaryQueueBusy = false
    }

    private func performTopicSummary(
        sessionID: Session.ID,
        topic: Topic,
        contextProfile: Session.MeetingContextProfile
    ) async {
        do {
            startSummaryRefreshLoop(selecting: sessionID)
            defer { stopSummaryRefreshLoop() }
            try await topicSummaryRunner.run(
                topic: topic,
                contextProfile: contextProfile
            )
            try reloadSessions(selecting: sessionID)
        } catch {
            try? reloadSessions(selecting: sessionID)
            errorMessage = error.localizedDescription
        }
    }

    private func performMeetingSummary(
        sessionID: Session.ID,
        contextProfile: Session.MeetingContextProfile,
        topicSummaries: [String]
    ) async {
        isSummarizingMeeting = true
        defer { isSummarizingMeeting = false }

        do {
            startSummaryRefreshLoop(selecting: sessionID)
            defer { stopSummaryRefreshLoop() }

            let request = SummarizationRequest(
                scope: .meeting,
                contextProfile: contextProfile,
                transcripts: topicSummaries
            )
            meetingSummaryText = try await summarySummarizer.summarize(request: request)
            try reloadSessions(selecting: sessionID)
        } catch {
            try? reloadSessions(selecting: sessionID)
            errorMessage = error.localizedDescription
        }
    }

    func requestMeetingSummary() {
        guard let sessionID = selectedSessionID,
              let detail = selectedSessionDetail else { return }
        let topicSummaries = detail.topics.compactMap(\.summaryText)
        guard !topicSummaries.isEmpty else {
            errorMessage = "要約できるトピックがありません。先にトピックの要約を実行してください。"
            return
        }
        enqueueSummaryJob {
            await self.performMeetingSummary(
                sessionID: sessionID,
                contextProfile: detail.session.meetingContextProfile,
                topicSummaries: topicSummaries
            )
        }
    }
}

private enum AppStateAccessError: LocalizedError {
    case accessRequired

    var errorDescription: String? {
        switch self {
        case .accessRequired:
            return "利用開始後に録音を開始してください。"
        }
    }
}

struct SessionDetailSnapshot {
    let session: Session
    let topics: [Topic]
    let utterances: [UtteranceDetailSnapshot]
}

struct ChatMessage: Identifiable, Sendable {
    enum Role: Sendable { case user, assistant }
    let id: UUID
    let role: Role
    let text: String
    let createdAt: Date

    init(role: Role, text: String) {
        self.id = UUID()
        self.role = role
        self.text = text
        self.createdAt = Date()
    }
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

    var isDiscardedNoise: Bool {
        latestTranscriptArtifact == nil && latestTranscriptionJob?.status == .discarded
    }
}
