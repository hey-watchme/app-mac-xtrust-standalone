import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct ChatView: View {
    @ObservedObject var appState: AppState
    @State private var inputText: String = ""
    @State private var pendingImageURL: URL?
    @State private var pendingImageDisplayName: String = ""
    @State private var pendingTextFileURL: URL?
    @State private var pendingTextContent: String?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            chatHeader
            Divider()
            if appState.chatMessages.isEmpty {
                chatEmptyState
            } else {
                chatMessagesList
            }
            Divider()
            chatInputArea
        }
        .background(XT.C.windowBG)
    }

    // MARK: Header

    private var chatHeader: some View {
        HStack {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(XT.C.accent)
            Text("チャット")
                .font(XT.F.sidebarItem)
                .foregroundStyle(XT.C.textPrimary)
            Spacer()
            Text("Gemma 4 E4B · ローカル")
                .font(XT.F.caption)
                .foregroundStyle(XT.C.textTertiary)
        }
        .padding(.horizontal, XT.S.xl)
        .padding(.vertical, XT.S.md)
    }

    // MARK: Empty State

    private var chatEmptyState: some View {
        VStack(spacing: XT.S.lg) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 40))
                .foregroundStyle(XT.C.textTertiary)
                .symbolRenderingMode(.hierarchical)
            Text("ローカル LLM に何でも聞いてください")
                .font(XT.F.body)
                .foregroundStyle(XT.C.textSecondary)
                .multilineTextAlignment(.center)
            VStack(spacing: XT.S.xxs) {
                Label("画像・PDF（PNG / JPEG / WebP / PDF 先頭ページ）", systemImage: "photo")
                Label("テキストファイル（.txt / .md / .csv / コード等）", systemImage: "doc.text")
            }
            .font(XT.F.caption)
            .foregroundStyle(XT.C.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Messages

    private var chatMessagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: XT.S.md) {
                    ForEach(appState.chatMessages) { message in
                        ChatBubble(message: message)
                            .id(message.id)
                    }
                    if appState.isChatLoading {
                        ChatTypingIndicator()
                            .id("typing")
                    }
                }
                .padding(.horizontal, XT.S.xl)
                .padding(.vertical, XT.S.lg)
            }
            .onChange(of: appState.chatMessages.count) {
                withAnimation {
                    if let last = appState.chatMessages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: appState.isChatLoading) { _, loading in
                if loading {
                    withAnimation { proxy.scrollTo("typing", anchor: .bottom) }
                }
            }
        }
    }

    // MARK: Input

    private var chatInputArea: some View {
        VStack(spacing: XT.S.sm) {
            if pendingImageURL != nil || pendingTextFileURL != nil {
                pendingAttachmentStrip
            }
            HStack(alignment: .bottom, spacing: XT.S.sm) {
                textFileButton
                imageAttachButton
                TextField("メッセージを入力…", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(XT.F.body)
                    .lineLimit(1...6)
                    .focused($isInputFocused)
                    .onSubmit { submitIfPossible() }
                    .padding(.horizontal, XT.S.md)
                    .padding(.vertical, XT.S.sm)
                    .background(XT.C.cardBG)
                    .clipShape(RoundedRectangle(cornerRadius: XT.R.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: XT.R.md)
                            .stroke(XT.C.divider, lineWidth: 1)
                    )
                sendButton
            }
        }
        .padding(.horizontal, XT.S.xl)
        .padding(.vertical, XT.S.md)
        .background(XT.C.windowBG)
    }

    private var pendingAttachmentStrip: some View {
        HStack(spacing: XT.S.sm) {
            if let imageURL = pendingImageURL {
                AttachmentChip(
                    thumbnail: NSImage(contentsOf: imageURL),
                    name: pendingImageDisplayName,
                    onRemove: {
                        pendingImageURL = nil
                        pendingImageDisplayName = ""
                    }
                )
            }
            if let textURL = pendingTextFileURL {
                AttachmentChip(
                    iconName: "doc.text",
                    name: textURL.lastPathComponent,
                    onRemove: {
                        pendingTextFileURL = nil
                        pendingTextContent = nil
                    }
                )
            }
            Spacer()
        }
    }

    private var textFileButton: some View {
        Button(action: openTextFilePicker) {
            Image(systemName: pendingTextFileURL != nil ? "doc.text.fill" : "doc.text")
                .font(.system(size: 17))
                .foregroundStyle(pendingTextFileURL != nil ? XT.C.accent : XT.C.textTertiary)
        }
        .buttonStyle(.plain)
        .disabled(appState.isChatLoading)
        .padding(.bottom, 2)
        .help("テキストファイルを添付（.txt / .md / .csv / コード等）")
    }

    private var imageAttachButton: some View {
        Button(action: openImagePicker) {
            Image(systemName: pendingImageURL != nil ? "photo.fill" : "photo")
                .font(.system(size: 17))
                .foregroundStyle(pendingImageURL != nil ? XT.C.accent : XT.C.textTertiary)
        }
        .buttonStyle(.plain)
        .disabled(appState.isChatLoading)
        .padding(.bottom, 2)
        .help("画像・PDF を添付（PNG / JPEG / WebP / PDF）")
    }

    private var sendButton: some View {
        Button(action: submitIfPossible) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(canSubmit ? XT.C.accent : XT.C.textTertiary)
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
        .padding(.bottom, 2)
    }

    // MARK: Actions

    private var canSubmit: Bool {
        let hasText = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (hasText || pendingImageURL != nil || pendingTextFileURL != nil) && !appState.isChatLoading
    }

    private func submitIfPossible() {
        guard canSubmit else { return }
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let imagePath = pendingImageURL?.path(percentEncoded: false)
        let fileName = pendingTextFileURL?.lastPathComponent
        let textContent = pendingTextContent

        inputText = ""
        pendingImageURL = nil
        pendingImageDisplayName = ""
        pendingTextFileURL = nil
        pendingTextContent = nil

        let finalText: String
        if text.isEmpty {
            finalText = imagePath != nil ? "この画像について説明してください。" : "このファイルの内容を要約してください。"
        } else {
            finalText = text
        }

        appState.sendChatMessage(
            finalText,
            imagePath: imagePath,
            attachedFileName: fileName,
            attachedTextContent: textContent
        )
    }

    private func openImagePicker() {
        let panel = NSOpenPanel()
        panel.title = "画像または PDF を選択"
        panel.allowedContentTypes = [.png, .jpeg, .webP, .pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "PNG / JPEG / WebP / PDF（先頭ページを画像化）"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        if url.pathExtension.lowercased() == "pdf" {
            guard let rendered = renderPDFFirstPage(url: url) else {
                appState.errorMessage = "PDF の先頭ページを画像化できませんでした: \(url.lastPathComponent)"
                return
            }
            pendingImageURL = rendered
            pendingImageDisplayName = url.lastPathComponent
        } else {
            pendingImageURL = url
            pendingImageDisplayName = url.lastPathComponent
        }
    }

    private func openTextFilePicker() {
        let panel = NSOpenPanel()
        panel.title = "テキストファイルを選択"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = ".txt / .md / .csv / コードファイル等（UTF-8）"
        panel.allowedContentTypes = []
        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            appState.errorMessage = "ファイルをテキストとして読み込めませんでした: \(url.lastPathComponent)"
            return
        }
        pendingTextFileURL = url
        pendingTextContent = content
    }

    private func renderPDFFirstPage(url: URL) -> URL? {
        guard let pdf = PDFDocument(url: url),
              let page = pdf.page(at: 0) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            NSColor.white.setFill()
            NSBezierPath(rect: rect).fill()
            ctx.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: ctx)
            return true
        }
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).png")
        try? png.write(to: tmp)
        return tmp
    }
}

