import AppCore
import SwiftUI

struct SessionDetailView: View {
    let detail: SessionDetailSnapshot?
    let isPlaying: Bool
    let onTogglePlayback: () -> Void
    let onStopPlayback: () -> Void
    let onTranscribe: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let detail {
                let session = detail.session
                let hasExistingJobs = detail.utterances.contains { !$0.transcriptionJobs.isEmpty }

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
                if session.audioFilePath != nil {
                    HStack(spacing: 12) {
                        Button(isPlaying ? "Pause Playback" : "Play Recording") {
                            onTogglePlayback()
                        }
                        .buttonStyle(.bordered)

                        Button("Stop Playback") {
                            onStopPlayback()
                        }
                        .buttonStyle(.bordered)
                        .disabled(!isPlaying)

                        Button("Transcribe Recording") {
                            onTranscribe()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(session.transcriptionStatus == .running)

                        if hasExistingJobs, session.transcriptionStatus != .running {
                            Button("Retry Transcription") {
                                onTranscribe()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                CopyableDetailRow(title: "Transcription", value: session.transcriptionStatus.rawValue)
                if let transcriptFilePath = session.transcriptFilePath {
                    CopyableDetailRow(title: "Transcript File", value: transcriptFilePath, isMonospaced: true)
                }
                if let transcriptionDurationSeconds = session.transcriptionDurationSeconds {
                    CopyableDetailRow(
                        title: "ASR Time",
                        value: String(format: "%.1f sec", transcriptionDurationSeconds)
                    )
                }
                if let transcriptionError = session.transcriptionError {
                    CopyableDetailRow(title: "ASR Error", value: transcriptionError)
                }

                Divider()

                latestJobSection(detail: detail)

                Divider()

                utterancesSection(detail: detail)

                Divider()

                Text("Transcript")
                    .font(.headline)
                Text(session.transcriptText ?? "Not available yet.")
                    .foregroundStyle(session.transcriptText == nil ? .secondary : .primary)
                    .textSelection(.enabled)

                Text("Summary")
                    .font(.headline)
                Text("Not available yet in Milestone 3.")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
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
                ForEach(detail.utterances) { utteranceDetail in
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
                                }

                                if job.id != utteranceDetail.transcriptionJobs.first?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if utteranceDetail.id != detail.utterances.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private func format(date: Date) -> String {
        date.formatted(.dateTime.year().month().day().hour().minute().second())
    }
}
