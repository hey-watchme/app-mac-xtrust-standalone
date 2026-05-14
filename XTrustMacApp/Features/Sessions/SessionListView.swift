import AppCore
import SwiftUI

// MARK: - Root Layout

struct SessionListView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Group {
            if appState.activeAccessSession == nil {
                LockedDeviceView(appState: appState)
            } else {
                NavigationSplitView {
                    SidebarView(
                        sessions: appState.sessions,
                        selectedSessionID: Binding(
                            get: { appState.selectedSessionID },
                            set: { appState.selectSession($0) }
                        ),
                        isShowingSettings: appState.isShowingSettings,
                        isShowingChat: appState.isShowingChat,
                        isMeetingsSectionExpanded: appState.isMeetingsSectionExpanded,
                        activeAccountName: appState.activeAccessAccountDisplayName,
                        onNewSession: { appState.createSession() },
                        onShowSettings: { appState.showSettings() },
                        onShowChat: { appState.showChat() },
                        onToggleMeetings: {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                appState.isMeetingsSectionExpanded.toggle()
                            }
                        },
                        onLogout: { appState.logoutActiveAccess() }
                    )
                    .navigationSplitViewColumnWidth(
                        min: 200, ideal: XT.Layout.sidebarWidth, max: 320
                    )
                } detail: {
                    if appState.isShowingChat {
                        ChatView(appState: appState)
                    } else if appState.isShowingSettings {
                        SettingsView(
                            diagnostics: appState.diagnostics,
                            sessionCount: appState.sessions.count,
                            errorMessage: appState.errorMessage,
                            maintenanceMessage: appState.maintenanceMessage,
                            isSummaryQueueBusy: appState.isSummaryQueueBusy,
                            onRecoverStaleSummaries: { appState.recoverStaleSummaries() },
                            onRefreshMlxServerStatus: { await appState.refreshMlxServerStatus() },
                            onStopMlxServer: { await appState.stopMlxServer() }
                        )
                    } else {
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
                            onTranscribeUtterance: { id in
                                Task { await appState.transcribeUtterance(utteranceID: id) }
                            },
                            onSummarizeTopic: { id in appState.requestTopicSummary(topicID: id) },
                            onSetSessionStatus: { appState.setSessionStatus($0) },
                            onSetMeetingContextProfile: { appState.setMeetingContextProfile($0) },
                            onSummarizeMeeting: { appState.requestMeetingSummary() },
                            onCopyWrapUp: {
                                guard let detail = appState.selectedSessionDetail else { return }
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(
                                    appState.wrapUpText(for: detail), forType: .string
                                )
                            },
                            meetingSummaryText: appState.meetingSummaryText,
                            isSummarizingMeeting: appState.isSummarizingMeeting,
                            isSummaryQueueBusy: appState.isSummaryQueueBusy
                        )
                    }
                }
                .navigationSplitViewStyle(.balanced)
            }
        }
    }
}

// MARK: - Sidebar

private struct SidebarView: View {
    let sessions: [Session]
    @Binding var selectedSessionID: Session.ID?
    let isShowingSettings: Bool
    let isShowingChat: Bool
    let isMeetingsSectionExpanded: Bool
    let activeAccountName: String?
    let onNewSession: () -> Void
    let onShowSettings: () -> Void
    let onShowChat: () -> Void
    let onToggleMeetings: () -> Void
    let onLogout: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            sidebarHeader
            Divider().padding(.horizontal, XT.S.md)

            ScrollView {
                VStack(spacing: 0) {
                    meetingsSectionHeader
                    if isMeetingsSectionExpanded {
                        newSessionButton
                        if sessions.isEmpty {
                            sidebarEmpty
                        } else {
                            sessionsList
                        }
                    }
                    Divider()
                        .padding(.horizontal, XT.S.md)
                        .padding(.vertical, XT.S.xs)
                    chatRow
                }
            }

