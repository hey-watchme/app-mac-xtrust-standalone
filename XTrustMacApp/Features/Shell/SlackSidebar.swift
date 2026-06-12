import AppCore
import SwiftUI

// MARK: - Slack-style Sidebar (264px)

struct SlackSidebar: View {
    let sessions: [CaptureSession]
    let selectedSessionID: UUID?
    let minutesStatusBySession: [UUID: MeetingMinutes.Status]
    let isShowingSettings: Bool
    let isShowingChat: Bool
    let isMeetingsSectionExpanded: Bool
    let activeAccountName: String?
    let isCapturing: Bool
    let onSelectSession: (UUID?) -> Void
    let onShowSettings: () -> Void
    let onShowChat: () -> Void
    let onToggleMeetings: () -> Void
    let onLogout: () -> Void
    let onStartNewMeeting: () -> Void

    // Sidebar mode: meeting or document
    @State private var sidebarMode: SidebarMode = .meeting

    enum SidebarMode { case meeting, document }

    var body: some View {
        VStack(spacing: 0) {
            workspaceHeader
            modeSwitch
            searchBox
            Divider().background(XT.C.navDivider).padding(.vertical, 4)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if sidebarMode == .meeting {
                        meetingContent
                    } else {
                        documentPlaceholder
                    }
                }
                .padding(.bottom, 8)
            }