// MARK: - Attachment Chip

private struct AttachmentChip: View {
    var thumbnail: NSImage? = nil
    var iconName: String? = nil
    let name: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: XT.S.xs) {
            if let nsImage = thumbnail {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: XT.R.sm))
            } else if let icon = iconName {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(XT.C.accent)
                    .frame(width: 40, height: 40)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(XT.F.caption)
                    .foregroundStyle(XT.C.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 120)
                Button("削除", action: onRemove)
                    .buttonStyle(.plain)
                    .font(XT.F.caption)
                    .foregroundStyle(XT.C.textTertiary)
            }
        }
        .padding(XT.S.xs)
        .background(XT.C.cardBG)
        .clipShape(RoundedRectangle(cornerRadius: XT.R.md))
        .overlay(
            RoundedRectangle(cornerRadius: XT.R.md)
                .stroke(XT.C.divider, lineWidth: 1)
        )
    }
}

// MARK: - Chat Bubble

private struct ChatBubble: View {
    let message: ChatMessage

    var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: XT.S.xxs) {
                VStack(alignment: isUser ? .trailing : .leading, spacing: XT.S.xs) {
                    if let imagePath = message.imagePath,
                       let nsImage = NSImage(contentsOfFile: imagePath) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 240, maxHeight: 180)
                            .clipShape(RoundedRectangle(cornerRadius: XT.R.md))
                    }
                    if let fileName = message.attachedFileName {
                        Label(fileName, systemImage: "doc.text")
                            .font(XT.F.caption)
                            .foregroundStyle(isUser ? Color.white.opacity(0.85) : XT.C.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if !message.text.isEmpty {
                        Text(message.text)
                            .font(XT.F.body)
                            .foregroundStyle(isUser ? Color.white : XT.C.textPrimary)
                            .textSelection(.enabled)
                    }
                }
                .padding(.horizontal, XT.S.md)
                .padding(.vertical, XT.S.sm)
                .background(
                    RoundedRectangle(cornerRadius: XT.R.lg)
                        .fill(isUser ? XT.C.accent : XT.C.cardBG)
                )

                Text(message.createdAt.formatted(.dateTime.hour().minute()))
                    .font(XT.F.caption)
                    .foregroundStyle(XT.C.textTertiary)
            }

            if !isUser { Spacer(minLength: 60) }
        }
    }
}

// MARK: - Typing Indicator

private struct ChatTypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            HStack(spacing: 5) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(XT.C.textTertiary)
                        .frame(width: 7, height: 7)
                        .scaleEffect(animating ? 1.3 : 0.8)
                        .animation(
                            .easeInOut(duration: 0.5)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.16),
                            value: animating
                        )
                }
            }
            .padding(.horizontal, XT.S.md)
            .padding(.vertical, XT.S.sm)
            .background(
                RoundedRectangle(cornerRadius: XT.R.lg)
                    .fill(XT.C.cardBG)
            )

            Spacer(minLength: 60)
        }
        .onAppear { animating = true }
    }
}
