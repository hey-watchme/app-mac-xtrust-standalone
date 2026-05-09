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
                Text(sessionTitle(from: session.startedAt))
                    .font(.headline)
                    .padding(.vertical, 4)
            }
            .overlay {
                if appState.sessions.isEmpty {
                    ContentUnavailableView(
                        "セッションがありません",
                        systemImage: "waveform.badge.plus",
                        description: Text("「新規セッション」を押して開始してください。")
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("新規セッション") {
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
                        diagnostics: appState.diagnostics,
                        sessionCount: appState.sessions.count,
                        errorMessage: appState.errorMessage,
                        onStartListening: {
                            Task { await appState.startListening() }
                        },
                        onStopListening: { appState.stopListening() },
                        onTranscribeUtterance: { utteranceID in
                            Task { await appState.transcribeUtterance(utteranceID: utteranceID) }
                        },
                        onSummarizeTopic: { topicID in
                            Task { await appState.summarizeTopic(topicID: topicID) }
                        },
                        onSetSessionStatus: { appState.setSessionStatus($0) },
                        onSummarizeMeeting: {
                            Task { await appState.summarizeMeeting() }
                        },
                        onCopyWrapUp: {
                            if let detail = appState.selectedSessionDetail {
                                let text = appState.wrapUpText(for: detail)
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(text, forType: .string)
                            }
                        },
                        meetingSummaryText: appState.meetingSummaryText,
                        isSummarizingMeeting: appState.isSummarizingMeeting
                    )

                    Spacer(minLength: 0)
                }
                .padding(32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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

}
