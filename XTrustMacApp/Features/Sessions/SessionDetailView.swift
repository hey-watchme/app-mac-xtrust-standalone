import AppCore
import SwiftUI

struct SessionDetailView: View {
    let detail: SessionDetailSnapshot?
    let isListening: Bool
    let isSpeechActive: Bool
    let audioLevel: Float
    let onStartListening: () -> Void
    let onStopListening: () -> Void
    let onTranscribeUtterance: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let detail {
                let session = detail.session
                let latestJobStatusText: String = detail.utterances
                    .compactMap(\.latestTranscriptionJob)
                    .max(by: { $0.createdAt < $1.createdAt })
                    .map { $0.status.rawValue } ?? "idle"
                Text("Session Detail")
                    .font(.title)
                    .fontWeight(.semibold)

                CopyableDetailRow(title: "Session ID", value: session.id.uuidString, isMonospaced: true)
                CopyableDetailRow(
                    title: "Created",
                    value: session.startedAt.formatted(.dateTime.year().month().day().hour().minute().second())
                )
                CopyableDetailRow(title: "Status", value: session.status.rawValue)
                if let endedAt = session.endedAt {
                    CopyableDetailRow(
                        title: "Ended",
                        value: endedAt.formatted(.dateTime.year().month().day().hour().minute().second())
                    )
                }
                if let audioFilePath = session.audioFilePath {
                    CopyableDetailRow(title: "Audio File", value: audioFilePath, isMonospaced: true)
                }
                if let durationSeconds = session.durationSeconds {
                    CopyableDetailRow(title: "Duration", value: String(format: "%.1f sec", durationSeconds))
                }
                HStack(spacing: 12) {
                    if isListening {
                        Button("Stop") { onStopListening() }
                            .buttonStyle(.bordered)
                        captureStatusView
                        ProgressView(value: Double(min(audioLevel * 10, 1.0)))
                            .progressViewStyle(.linear)
                            .frame(width: 80)
                            .tint(.green)
                    } else {
                        Button("Start") { onStartListening() }
                            .buttonStyle(.borderedProminent)
                    }
                }

                CopyableDetailRow(title: "Transcription", value: latestJobStatusText)

                Divider()

                latestJobSection(detail: detail)

                Divider()

                utterancesSection(detail: detail)

            } else {
                ContentUnavailableView(
                    "No Session Selected",
                    systemImage: "sidebar.left",
                    description: Text("Create a draft session or select one from the list.")
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func latestJobSection(detail: SessionDetailSnapshot) -> some View {
        Text("Latest Transcription Job")
            .font(.headline)

        if let latestJob = detail.utterances
            .compactMap(\.latestTranscriptionJob)
            .max(by: { lhs, rhs in lhs.createdAt < rhs.createdAt }) {
            CopyableDetailRow(title: "Job ID", value: latestJob.id.uuidString, isMonospaced: true)
            CopyableDetailRow(title: "Status", value: latestJob.status.rawValue)
            CopyableDetailRow(title: "Model", value: latestJob.modelIdentifier)
            CopyableDetailRow(title: "Language", value: latestJob.language)
            CopyableDetailRow(title: "Created", value: format(date: latestJob.createdAt))
            if let startedAt = latestJob.startedAt {
                CopyableDetailRow(title: "Started", value: format(date: startedAt))
            }
            if let endedAt = latestJob.endedAt {
                CopyableDetailRow(title: "Ended", value: format(date: endedAt))
            }
            CopyableDetailRow(title: "Working Dir", value: latestJob.workingDirectoryPath, isMonospaced: true)
            CopyableDetailRow(title: "Command", value: latestJob.command, isMonospaced: true)
            if !latestJob.arguments.isEmpty {
                CopyableDetailRow(title: "Arguments", value: latestJob.arguments.joined(separator: " "), isMonospaced: true)
            }
            if let stdoutFilePath = latestJob.stdoutFilePath {
                CopyableDetailRow(title: "Stdout", value: stdoutFilePath, isMonospaced: true)
            }
            if let stderrFilePath = latestJob.stderrFilePath {
                CopyableDetailRow(title: "Stderr", value: stderrFilePath, isMonospaced: true)
            }
            if let exitCode = latestJob.exitCode {
                CopyableDetailRow(title: "Exit Code", value: String(exitCode))
            }
            if !latestJob.outputFileNames.isEmpty {
                CopyableDetailRow(title: "Output Files", value: latestJob.outputFileNames.joined(separator: ", "), isMonospaced: true)
            }
            if let failureMessage = latestJob.failureMessage {
                CopyableDetailRow(title: "Failure", value: failureMessage)
            }
        } else {
            Text("No persisted transcription job yet.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func utterancesSection(detail: SessionDetailSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Utterances")
                .font(.headline)

            if detail.utterances.isEmpty {
                Text("No utterances have been materialized for this session yet.")
                    .foregroundStyle(.secondary)
            } else {
                let unassigned = detail.utterances.filter { $0.utterance.topicID == nil }
                if !unassigned.isEmpty {
                    utteranceList(unassigned)
                }

                ForEach(Array(detail.topics.enumerated()), id: \.element.id) { index, topic in
                    let topicUtterances = detail.utterances.filter { $0.utterance.topicID == topic.id }
                    if !topicUtterances.isEmpty {
                        topicHeaderView(topic: topic, index: index + 1)
                        utteranceList(topicUtterances)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func topicHeaderView(topic: Topic, index: Int) -> some View {
        HStack(spacing: 8) {
            Text("Topic \(index)")
                .font(.subheadline)
                .fontWeight(.semibold)
            Text("— \(format(date: topic.startedAt))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if topic.status == .active {
                Text("active")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.15))
                    .foregroundStyle(.green)
                    .clipShape(Capsule())
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func utteranceList(_ utterances: [UtteranceDetailSnapshot]) -> some View {
        ForEach(utterances) { utteranceDetail in
            utteranceCard(utteranceDetail)
            if utteranceDetail.id != utterances.last?.id {
                Divider()
            }
        }
    }

    @ViewBuilder
    private func utteranceCard(_ utteranceDetail: UtteranceDetailSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Utterance \(utteranceDetail.utterance.id.uuidString)")
                .font(.subheadline)
                .fontWeight(.semibold)
                .textSelection(.enabled)

            CopyableDetailRow(title: "Started", value: format(date: utteranceDetail.utterance.startedAt))
            if let endedAt = utteranceDetail.utterance.endedAt {
                CopyableDetailRow(title: "Ended", value: format(date: endedAt))
            }
            if let durationSeconds = utteranceDetail.utterance.durationSeconds {
                CopyableDetailRow(title: "Duration", value: String(format: "%.1f sec", durationSeconds))
            }
            if let audioFilePath = utteranceDetail.utterance.audioFilePath {
                CopyableDetailRow(title: "Audio File", value: audioFilePath, isMonospaced: true)
            }
            CopyableDetailRow(title: "Transcription", value: utteranceDetail.utterance.transcriptionStatus.rawValue)

            if let recordingArtifact = utteranceDetail.latestRecordingArtifact {
                CopyableDetailRow(title: "Recording Artifact", value: recordingArtifact.id.uuidString, isMonospaced: true)
                CopyableDetailRow(title: "Audio Bytes", value: ByteCountFormatter.string(fromByteCount: recordingArtifact.byteSize, countStyle: .file))
                let isThisUtteranceRunning = utteranceDetail.latestTranscriptionJob?.status == .running
                Button("Transcribe") {
                    onTranscribeUtterance(utteranceDetail.utterance.id)
                }
                .buttonStyle(.bordered)
                .disabled(isThisUtteranceRunning)
            }

            if let latestJob = utteranceDetail.latestTranscriptionJob {
                CopyableDetailRow(title: "Latest Job", value: latestJob.id.uuidString, isMonospaced: true)
                CopyableDetailRow(title: "Job Status", value: latestJob.status.rawValue)
                if let stdoutFilePath = latestJob.stdoutFilePath {
                    CopyableDetailRow(title: "Stdout", value: stdoutFilePath, isMonospaced: true)
                }
                if let stderrFilePath = latestJob.stderrFilePath {
                    CopyableDetailRow(title: "Stderr", value: stderrFilePath, isMonospaced: true)
                }
                if let failureMessage = latestJob.failureMessage {
                    CopyableDetailRow(title: "Failure", value: failureMessage)
                }
            }

            if let transcriptArtifact = utteranceDetail.latestTranscriptArtifact {
                CopyableDetailRow(title: "Transcript Artifact", value: transcriptArtifact.id.uuidString, isMonospaced: true)
                CopyableDetailRow(title: "Transcript File", value: transcriptArtifact.filePath, isMonospaced: true)
                Text(transcriptArtifact.text)
                    .textSelection(.enabled)
            }

            if !utteranceDetail.transcriptionJobs.isEmpty {
                Divider()

                Text("Job Attempts")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                ForEach(Array(utteranceDetail.transcriptionJobs.enumerated()).reversed(), id: \.element.id) { offset, job in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Attempt \(offset + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        CopyableDetailRow(title: "Job ID", value: job.id.uuidString, isMonospaced: true)
                        CopyableDetailRow(title: "Status", value: job.status.rawValue)
                        CopyableDetailRow(title: "Created", value: format(date: job.createdAt))
                        if let stdoutFilePath = job.stdoutFilePath {
                            CopyableDetailRow(title: "Stdout", value: stdoutFilePath, isMonospaced: true)
                        }
                        if let stderrFilePath = job.stderrFilePath {
                            CopyableDetailRow(title: "Stderr", value: stderrFilePath, isMonospaced: true)
                        }
                        if let exitCode = job.exitCode {
                            CopyableDetailRow(title: "Exit Code", value: String(exitCode))
                        }
                        if let failureMessage = job.failureMessage {
                            CopyableDetailRow(title: "Failure", value: failureMessage)
                        }
                        if let artifact = utteranceDetail.transcriptArtifacts.first(where: { $0.transcriptionJobID == job.id }) {
                            CopyableDetailRow(title: "Transcript ID", value: artifact.id.uuidString, isMonospaced: true)
                            CopyableDetailRow(title: "Transcript File", value: artifact.filePath, isMonospaced: true)
                        }
                    }

                    if job.id != utteranceDetail.transcriptionJobs.first?.id {
                        Divider()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var captureStatusView: some View {
        HStack(spacing: 10) {
            // 録音中/待機中 — speechActive の実際の状態に基づく
            HStack(spacing: 5) {
                Circle()
                    .fill(isSpeechActive ? Color.red : Color.secondary.opacity(0.4))
                    .frame(width: 8, height: 8)
                Text(isSpeechActive ? "録音中" : "待機中")
                    .foregroundStyle(isSpeechActive ? .red : .secondary)
            }
            .font(.caption)
            .animation(.easeInOut(duration: 0.1), value: isSpeechActive)

            // 発話を検出 — 瞬間 RMS パラメータ
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

    private func format(date: Date) -> String {
        date.formatted(.dateTime.year().month().day().hour().minute().second())
    }
}