            Divider().background(XT.C.navDivider)
            userStrip
        }
        .frame(width: XT.Layout.slackSidebarWidth)
        .background(XT.C.navBg)
    }

    // MARK: - Workspace Header

    private var workspaceHeader: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("渋谷支店")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(XT.C.navText)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(XT.C.navTextDim)
                }
                HStack(spacing: 4) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(XT.C.ok)
                    Text("On-device · Encrypted")
                        .font(.system(size: 11))
                        .foregroundStyle(XT.C.navTextDim)
                }
            }
            Spacer()
            Button(action: onStartNewMeeting) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(XT.C.navTextDim)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(XT.C.navHover)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    // MARK: - Mode Switch

    private var modeSwitch: some View {
        HStack(spacing: 4) {
            modeButton(title: "会議", mode: .meeting)
            modeButton(title: "資料", mode: .document, isBeta: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func modeButton(title: String, mode: SidebarMode, isBeta: Bool = false) -> some View {
        Button(action: { sidebarMode = mode }) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 12.5, weight: sidebarMode == mode ? .semibold : .regular))
                    .foregroundStyle(sidebarMode == mode ? .white : XT.C.navTextDim)
                if isBeta {
                    Text("BETA")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(sidebarMode == mode ? .white.opacity(0.75) : XT.C.navTextMute)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(sidebarMode == mode ? Color.white.opacity(0.2) : XT.C.navHover)
                        )
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        sidebarMode == mode
                        ? LinearGradient(
                            colors: [Color(hex: "#4F46E5"), Color(hex: "#6366F1")],
                            startPoint: .leading, endPoint: .trailing
                          )
                        : LinearGradient(colors: [Color.clear], startPoint: .leading, endPoint: .trailing)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Search Box

    private var searchBox: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(XT.C.navTextMute)
            Text("会議、要約、ナレッジを検索…")
                .font(.system(size: 12))
                .foregroundStyle(XT.C.navTextMute)
            Spacer()
            Text("⌘K")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(XT.C.navTextMute)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(XT.C.navHover)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    // MARK: - Meeting Content

    private var meetingContent: some View {
        VStack(spacing: 0) {
            // Main nav items
            mainNavSection

            sidebarDivider

            // DEALS channels
            dealsSection

            sidebarDivider

            // PORTFOLIO channels
            portfolioSection

            sidebarDivider

            // DM section
            dmSection
        }
    }

    // MARK: - Main Nav Section

    private var mainNavSection: some View {
        VStack(spacing: 1) {
            // Meeting list (real data)
            navRow(
                icon: "calendar",
                title: "会議一覧",
                badge: sessions.isEmpty ? nil : "\(sessions.count)",
                isActive: false,
                isExpandable: true,
                isExpanded: isMeetingsSectionExpanded,
                onToggle: onToggleMeetings
            )

            if isMeetingsSectionExpanded {
                VStack(spacing: 1) {
                    if sessions.isEmpty {
                        Text("まだ会議がありません")
                            .font(XT.F.caption)
                            .foregroundStyle(XT.C.navTextMute)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(sessions) { session in
                            SlackSidebarMeetingRow(
                                session: session,
                                minutesStatus: minutesStatusBySession[session.id],
                                isSelected: selectedSessionID == session.id && !isShowingChat && !isShowingSettings,
                                isCapturing: isCapturing && session.status == .recording
                            ) {
                                onSelectSession(session.id)
                            }
                        }
                    }
                }
                .padding(.leading, 16)
            }

            // Live transcript (active if capturing)
            navRow(
                icon: "waveform.badge.microphone",
                title: "ライブ議事録",
                badge: nil,
                liveBadge: isCapturing,
                isActive: isCapturing && selectedSessionID != nil && !isShowingChat && !isShowingSettings,
                action: {
                    if let id = selectedSessionID { onSelectSession(id) }
                }
            )

            navRow(icon: "doc.text", title: "要約", badge: "47", isActive: false)
            navRow(icon: "checkmark.square", title: "タスク", badge: "3", badgeRed: true, isActive: false)
            navRow(icon: "lightbulb", title: "ナレッジ", badge: "312", isActive: false)
            navRow(icon: "archivebox", title: "アーカイブ", badge: nil, isActive: false)
        }
        .padding(.vertical, 4)
    }

    // MARK: - DEALS Section

    private var dealsSection: some View {
        VStack(spacing: 0) {
            sectionHeader(title: "DEALS")
            VStack(spacing: 1) {
                channelRow(name: "投資検討", unread: nil)
                channelRow(name: "PMI", unread: 4)
                channelRow(name: "DDレビュー", unread: 12)
                channelRow(name: "経営会議", unread: nil)
            }
        }
    }

    // MARK: - PORTFOLIO Section

    private var portfolioSection: some View {
        VStack(spacing: 0) {
            sectionHeader(title: "PORTFOLIO")
            VStack(spacing: 1) {
                // A社 - active with LIVE badge
                portfolioActiveRow
                channelRow(name: "B社", unread: nil)
                channelRow(name: "C社", unread: nil, muted: true)
                channelRow(name: "D社", unread: 1)
            }
        }
    }

    private var portfolioActiveRow: some View {
        HStack(spacing: 6) {
            Text("#")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(XT.C.navText)
                .frame(width: 14)
            Text("A社")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
            // LIVE badge
            HStack(spacing: 3) {
                PulseDot(color: XT.C.live, size: 5)
                Text("LIVE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(XT.C.live)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(XT.C.live.opacity(0.12))
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#4F46E5").opacity(0.35), Color(hex: "#6366F1").opacity(0.20)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
        )
        .padding(.horizontal, 6)
    }

    // MARK: - DM Section

    private var dmSection: some View {
        VStack(spacing: 0) {
            sectionHeader(title: "DIRECT MESSAGES")
            VStack(spacing: 1) {
                dmRow(name: "Priya Nair",   initials: "PN", statusColor: Color(hex: "#22A06B"))
                dmRow(name: "Michael Chen", initials: "MC", statusColor: Color(hex: "#22A06B"))
                dmRow(name: "山田 有紀",    initials: "山",  statusColor: Color(hex: "#EF4444"))
                dmRow(name: "Daniel Kim",   initials: "DK", statusColor: Color(hex: "#6B7280"))
                // XTRUST AI chat entry
                Button(action: onShowChat) {
                    HStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: "#1F2937"), Color(hex: "#0F172A")],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 20, height: 20)
                            Image(systemName: "sparkles")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        Text("XTRUST AI")
                            .font(.system(size: 13, weight: isShowingChat ? .semibold : .regular))
                            .foregroundStyle(isShowingChat ? XT.C.navText : XT.C.navTextDim)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isShowingChat ? XT.C.navActive : Color.clear)
                    )
                    .padding(.horizontal, 6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - User Strip

    private var userStrip: some View {
        HStack(spacing: 8) {
            // Avatar
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#6366F1"), Color(hex: "#4338CA")],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 30, height: 30)
                Text("佐")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("佐藤 美咲")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(XT.C.navText)
                Text("Active · Partner")
                    .font(.system(size: 11))
                    .foregroundStyle(XT.C.navTextDim)
            }
            Spacer()
            Button(action: onLogout) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 12))
                    .foregroundStyle(XT.C.navTextMute)
            }
            .buttonStyle(.plain)
            .help("退出")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.18))
    }

    // MARK: - Helpers

    private var sidebarDivider: some View {
        Divider()
            .background(XT.C.navDivider)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
    }

    private func sectionHeader(title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(XT.C.navTextMute)
            Spacer()
            Image(systemName: "chevron.down")
                .font(.system(size: 9))
                .foregroundStyle(XT.C.navTextMute)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    private func navRow(
        icon: String,
        title: String,
        badge: String?,
        badgeRed: Bool = false,
        liveBadge: Bool = false,
        isActive: Bool,
        isExpandable: Bool = false,
        isExpanded: Bool = false,
        onToggle: (() -> Void)? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        Button(action: { action?() ?? onToggle?() }) {
            HStack(spacing: 6) {
                if isExpandable {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(XT.C.navTextMute)
                        .frame(width: 12)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 13))
                        .foregroundStyle(isActive ? XT.C.navText : XT.C.navTextDim)
                        .frame(width: 16)
                }
                if isExpandable {
                    Image(systemName: icon)
                        .font(.system(size: 13))
                        .foregroundStyle(isActive ? XT.C.navText : XT.C.navTextDim)
                }
                Text(title)
                    .font(.system(size: 13.5, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? XT.C.navText : XT.C.navTextDim)
                Spacer()
                if liveBadge {
                    HStack(spacing: 3) {
                        PulseDot(color: XT.C.live, size: 5)
                        Text("LIVE")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(XT.C.live)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(XT.C.live.opacity(0.12))
                    )
                } else if let badge = badge {
                    Text(badge)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(badgeRed ? .white : XT.C.navTextDim)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule()
                                .fill(badgeRed ? XT.C.live : XT.C.navHover)
                        )
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? XT.C.navActive : Color.clear)
            )
            .overlay(
                isActive ?
                HStack {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(XT.C.navActiveLine)
                        .frame(width: 2)
                    Spacer()
                }
                : nil
            )
            .padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
    }

    private func channelRow(name: String, unread: Int?, muted: Bool = false) -> some View {
        HStack(spacing: 6) {
            Text("#")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(muted ? XT.C.navTextMute : XT.C.navTextDim)
                .frame(width: 14)
            Text(name)
                .font(.system(size: 13))
                .foregroundStyle(muted ? XT.C.navTextMute : XT.C.navTextDim)
                .strikethrough(muted, color: XT.C.navTextMute)
            Spacer()
            if let unread = unread, unread > 0 {
                Text("\(unread)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(XT.C.navText)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(XT.C.accentIndigo2.opacity(0.5))
                    )
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .padding(.horizontal, 6)
    }

    private func dmRow(name: String, initials: String, statusColor: Color) -> some View {
        HStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(hex: "#2A3550"))
                    .frame(width: 20, height: 20)
                Text(initials.prefix(2).uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(XT.C.navTextDim)
                // Status dot
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                    .offset(x: 2, y: 2)
            }
            Text(name)
                .font(.system(size: 13))
                .foregroundStyle(XT.C.navTextDim)
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .padding(.horizontal, 6)
    }

    // MARK: - Document placeholder

    private var documentPlaceholder: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 32)
            Image(systemName: "doc.richtext")
                .font(.system(size: 32))
                .foregroundStyle(XT.C.navTextMute)
            Text("資料スキャンモード\nは近日公開予定")
                .font(.system(size: 13))
                .foregroundStyle(XT.C.navTextMute)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}

