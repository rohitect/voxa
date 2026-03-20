import SwiftUI

struct AgentPanelContent: View {
    let state: AgentPanelState
    let onDismiss: () -> Void
    let onNewSession: () -> Void

    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    private var isBusy: Bool {
        state.isListening || state.isProcessing || state.isStreaming
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            chatArea
            inputBar
        }
        .frame(minWidth: 320, minHeight: 260)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Text("Voxa")
                .font(.subheadline.weight(.semibold))

            Spacer()

            Button(action: onNewSession) {
                Image(systemName: "plus.message")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("New Session")

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
            .help("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Chat Area

    private var chatArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let session = state.session {
                        let messages = session.displayMessages
                        ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                            CompactBubble(
                                message: message,
                                isFirstInGroup: isFirstInGroup(index, messages: messages)
                            )
                            .id(message.id)
                        }
                    }

                    if state.isStreaming, !state.streamingText.isEmpty {
                        streamingBubble.id("streaming")
                    }

                    // Tool confirmation banner
                    if let registry = state.toolRegistry,
                       let confirmation = registry.pendingConfirmation {
                        CompactConfirmationBanner(
                            request: confirmation,
                            onApprove: { registry.approveConfirmation() },
                            onDeny: { registry.denyConfirmation() }
                        )
                        .id("confirmation")
                    }

                    if state.isListening {
                        statusBubble {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(.red)
                                    .frame(width: 8, height: 8)
                                    .modifier(PulseModifier())
                                Text("Listening...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .id("status")
                    } else if state.isProcessing {
                        statusBubble {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.mini)
                                if let toolName = state.currentToolName {
                                    Label(toolDisplayName(toolName), systemImage: "gearshape.fill")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                } else {
                                    Text("Thinking...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .id("status")
                        .animation(.easeInOut(duration: 0.2), value: state.currentToolName)
                    }

                    if !hasContent && !isBusy {
                        compactEmptyState.id("empty")
                    }

                    Color.clear.frame(height: 1).id("bottomAnchor")
                }
                .padding(12)
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    proxy.scrollTo("bottomAnchor", anchor: .bottom)
                }
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

    private var streamingBubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            MarkdownView(state.streamingText, fontSize: 12, isUser: false)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            CompactTypingDots()
                .padding(.leading, 12)
        }
        .padding(.vertical, 4)
    }

    private var compactEmptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 24))
                .foregroundStyle(.quaternary)
            Text("Ask anything or hold\nthe hotkey to speak")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($isInputFocused)
                .onSubmit { sendMessage() }
                .disabled(isBusy)
                .font(.subheadline)

            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(canSend ? Color.accentColor : Color.secondary.opacity(0.3))
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

    private func isFirstInGroup(_ index: Int, messages: [DisplayMessage]) -> Bool {
        guard index > 0 else { return true }
        return messages[index].role != messages[index - 1].role
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isBusy else { return }
        inputText = ""
        state.sendMessage?(text)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo("bottomAnchor", anchor: .bottom)
        }
    }

    private func statusBubble<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack {
            content()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func toolDisplayName(_ name: String) -> String {
        name.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}

// MARK: - Compact Message Bubble

private struct CompactBubble: View {
    let message: DisplayMessage
    let isFirstInGroup: Bool
    @State private var isHovered = false
    @State private var showCopied = false
    @State private var showTrace = false

    var body: some View {
        Group {
            if message.role == .user {
                userBubble
            } else {
                assistantBubble
            }
        }
        .sheet(isPresented: $showTrace) {
            if let trace = message.trace {
                TraceInspectorView(trace: trace)
            }
        }
    }

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 48)
            Text(message.content)
                .font(.subheadline)
                .lineSpacing(1)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)
        }
        .padding(.top, isFirstInGroup ? 10 : 3)
        .padding(.bottom, 3)
        .onHover { isHovered = $0 }
        .overlay(alignment: .bottomLeading) {
            compactActionButtons
        }
    }

    private var assistantBubble: some View {
        HStack {
            MarkdownView(message.content, fontSize: 12, isUser: false)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            Spacer(minLength: 32)
        }
        .padding(.top, isFirstInGroup ? 10 : 3)
        .padding(.bottom, 3)
        .onHover { isHovered = $0 }
        .overlay(alignment: .bottomTrailing) {
            compactActionButtons
        }
    }

    private var compactActionButtons: some View {
        HStack(spacing: 2) {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.content, forType: .string)
                showCopied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showCopied = false }
            } label: {
                Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 9))
                    .foregroundStyle(showCopied ? .green : .secondary)
                    .frame(width: 20, height: 20)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)

            if message.trace != nil {
                Button {
                    showTrace = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
            }
        }
        .transition(.opacity)
    }
}

// MARK: - Compact Confirmation Banner

private struct CompactConfirmationBanner: View {
    let request: ToolConfirmationRequest
    let onApprove: () -> Void
    let onDeny: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)

                Text("Confirm: \(request.toolName)")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }

            if !request.arguments.isEmpty && request.arguments != "{}" {
                Text(formattedArguments)
                    .font(.system(size: 10).monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 4))
            }

            HStack(spacing: 8) {
                Button(action: onApprove) {
                    Text("Allow")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)

                Button(action: onDeny) {
                    Text("Deny")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.orange.opacity(0.2), lineWidth: 1)
        )
        .padding(.vertical, 4)
    }

    private var formattedArguments: String {
        guard let data = request.arguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
              let str = String(data: pretty, encoding: .utf8) else {
            return request.arguments
        }
        return str
    }
}

// MARK: - Compact Typing Dots

private struct CompactTypingDots: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 4, height: 4)
                    .offset(y: animating ? -2 : 0)
                    .animation(
                        .easeInOut(duration: 0.35)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.12),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}
