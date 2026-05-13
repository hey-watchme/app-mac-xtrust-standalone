import SwiftUI

struct ChatView: View {
    @ObservedObject var appState: AppState
    @State private var inputText: String = ""
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
        HStack(alignment: .bottom, spacing: XT.S.sm) {
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

            Button(action: submitIfPossible) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(canSubmit ? XT.C.accent : XT.C.textTertiary)
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .padding(.bottom, 2)
        }
        .padding(.horizontal, XT.S.xl)
        .padding(.vertical, XT.S.md)
        .background(XT.C.windowBG)
    }

    private var canSubmit: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !appState.isChatLoading
    }

    private func submitIfPossible() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !appState.isChatLoading else { return }
        inputText = ""
        appState.sendChatMessage(text)
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
                Text(message.text)
                    .font(XT.F.body)
                    .foregroundStyle(isUser ? Color.white : XT.C.textPrimary)
                    .textSelection(.enabled)
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
