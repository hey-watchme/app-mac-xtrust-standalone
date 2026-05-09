import AppCore
import SwiftUI

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
    let onSummarizeMeeting: () -> Void
    let onCopyWrapUp: () -> Void
    let meetingSummaryText: String?
    let isSummarizingMeeting: Bool

    @State private var showDiagnostics = false
    @State private var showLatestJobInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let detail {
                let session = detail.session

                HStack(alignment: .firstTextBaseline) {
                    Text(sessionTitle(from: session.startedAt))
                        .font(.title)
                        .fontWeight(.semibold)
                    Spacer()
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
                    Button {
                        showDiagnostics.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showDiagnostics, arrowEdge: .top) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("セッション基本情報")
                                        .font(.title3)
                                        .fontWeight(.semibold)
                                    CopyableDetailRow(title: "セッションID", value: session.id.uuidString, isMonospaced: true)
                                    CopyableDetailRow(
                                        title: "作成日時",
                                        value: session.startedAt.formatted(
                                            .dateTime.year().month().day().hour().minute().second()
                                            .locale(Locale(identifier: "ja_JP"))
                                        )
                                    )
                                }
                                Divider()
                                DiagnosticsView(
                                    diagnostics: diagnostics,
                                    sessionCount: sessionCount,
                                    errorMessage: errorMessage
                                )
                            }
                            .padding(20)
                        }
                        .frame(minWidth: 420, maxHeight: 600)
                    }
                    Button {
                        onCopyWrapUp()
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("まとめをクリップボードにコピー")
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.callout)
                        .textSelection(.enabled)
                }
                if let endedAt = session.endedAt {
                    CopyableDetailRow(
                        title: "終了",
                        value: endedAt.formatted(.dateTime.year().month().day().hour().minute().second()),
                        showCopyButton: false
                    )
                }
                if let durationSeconds = session.durationSeconds {
                    CopyableDetailRow(title: "録音時間", value: String(format: "%.1f 秒", durationSeconds), showCopyButton: false)
                }

                HStack(spacing: 12) {
                    if isListening {
                        Button("停止") { onStopListening() }
                            .buttonStyle(.bordered)
                        captureStatusView
                        ProgressView(value: Double(min(audioLevel * 10, 1.0)))
                            .progressViewStyle(.linear)
                            .frame(width: 80)
                            .tint(.green)
                    } else {
                        Button("開始") { onStartListening() }
                            .buttonStyle(.borderedProminent)
                            .disabled(session.status == .closed)
                        Button("会議の要約") { onSummarizeMeeting() }
                            .buttonStyle(.bordered)
                            .disabled(isSummarizingMeeting)
                    }
                }

                if isSummarizingMeeting {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("会議を要約中…").foregroundStyle(.secondary)
                    }
                } else if let text = meetingSummaryText {
                    Text(text)
                        .textSelection(.enabled)
                        .padding(.top, 2)
                }

                Divider()

                utterancesSection(detail: detail)

            } else {
                ContentUnavailableView(
                    "セッション未選択",
                    systemImage: "sidebar.left",
                    description: Text("左側のリストからセッションを選択するか、新規セッションを作成してください。")
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func latestJobSection(detail: SessionDetailSnapshot) -> some View {
        Text("最新の文字起こしジョブ")
            .font(.headline)

        if let latestJob = detail.utterances
            .compactMap(\.latestTranscriptionJob)
            .max(by: { lhs, rhs in lhs.createdAt < rhs.createdAt }) {
            CopyableDetailRow(title: "ジョブID", value: latestJob.id.uuidString, isMonospaced: true)
            CopyableDetailRow(title: "ステータス", value: latestJob.status.rawValue)
            CopyableDetailRow(title: "モデル", value: latestJob.modelIdentifier)
            CopyableDetailRow(title: "言語", value: latestJob.language)
            CopyableDetailRow(title: "作成", value: format(date: latestJob.createdAt))
            if let startedAt = latestJob.startedAt {
                CopyableDetailRow(title: "開始", value: format(date: startedAt))
            }
            if let endedAt = latestJob.endedAt {
                CopyableDetailRow(title: "終了", value: format(date: endedAt))
            }
            CopyableDetailRow(title: "作業ディレクトリ", value: latestJob.workingDirectoryPath, isMonospaced: true)
            CopyableDetailRow(title: "コマンド", value: latestJob.command, isMonospaced: true)
            if !latestJob.arguments.isEmpty {
                CopyableDetailRow(title: "引数", value: latestJob.arguments.joined(separator: " "), isMonospaced: true)
            }
            if let stdoutFilePath = latestJob.stdoutFilePath {
                CopyableDetailRow(title: "標準出力", value: stdoutFilePath, isMonospaced: true)
            }
            if let stderrFilePath = latestJob.stderrFilePath {
                CopyableDetailRow(title: "標準エラー", value: stderrFilePath, isMonospaced: true)
            }
            if let exitCode = latestJob.exitCode {
                CopyableDetailRow(title: "終了コード", value: String(exitCode))
            }
            if !latestJob.outputFileNames.isEmpty {
                CopyableDetailRow(title: "出力ファイル", value: latestJob.outputFileNames.joined(separator: ", "), isMonospaced: true)
            }
            if let failureMessage = latestJob.failureMessage {
                CopyableDetailRow(title: "エラー詳細", value: failureMessage)
            }
        } else {
            Text("文字起こしジョブはまだありません。")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func utterancesSection(detail: SessionDetailSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("発言一覧")
                    .font(.headline)
                Button {
                    showLatestJobInfo.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("最新の文字起こしジョブ")
                .popover(isPresented: $showLatestJobInfo, arrowEdge: .top) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("最新の文字起こしジョブ")
                                .font(.headline)
                                .padding(.bottom, 4)
                            latestJobSection(detail: detail)
                        }
                        .padding(16)
                    }
                    .frame(minWidth: 380, maxHeight: 500)
                }
            }

            if detail.utterances.isEmpty {
                Text("このセッションにはまだ発言がありません。")
                    .foregroundStyle(.secondary)
            } else {
                let unassigned = detail.utterances.filter { $0.utterance.topicID == nil }
                if !unassigned.isEmpty {
                    utteranceList(unassigned)
                }

                ForEach(Array(detail.topics.enumerated()), id: \.element.id) { index, topic in
                    let topicUtterances = detail.utterances.filter { $0.utterance.topicID == topic.id }
                    if !topicUtterances.isEmpty {
                        if index > 0 {
                            Divider()
                        }
                        topicHeaderView(topic: topic, index: index + 1)
                        utteranceList(topicUtterances)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func topicHeaderView(topic: Topic, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("トピック \(index)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("— \(format(date: topic.startedAt))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if topic.status == .active {
                    Text("録音中")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.15))
                        .foregroundStyle(.green)
                        .clipShape(Capsule())
                }
                Spacer()
                summaryBadge(for: topic)
                Button("要約") { onSummarizeTopic(topic.id) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(topic.summaryStatus == .running)
            }
            if let summaryText = topic.summaryText {
                Text(summaryText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 4)
            }
            if let summaryError = topic.summaryError, topic.summaryStatus == .failed {
                Text("要約失敗: \(summaryError)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func summaryBadge(for topic: Topic) -> some View {
        switch topic.summaryStatus {
        case .idle:
            EmptyView()
        case .running:
            Text("要約中…")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.15))
                .foregroundStyle(.blue)
                .clipShape(Capsule())
        case .completed:
            Text("要約完了")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.15))
                .foregroundStyle(.green)
                .clipShape(Capsule())
        case .failed:
            Text("要約失敗")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.red.opacity(0.15))
                .foregroundStyle(.red)
                .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private func utteranceList(_ utterances: [UtteranceDetailSnapshot]) -> some View {
        ForEach(utterances) { utteranceDetail in
            UtteranceCardView(
                utteranceDetail: utteranceDetail,
                onTranscribeUtterance: onTranscribeUtterance
            )
        }
    }

    @ViewBuilder
    private var captureStatusView: some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                Circle()
                    .fill(isSpeechActive ? Color.red : Color.secondary.opacity(0.4))
                    .frame(width: 8, height: 8)
                Text(isSpeechActive ? "録音中" : "待機中")
                    .foregroundStyle(isSpeechActive ? .red : .secondary)
            }
            .font(.caption)
            .animation(.easeInOut(duration: 0.1), value: isSpeechActive)

            HStack(spacing: 5) {
                Circle()
                    .fill(audioLevel > 0.01 ? Color.orange : Color.clear)
                    .overlay(Circle().strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1))
                    .frame(width: 6, height: 6)
                Text("発話を検出")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
    }

    private func sessionTitle(from date: Date) -> String {
        let cal = Calendar.current
        let year = cal.component(.year, from: date)
        let month = cal.component(.month, from: date)
        let day = cal.component(.day, from: date)
        let hour = cal.component(.hour, from: date)
        return "\(year)年\(month)月\(day)日\(hour)時の会議"
    }

    private func format(date: Date) -> String {
        date.formatted(.dateTime.year().month().day().hour().minute().second())
    }
}

