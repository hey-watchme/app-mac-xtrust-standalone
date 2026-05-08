import AppKit
import SwiftUI

struct CopyableDetailRow: View {
    let title: String
    let value: String
    var isMonospaced: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)

            Text(value)
                .font(isMonospaced ? .system(.body, design: .monospaced) : .body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
            }
            .buttonStyle(.borderless)
        }
    }
}
