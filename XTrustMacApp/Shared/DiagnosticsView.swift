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
                title: "Gemma 4 MLX Model",
                value: diagnostics.mlxModelDirectory,
                isMonospaced: true
            )
            CopyableDetailRow(
                title: "Speech Locale",
                value: diagnostics.speechAssetStatus?.localeIdentifier ?? "ja-JP",
                showCopyButton: false
            )
            CopyableDetailRow(
                title: "Memory Safety",
                value: "Pressure monitoring active",
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
                title: "Recovered Minutes",
                value: String(diagnostics.recoveredMinutesCount),
                showCopyButton: false
            )
            CopyableDetailRow(title: "Session Count", value: String(sessionCount))

            statusRow("Audio Directory", isReady: diagnostics.audioReady)
            statusRow("Models Directory", isReady: diagnostics.modelsReady)
            statusRow(
                "Speech Locale Supported",
                isReady: diagnostics.speechAssetStatus?.localeSupported ?? false
            )
            statusRow(
                "Speech Assets Installed",
                isReady: diagnostics.speechAssetStatus?.localeInstalled ?? false
            )
            statusRow("Gemma 4 MLX Ready", isReady: diagnostics.gemmaModelReady)
            statusRow("Database File", isReady: diagnostics.databaseReady)
            statusRow("Access Active", isReady: diagnostics.accessActive)
            statusRow("Recording Active", isReady: diagnostics.recordingActive)

            mlxServerSection

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

    @ViewBuilder
    private var mlxServerSection: some View {
        if let status = diagnostics.mlxServerStatus {
            Divider().padding(.vertical, 2)

            Text("MLX Server")
                .font(.headline)

            CopyableDetailRow(
                title: "State",
                value: stateLabel(for: status.state),
                showCopyButton: false
            )
            CopyableDetailRow(
                title: "PID",
                value: status.pid.map(String.init) ?? "—",
                showCopyButton: false
            )
            CopyableDetailRow(
                title: "Port",
                value: status.port.map(String.init) ?? "—",
                showCopyButton: false
            )
            CopyableDetailRow(
                title: "Uptime",
                value: uptimeLabel(startedAt: status.startedAt),
                showCopyButton: false
            )
            CopyableDetailRow(
                title: "Last Request",
                value: relativeLabel(date: status.lastRequestAt),
                showCopyButton: false
            )
            CopyableDetailRow(
                title: "Idle Timeout",
                value: "\(Int(status.idleTimeout / 60)) min",
                showCopyButton: false
            )
            if let message = status.lastErrorMessage, !message.isEmpty {
                CopyableDetailRow(
                    title: "Last Error",
                    value: message,
                    isMonospaced: true
                )
            }
        }
    }

    private func stateLabel(for state: MLXModelServerStatus.State) -> String {
        switch state {
        case .stopped: return "Stopped"
        case .starting: return "Starting"
        case .running: return "Running"
        case .killed: return "Killed"
        case .failed: return "Failed"
        }
    }

    private func uptimeLabel(startedAt: Date?) -> String {
        guard let startedAt else { return "—" }
        let seconds = Int(Date().timeIntervalSince(startedAt))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        let remaining = seconds % 60
        return "\(minutes)m \(remaining)s"
    }

    private func relativeLabel(date: Date?) -> String {
        guard let date else { return "—" }
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        return "\(minutes)m ago"
    }
}
