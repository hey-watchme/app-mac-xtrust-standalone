import AppCore
import SwiftUI

// Finalized utterances plus a trailing volatile (gray, italic) line.
// Auto-scrolls to the bottom as content arrives.
struct LiveTranscriptView: View {
    let utterances: [Utterance]
    let volatileText: String

    private static let volatileLineID = "volatile-line"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: XT.S.sm) {
                    ForEach(utterances) { utterance in
                        TranscriptLineView(utterance: utterance)
                            .id(utterance.id)
                    }

                    if !volatileText.isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: XT.S.lg) {
                            Text("…")
                                .font(XT.F.mono)
                                .foregroundStyle(XT.C.textTertiary)
                                .frame(width: 64, alignment: .trailing)
                            Text(volatileText)
                                .font(XT.F.body)
                                .italic()
                                .foregroundStyle(XT.C.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(Self.volatileLineID)
                }
                .padding(.horizontal, XT.Layout.contentPadding)
                .padding(.vertical, XT.S.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: utterances.count) {
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(Self.volatileLineID, anchor: .bottom)
                }
            }
            .onChange(of: volatileText) {
                proxy.scrollTo(Self.volatileLineID, anchor: .bottom)
            }
        }
    }
}

// Single finalized transcript line: [HH:mm:ss] text.
struct TranscriptLineView: View {
    let utterance: Utterance

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: XT.S.lg) {
            Text(MeetingStore.timestamp(fromSeconds: utterance.startOffsetSeconds))
                .font(XT.F.mono)
                .foregroundStyle(XT.C.textTertiary)
                .frame(width: 64, alignment: .trailing)
                .layoutPriority(1)

            Text(utterance.text)
                .font(XT.F.body)
                .foregroundStyle(XT.C.textPrimary)
                .textSelection(.enabled)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}