// MARK: - Sidebar Meeting Row

struct SlackSidebarMeetingRow: View {
    let session: CaptureSession
    let minutesStatus: MeetingMinutes.Status?
    let isSelected: Bool
    let isCapturing: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                if isCapturing {
                    PulseDot(color: XT.C.live, size: 6)
                } else {
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 6, height: 6)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(dateLabel)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? XT.C.navText : XT.C.navTextDim)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(timeLabel)
                            .font(.system(size: 10))
                            .foregroundStyle(XT.C.navTextMute)
                        if session.utteranceCount > 0 {
                            Text("· \(session.utteranceCount)件")
                                .font(.system(size: 10))
                                .foregroundStyle(XT.C.navTextMute)
                        }
                    }
                }
                Spacer()
                minutesBadge
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? XT.C.navActive : (isHovered ? XT.C.navHover : Color.clear))
            )
            .padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.easeInOut(duration: 0.08)) { isHovered = h }
        }
    }

    @ViewBuilder
    private var minutesBadge: some View {
        switch minutesStatus {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(XT.C.ok)
        case .pending, .running:
            ProgressView()
                .controlSize(.mini)
                .scaleEffect(0.7)
        case .failed:
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 10))
                .foregroundStyle(XT.C.live)
        case nil:
            EmptyView()
        }
    }

    private var dateLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M/d（E）"
        return f.string(from: session.startedAt)
    }

    private var timeLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "H:mm"
        return f.string(from: session.startedAt)
    }
}

// MARK: - Pulse Dot

struct PulseDot: View {
    let color: Color
    let size: CGFloat
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .opacity(pulsing ? 0.3 : 1.0)
            .animation(
                .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                value: pulsing
            )
            .onAppear { pulsing = true }
    }
}
