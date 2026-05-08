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
                    set: { appState.selectSession($0) }
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
                        description: Text("Select \"New Session\" above to start.")
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New Session") {
                        appState.createSession()
                    }
                }
            }
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SessionDetailView(
                        detail: appState.selectedSessionDetail,
                        isListening: appState.isListening,
                        isSpeechActive: appState.isSpeechActive,
                        audioLevel: appState.audioLevel,
                        onStartListening: {
                            Task { await appState.startListening() }
                        },
                        onStopListening: { appState.stopListening() },
                        onTranscribeUtterance: { utteranceID in
                            Task { await appState.transcribeUtterance(utteranceID: utteranceID) }
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