            Spacer(minLength: 0)
            Divider().padding(.horizontal, XT.S.md)
            footerMenu
        }
    }

    // MARK: Header

    private var sidebarHeader: some View {
        VStack(spacing: XT.S.xs) {
            HStack {
                XTrustLogoView()
                Spacer()
            }
            HStack {
                Text(activeAccountName.map { "使用中: \($0)" } ?? "使用中")
                    .font(XT.F.caption)
                    .foregroundStyle(XT.C.textSecondary)
                Spacer()
            }
        }
        .padding(.horizontal, XT.S.lg)
        .padding(.vertical, XT.S.md)
    }

    // MARK: Meetings Section Header

    private var meetingsSectionHeader: some View {
        Button(action: onToggleMeetings) {
            HStack(spacing: XT.S.xs) {
                Image(systemName: isMeetingsSectionExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(XT.C.textTertiary)
                    .frame(width: 12)
                Text("会議")
                    .font(XT.F.sectionLabel)
                    .foregroundStyle(XT.C.textSecondary)
                    .textCase(.uppercase)
                Spacer()
            }
            .padding(.horizontal, XT.S.lg)
            .padding(.vertical, XT.S.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: New Session Button

    private var newSessionButton: some View {
        Button(action: onNewSession) {
            HStack(spacing: XT.S.sm) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(XT.C.accent)
                Text("新規セッション")
                    .font(XT.F.sidebarItem)
                    .foregroundStyle(XT.C.accent)
                Spacer()
            }
            .padding(.horizontal, XT.S.md)
            .padding(.vertical, XT.S.sm + 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, XT.S.sm)
        .padding(.vertical, XT.S.xs)
    }

    // MARK: Session List

    private var sessionsList: some View {
        LazyVStack(spacing: 1) {
            ForEach(sessions) { session in
                SidebarSessionRow(
                    session: session,
                    isSelected: selectedSessionID == session.id
                ) {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        selectedSessionID = session.id
                    }
                }
            }
        }
        .padding(.vertical, XT.S.xs)
        .padding(.horizontal, XT.S.sm)
    }

    // MARK: Empty State

    private var sidebarEmpty: some View {
        VStack(spacing: XT.S.sm) {
            Image(systemName: "waveform.badge.microphone")
                .font(.system(size: 24))
                .foregroundStyle(XT.C.textTertiary)
                .symbolRenderingMode(.hierarchical)
            Text("まだセッションがありません")
                .font(XT.F.caption)
                .foregroundStyle(XT.C.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, XT.S.xxl)
    }

    // MARK: Chat Row

    private var chatRow: some View {
        Button(action: onShowChat) {
            HStack(spacing: XT.S.sm) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isShowingChat ? XT.C.textPrimary : XT.C.accent)
                Text("チャット")
                    .font(XT.F.sidebarItem)
                    .foregroundStyle(XT.C.textPrimary)
                Spacer()
            }
            .padding(.horizontal, XT.S.lg)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: XT.R.sm)
                    .fill(isShowingChat ? XT.C.selectedBG : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, XT.S.sm)
    }

    // MARK: Footer

    private var footerMenu: some View {
        VStack(spacing: 0) {
            sidebarFooterButton(
                title: "退出",
                systemImage: "rectangle.portrait.and.arrow.right",
                isSelected: false,
                action: onLogout
            )
            sidebarFooterButton(
                title: "Settings",
                systemImage: "gearshape",
                isSelected: isShowingSettings,
                action: onShowSettings
            )
        }
    }

    private func sidebarFooterButton(
        title: String,
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: XT.S.sm) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isSelected ? XT.C.textPrimary : XT.C.accent)
                Text(title)
                    .font(XT.F.sidebarItem)
                    .foregroundStyle(XT.C.textPrimary)
                Spacer()
            }
            .padding(.horizontal, XT.S.lg)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: XT.R.sm)
                    .fill(isSelected ? XT.C.selectedBG : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Locked Device

private struct LockedDeviceView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    XT.C.windowBG,
                    XT.C.cardBG.opacity(0.94)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: XT.S.xl) {
                XTCard {
                    VStack(alignment: .leading, spacing: XT.S.lg) {
                        VStack(alignment: .leading, spacing: XT.S.sm) {
                            XTrustLogoView()
                            Text("共有会議デバイス")
                                .font(XT.F.displayTitle)
                                .foregroundStyle(XT.C.textPrimary)
                            Text("利用開始すると、この場の会議だけを処理します。終了後は共有画面をリセットします。")
                                .font(XT.F.body)
                                .foregroundStyle(XT.C.textSecondary)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: XT.S.sm) {
                            CopyableDetailRow(
                                title: "Organization",
                                value: appState.sharedDeviceContext.organization.name,
                                showCopyButton: false
                            )
                            CopyableDetailRow(
                                title: "Workspace",
                                value: appState.sharedDeviceContext.workspace.name,
                                showCopyButton: false
                            )
                            CopyableDetailRow(
                                title: "Device",
                                value: appState.sharedDeviceContext.device.displayName,
                                showCopyButton: false
                            )
                            if let location = appState.sharedDeviceContext.device.locationLabel {
                                CopyableDetailRow(
                                    title: "Location",
                                    value: location,
                                    showCopyButton: false
                                )
                            }
                        }

                        HStack {
                            Button(action: { appState.beginLocalAccess() }) {
                                Label("ゲストとして利用を開始", systemImage: "person.circle.fill")
                            }
                            .buttonStyle(XTPrimaryButtonStyle())

                            Spacer()
                        }

                        if let errorMessage = appState.errorMessage {
                            Text(errorMessage)
                                .font(XT.F.caption)
                                .foregroundStyle(XT.C.destructive)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(XT.S.xl)
                }
                .frame(maxWidth: 640)
            }
            .padding(XT.S.xxxl)
        }
    }
}

