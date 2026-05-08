import SwiftUI

struct DiagnosticsView: View {
    let diagnostics: AppDiagnostics
    let sessionCount: Int
    let errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Diagnostics")
                .font(.title3)
                .fontWeight(.semibold)

            CopyableDetailRow(
                title: "Workspace Root",
                value: diagnostics.workspaceRoot.path(percentEncoded: false),
                isMonospaced: true
            )
            CopyableDetailRow(
                title: "Database",
                value: diagnostics.databaseURL.path(percentEncoded: false),
                isMonospaced: true
            )
            CopyableDetailRow(
                title: "Whisper Model",
                value: diagnostics.whisperModelPath,
                isMonospaced: true
            )
            CopyableDetailRow(
                title: "Gemma 4 Model",
                value: diagnostics.gemmaModelPath,
                isMonospaced: true
            )
            CopyableDetailRow(title: "Session Count", value: String(sessionCount))

            statusRow("Audio Directory", isReady: diagnostics.audioReady)
            statusRow("Transcript Directory", isReady: diagnostics.transcriptsReady)
            statusRow("Summary Directory", isReady: diagnostics.summariesReady)
            statusRow("Models Directory", isReady: diagnostics.modelsReady)
            statusRow("Whisper Model Ready", isReady: diagnostics.whisperModelReady)
            statusRow("Gemma 4 Model Ready", isReady: diagnostics.gemmaModelReady)
            statusRow("Database File", isReady: diagnostics.databaseReady)
            statusRow("Recording Active", isReady: diagnostics.recordingActive)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.callout)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func statusRow(_ title: String, isReady: Bool) -> some View {
        CopyableDetailRow(title: title, value: isReady ? "Yes" : "No")
    }
}
