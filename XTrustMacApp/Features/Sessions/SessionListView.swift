import AppCore
import SwiftUI

struct SessionListView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        NavigationSplitView {
            List(
                appState.sessions,
                selection: Binding(
                    get: { appState.selectedSessionID },
                    set: { appState.selectedSessionID = $0 }
                )
            ) { session in
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.startedAt, format: .dateTime.year().month().day().hour().minute())
                        .font(.headline)
                    Text(session.status.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .overlay {
                if appState.sessions.isEmpty {
                    ContentUnavailableView(
                        "No Sessions Yet",
                        systemImage: "waveform.badge.plus",
                        description: Text("Create an empty local session to verify workspace setup.")
                    )
                }
            }
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Local Sessions")
                        .font(.largeTitle)
                        .fontWeight(.semibold)

                    Button("New Session") {
                        appState.createSession()
                    }
                    .buttonStyle(.borderedProminent)

                    HStack(spacing: 12) {
                        Button("Start Recording") {
                            Task {
                                await appState.startRecording()
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(appState.isRecording)

                        Button("Stop Recording") {
                            Task {
                                await appState.stopRecording()
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(!appState.isRecording)
                    }

                SessionDetailView(
                    session: appState.selectedSession,
                    isPlaying: appState.isPlayingSelectedSession,
                    onTogglePlayback: { appState.togglePlaybackForSelectedSession() },
                    onStopPlayback: { appState.stopPlayback() },
                    onTranscribe: {
                        Task {
                            await appState.transcribeSelectedSession()
                        }
                    }
                )

                    Divider()

                    DiagnosticsView(
                        diagnostics: appState.diagnostics,
                        sessionCount: appState.sessions.count,
                        errorMessage: appState.errorMessage
                    )

                    Spacer(minLength: 0)
                }
                .padding(32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