private struct UtteranceCardView: View {
    let utteranceDetail: UtteranceDetailSnapshot
    let onTranscribeUtterance: (UUID) -> Void

    @State private var showDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            transcriptContent

            HStack(spacing: 4) {
                Text(format(date: utteranceDetail.utterance.startedAt))
                Text("—")
                if let endedAt = utteranceDetail.utterance.endedAt {
                    Text(format(date: endedAt))
                }
                Spacer()
                Button {
                    showDetail.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showDetail, arrowEdge: .bottom) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            detailContent
                        }
                        .padding(16)
                    }
                    .frame(minWidth: 380, maxHeight: 480)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var transcriptContent: some View {
        if let text = utteranceDetail.latestTranscriptArtifact?.text {
            Text(text)
                .textSelection(.enabled)
        } else if utteranceDetail.latestTranscriptionJob?.status == .running {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("文字起こし中…")
                    .foregroundStyle(.secondary)
            }
        } else if utteranceDetail.latestTranscriptionJob?.status == .failed {
            Text("文字起こし失敗")
                .foregroundStyle(.red)
        } else {
            Text("（未文字起こし）")
                .foregroundStyle(.tertiary)
                .italic()
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if utteranceDetail.latestRecordingArtifact != nil {
            let isRunning = utteranceDetail.latestTranscriptionJob?.status == .running
            Button("文字起こし再実行") {
                onTranscribeUtterance(utteranceDetail.utterance.id)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isRunning)
            Divider()
        }
        if let durationSeconds = utteranceDetail.utterance.durationSeconds {
            CopyableDetailRow(title: "長さ", value: String(format: "%.1f 秒", durationSeconds), showCopyButton: false)
        }
        CopyableDetailRow(title: "文字起こし状態", value: utteranceDetail.utterance.transcriptionStatus.rawValue, showCopyButton: false)
        if let artifact = utteranceDetail.latestRecordingArtifact {
            CopyableDetailRow(title: "音声サイズ", value: ByteCountFormatter.string(fromByteCount: artifact.byteSize, countStyle: .file), showCopyButton: false)
        }

        if let latestJob = utteranceDetail.latestTranscriptionJob {
            Divider()
            Text("最新ジョブ")
                .font(.subheadline)
                .fontWeight(.semibold)
            CopyableDetailRow(title: "ジョブID", value: latestJob.id.uuidString, isMonospaced: true)
            CopyableDetailRow(title: "ジョブ状態", value: latestJob.status.rawValue, showCopyButton: false)
            if let stdoutFilePath = latestJob.stdoutFilePath {
                CopyableDetailRow(title: "標準出力", value: stdoutFilePath, isMonospaced: true)
            }
            if let stderrFilePath = latestJob.stderrFilePath {
                CopyableDetailRow(title: "標準エラー", value: stderrFilePath, isMonospaced: true)
            }
            if let failureMessage = latestJob.failureMessage {
                CopyableDetailRow(title: "エラー詳細", value: failureMessage, showCopyButton: false)
            }
        }

        if !utteranceDetail.transcriptionJobs.isEmpty {
            Divider()
            Text("試行履歴")
                .font(.subheadline)
                .fontWeight(.semibold)
            ForEach(Array(utteranceDetail.transcriptionJobs.enumerated()).reversed(), id: \.element.id) { offset, job in
                VStack(alignment: .leading, spacing: 6) {
                    Text("試行 \(offset + 1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    CopyableDetailRow(title: "ジョブID", value: job.id.uuidString, isMonospaced: true)
                    CopyableDetailRow(title: "ステータス", value: job.status.rawValue, showCopyButton: false)
                    CopyableDetailRow(title: "作成", value: format(date: job.createdAt), showCopyButton: false)
                    if let stdoutFilePath = job.stdoutFilePath {
                        CopyableDetailRow(title: "標準出力", value: stdoutFilePath, isMonospaced: true)
                    }
                    if let stderrFilePath = job.stderrFilePath {
                        CopyableDetailRow(title: "標準エラー", value: stderrFilePath, isMonospaced: true)
                    }
                    if let exitCode = job.exitCode {
                        CopyableDetailRow(title: "終了コード", value: String(exitCode), showCopyButton: false)
                    }
                    if let failureMessage = job.failureMessage {
                        CopyableDetailRow(title: "エラー詳細", value: failureMessage, showCopyButton: false)
                    }
                }
                if job.id != utteranceDetail.transcriptionJobs.first?.id {
                    Divider()
                }
            }
        }

        if let transcriptArtifact = utteranceDetail.latestTranscriptArtifact {
            Divider()
            CopyableDetailRow(title: "文字起こしファイル", value: transcriptArtifact.filePath, isMonospaced: true)
        }
    }

    private func format(date: Date) -> String {
        date.formatted(.dateTime.hour().minute().second())
    }
}
