import SwiftUI

struct AgentPanelContent: View {
    let state: AgentPanelState
    let onDismiss: () -> Void
    let onNewSession: () -> Void

    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    /// Whether the agent is busy (listening, processing, streaming, tool execution).
    private var isBusy: Bool {
        state.isListening || state.isProcessing || state.isStreaming
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            chatArea
            Divider()
            inputBar
        }
        .frame(minWidth: 320, minHeight: 260)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            Image(systemName: "brain.head.profile")
                .foregroundStyle(.secondary)

            Text("Agent")
                .font(.headline)

            Spacer()

            Button(action: onNewSession) {
                Image(systemName: "plus.message")
                    .font(.system(size: 13))
            }
            .buttonStyle(.borderless)
            .help("New Session")

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Chat Area

    private var chatArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    // Message history
                    if let session = state.session {
                        ForEach(session.displayMessages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }

                    // Streaming assistant response (live)
                    if state.isStreaming, !state.streamingText.isEmpty {
                        HStack {
                            Text(state.streamingText)
                                .font(.body)
                                .textSelection(.enabled)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                            Spacer(minLength: 40)
                        }
                        .id("streaming")
                    }

                    // Status indicator (inline at bottom of messages)
                    if state.isListening {
                        statusBubble {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(.red)
                                    .frame(width: 10, height: 10)
                                    .modifier(PulseModifier())
                                Text("Listening...")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .id("status")
                    } else if state.isProcessing {
                        statusBubble {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                if let toolName = state.currentToolName {
                                    Label(toolDisplayName(toolName), systemImage: "gearshape.fill")
                                        .font(.callout)
                                        .foregroundStyle(.orange)
                                } else {
                                    Text("Thinking...")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .id("status")
                        .animation(.easeInOut(duration: 0.2), value: state.currentToolName)
                    }

                    // Empty state
                    if !hasContent && !isBusy {
                        VStack(spacing: 8) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 28))
                                .foregroundStyle(.tertiary)
                            Text("Type a message or hold the hotkey to speak")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                        .id("empty")
                    }
                }
                .padding(14)
            }
            .onChange(of: state.session?.displayMessages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: state.streamingText) { _, _ in
                if state.isStreaming {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo("streaming", anchor: .bottom)
                    }
                }
            }
            .onChange(of: state.isListening) { _, isListening in
                if isListening { scrollToBottom(proxy) }
            }
            .onChange(of: state.isProcessing) { _, isProcessing in
                if isProcessing { scrollToBottom(proxy) }
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Message...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($isInputFocused)
                .onSubmit {
                    sendMessage()
                }
                .disabled(isBusy)

            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            .disabled(!canSend)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isBusy
    }

    private var hasContent: Bool {
        if let session = state.session, !session.displayMessages.isEmpty { return true }
        if state.statusMessage != nil { return true }
        return false
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isBusy else { return }
        inputText = ""
        state.sendMessage?(text)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        let target: String
        if state.isListening || state.isProcessing {
            target = "status"
        } else if let last = state.session?.displayMessages.last {
            target = last.id.uuidString
        } else {
            return
        }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(target, anchor: .bottom)
        }
    }

    private func statusBubble<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack {
            content()
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
            Spacer()
        }
    }

    private func toolDisplayName(_ name: String) -> String {
        name.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}

// MARK: - Message Bubble

private struct MessageBubble: View {
    let message: DisplayMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }

            Text(message.content)
                .font(.body)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(backgroundColor, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(message.role == .user ? .white : .primary)

            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }

    private var backgroundColor: Color {
        message.role == .user ? .accentColor : Color(.controlBackgroundColor)
    }
}
