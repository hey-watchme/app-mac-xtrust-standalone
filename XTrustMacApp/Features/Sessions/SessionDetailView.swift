import AppCore
import SwiftUI

struct SessionDetailView: View {
    let session: Session?
    let isPlaying: Bool
    let onTogglePlayback: () -> Void
    let onStopPlayback: () -> Void
    let onTranscribe: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let session {
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
}
