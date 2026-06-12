import AppCore
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    let paths: WorkspacePaths
    let sharedDeviceContext: SharedDeviceContext
    let accessSessionService: AccessSessionService
    let captureSessionStore: any CaptureSessionStore
    let minutesStore: any MeetingMinutesStore
    let minutesService: MeetingMinutesService
    let minutesRecoveryService: MinutesRecoveryService
    let mlxChatRunner: MLXChatRunner
    let mlxModelServer: MLXModelServer
    let mlxConfiguration: MLXSummarizerConfiguration
    let audioPlaybackController: AudioPlaybackController
    let meetingStore: MeetingStore

    var activeAccessSession: AccessSession?
    var isShowingSettings = false
    var isShowingChat = false
    var isMeetingsSectionExpanded = true
    var chatMessages: [ChatMessage] = []
    var isChatLoading = false
    var sessions: [CaptureSession] = []
    var selectedSessionID: UUID?
    var minutesStatusBySession: [UUID: MeetingMinutes.Status] = [:]
    var diagnostics: AppDiagnostics
    var errorMessage: String?
    var maintenanceMessage: String?

    @ObservationIgnored private var lastMlxServerStatus: MLXModelServerStatus?
    @ObservationIgnored private var speechAssetStatus: SpeechAssetStatus?
    @ObservationIgnored private var recoveredMinutesCount = 0

    static func bootstrap() throws -> AppModel {
        let runtime = try AppRuntime.bootstrap()
        return AppModel(runtime: runtime)
    }

    init(runtime: AppRuntime) {
        self.paths = runtime.paths
        self.sharedDeviceContext = runtime.sharedDeviceContext
        self.accessSessionService = runtime.accessSessionService
        self.captureSessionStore = runtime.sessionStore
        self.minutesStore = runtime.sessionStore
        self.minutesService = runtime.minutesService
        self.minutesRecoveryService = runtime.minutesRecoveryService
        self.mlxChatRunner = runtime.mlxChatRunner
        self.mlxModelServer = runtime.mlxModelServer
        self.mlxConfiguration = runtime.mlxConfiguration
        self.audioPlaybackController = runtime.audioPlaybackController
        self.meetingStore = runtime.meetingStore
        self.activeAccessSession = runtime.initialAccessSession
        self.diagnostics = runtime.diagnostics

        meetingStore.onSessionUpserted = { [weak self] session in
            self?.upsertSession(session)
        }
        meetingStore.onMinutesUpdated = { [weak self] minutes in
            self?.minutesStatusBySession[minutes.captureSessionID] = minutes.status
        }

        if activeAccessSession != nil {
            reloadSessions()
        }

        Task { [weak self] in
            await self?.runMinutesRecovery()
        }
        Task { [weak self] in
            await self?.refreshSpeechAssetStatus()
        }
    }

    // MARK: - Sessions

    var selectedSession: CaptureSession? {
        guard let selectedSessionID else { return nil }
        return sessions.first { $0.id == selectedSessionID }
    }

    func selectSession(_ sessionID: UUID?) {
        guard !meetingStore.isCapturing else {
            errorMessage = "録音中は他の会議を選択できません。先に会議を終了してください。"
            return
        }
        isShowingSettings = false
        isShowingChat = false
        selectedSessionID = sessionID
        meetingStore.selectSession(sessions.first { $0.id == sessionID })
    }

    func startMeeting() {
        guard let activeAccessSession else {
            errorMessage = "利用開始後に会議を開始してください。"
            return
        }
        guard !meetingStore.isCapturing else { return }
        isShowingSettings = false
        isShowingChat = false
        errorMessage = nil
        Task { [weak self] in
            guard let self else { return }
            await self.meetingStore.startMeeting(
                context: self.sharedDeviceContext,
                accessSessionID: activeAccessSession.id
            )
        }
    }

    func stopMeeting() {
        Task { [weak self] in
            await self?.meetingStore.stopAndCloseMeeting()
        }
    }

    private func upsertSession(_ session: CaptureSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.insert(session, at: 0)
        }
        selectedSessionID = session.id
    }

    private func reloadSessions() {
        do {
            sessions = try captureSessionStore
                .listCaptureSessions()
                .sorted { $0.startedAt > $1.startedAt }
            reloadMinutesStatuses()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reloadMinutesStatuses() {
        let all = (try? minutesStore.listMeetingMinutes(
            statuses: [.pending, .running, .completed, .failed]
        )) ?? []
        minutesStatusBySession = Dictionary(
            all.map { ($0.captureSessionID, $0.status) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    // MARK: - Access session

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
            selectedSessionID = nil
            meetingStore.selectSession(nil)
            reloadSessions()
            errorMessage = nil
            refreshDiagnostics()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func logoutActiveAccess() {
        guard let activeAccessSession else { return }
        guard !meetingStore.isCapturing else {
            errorMessage = "録音中は退出できません。先に会議を終了してください。"
            return
        }
        do {
            _ = try accessSessionService.endAccess(activeAccessSession, status: .loggedOut)
            self.activeAccessSession = nil
            isShowingSettings = false
            isShowingChat = false
            chatMessages = []
            sessions = []
            minutesStatusBySession = [:]
            selectedSessionID = nil
            meetingStore.selectSession(nil)
            errorMessage = nil
            maintenanceMessage = nil
            refreshDiagnostics()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Navigation

    func showSettings() {
        isShowingSettings = true
        isShowingChat = false
        refreshDiagnostics()
    }

    func showChat() {
        isShowingSettings = false
        isShowingChat = true
    }

    // MARK: - Chat

    func sendChatMessage(
        _ text: String,
        imagePath: String? = nil,
        attachedFileName: String? = nil,
        attachedTextContent: String? = nil
    ) {
        let userMessage = ChatMessage(
            role: .user,
            text: text,
            imagePath: imagePath,
            attachedFileName: attachedFileName,
            attachedTextContent: attachedTextContent
        )
        chatMessages.append(userMessage)
        isChatLoading = true
        let snapshot = chatMessages
        Task { [weak self] in
            guard let self else { return }
            do {
                let reply = try await self.mlxChatRunner.chat(messages: snapshot)
                self.chatMessages.append(ChatMessage(role: .assistant, text: reply))
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isChatLoading = false
        }
    }

    // MARK: - Minutes recovery

    private func runMinutesRecovery() async {
        let pending: [MeetingMinutes]
        do {
            pending = try minutesRecoveryService.recover()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        guard !pending.isEmpty else { return }

        recoveredMinutesCount = pending.count
        maintenanceMessage = "前回未完了だった議事録 \(pending.count) 件を再開します。"
        refreshDiagnostics()

        let allSessions = (try? captureSessionStore.listCaptureSessions()) ?? []
        for minutes in pending {
            minutesStatusBySession[minutes.captureSessionID] = .running
            let profile = allSessions
                .first { $0.id == minutes.captureSessionID }?
                .meetingContextProfile ?? .general
            do {
                let completed = try await minutesService.run(minutes, contextProfile: profile)
                minutesStatusBySession[completed.captureSessionID] = completed.status
                meetingStore.applyExternalMinutesUpdate(completed)
            } catch {
                if let stored = (try? minutesStore.getMeetingMinutes(
                    captureSessionID: minutes.captureSessionID
                )) ?? nil {
                    minutesStatusBySession[stored.captureSessionID] = stored.status
                    meetingStore.applyExternalMinutesUpdate(stored)
                }
            }
        }
        maintenanceMessage = "未完了だった議事録の再開処理が完了しました。"
    }

    // MARK: - Diagnostics

    func refreshDiagnostics() {
        diagnostics = AppDiagnostics(
            paths: paths,
            sharedDeviceContext: sharedDeviceContext,
            accessActive: activeAccessSession != nil,
            activeAccessAccountDisplayName: activeAccessAccountDisplayName,
            recoveredMinutesCount: recoveredMinutesCount,
            recordingActive: meetingStore.isCapturing,
            mlxConfiguration: mlxConfiguration,
            mlxServerStatus: lastMlxServerStatus,
            speechAssetStatus: speechAssetStatus
        )
    }

    func refreshSpeechAssetStatus() async {
        speechAssetStatus = await SpeechAssetStatusProvider.status()
        refreshDiagnostics()
    }

    func refreshMlxServerStatus() async {
        // status() is a passive read; it never spawns the server process.
        lastMlxServerStatus = await mlxModelServer.status()
        refreshDiagnostics()
    }

    func stopMlxServer() async {
        await mlxModelServer.stop()
        await refreshMlxServerStatus()
    }
}

struct ChatMessage: Identifiable, Sendable {
    enum Role: Sendable { case user, assistant }
    let id: UUID
    let role: Role
    let text: String
    let imagePath: String?
    let attachedFileName: String?
    let attachedTextContent: String?
    let createdAt: Date

    init(
        role: Role,
        text: String,
        imagePath: String? = nil,
        attachedFileName: String? = nil,
        attachedTextContent: String? = nil
    ) {
        self.id = UUID()
        self.role = role
        self.text = text
        self.imagePath = imagePath
        self.attachedFileName = attachedFileName
        self.attachedTextContent = attachedTextContent
        self.createdAt = Date()
    }
}