// MARK: - Sidebar Session Row

private struct SidebarSessionRow: View {
    let session: Session
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: XT.S.sm) {
                // Status indicator dot
                statusDot

                VStack(alignment: .leading, spacing: 3) {
                    Text(dateLabel(from: session.startedAt))
                        .font(XT.F.sidebarItem)
                        .foregroundStyle(XT.C.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: XT.S.xs) {
                        Text(timeLabel(from: session.startedAt))
                            .font(XT.F.sidebarSub)
                            .foregroundStyle(XT.C.textSecondary)

                        if session.utteranceCount > 0 {
                            Text("·")
                                .foregroundStyle(XT.C.textTertiary)
                            Text("\(session.utteranceCount) 件")
                                .font(XT.F.sidebarSub)
                                .foregroundStyle(XT.C.textTertiary)
                        }
                    }
                }

                Spacer()

                statusIcon
                    .padding(.leading, XT.S.xxs)
            }
            .padding(.horizontal, XT.S.md)
            .padding(.vertical, XT.S.sm + 1)
            .background(
                RoundedRectangle(cornerRadius: XT.R.sm)
                    .fill(rowBackground)
            )
            .contentShape(RoundedRectangle(cornerRadius: XT.R.sm))
        }
        .buttonStyle(.plain)
        .onHover { hovered in
            withAnimation(.easeInOut(duration: 0.08)) { isHovered = hovered }
        }
    }

    private var rowBackground: Color {
        if isSelected { return XT.C.selectedBG }
        if isHovered  { return XT.C.hoveredBG }
        return .clear
    }

    private var statusDot: some View {
        Circle()
            .fill(session.status == .recording ? XT.C.recording : Color.clear)
            .frame(width: 6, height: 6)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch session.status {
        case .draft:
            Image(systemName: "circle")
                .font(.system(size: 10))
                .foregroundStyle(XT.C.textTertiary)
        case .recording:
            Image(systemName: "record.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(XT.C.recording)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(XT.C.success)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(XT.C.destructive)
        case .closed:
            Image(systemName: "archivebox.fill")
                .font(.system(size: 10))
                .foregroundStyle(XT.C.textTertiary)
        }
    }

    private func dateLabel(from date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M月d日（E）"
        return f.string(from: date)
    }

    private func timeLabel(from date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "H:mm"
        return f.string(from: date)
    }
}
