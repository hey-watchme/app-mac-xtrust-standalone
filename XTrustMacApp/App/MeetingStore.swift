import AppCore
import Foundation
import Observation

// Drives a single meeting at a time: live capture state, finalized utterances,
// and meeting minutes for the selected capture session.
@MainActor
@Observable
final class MeetingStore {
    private let engine: any MeetingCaptureEngine
    private let captureSessionService: CaptureSessionService
    private let liveMeetingRecorder: LiveMeetingRecorder
    private let minutesService: MeetingMinutesService
    private let utteranceStore: any UtteranceStore
    private let minutesStore: any MeetingMinutesStore
    private let audioDirectory: URL
    private let localeIdentifier = "ja-JP"

    private(set) var captureState: CaptureEngineState = .idle
    private(set) var audioLevel: Float = 0
    private(set) var volatileText: String = ""
    private(set) var utterances: [Utterance] = []
    private(set) var session: CaptureSession?
    private(set) var minutes: MeetingMinutes?
    private(set) var isGeneratingMinutes = false
    var errorMessage: String?

    // Wired by AppModel to keep the sidebar list in sync.
    @ObservationIgnored var onSessionUpserted: ((CaptureSession) -> Void)?
    @ObservationIgnored var onMinutesUpdated: ((MeetingMinutes) -> Void)?

    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var currentAudioFileURL: URL?

    init(
        engine: any MeetingCaptureEngine,
        captureSessionService: CaptureSessionService,
        liveMeetingRecorder: LiveMeetingRecorder,
        minutesService: MeetingMinutesService,
        utteranceStore: any UtteranceStore,
        minutesStore: any MeetingMinutesStore,
        audioDirectory: URL
    ) {
        self.engine = engine
        self.captureSessionService = captureSessionService
        self.liveMeetingRecorder = liveMeetingRecorder
        self.minutesService = minutesService
        self.utteranceStore = utteranceStore
        self.minutesStore = minutesStore
        self.audioDirectory = audioDirectory
    }

    var isCapturing: Bool {
        switch captureState {
        case .preparing, .listening, .stopping:
            return true
        case .idle, .stopped, .failed:
            return false
        }
    }

    // MARK: - Meeting lifecycle

