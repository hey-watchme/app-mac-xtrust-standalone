import AppCore
import SwiftUI

// MARK: - Session Detail View

struct SessionDetailView: View {
    let detail: SessionDetailSnapshot?
    let isListening: Bool
    let isSpeechActive: Bool
    let audioLevel: Float
    let diagnostics: AppDiagnostics
    let sessionCount: Int
    let errorMessage: String?
    let onStartListening: () -> Void
    let onStopListening: () -> Void
    let onTranscribeUtterance: (UUID) -> Void
    let onSummarizeTopic: (UUID) -> Void
    let onSetSessionStatus: (Session.Status) -> Void
    let onSetMeetingContextProfile: (Session.MeetingContextProfile) -> Void
    let onSummarizeMeeting: () -> Void
    let onCopyWrapUp: () -> Void
    let meetingSummaryText: String?
    let isSummarizingMeeting: Bool
    let isSummaryQueueBusy: Bool

    @State private var showDiagnostics = false

    var body: some View {
        if let detail {
            contentView(detail: detail)
                .navigationTitle(sessionTitle(from: detail.session.startedAt))
        } else {
            emptyState
                .navigationTitle("")
        }
    }

    // MARK: - Main Content

    private func contentView(detail: SessionDetailSnapshot) -> some View {
        VStack(spacing: 0) {
            sessionHeader(session: detail.session)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: XT.S.xxl) {

                    if isListening {
                        recordingBar
                    } else {
                        controlBar(session: detail.session)
                    }

                    if let msg = errorMessage {
                        errorBanner(msg)
                    }

                    if isSummarizingMeeting || meetingSummaryText != nil {
                        meetingSummaryCard
                    }

                    topicsSection(detail: detail)
                }
                .padding(XT.Layout.contentPadding)
                .frame(maxWidth: XT.Layout.contentMaxWidth)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Session Header

    private func sessionHeader(session: Session) -> some View {
        HStack(spacing: XT.S.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text(sessionTitle(from: session.startedAt))
                    .font(XT.F.displayTitle)
                    .foregroundStyle(XT.C.textPrimary)

                HStack(spacing: XT.S.sm) {
                    XTSessionStatusBadge(status: session.status)

                    if session.topicCount > 0 {
                        Text("\(session.topicCount) トピック")
                            .font(XT.F.caption)
                            .foregroundStyle(XT.C.textSecondary)
                    }

                    if let dur = session.durationSeconds {
                        Text("·")
                            .foregroundStyle(XT.C.textTertiary)
                        Text(formatDuration(dur))
                            .font(XT.F.caption)
                            .foregroundStyle(XT.C.textTertiary)
                    }
                }
            }

            Spacer()

            Button(action: onCopyWrapUp) {
                Label("まとめをコピー", systemImage: "doc.on.doc")
            }
            .buttonStyle(XTSecondaryButtonStyle())
            .help("会議のまとめをクリップボードにコピー")

            Button {
                showDiagnostics.toggle()
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(XT.C.textSecondary)
            }
            .buttonStyle(XTIconButtonStyle())
            .popover(isPresented: $showDiagnostics, arrowEdge: .bottom) {
                diagnosticsPopover(session: session)
            }
        }
        .padding(.horizontal, XT.Layout.contentPadding)
        .frame(height: 64)
    }

    // MARK: - Recording Bar

    private var recordingBar: some View {
        HStack(spacing: XT.S.lg) {
            RecordingDot()

            VStack(alignment: .leading, spacing: 2) {
                Text(isSpeechActive ? "発話を検出" : "待機中")
                    .font(XT.F.body)
                    .fontWeight(.medium)
                    .foregroundStyle(isSpeechActive ? XT.C.recording : XT.C.textPrimary)
                    .animation(.easeInOut(duration: 0.1), value: isSpeechActive)

                Text("VAD · RMS 0.01 · 無音 3 秒でセグメント化")
                    .font(XT.F.caption)
                    .foregroundStyle(XT.C.textTertiary)
            }

            Spacer()

            AudioLevelMeter(level: audioLevel)
                .frame(width: 88)

            Button(action: onStopListening) {
                Label("停止", systemImage: "stop.fill")
            }
            .buttonStyle(XTDestructiveButtonStyle())
        }
        .padding(XT.S.lg)
        .background(XT.C.recordingBG)
        .clipShape(RoundedRectangle(cornerRadius: XT.R.lg))
        .overlay(
            RoundedRectangle(cornerRadius: XT.R.lg)
                .strokeBorder(XT.C.recordingBorder, lineWidth: 1)
        )
    }

