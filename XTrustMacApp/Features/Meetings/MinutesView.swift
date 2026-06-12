import AppCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MinutesView: View {
    let minutes: MeetingMinutes?
    let isGenerating: Bool
    let transcriptMarkdown: String
    let onRetry: () -> Void

    var body: some View {
        XTCard {
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider()
                    .padding(.horizontal, XT.S.md)
                body_
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            XTSectionLabel(text: "議事録")
            Spacer()

            if isRunning {
                HStack(spacing: XT.S.xs) {
                    ProgressView().controlSize(.mini)
                    Text("生成中…")
                        .font(XT.F.caption)
                        .foregroundStyle(XT.C.textSecondary)
                }
            } else if let minutes, minutes.status == .completed {
                HStack(spacing: XT.S.sm) {
                    Button {
                        copyMinutes(minutes)
                    } label: {
                        Label("コピー", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(XTSecondaryButtonStyle())
                    .controlSize(.small)

                    Button {
                        exportMarkdown()
                    } label: {
                        Label("Markdownを書き出し", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(XTSecondaryButtonStyle())
                    .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, XT.S.lg)
        .padding(.top, XT.S.lg)
        .padding(.bottom, XT.S.md)
    }

    // MARK: - Body

    @ViewBuilder
    private var body_: some View {
        if isRunning {
            VStack(alignment: .leading, spacing: XT.S.sm) {
                Text("議事録を生成中…")
                    .font(XT.F.body)
                    .foregroundStyle(XT.C.textSecondary)
                Text("ローカル LLM (Gemma 4) が文字起こしから議事録を作成しています。")
                    .font(XT.F.caption)
                    .foregroundStyle(XT.C.textTertiary)
            }
            .padding(XT.S.lg)
        } else if let minutes, minutes.status == .completed, let text = minutes.markdownText {
            VStack(alignment: .leading, spacing: XT.S.md) {
                Text(text)
                    .font(XT.F.body)
                    .foregroundStyle(XT.C.textPrimary)
                    .textSelection(.enabled)
                    .lineSpacing(4)

                if let modelIdentifier = minutes.modelIdentifier {
                    Text("モデル: \(modelIdentifier)")
                        .font(XT.F.caption)
                        .foregroundStyle(XT.C.textTertiary)
                }
            }
            .padding(XT.S.lg)
        } else if let minutes, minutes.status == .failed {
            VStack(alignment: .leading, spacing: XT.S.md) {
                HStack(spacing: XT.S.xs) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(XT.C.destructive)
                    Text("議事録の生成に失敗しました: \(minutes.errorMessage ?? "原因不明")")
                        .font(XT.F.caption)
                        .foregroundStyle(XT.C.destructive)
                        .textSelection(.enabled)
                }

                Button(action: onRetry) {
                    Label("再試行", systemImage: "arrow.clockwise")
                }
                .buttonStyle(XTSecondaryButtonStyle())
            }
            .padding(XT.S.lg)
        } else {
            VStack(alignment: .leading, spacing: XT.S.md) {
                Text("議事録はまだありません。")
                    .font(XT.F.body)
                    .foregroundStyle(XT.C.textTertiary)

                Button(action: onRetry) {
                    Label("議事録を作成", systemImage: "sparkles")
                }
                .buttonStyle(XTSecondaryButtonStyle())
            }
            .padding(XT.S.lg)
        }
    }

    private var isRunning: Bool {
        if isGenerating { return true }
        switch minutes?.status {
        case .pending, .running: return true
        default: return false
        }
    }

    // MARK: - Actions

    private func copyMinutes(_ minutes: MeetingMinutes) {
        guard let text = minutes.markdownText else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func exportMarkdown() {
        let panel = NSSavePanel()
        panel.title = "議事録を書き出し"
        if let markdownType = UTType(filenameExtension: "md") {
            panel.allowedContentTypes = [markdownType]
        }
        panel.nameFieldStringValue = "meeting-minutes.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? transcriptMarkdown.write(to: url, atomically: true, encoding: .utf8)
    }
}
