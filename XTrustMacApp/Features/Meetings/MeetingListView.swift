import AppCore
import SwiftUI

// MARK: - Root Layout

struct MeetingListView: View {
    var model: AppModel

    var body: some View {
        Group {
            if model.activeAccessSession == nil {
                LockedDeviceView(model: model)
            } else {
                slackShell
            }
        }
    }

    // MARK: - Slack-style Shell

    private var slackShell: some View {
        HStack(spacing: 0) {
            // 1. WorkspaceRail (60px)
            WorkspaceRail(
                onShowSettings: { model.showSettings() }
            )

            // 2. Sidebar (264px)
            SlackSidebar(
                sessions: model.sessions,
                selectedSessionID: model.selectedSessionID,
                minutesStatusBySession: model.minutesStatusBySession,
                isShowingSettings: model.isShowingSettings,
                isShowingChat: model.isShowingChat,
                isMeetingsSectionExpanded: model.isMeetingsSectionExpanded,
                activeAccountName: model.activeAccessAccountDisplayName,
                isCapturing: model.meetingStore.isCapturing,
                onSelectSession: { model.selectSession($0) },
                onShowSettings: { model.showSettings() },
                onShowChat: { model.showChat() },
                onToggleMeetings: {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        model.isMeetingsSectionExpanded.toggle()
                    }
                },
                onLogout: { model.logoutActiveAccess() },
                onStartNewMeeting: { model.startMeeting() }
            )

            // 3. Main content (flex)
            mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 4. Inspector (384px, collapsible) — hidden while chat is open
            if !model.isShowingChat {
                AIInspector(
                    minutes: model.meetingStore.minutes,
                    isGeneratingMinutes: model.meetingStore.isGeneratingMinutes,
                    isVisible: model.isInspectorVisible,
                    onToggle: { model.toggleInspector() },
                    onRetryMinutes: { model.meetingStore.retryMinutes() }
                )
                .animation(.spring(response: 0.28, dampingFraction: 0.85), value: model.isInspectorVisible)
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if model.isShowingChat {
            ChatView(appState: model)
                .background(XT.C.winBg)
        } else if model.isShowingSettings {
            SettingsView(
                diagnostics: model.diagnostics,
                sessionCount: model.sessions.count,
                errorMessage: model.errorMessage,
                maintenanceMessage: model.maintenanceMessage,
                onRefreshMlxServerStatus: { await model.refreshMlxServerStatus() },
                onStopMlxServer: { await model.stopMlxServer() }
            )
        } else {
            SlackMeetingView(model: model)
        }
    }
}

// MARK: - Locked Device Screen (redesigned with dark navy branding)

private struct LockedDeviceView: View {
    var model: AppModel

    var body: some View {
        ZStack {
            // Dark navy gradient background
            LinearGradient(
                colors: [
                    Color(hex: "#0C1226"),
                    Color(hex: "#131A2E"),
                    Color(hex: "#1A2238")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Subtle grid pattern overlay
            Canvas { context, size in
                let spacing: CGFloat = 40
                var x: CGFloat = 0
                while x < size.width {
                    var y: CGFloat = 0
                    while y < size.height {
                        context.fill(
                            Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)),
                            with: .color(.white.opacity(0.04))
                        )
                        y += spacing
                    }
                    x += spacing
                }
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 32) {
                    // Logo + tagline
                    VStack(spacing: 12) {
                        // XTRUST logo tile
                        ZStack {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: "#6366F1"), Color(hex: "#4F46E5")],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 72, height: 72)
                                .shadow(color: Color(hex: "#6366F1").opacity(0.5), radius: 20, x: 0, y: 8)
                            Text("X")
                                .font(.system(size: 32, weight: .black))
                                .foregroundStyle(.white)
                        }

                        VStack(spacing: 6) {
                            HStack(spacing: 0) {
                                Text("X")
                                    .font(.system(size: 28, weight: .black))
                                    .foregroundStyle(.white)
                                Text("TRUST")
                                    .font(.system(size: 28, weight: .ultraLight))
                                    .tracking(3)
                                    .foregroundStyle(.white)
                            }
                            Text("AI 議事録 · オンデバイス · 暗号化")
                                .font(.system(size: 13))
                                .foregroundStyle(Color(hex: "#A5B4FC").opacity(0.8))
                        }
                    }

                    // Card
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("共有会議デバイス")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white)
                            Text("利用開始すると、この場の会議だけを処理します。\n終了後は共有画面をリセットします。")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.white.opacity(0.65))
                                .lineSpacing(4)
                        }

                        Divider().background(Color.white.opacity(0.08))

                        VStack(alignment: .leading, spacing: 8) {
                            deviceInfoRow(label: "Organization", value: model.sharedDeviceContext.organization.name)
                            deviceInfoRow(label: "Workspace", value: model.sharedDeviceContext.workspace.name)
                            deviceInfoRow(label: "Device", value: model.sharedDeviceContext.device.displayName)
                            if let location = model.sharedDeviceContext.device.locationLabel {
                                deviceInfoRow(label: "Location", value: location)
                            }
                        }

                        Divider().background(Color.white.opacity(0.08))

                        // Security badges
                        HStack(spacing: 8) {
                            securityBadge(icon: "cpu", text: "オンデバイス処理")
                            securityBadge(icon: "lock.shield.fill", text: "AES-256 暗号化")
                            securityBadge(icon: "wifi.slash", text: "外部送信なし")
                        }

                        // Action button
                        Button(action: { model.beginLocalAccess() }) {
                            HStack(spacing: 8) {
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 16))
                                Text("ゲストとして利用を開始")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(
                                LinearGradient(
                                    colors: [Color(hex: "#4F46E5"), Color(hex: "#6366F1")],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .shadow(color: Color(hex: "#4F46E5").opacity(0.5), radius: 12, x: 0, y: 4)
                        }
                        .buttonStyle(.plain)

                        if let errorMessage = model.errorMessage {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Color(hex: "#EF4444"))
                                Text(errorMessage)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color(hex: "#FECACA"))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding(24)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                    )
                    .frame(maxWidth: 480)
                }

                Spacer()
            }
            .padding(.horizontal, 40)
        }
    }

    private func deviceInfoRow(label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.45))
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.8))
        }
    }

    private func securityBadge(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(Color(hex: "#34D399"))
            Text(text)
                .font(.system(size: 10.5))
                .foregroundStyle(Color.white.opacity(0.55))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.06))
        .clipShape(Capsule())
    }
}
