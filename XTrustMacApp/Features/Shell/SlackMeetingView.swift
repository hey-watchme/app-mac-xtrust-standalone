import AppCore
import SwiftUI

// MARK: - Slack-style Meeting Main Content Area

struct SlackMeetingView: View {
    var model: AppModel
    private var store: MeetingStore { model.meetingStore }

    var body: some View {
        VStack(spacing: 0) {
            if let session = store.session {
                meetingHeader(session: session)
                Divider().background(XT.C.line)
                transcriptFeed(session: session)
                Divider().background(XT.C.line)
                composerBar
            } else {
                emptyState
            }
        }
        .background(XT.C.winBg)
    }

    // MARK: - Meeting Header

    private func meetingHeader(session: CaptureSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Breadcrumb + right pills
            HStack(spacing: 0) {
                // Breadcrumb
                HStack(spacing: 4) {
                    Text("# A社")
                        .font(.system(size: 12))
                        .foregroundStyle(XT.C.ink3)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9))
                        .foregroundStyle(XT.C.ink4)
                    Text("ライブ議事録")
                        .font(.system(size: 12))
                        .foregroundStyle(XT.C.ink3)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9))
                        .foregroundStyle(XT.C.ink4)
                    Text(sessionDateLabel(session.startedAt))
                        .font(.system(size: 12))
                        .foregroundStyle(XT.C.ink3)
                }
                Spacer()
                // Right pills
                HStack(spacing: 8) {
                    headerPill(icon: "pin", text: "4")
                    headerPill(icon: "person.2", text: "8")
                }
            }

            // Title row
            HStack(alignment: .center, spacing: 10) {
                Text(meetingTitle(from: session.startedAt))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(XT.C.ink)
                    .lineLimit(1)

                // REC badge with elapsed time
                if store.isCapturing {
                    recBadge
                }

                Spacer()

                // Stacked avatars (placeholder)
                stackedAvatars
            }

            // Status pills row
            HStack(spacing: 6) {
                if store.isCapturing {
                    statusPill(
                        text: "録音中",
                        icon: "record.circle.fill",
                        fg: XT.C.liveInk,
                        bg: XT.C.liveSoft,
                        border: XT.C.liveLine
                    )
                    statusPill(
                        text: "Live Transcript",
                        icon: "text.bubble",
                        fg: XT.C.accentInk,
                        bg: XT.C.accentSoft,
                        border: XT.C.accentLine
                    )
                    statusPill(
                        text: "AI 解析 ON",
                        icon: "sparkles",
                        fg: XT.C.accentInk,
                        bg: XT.C.accentSoft,
                        border: XT.C.accentLine
                    )
                } else {
                    // Show state pill
                    CaptureStatePill(state: store.captureState)
                }
                statusPill(
                    text: "ローカル処理 · AES-256",
                    icon: "lock.shield.fill",
                    fg: XT.C.okInk,
                    bg: XT.C.okSoft,
                    border: XT.C.ok.opacity(0.3)
                )
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(XT.C.winBg)
    }

    // MARK: - Transcript Feed

    private func transcriptFeed(session: CaptureSession) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if store.isCapturing {
                        // Live mode: show real utterances
                        if store.utterances.isEmpty && store.volatileText.isEmpty {
                            liveWaitingPlaceholder
                        } else {
                            ForEach(store.utterances) { utterance in
                                SlackTranscriptRow(
                                    utterance: utterance,
                                    sessionStart: session.startedAt
                                )
                                .id(utterance.id)
                            }
                            if !store.volatileText.isEmpty {
                                liveTypingRow
                                    .id("volatile-anchor")
                            }
                        }
                    } else {
                        // Closed session: show real utterances or demo data if none
                        if store.utterances.isEmpty {
                            ForEach(DemoTranscript.entries) { entry in
                                DemoTranscriptRow(entry: entry)
                            }
                        } else {
                            ForEach(store.utterances) { utterance in
                                SlackTranscriptRow(
                                    utterance: utterance,
                                    sessionStart: session.startedAt
                                )
                                .id(utterance.id)
                            }
                        }
                    }

                    // Spacer at end for compositor bar breathing room
                    Color.clear.frame(height: 8).id("bottom-anchor")
                }
            }
            .onChange(of: store.utterances.count) {
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("bottom-anchor", anchor: .bottom)
                }
            }
            .onChange(of: store.volatileText) {
                proxy.scrollTo("volatile-anchor", anchor: .bottom)
            }
        }
    }

    // MARK: - Live Typing Row

    private var liveTypingRow: some View {
        HStack(alignment: .top, spacing: 12) {
            // Generic participant avatar
            genericAvatar(size: 20)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("参加者")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(XT.C.ink3)
                    Text("発言中")
                        .font(.system(size: 11))
                        .foregroundStyle(XT.C.ink4)
                    TypingDotsView()
                }
                if !store.volatileText.isEmpty {
                    Text(store.volatileText)
                        .font(.system(size: 14))
                        .foregroundStyle(XT.C.ink3)
                        .italic()
                        .lineSpacing(4)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    // MARK: - Live Waiting Placeholder

    private var liveWaitingPlaceholder: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                PulseDot(color: XT.C.live, size: 8)
                Text("録音中 — 発話を待機しています")
                    .font(.system(size: 14))
                    .foregroundStyle(XT.C.ink3)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Composer Bar

    private var composerBar: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                // Record card
                recordCard

                Spacer()

                // Mode buttons
                modeButtons
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: [XT.C.panel2, XT.C.winBg],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    private var recordCard: some View {
        HStack(spacing: 10) {
            // Record / Stop button
            recordButton

            // Waveform + caption area
            VStack(alignment: .leading, spacing: 3) {
                if store.isCapturing {
                    HStack(spacing: 6) {
                        // Waveform bars
                        WaveformView(level: store.audioLevel)
                        Spacer()
                    }
                    HStack(spacing: 6) {
                        PulseDot(color: XT.C.live, size: 5)
                        Text("LIVE CAPTION")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(XT.C.live)
                        if !store.volatileText.isEmpty {
                            Text(store.volatileText)
                                .font(.system(size: 12.5))
                                .foregroundStyle(XT.C.ink3)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                } else {
                    Text("会議を開始")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(XT.C.ink3)
                    Text("録音とリアルタイム書き起こしを開始")
                        .font(.system(size: 11))
                        .foregroundStyle(XT.C.ink4)
                }
            }

            if store.isCapturing {
                Spacer(minLength: 8)
                // Elapsed timer
                VStack(alignment: .trailing, spacing: 2) {
                    ElapsedTimerView(startDate: elapsedStartDate)
                        .font(.system(size: 13, design: .monospaced).weight(.semibold))
                        .foregroundStyle(XT.C.ink)
                    Text("word count \(store.utterances.reduce(0) { $0 + $1.text.count / 3 })")
                        .font(.system(size: 10))
                        .foregroundStyle(XT.C.ink4)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(XT.C.line, lineWidth: 0.5)
        )
    }

    private var recordButton: some View {
        Group {
            let isCapturing = store.isCapturing
            let canStop: Bool = {
                if case .listening = store.captureState { return true }
                return false
            }()

            if isCapturing {
                Button(action: { model.stopMeeting() }) {
                    ZStack {
                        Circle()
                            .fill(XT.C.live)
                            .frame(width: 36, height: 36)
                            .shadow(color: XT.C.live.opacity(0.35), radius: 6, x: 0, y: 0)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.white)
                            .frame(width: 12, height: 12)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!canStop)
            } else {
                Button(action: { model.startMeeting() }) {
                    ZStack {
                        Circle()
                            .fill(XT.C.live)
                            .frame(width: 36, height: 36)
                        Image(systemName: "mic.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var modeButtons: some View {
        HStack(spacing: 6) {
            modeButton(title: "日本語", icon: nil, isActive: true)
            modeButton(title: "翻訳", icon: "globe", isActive: false)
            modeButton(title: "AIに質問", icon: "sparkles", isActive: false) {
                model.showChat()
            }
            modeButton(title: "タグ付け", icon: "tag", isActive: false)

            Spacer(minLength: 12)

            Text("自動保存 · ローカル保存")
                .font(.system(size: 11))
                .foregroundStyle(XT.C.ink4)
        }
    }

    private func modeButton(title: String, icon: String?, isActive: Bool, action: (() -> Void)? = nil) -> some View {
        Button(action: action ?? {}) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                }
                Text(title)
                    .font(.system(size: 12))
            }
            .foregroundStyle(isActive ? XT.C.accentInk : XT.C.ink3)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? XT.C.accentSoft : XT.C.panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isActive ? XT.C.accentLine : XT.C.line, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "waveform.badge.microphone")
                    .font(.system(size: 52))
                    .foregroundStyle(XT.C.ink4)
                    .symbolRenderingMode(.hierarchical)
                Text("会議を開始")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(XT.C.ink)
                Text("「+」ボタンまたは録音ボタンを押すと\n録音とリアルタイム書き起こしが始まります。")
                    .font(.system(size: 14))
                    .foregroundStyle(XT.C.ink3)
                    .multilineTextAlignment(.center)

                if let msg = model.errorMessage ?? store.errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(XT.C.warn2)
                        Text(msg)
                            .font(.system(size: 12))
                            .foregroundStyle(XT.C.ink)
                    }
                    .padding(10)
                    .background(XT.C.warnSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            Spacer()
            Divider().background(XT.C.line)
            // Start button in composer bar position
            HStack {
                Button(action: { model.startMeeting() }) {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(XT.C.live)
                                .frame(width: 36, height: 36)
                            Image(systemName: "mic.fill")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        Text("会議を開始")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(XT.C.ink)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(XT.C.line, lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 1)
                }
                .buttonStyle(.plain)
                Spacer()
                CaptureStatePill(state: store.captureState)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(XT.C.panel2)
        }
        .background(XT.C.winBg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func meetingTitle(from date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M月d日（E） H:mm の会議"
        return f.string(from: date)
    }

    private func sessionDateLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func headerPill(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 11))
        }
        .foregroundStyle(XT.C.ink3)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(XT.C.panel)
        .clipShape(Capsule())
    }

    private func statusPill(text: String, icon: String, fg: Color, bg: Color, border: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(text)
                .font(.system(size: 11))
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(bg)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(border, lineWidth: 0.5))
    }

    private var stackedAvatars: some View {
        HStack(spacing: -8) {
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .fill(avatarColors[i % avatarColors.count])
                    .frame(width: 26, height: 26)
                    .overlay(
                        Circle().strokeBorder(.white, lineWidth: 1.5)
                    )
            }
            Text("+4")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(XT.C.ink3)
                .frame(width: 26, height: 26)
                .background(XT.C.panel)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
        }
    }

    private let avatarColors: [Color] = [
        Color(hex: "#6366F1"), Color(hex: "#3B82F6"),
        Color(hex: "#A855F7"), Color(hex: "#EC4899")
    ]

    private var recBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(.white)
                .frame(width: 6, height: 6)
            Text("REC · ")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
            ElapsedTimerView(startDate: elapsedStartDate)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(XT.C.live)
        .clipShape(Capsule())
    }

    private var elapsedStartDate: Date? {
        store.session?.startedAt
    }

    private func genericAvatar(size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#6B7280"), Color(hex: "#4B5563")],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
            Image(systemName: "person.fill")
                .font(.system(size: size * 0.55))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}

// MARK: - Slack Transcript Row (real utterances)

struct SlackTranscriptRow: View {
    let utterance: Utterance
    let sessionStart: Date

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Generic participant avatar
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#6B7280"), Color(hex: "#374151")],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                Image(systemName: "person.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                // Meta row
                HStack(spacing: 6) {
                    Text("参加者")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(XT.C.ink)
                    // Timestamp chip
                    Text(MeetingStore.timestamp(fromSeconds: utterance.startOffsetSeconds))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(XT.C.ink4)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(XT.C.panel)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    // Language badge
                    Text(utterance.locale.prefix(2).uppercased())
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(XT.C.ink3)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(XT.C.panel2)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(XT.C.line, lineWidth: 0.5)
                        )
                }
                // Body text
                Text(utterance.text)
                    .font(.system(size: 14.5))
                    .foregroundStyle(XT.C.ink)
                    .textSelection(.enabled)
                    .lineSpacing(utterance.text.count > 60 ? 6 : 3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }
}

// MARK: - Demo Transcript Row (placeholder for idle/demo view)

struct DemoTranscriptRow: View {
    let entry: DemoTranscriptEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(entry.avatarGradient)
                    .frame(width: 36, height: 36)
                Text(entry.initial)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                // Meta row
                HStack(spacing: 6) {
                    Text(entry.speaker)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(XT.C.ink)
                    if let role = entry.role {
                        Text(role)
                            .font(.system(size: 11))
                            .foregroundStyle(XT.C.ink3)
                    }
                    Text(entry.timestamp)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(XT.C.ink4)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(XT.C.panel)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    Text(entry.language)
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(XT.C.ink3)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(XT.C.panel2)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(XT.C.line, lineWidth: 0.5)
                        )
                    // Tag pills
                    ForEach(entry.tags, id: \.self) { tag in
                        TagPill(tag: tag)
                    }
                }
                // Body
                Text(entry.text)
                    .font(.system(size: 14.5))
                    .foregroundStyle(XT.C.ink)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }
}

// MARK: - Tag Pill

struct TagPill: View {
    let tag: String

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(tagColor)
                .frame(width: 4, height: 4)
            Text(tag)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(tagFg)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(tagBg)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var tagColor: Color {
        switch tag {
        case "決定":  return XT.C.accentIndigo
        case "リスク": return Color(hex: "#9B2A2E")
        case "ToDo":  return XT.C.ok
        case "論点":  return XT.C.warn2
        default:      return XT.C.ink3
        }
    }

    private var tagFg: Color {
        switch tag {
        case "決定":  return XT.C.accentInk
        case "リスク": return Color(hex: "#9B2A2E")
        case "ToDo":  return XT.C.okInk
        case "論点":  return XT.C.warnInk
        default:      return XT.C.ink3
        }
    }

    private var tagBg: Color {
        switch tag {
        case "決定":  return XT.C.accentSoft
        case "リスク": return Color(hex: "#FCEAEA")
        case "ToDo":  return XT.C.okSoft
        case "論点":  return XT.C.warnSoft
        default:      return XT.C.panel
        }
    }
}

// MARK: - Waveform View (80 bars)

struct WaveformView: View {
    let level: Float
    @State private var phase: Double = 0

    private let barCount = 80
    private let redTailCount = 14

    var body: some View {
        HStack(alignment: .center, spacing: 1.5) {
            ForEach(0..<barCount, id: \.self) { i in
                Capsule()
                    .fill(barColor(index: i))
                    .frame(width: 2, height: barHeight(index: i))
                    .animation(.linear(duration: 0.07), value: level)
            }
        }
        .frame(height: 22)
        .onAppear {
            withAnimation(
                .linear(duration: 1.1).repeatForever(autoreverses: false)
            ) {
                phase = 1
            }
        }
    }

    private func barHeight(index: Int) -> CGFloat {
        let minH: CGFloat = 2
        let maxH: CGFloat = 22
        let liveRegion = index >= barCount - redTailCount
        let animOffset = liveRegion
            ? sin(Double(index) * 0.4 + phase * .pi * 2) * 0.5 + 0.5
            : 0.0
        let base = CGFloat(max(0, min(1, level)))
        let waveLevel = liveRegion
            ? max(base, CGFloat(animOffset) * 0.8)
            : base * CGFloat(waveShape(index: index))
        return minH + (maxH - minH) * waveLevel
    }

    private func waveShape(index: Int) -> Double {
        // Natural speech envelope: quieter at edges
        let t = Double(index) / Double(barCount)
        return 0.3 + 0.7 * sin(t * .pi)
    }

    private func barColor(index: Int) -> Color {
        if index >= barCount - redTailCount {
            return XT.C.live.opacity(0.85)
        }
        return XT.C.ink3.opacity(0.5)
    }
}

// MARK: - Typing Dots

struct TypingDotsView: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(XT.C.ink3)
                    .frame(width: 5, height: 5)
                    .opacity(animating ? 0.3 : 1.0)
                    .animation(
                        .easeInOut(duration: 0.4)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.15),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}

