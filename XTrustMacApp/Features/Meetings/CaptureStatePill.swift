import AppCore
import SwiftUI

// Surfaces every capture engine state so recording start never looks frozen.
struct CaptureStatePill: View {
    let state: CaptureEngineState

    var body: some View {
        HStack(spacing: XT.S.xs + 2) {
            indicator
            Text(label)
                .font(XT.F.caption)
                .foregroundStyle(foreground)
        }
        .padding(.horizontal, XT.S.sm)
        .padding(.vertical, XT.S.xxs + 1)
        .background(background)
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var indicator: some View {
        switch state {
        case .idle, .stopped:
            Image(systemName: "circle")
                .font(.system(size: 9))
                .foregroundStyle(XT.C.textTertiary)
        case .preparing, .stopping:
            ProgressView()
                .controlSize(.mini)
        case .listening:
            RecordingDot()
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(XT.C.destructive)
        }
    }

    private var label: String {
        switch state {
        case .idle:
            return "待機中"
        case let .preparing(step):
            switch step {
            case .checkingPermission:
                return "マイク権限を確認中…"
            case .checkingAssets:
                return "音声認識アセットを確認中…"
            case let .downloadingAssets(progress):
                if let progress {
                    return "アセットをダウンロード中… \(Int(progress * 100))%"
                }
                return "アセットをダウンロード中…"
            case .startingAudio:
                return "開始しています…"
            }
        case .listening:
            return "録音中"
        case .stopping:
            return "停止処理中…"
        case .stopped:
            return "停止しました"
        case .failed:
            return "エラー"
        }
    }

    private var foreground: Color {
        switch state {
        case .listening: return XT.C.recording
        case .failed: return XT.C.destructive
        case .preparing, .stopping: return XT.C.textSecondary
        case .idle, .stopped: return XT.C.textTertiary
        }
    }

    private var background: Color {
        switch state {
        case .listening, .failed: return XT.C.recordingBG
        case .preparing, .stopping: return XT.C.accent.opacity(0.08)
        case .idle, .stopped: return XT.C.textTertiary.opacity(0.07)
        }
    }
}
