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
                title: "Organization",
                value: diagnostics.sharedDeviceContext.organization.name
            )
            CopyableDetailRow(
                title: "Workspace",
                value: diagnostics.sharedDeviceContext.workspace.name
            )
            CopyableDetailRow(
                title: "Device",
                value: diagnostics.sharedDeviceContext.device.displayName
            )
            if let locationLabel = diagnostics.sharedDeviceContext.device.locationLabel {
                CopyableDetailRow(title: "Device Location", value: locationLabel)
            }
            CopyableDetailRow(
                title: "Bootstrap Account",
                value: diagnostics.sharedDeviceContext.bootstrapAccount.displayName
            )
            CopyableDetailRow(
                title: "Active Access Account",
                value: diagnostics.activeAccessAccountDisplayName ?? "None"
            )
            CopyableDetailRow(
                title: "Moonshine Model",
                value: diagnostics.moonshineModelDirectory,
                isMonospaced: true
            )
            CopyableDetailRow(
                title: "Gemma 4 MLX Model",
                value: diagnostics.mlxModelDirectory,
                isMonospaced: true
            )
            CopyableDetailRow(
                title: "MLX Required Memory",
                value: ByteCountFormatter.string(
                    fromByteCount: Int64(diagnostics.mlxRequiredAvailableMemoryBytes),
                    countStyle: .memory
                ),
                showCopyButton: false
            )
            CopyableDetailRow(
                title: "Current Free Memory",
                value: diagnostics.currentAvailableMemoryBytes.map {
                    ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .memory)
                } ?? "Unknown",
                showCopyButton: false
            )
            CopyableDetailRow(
                title: "Recovered Stale Summaries",
                value: String(diagnostics.recoveredStaleSummaryCount),
                showCopyButton: false
            )
            CopyableDetailRow(title: "Session Count", value: String(sessionCount))

            statusRow("Audio Directory", isReady: diagnostics.audioReady)
            statusRow("Transcript Directory", isReady: diagnostics.transcriptsReady)
            statusRow("Summary Directory", isReady: diagnostics.summariesReady)
            statusRow("Models Directory", isReady: diagnostics.modelsReady)
            statusRow("Moonshine Model Ready", isReady: diagnostics.moonshineModelReady)
            statusRow("Gemma 4 MLX Ready", isReady: diagnostics.gemmaModelReady)
            statusRow("Database File", isReady: diagnostics.databaseReady)
            statusRow("Access Active", isReady: diagnostics.accessActive)
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
