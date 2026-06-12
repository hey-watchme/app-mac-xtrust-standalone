import AppCore
import SwiftUI

struct MeetingControlsBar: View {
    let captureState: CaptureEngineState
    let onStart: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: XT.S.sm) {
            if isCapturing {
                Button(action: onStop) {
                    Label("会議を終了して議事録を作成", systemImage: "stop.fill")
                }
                .buttonStyle(XTDestructiveButtonStyle())
                .disabled(!canStop)
            } else {
                Button(action: onStart) {
                    Label("会議を開始", systemImage: "mic.fill")
                }
                .buttonStyle(XTPrimaryButtonStyle())
            }

            Spacer()

            CaptureStatePill(state: captureState)
        }
        .padding(.horizontal, XT.Layout.contentPadding)
        .padding(.vertical, XT.S.md)
    }

    private var isCapturing: Bool {
        switch captureState {
        case .preparing, .listening, .stopping:
            return true
        case .idle, .stopped, .failed:
            return false
        }
    }

    // Stop is only valid while listening; it stays disabled during
    // preparation and the stop sequence itself.
    private var canStop: Bool {
        if case .listening = captureState { return true }
        return false
    }
}
