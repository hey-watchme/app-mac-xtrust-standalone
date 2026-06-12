import AppCore
import SwiftUI

// MARK: - Logo

/// XTrust wordmark.
/// Swap `Image("XTrustLogo")` once the SVG asset is added to the Xcode asset catalog.
struct XTrustLogoView: View {
    var color: Color = Color(nsColor: .labelColor)

    var body: some View {
        HStack(spacing: 0) {
            Text("X")
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(color)
            Text("TRUST")
                .font(.system(size: 15, weight: .light))
                .tracking(1.8)
                .foregroundStyle(color)
        }
    }
}

// MARK: - Capture Session Status Badge

struct XTCaptureStatusBadge: View {
    let status: CaptureSession.Status

    var body: some View {
        Label(label, systemImage: icon)
            .font(XT.F.caption)
            .foregroundStyle(fg)
            .padding(.horizontal, XT.S.xs + 2)
            .padding(.vertical, XT.S.xxs + 1)
            .background(bg)
            .clipShape(Capsule())
    }

    private var label: String {
        switch status {
        case .open:      return "準備中"
        case .recording: return "録音中"
        case .closed:    return "終了"
        }
    }

    private var icon: String {
        switch status {
        case .open:      return "circle"
        case .recording: return "record.circle.fill"
        case .closed:    return "archivebox.fill"
        }
    }

    private var fg: Color {
        switch status {
        case .open:      return XT.C.textTertiary
        case .recording: return XT.C.recording
        case .closed:    return XT.C.textTertiary
        }
    }

    private var bg: Color {
        switch status {
        case .open:      return XT.C.textTertiary.opacity(0.08)
        case .recording: return XT.C.recordingBG
        case .closed:    return XT.C.textTertiary.opacity(0.06)
        }
    }
}

// MARK: - Meeting Minutes Badge

struct XTMinutesBadge: View {
    let status: MeetingMinutes.Status?

    var body: some View {
        switch status {
        case nil:
            EmptyView()
        case .pending, .running:
            badge(text: "議事録作成中", icon: "arrow.triangle.2.circlepath",
                  fg: XT.C.accent, bg: XT.C.accent.opacity(0.09))
        case .completed:
            badge(text: "議事録", icon: "checkmark.circle.fill",
                  fg: XT.C.success, bg: XT.C.successBG)
        case .failed:
            badge(text: "議事録失敗", icon: "exclamationmark.circle",
                  fg: XT.C.destructive, bg: XT.C.recordingBG)
        }
    }

    private func badge(text: String, icon: String, fg: Color, bg: Color) -> some View {
        Label(text, systemImage: icon)
            .font(XT.F.caption)
            .foregroundStyle(fg)
            .padding(.horizontal, XT.S.xs + 2)
            .padding(.vertical, XT.S.xxs + 1)
            .background(bg)
            .clipShape(Capsule())
    }
}

// MARK: - Pulsing Recording Dot

struct RecordingDot: View {
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(XT.C.recording)
            .frame(width: 8, height: 8)
            .scaleEffect(pulsing ? 1.35 : 1.0)
            .opacity(pulsing ? 0.55 : 1.0)
            .animation(
                .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                value: pulsing
            )
            .onAppear { pulsing = true }
    }
}

// MARK: - Audio Level Meter

struct AudioLevelMeter: View {
    let level: Float

    // Static per-bar sensitivity offsets so bars move at slightly different heights
    private let offsets: [Double] = [0.38, 0.55, 0.75, 0.90, 1.00, 0.88, 0.95, 0.70, 0.50, 0.60, 0.32]

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<offsets.count, id: \.self) { i in
                Capsule()
                    .fill(XT.C.recording.opacity(0.82))
                    .frame(width: 3, height: barHeight(for: i))
                    .animation(.linear(duration: 0.07), value: level)
            }
        }
        .frame(height: 24)
    }

    private func barHeight(for index: Int) -> CGFloat {
        let minH: CGFloat = 3
        let maxH: CGFloat = 24
        let l = CGFloat(max(0, min(1, level))) * CGFloat(offsets[index])
        return minH + (maxH - minH) * l
    }
}

// MARK: - Card Container

struct XTCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .background(XT.C.cardBG)
        .clipShape(RoundedRectangle(cornerRadius: XT.Layout.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: XT.Layout.cardRadius)
                .strokeBorder(XT.C.divider, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.035), radius: 6, x: 0, y: 2)
    }
}

// MARK: - Section Label

struct XTSectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(XT.F.sectionLabel)
            .foregroundStyle(XT.C.textTertiary)
            .tracking(0.7)
    }
}

// MARK: - Button Styles

struct XTPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(XT.F.body)
            .padding(.horizontal, XT.S.md)
            .padding(.vertical, XT.S.xs + 2)
            .background(configuration.isPressed ? XT.C.accent.opacity(0.78) : XT.C.accent)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: XT.R.sm))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct XTSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(XT.F.body)
            .padding(.horizontal, XT.S.md)
            .padding(.vertical, XT.S.xs + 2)
            .background(configuration.isPressed ? XT.C.pressedBG : XT.C.hoveredBG)
            .foregroundStyle(XT.C.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: XT.R.sm))
            .overlay(
                RoundedRectangle(cornerRadius: XT.R.sm)
                    .strokeBorder(XT.C.divider, lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct XTDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(XT.F.body)
            .padding(.horizontal, XT.S.md)
            .padding(.vertical, XT.S.xs + 2)
            .background(configuration.isPressed ? XT.C.recording.opacity(0.75) : XT.C.recording)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: XT.R.sm))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct XTIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(XT.S.xs + 2)
            .background(configuration.isPressed ? XT.C.pressedBG : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: XT.R.sm))
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Sidebar Row Button Style

struct XTSidebarRowStyle: ButtonStyle {
    let isSelected: Bool
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: XT.R.sm)
                    .fill(rowFill(pressed: configuration.isPressed))
            )
    }

    private func rowFill(pressed: Bool) -> Color {
        if isSelected { return XT.C.selectedBG }
        if pressed    { return XT.C.pressedBG }
        if isHovered  { return XT.C.hoveredBG }
        return .clear
    }
}
