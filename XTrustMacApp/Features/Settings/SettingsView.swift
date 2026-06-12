import AppCore
import SwiftUI

struct SettingsView: View {
    let diagnostics: AppDiagnostics
    let sessionCount: Int
    let errorMessage: String?
    let maintenanceMessage: String?
    let onRefreshMlxServerStatus: () async -> Void
    let onStopMlxServer: () async -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: XT.S.xxl) {
                    deviceScopeCard
                    accountCard
                    maintenanceCard
                    diagnosticsCard
                    mlxServerControlCard
                }
                .padding(XT.Layout.contentPadding)
                .frame(maxWidth: XT.Layout.contentMaxWidth)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle("Settings")
        .task {
            while !Task.isCancelled {
                await onRefreshMlxServerStatus()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private var mlxServerControlCard: some View {
        XTCard {
            VStack(alignment: .leading, spacing: XT.S.lg) {
                XTSectionLabel(text: "MLX Server Control")

                Text("ローカル LLM (mlx_vlm.server) を常駐プロセスとして起動・再利用します。アイドルが \(idleTimeoutMinutes) 分続くと自動停止します。")
                    .font(XT.F.caption)
                    .foregroundStyle(XT.C.textSecondary)

                Button(action: {
                    Task { await onStopMlxServer() }
                }) {
                    Label("Stop MLX Server", systemImage: "stop.circle")
                }
                .buttonStyle(XTSecondaryButtonStyle())
                .disabled(!isMlxServerRunnable)
            }
            .padding(XT.S.xl)
        }
    }

    private var idleTimeoutMinutes: Int {
        guard let status = diagnostics.mlxServerStatus else { return 10 }
        return max(1, Int(status.idleTimeout / 60))
    }

    private var isMlxServerRunnable: Bool {
        guard let status = diagnostics.mlxServerStatus else { return false }
        switch status.state {
        case .running, .starting: return true
        case .stopped, .killed, .failed: return false
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Settings")
                    .font(XT.F.displayTitle)
                    .foregroundStyle(XT.C.textPrimary)

                Text("共有デバイスの現在の構成と状態")
                    .font(XT.F.caption)
                    .foregroundStyle(XT.C.textSecondary)
            }

            Spacer()
        }
        .padding(.horizontal, XT.Layout.contentPadding)
        .frame(height: 64)
    }

    private var deviceScopeCard: some View {
        XTCard {
            VStack(alignment: .leading, spacing: XT.S.lg) {
                XTSectionLabel(text: "Device Scope")

                CopyableDetailRow(
                    title: "Organization",
                    value: diagnostics.sharedDeviceContext.organization.name
                )
                CopyableDetailRow(
                    title: "Workspace",
                    value: diagnostics.sharedDeviceContext.workspace.name
                )
                CopyableDetailRow(
                    title: "Workspace Code",
                    value: diagnostics.sharedDeviceContext.workspace.code ?? "None"
                )
                CopyableDetailRow(
                    title: "Device",
                    value: diagnostics.sharedDeviceContext.device.displayName
                )
                CopyableDetailRow(
                    title: "Location",
                    value: diagnostics.sharedDeviceContext.device.locationLabel ?? "None"
                )
                CopyableDetailRow(
                    title: "Provisioning",
                    value: "Bootstrap Default"
                )
            }
            .padding(XT.S.xl)
        }
    }

    private var accountCard: some View {
        XTCard {
            VStack(alignment: .leading, spacing: XT.S.lg) {
                XTSectionLabel(text: "Accounts")

                CopyableDetailRow(
                    title: "Bootstrap Account",
                    value: diagnostics.sharedDeviceContext.bootstrapAccount.displayName
                )
                CopyableDetailRow(
                    title: "Active Access",
                    value: diagnostics.activeAccessAccountDisplayName ?? "None"
                )
                CopyableDetailRow(
                    title: "Access Status",
                    value: diagnostics.accessActive ? "Active" : "Locked"
                )
            }
            .padding(XT.S.xl)
        }
    }

    private var diagnosticsCard: some View {
        XTCard {
            DiagnosticsView(
                diagnostics: diagnostics,
                sessionCount: sessionCount,
                errorMessage: errorMessage
            )
            .padding(XT.S.xl)
        }
    }

    private var maintenanceCard: some View {
        XTCard {
            VStack(alignment: .leading, spacing: XT.S.lg) {
                XTSectionLabel(text: "Maintenance")

                CopyableDetailRow(
                    title: "Recovered Minutes",
                    value: String(diagnostics.recoveredMinutesCount),
                    showCopyButton: false
                )

                Text("起動時に前回中断された議事録生成を自動で再開します。")
                    .font(XT.F.caption)
                    .foregroundStyle(XT.C.textSecondary)

                if let maintenanceMessage {
                    Text(maintenanceMessage)
                        .font(XT.F.caption)
                        .foregroundStyle(XT.C.textSecondary)
                        .textSelection(.enabled)
                }
            }
            .padding(XT.S.xl)
        }
    }
}
