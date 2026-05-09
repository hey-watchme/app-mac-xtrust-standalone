import AppCore
import SwiftUI

// MARK: - Root Layout

struct SessionListView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        NavigationSplitView {
            SidebarView(
                sessions: appState.sessions,
                selectedSessionID: Binding(
                    get: { appState.selectedSessionID },
                    set: { appState.selectSession($0) }
                ),
                onNewSession: { appState.createSession() }
            )
            .navigationSplitViewColumnWidth(
                min: 200, ideal: XT.Layout.sidebarWidth, max: 320
            )
        } detail: {
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
                onSummarizeTopic: { id in
                    Task { await appState.summarizeTopic(topicID: id) }
                },
                onSetSessionStatus: { appState.setSessionStatus($0) },
                onSummarizeMeeting: {
                    Task { await appState.summarizeMeeting() }
                },
                onCopyWrapUp: {
                    guard let detail = appState.selectedSessionDetail else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        appState.wrapUpText(for: detail), forType: .string
                    )
                },
                meetingSummaryText: appState.meetingSummaryText,
                isSummarizingMeeting: appState.isSummarizingMeeting
            )
        }
        .navigationSplitViewStyle(.balanced)
    }
}

// MARK: - Sidebar

private struct SidebarView: View {
    let sessions: [Session]
    @Binding var selectedSessionID: Session.ID?
    let onNewSession: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            sidebarHeader

            Divider()
                .padding(.horizontal, XT.S.md)

            if sessions.isEmpty {
                sidebarEmpty
            } else {
                sidebarList
            }

            Spacer(minLength: 0)

            Divider()
                .padding(.horizontal, XT.S.md)

            newSessionButton
        }
    }

    // MARK: Header

    private var sidebarHeader: some View {
        HStack {
            XTrustLogoView()
            Spacer()
        }
        .padding(.horizontal, XT.S.lg)
        .frame(height: 52)
    }

    // MARK: Session List

    private var sidebarList: some View {
        ScrollView {
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
            .padding(.vertical, XT.S.sm)
            .padding(.horizontal, XT.S.sm)
        }
    }

    // MARK: Empty State

    private var sidebarEmpty: some View {
        VStack(spacing: XT.S.sm) {
            Image(systemName: "waveform.badge.microphone")
                .font(.system(size: 28))
                .foregroundStyle(XT.C.textTertiary)
                .symbolRenderingMode(.hierarchical)
            Text("まだセッションがありません")
                .font(XT.F.caption)
                .foregroundStyle(XT.C.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, XT.S.xxxl)
    }

    // MARK: New Session Button

    private var newSessionButton: some View {
        Button(action: onNewSession) {
            HStack(spacing: XT.S.sm) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(XT.C.accent)
                Text("新規セッション")
                    .font(XT.F.sidebarItem)
                    .foregroundStyle(XT.C.textPrimary)
                Spacer()
            }
            .padding(.horizontal, XT.S.lg)
            .frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