    func startMeeting(context: SharedDeviceContext, accessSessionID: UUID?) async {
        guard !isCapturing else { return }
        errorMessage = nil

        let newSession: CaptureSession
        do {
            newSession = try captureSessionService.createCaptureSession(
                context: context,
                accessSessionID: accessSessionID
            )
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        session = newSession
        utterances = []
        minutes = nil
        volatileText = ""
        audioLevel = 0
        onSessionUpserted?(newSession)

        let audioFileURL = audioDirectory.appending(path: "\(newSession.id.uuidString).wav")
        currentAudioFileURL = audioFileURL

        await liveMeetingRecorder.begin(
            captureSessionID: newSession.id,
            sessionStartedAt: newSession.startedAt,
            locale: localeIdentifier
        )

        let stream = engine.start(CaptureStartRequest(
            localeIdentifier: localeIdentifier,
            audioFileURL: audioFileURL
        ))
        consumeEvents(stream)
    }

    func stopAndCloseMeeting() async {
        guard let current = session, case .listening = captureState else { return }

        let stopResult: CaptureStopResult
        do {
            stopResult = try await engine.stop()
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        // The event stream is finished at this point; drain remaining
        // finalized utterances before counting.
        await eventTask?.value
        eventTask = nil

        let utteranceCount = await liveMeetingRecorder.finish()
        audioLevel = 0
        volatileText = ""

        let closed: CaptureSession
        do {
            closed = try captureSessionService.close(
                current,
                endedAt: Date(),
                audioDurationSeconds: stopResult.durationSeconds,
                utteranceCount: utteranceCount
            )
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        session = closed
        onSessionUpserted?(closed)

        await generateMinutes(for: closed)
    }

    func retryMinutes() {
        guard let session, !isGeneratingMinutes, !isCapturing else { return }
        Task { await generateMinutes(for: session) }
    }

    // MARK: - Selection

    func selectSession(_ newSession: CaptureSession?) {
        guard !isCapturing else { return }
        errorMessage = nil
        captureState = .idle
        audioLevel = 0
        volatileText = ""
        session = newSession

        guard let newSession else {
            utterances = []
            minutes = nil
            return
        }
        do {
            utterances = try utteranceStore.listUtterances(captureSessionID: newSession.id)
            minutes = try minutesStore.getMeetingMinutes(captureSessionID: newSession.id)
        } catch {
            utterances = []
            minutes = nil
            errorMessage = error.localizedDescription
        }
    }

    // Applies a minutes update produced outside this store (e.g. launch recovery).
    func applyExternalMinutesUpdate(_ updated: MeetingMinutes) {
        guard session?.id == updated.captureSessionID else { return }
        minutes = updated
    }

    // MARK: - Export

    var transcriptMarkdown: String {
        guard let session else { return "" }

        var lines: [String] = []
        lines.append("# 議事録 — \(Self.titleFormatter.string(from: session.startedAt))")
        lines.append("")
        if let markdownText = minutes?.markdownText {
            lines.append(markdownText)
            lines.append("")
        }
        lines.append("## 文字起こし")
        if utterances.isEmpty {
            lines.append("（発話はありません）")
        } else {
            for utterance in utterances {
                lines.append("[\(Self.timestamp(fromSeconds: utterance.startOffsetSeconds))] \(utterance.text)")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Private

    private func generateMinutes(for session: CaptureSession) async {
        isGeneratingMinutes = true
        defer { isGeneratingMinutes = false }

        do {
            let queued = try minutesService.enqueue(captureSessionID: session.id)
            applyMinutes(queued)
            let completed = try await minutesService.run(
                queued,
                contextProfile: session.meetingContextProfile
            )
            applyMinutes(completed)
        } catch {
            // run() persists the failed state; reflect what is stored.
            if let stored = (try? minutesStore.getMeetingMinutes(captureSessionID: session.id)) ?? nil {
                applyMinutes(stored)
            }
            errorMessage = error.localizedDescription
        }
    }

    private func applyMinutes(_ updated: MeetingMinutes) {
        if session?.id == updated.captureSessionID {
            minutes = updated
        }
        onMinutesUpdated?(updated)
    }

    private func consumeEvents(_ stream: AsyncStream<CaptureEngineEvent>) {
        eventTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                await self.handle(event)
            }
        }
    }

    private func handle(_ event: CaptureEngineEvent) async {
        switch event {
        case let .stateChanged(newState):
            captureState = newState
            switch newState {
            case .listening:
                markRecordingStartedIfNeeded()
            case let .failed(failure):
                errorMessage = Self.failureMessage(failure)
                audioLevel = 0
                volatileText = ""
                _ = await liveMeetingRecorder.finish()
                closeSessionAfterFailureIfNeeded()
            default:
                break
            }
        case let .audioLevel(level):
            audioLevel = level
        case let .volatileTranscript(text):
            volatileText = text
        case let .finalizedUtterance(finalized):
            volatileText = ""
            do {
                let utterance = try await liveMeetingRecorder.record(finalized)
                if utterance.captureSessionID == session?.id {
                    utterances.append(utterance)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func markRecordingStartedIfNeeded() {
        guard let current = session, current.status == .open,
              let audioFileURL = currentAudioFileURL else { return }
        do {
            let updated = try captureSessionService.markRecordingStarted(
                current,
                audioFilePath: audioFileURL.path(percentEncoded: false)
            )
            session = updated
            onSessionUpserted?(updated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func closeSessionAfterFailureIfNeeded() {
        guard let current = session, current.status != .closed else { return }
        do {
            let closed = try captureSessionService.close(
                current,
                endedAt: Date(),
                audioDurationSeconds: nil,
                utteranceCount: utterances.count
            )
            session = closed
            onSessionUpserted?(closed)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func failureMessage(_ failure: CaptureEngineFailure) -> String {
        switch failure {
        case .microphonePermissionDenied:
            return "マイクへのアクセスが許可されていません。システム設定 > プライバシーとセキュリティで許可してください。"
        case let .localeNotSupported(identifier):
            return "音声認識がロケール \(identifier) に対応していません。"
        case let .assetInstallationFailed(message):
            return "音声認識アセットの準備に失敗しました: \(message)"
        case let .audioEngineFailed(message):
            return "オーディオ入力の開始に失敗しました: \(message)"
        case let .transcriberFailed(message):
            return "音声認識エンジンでエラーが発生しました: \(message)"
        }
    }

    private static let titleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy年M月d日（E） H:mm"
        return formatter
    }()

    static func timestamp(fromSeconds seconds: Double) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%02d:%02d:%02d", total / 3_600, (total % 3_600) / 60, total % 60)
    }
}
