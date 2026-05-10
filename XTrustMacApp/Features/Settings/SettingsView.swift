import AppCore
import SwiftUI

struct SettingsView: View {
    let diagnostics: AppDiagnostics
    let sessionCount: Int
    let errorMessage: String?
    let maintenanceMessage: String?
    let isSummaryQueueBusy: Bool
    let onRecoverStaleSummaries: () -> Void

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
                }
                .padding(XT.Layout.contentPadding)
                .frame(maxWidth: XT.Layout.contentMaxWidth)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle("Settings")
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
                    title: "Recovered Stale Summaries",
                    value: String(diagnostics.recoveredStaleSummaryCount),
                    showCopyButton: false
                )

                Text("起動時に前回中断された `running` 要約を自動で失敗扱いへ戻します。必要ならここから手動でも解除できます。")
                    .font(XT.F.caption)
                    .foregroundStyle(XT.C.textSecondary)

                Button(action: onRecoverStaleSummaries) {
                    Label("Reset Stuck Summaries", systemImage: "arrow.clockwise")
                }
                .buttonStyle(XTSecondaryButtonStyle())
                .disabled(isSummaryQueueBusy)

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
