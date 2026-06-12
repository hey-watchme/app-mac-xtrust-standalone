import AppCore
import SwiftUI

struct MeetingDetailView: View {
    var model: AppModel

    private var store: MeetingStore { model.meetingStore }

    var body: some View {
        Group {
            if let session = store.session {
                content(session: session)
                    .navigationTitle(meetingTitle(from: session.startedAt))
            } else {
                emptyState
                    .navigationTitle("")
            }
        }
    }

    // MARK: - Content

    private func content(session: CaptureSession) -> some View {
        VStack(spacing: 0) {
            header(session: session)
            Divider()

            if store.isCapturing {
                liveArea
            } else {
                closedArea(session: session)
            }

            Divider()
            MeetingControlsBar(
                captureState: store.captureState,
                onStart: { model.startMeeting() },
                onStop: { model.stopMeeting() }
            )
        }
    }

    // MARK: - Header

    private func header(session: CaptureSession) -> some View {
        HStack(spacing: XT.S.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text(meetingTitle(from: session.startedAt))
                    .font(XT.F.displayTitle)
                    .foregroundStyle(XT.C.textPrimary)

                HStack(spacing: XT.S.sm) {
                    CaptureStatePill(state: store.captureState)

                    if !store.isCapturing {
                        XTCaptureStatusBadge(status: session.status)
                    }

                    if let duration = session.audioDurationSeconds {
                        Text("·")
                            .foregroundStyle(XT.C.textTertiary)
                        Text(formatDuration(duration))
                            .font(XT.F.caption)
                            .foregroundStyle(XT.C.textTertiary)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, XT.Layout.contentPadding)
        .frame(height: 64)
    }

    // MARK: - Live Area

    private var liveArea: some View {
        VStack(spacing: 0) {
            recordingStrip
                .padding(.horizontal, XT.Layout.contentPadding)
                .padding(.vertical, XT.S.lg)

            if let message = store.errorMessage {
                errorBanner(message)
                    .padding(.horizontal, XT.Layout.contentPadding)
                    .padding(.bottom, XT.S.md)
            }

            LiveTranscriptView(
                utterances: store.utterances,
                volatileText: store.volatileText
            )
        }
    }

    private var recordingStrip: some View {
        HStack(spacing: XT.S.lg) {
            if case .listening = store.captureState {
                RecordingDot()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(stripTitle)
                    .font(XT.F.body)
                    .fontWeight(.medium)
                    .foregroundStyle(XT.C.textPrimary)

                Text("Apple SpeechAnalyzer · 完全オンデバイス · ja-JP")
                    .font(XT.F.caption)
                    .foregroundStyle(XT.C.textTertiary)
            }

            Spacer()

            AudioLevelMeter(level: store.audioLevel)
                .frame(width: 88)
        }
        .padding(XT.S.lg)
        .background(XT.C.recordingBG)
        .clipShape(RoundedRectangle(cornerRadius: XT.R.lg))
        .overlay(
            RoundedRectangle(cornerRadius: XT.R.lg)
                .strokeBorder(XT.C.recordingBorder, lineWidth: 1)
        )
    }

    private var stripTitle: String {
        switch store.captureState {
        case .listening:
            return store.volatileText.isEmpty ? "録音中" : "発話を認識中"
        case .stopping:
            return "停止処理中…"
        default:
            return "準備中…"
        }
    }

    // MARK: - Closed Area

    private func closedArea(session: CaptureSession) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XT.S.xxl) {
                if let message = store.errorMessage {
                    errorBanner(message)
                }

                if session.status == .closed {
                    MinutesView(
                        minutes: store.minutes,
                        isGenerating: store.isGeneratingMinutes,
                        transcriptMarkdown: store.transcriptMarkdown,
                        onRetry: { store.retryMinutes() }
                    )
                }

                transcriptCard
            }
            .padding(XT.Layout.contentPadding)
            .frame(maxWidth: XT.Layout.contentMaxWidth)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var transcriptCard: some View {
        XTCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    XTSectionLabel(text: "文字起こし")
                    Spacer()
                    Text("\(store.utterances.count) 件")
                        .font(XT.F.caption)
                        .foregroundStyle(XT.C.textTertiary)
                }
                .padding(.horizontal, XT.S.lg)
                .padding(.top, XT.S.lg)
                .padding(.bottom, XT.S.md)

                Divider()
                    .padding(.horizontal, XT.S.md)

                if store.utterances.isEmpty {
                    Text("発話はありません")
                        .font(XT.F.body)
                        .foregroundStyle(XT.C.textTertiary)
                        .padding(XT.S.lg)
                } else {
                    VStack(alignment: .leading, spacing: XT.S.sm) {
                        ForEach(store.utterances) { utterance in
                            TranscriptLineView(utterance: utterance)
                        }
                    }
                    .padding(XT.S.lg)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 0) {
            VStack(spacing: XT.S.lg) {
                Image(systemName: "waveform.badge.microphone")
                    .font(.system(size: 52))
                    .foregroundStyle(XT.C.textTertiary)
                    .symbolRenderingMode(.hierarchical)

                Text("会議を開始")
                    .font(XT.F.displayTitle)
                    .foregroundStyle(XT.C.textPrimary)

                Text("「会議を開始」を押すと録音とリアルタイム文字起こしが始まり、\n終了時に議事録を自動生成します。")
                    .font(XT.F.body)
                    .foregroundStyle(XT.C.textSecondary)
                    .multilineTextAlignment(.center)

                if let message = model.errorMessage ?? store.errorMessage {
                    errorBanner(message)
                        .frame(maxWidth: 480)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            MeetingControlsBar(
                captureState: store.captureState,
                onStart: { model.startMeeting() },
                onStop: { model.stopMeeting() }
            )
        }
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: XT.S.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(XT.C.warning)
            Text(message)
                .font(XT.F.caption)
                .foregroundStyle(XT.C.textPrimary)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(XT.S.md)
        .background(XT.C.warningBG)
        .clipShape(RoundedRectangle(cornerRadius: XT.R.sm))
        .overlay(
            RoundedRectangle(cornerRadius: XT.R.sm)
                .strokeBorder(XT.C.warning.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func meetingTitle(from date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M月d日（E） H:mm の会議"
        return f.string(from: date)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return m > 0 ? "\(m)分 \(s)秒" : "\(s)秒"
    }
}