// MARK: - Elapsed Timer View

struct ElapsedTimerView: View {
    let startDate: Date?
    @State private var elapsed: TimeInterval = 0
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(formattedElapsed)
            .onReceive(timer) { _ in
                if let start = startDate {
                    elapsed = Date().timeIntervalSince(start)
                }
            }
            .onAppear {
                if let start = startDate {
                    elapsed = Date().timeIntervalSince(start)
                }
            }
    }

    private var formattedElapsed: String {
        let h = Int(elapsed) / 3600
        let m = (Int(elapsed) % 3600) / 60
        let s = Int(elapsed) % 60
        if h > 0 {
            return String(format: "%02d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Demo Transcript Data

struct DemoTranscriptEntry: Identifiable {
    let id = UUID()
    let speaker: String
    let role: String?
    let timestamp: String
    let language: String
    let tags: [String]
    let text: String
    let initial: String
    let avatarGradient: LinearGradient
}

enum DemoTranscript {
    static let entries: [DemoTranscriptEntry] = [
        DemoTranscriptEntry(
            speaker: "鈴木 恒一", role: "Partner",
            timestamp: "14:02:11", language: "JA",
            tags: ["論点"],
            text: "では始めましょう。今日はDDの進捗確認とPMI初期スケッチの共有をお願いします。",
            initial: "鈴", avatarGradient: LinearGradient(colors: [Color(hex: "#3B82F6"), Color(hex: "#1D4ED8")], startPoint: .topLeading, endPoint: .bottomTrailing)
        ),
        DemoTranscriptEntry(
            speaker: "高橋 直人", role: nil,
            timestamp: "14:02:48", language: "JA",
            tags: ["リスク", "論点"],
            text: "営業とCSの役割分担が現状かなり曖昧で、PMI後の統合コストが読みにくい状況です。",
            initial: "高", avatarGradient: LinearGradient(colors: [Color(hex: "#A855F7"), Color(hex: "#7E22CE")], startPoint: .topLeading, endPoint: .bottomTrailing)
        ),
        DemoTranscriptEntry(
            speaker: "Ananya Gupta", role: "Analyst",
            timestamp: "14:03:36", language: "EN",
            tags: ["論点"],
            text: "Quick numbers update: ARR is ¥1.42B, NRR 118%, Top 10 customer concentration at 31%. Solid fundamentals.",
            initial: "AG", avatarGradient: LinearGradient(colors: [Color(hex: "#F43F5E"), Color(hex: "#BE123C")], startPoint: .topLeading, endPoint: .bottomTrailing)
        ),
        DemoTranscriptEntry(
            speaker: "山田 有紀", role: nil,
            timestamp: "14:04:21", language: "JA",
            tags: ["リスク"],
            text: "退職者のアカウントが未削除のまま残っているケースが複数確認されました。情報管理体制の整備が急務です。",
            initial: "山", avatarGradient: LinearGradient(colors: [Color(hex: "#EC4899"), Color(hex: "#BE185D")], startPoint: .topLeading, endPoint: .bottomTrailing)
        ),
        DemoTranscriptEntry(
            speaker: "Priya Nair", role: "Principal",
            timestamp: "14:05:09", language: "EN",
            tags: ["ToDo", "論点"],
            text: "I'll draft the PMI 100-day plan across 3 workstreams: Sales/CS integration, IT systems, and Talent retention.",
            initial: "PN", avatarGradient: LinearGradient(colors: [Color(hex: "#F59E0B"), Color(hex: "#D97706")], startPoint: .topLeading, endPoint: .bottomTrailing)
        ),
        DemoTranscriptEntry(
            speaker: "佐藤 美咲", role: "Managing Partner",
            timestamp: "14:06:02", language: "JA",
            tags: ["リスク", "ToDo"],
            text: "SOの設計と創業メンバーのロックアップ条件について、クロージング前に合意が必要です。IRR感応度の整理もお願いします。",
            initial: "佐", avatarGradient: LinearGradient(colors: [Color(hex: "#6366F1"), Color(hex: "#4338CA")], startPoint: .topLeading, endPoint: .bottomTrailing)
        ),
        DemoTranscriptEntry(
            speaker: "Michael Chen", role: "VP",
            timestamp: "14:07:14", language: "EN",
            tags: ["ToDo"],
            text: "I'll reach out to the existing shareholders this week — targeting alignment by end of next week.",
            initial: "MC", avatarGradient: LinearGradient(colors: [Color(hex: "#14B8A6"), Color(hex: "#0F766E")], startPoint: .topLeading, endPoint: .bottomTrailing)
        ),
        DemoTranscriptEntry(
            speaker: "Daniel Kim", role: nil,
            timestamp: "14:08:30", language: "JA",
            tags: ["論点"],
            text: "IRR感応度の試算です。Bear case 21%、Base case 27.4%、Bull case 33.1%。EXITマルチプル4〜6倍の前提です。",
            initial: "DK", avatarGradient: LinearGradient(colors: [Color(hex: "#10B981"), Color(hex: "#047857")], startPoint: .topLeading, endPoint: .bottomTrailing)
        ),
        DemoTranscriptEntry(
            speaker: "鈴木 恒一", role: "Partner",
            timestamp: "14:09:48", language: "JA",
            tags: ["決定", "ToDo"],
            text: "CFOサーチは早期着手で動きます。今週中にエグゼクティブサーチ2社に声がけします。",
            initial: "鈴", avatarGradient: LinearGradient(colors: [Color(hex: "#3B82F6"), Color(hex: "#1D4ED8")], startPoint: .topLeading, endPoint: .bottomTrailing)
        ),
        DemoTranscriptEntry(
            speaker: "高橋 直人", role: nil,
            timestamp: "14:10:22", language: "JA",
            tags: ["リスク", "ToDo"],
            text: "CTO・VP Engの主要人材依存について、departure シナリオ分析を来週金曜までに出します。",
            initial: "高", avatarGradient: LinearGradient(colors: [Color(hex: "#A855F7"), Color(hex: "#7E22CE")], startPoint: .topLeading, endPoint: .bottomTrailing)
        ),
    ]
}