    // MARK: - Control Bar

    private func controlBar(session: Session) -> some View {
        HStack(spacing: XT.S.sm) {
            Button(action: onStartListening) {
                Label("録音開始", systemImage: "mic.fill")
            }
            .buttonStyle(XTPrimaryButtonStyle())
            .disabled(session.status == .closed)

            Button(action: onSummarizeMeeting) {
                Label("会議を要約", systemImage: "sparkles")
            }
            .buttonStyle(XTSecondaryButtonStyle())
            .disabled(isSummaryQueueBusy)

            Spacer()

            Picker("会議プロファイル", selection: Binding(
                get: { session.meetingContextProfile },
                set: { onSetMeetingContextProfile($0) }
            )) {
                ForEach(Session.MeetingContextProfile.allCases, id: \.self) { profile in
                    Text(meetingContextProfileLabel(profile)).tag(profile)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)

            Picker("", selection: Binding(
                get: { session.status },
                set: { onSetSessionStatus($0) }
            )) {
                Text("下書き").tag(Session.Status.draft)
                Text("録音中").tag(Session.Status.recording)
                Text("完了").tag(Session.Status.completed)
                Text("失敗").tag(Session.Status.failed)
                Text("クローズ済み").tag(Session.Status.closed)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .controlSize(.small)
        }
    }

    // MARK: - Meeting Summary Card

    private var meetingSummaryCard: some View {
        XTCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    XTSectionLabel(text: "会議の要約")
                    Spacer()
                    if isSummarizingMeeting {
                        HStack(spacing: XT.S.xs) {
                            ProgressView().controlSize(.mini)
                            Text("生成中…")
                                .font(XT.F.caption)
                                .foregroundStyle(XT.C.textSecondary)
                        }
                    }
                }
                .padding(.horizontal, XT.S.lg)
                .padding(.top, XT.S.lg)
                .padding(.bottom, XT.S.md)

                Divider()
                    .padding(.horizontal, XT.S.md)

                if let text = meetingSummaryText {
                    Text(text)
                        .font(XT.F.body)
                        .foregroundStyle(XT.C.textPrimary)
                        .textSelection(.enabled)
                        .lineSpacing(4)
                        .padding(XT.S.lg)
                } else {
                    Text("Gemma 4 が会議の要約を生成しています…")
                        .font(XT.F.body)
                        .foregroundStyle(XT.C.textTertiary)
                        .padding(XT.S.lg)
                }
            }
        }
    }

    // MARK: - Topics Section

    @ViewBuilder
    private func topicsSection(detail: SessionDetailSnapshot) -> some View {
        if detail.utterances.isEmpty && !isListening {
            emptySessionHint
        } else {
            VStack(alignment: .leading, spacing: XT.S.xxl) {
                let unassigned = detail.utterances.filter { $0.utterance.topicID == nil }
                if !unassigned.isEmpty {
                    TopicCardView(
                        topic: nil,
                        index: nil,
                        utterances: unassigned,
                        isSummaryQueueBusy: isSummaryQueueBusy,
                        onSummarizeTopic: onSummarizeTopic,
                        onTranscribeUtterance: onTranscribeUtterance
                    )
                }

                ForEach(Array(detail.topics.enumerated()), id: \.element.id) { index, topic in
                    let topicUtterances = detail.utterances.filter {
                        $0.utterance.topicID == topic.id
                    }
                    if !topicUtterances.isEmpty
                        || topic.summaryText != nil
                        || topic.summaryStatus != .idle
                    {
                        TopicCardView(
                            topic: topic,
                            index: index + 1,
                            utterances: topicUtterances,
                            isSummaryQueueBusy: isSummaryQueueBusy,
                            onSummarizeTopic: onSummarizeTopic,
                            onTranscribeUtterance: onTranscribeUtterance
                        )
                    }
                }
            }
        }
    }

    // MARK: - Empty States

    private var emptyState: some View {
        VStack(spacing: XT.S.lg) {
            Image(systemName: "waveform.badge.microphone")
                .font(.system(size: 52))
                .foregroundStyle(XT.C.textTertiary)
                .symbolRenderingMode(.hierarchical)

            Text("セッションを選択")
                .font(XT.F.displayTitle)
                .foregroundStyle(XT.C.textPrimary)

            Text("左のリストからセッションを選択するか、\n新規セッションを作成してください。")
                .font(XT.F.body)
                .foregroundStyle(XT.C.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptySessionHint: some View {
        VStack(spacing: XT.S.sm) {
            Image(systemName: "mic.badge.plus")
                .font(.system(size: 36))
                .foregroundStyle(XT.C.textTertiary)
                .symbolRenderingMode(.hierarchical)

            Text("「録音開始」を押して会議を記録してください")
                .font(XT.F.body)
                .foregroundStyle(XT.C.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, XT.S.xxxl)
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

    // MARK: - Diagnostics Popover

    private func diagnosticsPopover(session: Session) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XT.S.xl) {
                VStack(alignment: .leading, spacing: XT.S.md) {
                    Text("セッション情報")
                        .font(.system(size: 14, weight: .semibold))

                    CopyableDetailRow(title: "ID", value: session.id.uuidString, isMonospaced: true)
                    CopyableDetailRow(
                        title: "開始",
                        value: session.startedAt.formatted(
                            .dateTime.year().month().day().hour().minute().second()
                                .locale(Locale(identifier: "ja_JP"))
                        )
                    )
                    if let endedAt = session.endedAt {
                        CopyableDetailRow(
                            title: "終了",
                            value: endedAt.formatted(.dateTime.year().month().day().hour().minute().second())
                        )
                    }
                }

                Divider()

                DiagnosticsView(
                    diagnostics: diagnostics,
                    sessionCount: sessionCount,
                    errorMessage: errorMessage
                )
            }
            .padding(XT.S.xl)
        }
        .frame(minWidth: 400, maxHeight: 580)
    }

    // MARK: - Helpers

    private func sessionTitle(from date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M月d日（E） H:mm の会議"
        return f.string(from: date)
    }

    private func meetingContextProfileLabel(_ profile: Session.MeetingContextProfile) -> String {
        switch profile {
        case .general:
            return "一般会議"
        case .engineering:
            return "開発"
        case .product:
            return "企画・プロダクト"
        case .recruitingHR:
            return "採用・人事"
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return m > 0 ? "\(m)分 \(s)秒" : "\(s)秒"
    }
}

// MARK: - Topic Card

private struct TopicCardView: View {
    let topic: Topic?
    let index: Int?
    let utterances: [UtteranceDetailSnapshot]
    let isSummaryQueueBusy: Bool
    let onSummarizeTopic: (UUID) -> Void
    let onTranscribeUtterance: (UUID) -> Void

    var body: some View {
        XTCard {
            VStack(alignment: .leading, spacing: 0) {
                topicHeader

                if let topic,
                   topic.summaryText != nil
                       || topic.summaryStatus == .running
                       || topic.summaryStatus == .failed
                {
                    topicSummaryArea(topic: topic)
                }

                if !utterances.isEmpty {
                    Divider()
                        .padding(.horizontal, XT.S.md)

                    utteranceList
                }
            }
        }
    }

    // MARK: Header

    private var topicHeader: some View {
        HStack(spacing: XT.S.sm) {
            // Topic label
            if let index {
                Text("Topic \(index)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(XT.C.textTertiary)
                    .padding(.horizontal, XT.S.sm)
                    .padding(.vertical, XT.S.xxs + 1)
                    .background(XT.C.textTertiary.opacity(0.09))
                    .clipShape(Capsule())
            } else {
                Text("未分類")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(XT.C.textTertiary)
            }

            if let topic {
                Text(formatTime(topic.startedAt))
                    .font(XT.F.mono)
                    .foregroundStyle(XT.C.textTertiary)

                if topic.status == .active {
                    RecordingDot()
                }
            }

            Spacer()

            if let topic {
                XTTopicSummaryBadge(status: topic.summaryStatus)

                Button("要約") { onSummarizeTopic(topic.id) }
                    .buttonStyle(XTSecondaryButtonStyle())
                    .controlSize(.small)
                    .disabled(isSummaryQueueBusy || topic.summaryStatus == .running)
            }
        }
        .padding(.horizontal, XT.S.lg)
        .frame(height: 46)
    }

    // MARK: Summary Area

    private func topicSummaryArea(topic: Topic) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
                .padding(.horizontal, XT.S.md)

            Group {
                if topic.summaryStatus == .running {
                    HStack(spacing: XT.S.sm) {
                        ProgressView().controlSize(.mini)
                        Text("Gemma 4 が要約を生成中…")
                            .font(XT.F.caption)
                            .foregroundStyle(XT.C.textSecondary)
                    }
                } else if let summaryText = topic.summaryText {
                    Text(summaryText)
                        .font(XT.F.body)
                        .foregroundStyle(XT.C.textPrimary)
                        .textSelection(.enabled)
                        .lineSpacing(4)
                } else if let error = topic.summaryError, topic.summaryStatus == .failed {
                    HStack(spacing: XT.S.xs) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(XT.C.destructive)
                        Text("要約失敗: \(error)")
                            .font(XT.F.caption)
                            .foregroundStyle(XT.C.destructive)
                    }
                }
            }
            .padding(XT.S.lg)
        }
    }

    // MARK: Utterance List

    private var utteranceList: some View {
        VStack(spacing: 0) {
            ForEach(utterances) { ud in
                UtteranceRowView(
                    utteranceDetail: ud,
                    onTranscribeUtterance: onTranscribeUtterance
                )

                if ud.id != utterances.last?.id {
                    Divider()
                        .padding(.leading, XT.S.lg + 72)
                }
            }
        }
    }

    private func formatTime(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().second())
    }
}

// MARK: - Utterance Row

private struct UtteranceRowView: View {
    let utteranceDetail: UtteranceDetailSnapshot
    let onTranscribeUtterance: (UUID) -> Void

    @State private var showDetail = false
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: XT.S.lg) {
            // Timestamp
            Text(formatTime(utteranceDetail.utterance.startedAt))
                .font(XT.F.mono)
                .foregroundStyle(XT.C.textTertiary)
                .frame(width: 72, alignment: .trailing)
                .layoutPriority(1)

            // Transcript
            VStack(alignment: .leading, spacing: XT.S.xxs + 1) {
                transcriptContent

                if let dur = utteranceDetail.utterance.durationSeconds {
                    Text(String(format: "%.1f 秒", dur))
                        .font(XT.F.caption)
                        .foregroundStyle(XT.C.textTertiary)
                }
            }

            Spacer(minLength: XT.S.sm)

            // Action menu (appears on hover)
            if isHovered || showDetail {
                Button {
                    showDetail.toggle()
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(XT.C.textSecondary)
                }
                .buttonStyle(XTIconButtonStyle())
                .popover(isPresented: $showDetail, arrowEdge: .bottom) {
                    utteranceDetailPopover
                }
                .transition(.opacity.animation(.easeInOut(duration: 0.1)))
            }
        }
        .padding(.horizontal, XT.S.lg)
        .padding(.vertical, XT.S.sm + 2)
        .background(isHovered ? XT.C.hoveredBG : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovered in
            withAnimation(.easeInOut(duration: 0.08)) { isHovered = hovered }
        }
    }

    // MARK: Transcript Content

    @ViewBuilder
    private var transcriptContent: some View {
        if let text = utteranceDetail.latestTranscriptArtifact?.text {
            Text(text)
                .font(XT.F.body)
                .foregroundStyle(XT.C.textPrimary)
                .textSelection(.enabled)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        } else if utteranceDetail.latestTranscriptionJob?.status == .running {
            HStack(spacing: XT.S.xs) {
                ProgressView().controlSize(.mini)
                Text("文字起こし中…")
                    .font(XT.F.body)
                    .foregroundStyle(XT.C.textSecondary)
            }
        } else if utteranceDetail.latestTranscriptionJob?.status == .failed {
            Text("文字起こし失敗")
                .font(XT.F.body)
                .foregroundStyle(XT.C.destructive)
        } else {
            Text("未文字起こし")
                .font(XT.F.body)
                .foregroundStyle(XT.C.textTertiary)
                .italic()
        }
    }

    // MARK: Detail Popover

    private var utteranceDetailPopover: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XT.S.md) {
                if utteranceDetail.latestRecordingArtifact != nil {
                    Button("文字起こし再実行") {
                        onTranscribeUtterance(utteranceDetail.utterance.id)
                    }
                    .buttonStyle(XTSecondaryButtonStyle())
                    .disabled(utteranceDetail.latestTranscriptionJob?.status == .running)

                    Divider()
                }

                if let dur = utteranceDetail.utterance.durationSeconds {
                    CopyableDetailRow(title: "長さ", value: String(format: "%.1f 秒", dur), showCopyButton: false)
                }
                CopyableDetailRow(
                    title: "文字起こし状態",
                    value: utteranceDetail.utterance.transcriptionStatus.rawValue,
                    showCopyButton: false
                )
                if let artifact = utteranceDetail.latestRecordingArtifact {
                    CopyableDetailRow(
                        title: "音声サイズ",
                        value: ByteCountFormatter.string(fromByteCount: artifact.byteSize, countStyle: .file),
                        showCopyButton: false
                    )
                }

                if let job = utteranceDetail.latestTranscriptionJob {
                    Divider()
                    Text("最新ジョブ")
                        .font(.system(size: 12, weight: .semibold))
                    CopyableDetailRow(title: "ジョブID", value: job.id.uuidString, isMonospaced: true)
                    CopyableDetailRow(title: "状態", value: job.status.rawValue, showCopyButton: false)
                    if let stdout = job.stdoutFilePath {
                        CopyableDetailRow(title: "stdout", value: stdout, isMonospaced: true)
                    }
                    if let stderr = job.stderrFilePath {
                        CopyableDetailRow(title: "stderr", value: stderr, isMonospaced: true)
                    }
                    if let msg = job.failureMessage {
                        CopyableDetailRow(title: "エラー詳細", value: msg, showCopyButton: false)
                    }
                }

                if utteranceDetail.transcriptionJobs.count > 1 {
                    Divider()
                    Text("試行履歴 (\(utteranceDetail.transcriptionJobs.count) 回)")
                        .font(.system(size: 12, weight: .semibold))
                    ForEach(
                        Array(utteranceDetail.transcriptionJobs.enumerated()).reversed(),
                        id: \.element.id
                    ) { offset, job in
                        HStack(spacing: XT.S.sm) {
                            Text("試行 \(offset + 1)")
                                .font(XT.F.caption)
                                .foregroundStyle(XT.C.textTertiary)
                            Text(job.status.rawValue)
                                .font(XT.F.caption)
                                .foregroundStyle(XT.C.textSecondary)
                            Spacer()
                            Text(job.createdAt.formatted(.dateTime.hour().minute().second()))
                                .font(XT.F.mono)
                                .foregroundStyle(XT.C.textTertiary)
                        }
                    }
                }

                if let artifact = utteranceDetail.latestTranscriptArtifact {
                    Divider()
                    CopyableDetailRow(title: "文字起こしファイル", value: artifact.filePath, isMonospaced: true)
                }
            }
            .padding(XT.S.lg)
        }
        .frame(minWidth: 360, maxHeight: 480)
    }

    private func formatTime(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().second())
    }
}
