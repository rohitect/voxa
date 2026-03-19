import SwiftUI

/// ChatGPT-style chat interface: conversation sidebar on the left, active chat on the right.
struct AgentChatPage: View {
    let appState: AppState

    private var coordinator: AgentCoordinator { appState.agentCoordinator }
    private var store: ConversationStore { coordinator.conversationStore }
    private var panelState: AgentPanelState { AgentPanel.shared.state }

    var body: some View {
        HStack(spacing: 0) {
            ChatSidebar(
                store: store,
                onNew: { coordinator.resetSession() },
                onSelect: { coordinator.switchConversation($0) },
                onDelete: {
                    store.delete($0)
                    panelState.session = coordinator.session
                },
                onDeleteAll: {
                    store.deleteAll()
                    panelState.session = coordinator.session
                }
            )
            .frame(width: 220)

            Divider()

            ChatMainArea(
                coordinator: coordinator,
                panelState: panelState
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            panelState.session = coordinator.session
        }
    }
}

// MARK: - Chat Sidebar

private struct ChatSidebar: View {
    let store: ConversationStore
    let onNew: () -> Void
    let onSelect: (ChatSession) -> Void
    let onDelete: (ChatSession) -> Void
    let onDeleteAll: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            newChatButton
            Divider().padding(.horizontal, 10)
            conversationList
            Spacer(minLength: 0)
            clearAllButton
        }
        .background(Color(.windowBackgroundColor).opacity(0.5))
    }

    private var newChatButton: some View {
        Button(action: onNew) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                Text("New Chat")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var conversationList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                let groups = store.groupedConversations
                ForEach(groups.indices, id: \.self) { index in
                    let group = groups[index]
                    sectionHeader(group.title)
                    ForEach(group.sessions) { conversation in
                        ConversationRow(
                            conversation: conversation,
                            isSelected: conversation.id == store.activeConversation.id,
                            onSelect: { onSelect(conversation) },
                            onDelete: { onDelete(conversation) }
                        )
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var clearAllButton: some View {
        VStack(spacing: 0) {
            Divider().padding(.horizontal, 10)
            Button(role: .destructive, action: onDeleteAll) {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                        .font(.caption)
                    Text("Clear All")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .padding(10)
        }
    }
}

// MARK: - Conversation Row

private struct ConversationRow: View {
    let conversation: ChatSession
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.title)
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(isSelected ? .primary : .secondary)

                    if conversation.hasHistory {
                        Text(relativeDate)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer(minLength: 0)

                if isHovered {
                    Button(action: onDelete) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.borderless)
        .onHover { isHovered = $0 }
    }

    private var rowBackground: Color {
        if isSelected { return Color.accentColor.opacity(0.12) }
        if isHovered { return Color(.controlBackgroundColor).opacity(0.6) }
        return .clear
    }

    private var relativeDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: conversation.createdAt, relativeTo: Date())
    }
}

// MARK: - Chat Main Area

private struct ChatMainArea: View {
    let coordinator: AgentCoordinator
    let panelState: AgentPanelState

    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    private var isBusy: Bool {
        panelState.isListening || panelState.isProcessing || panelState.isStreaming
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            chatArea
            Divider()
            inputBar
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Text(coordinator.session.title)
                .font(.headline)
                .lineLimit(1)

            Spacer()

            HStack(spacing: 6) {
                Circle().fill(.green).frame(width: 6, height: 6)
                Text(coordinator.providerManager.activeProviderName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(coordinator.providerManager.activeModel)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(.controlBackgroundColor), in: Capsule())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Chat Area

    private var chatArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                chatMessages
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
            }
            .onChange(of: panelState.session?.displayMessages.count) { _, _ in
                scrollToEnd(proxy)
            }
            .onChange(of: panelState.streamingText) { _, _ in
                if panelState.isStreaming {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo("streaming", anchor: .bottom)
                    }
                }
            }
            .onChange(of: panelState.isListening) { _, val in
                if val { scrollToEnd(proxy) }
            }
            .onChange(of: panelState.isProcessing) { _, val in
                if val { scrollToEnd(proxy) }
            }
        }
    }

    private var chatMessages: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            // Existing messages
            if let session = panelState.session {
                ForEach(session.displayMessages) { message in
                    ChatBubble(message: message)
                        .id(message.id)
                }
            }

            // Streaming response
            if panelState.isStreaming, !panelState.streamingText.isEmpty {
                streamingBubble.id("streaming")
            }

            // Status indicators
            if panelState.isListening {
                listeningIndicator.id("status")
            } else if panelState.isProcessing {
                processingIndicator.id("status")
            }

            // Empty state
            if !hasMessages && !isBusy {
                emptyState.id("empty")
            }
        }
    }

    private var streamingBubble: some View {
        HStack(alignment: .top, spacing: 10) {
            agentAvatar
            Text(panelState.streamingText)
                .font(.body)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
            Spacer(minLength: 60)
        }
    }

    private var listeningIndicator: some View {
        statusRow {
            Circle().fill(.red).frame(width: 10, height: 10)
                .modifier(PulseModifier())
            Text("Listening...")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var processingIndicator: some View {
        statusRow {
            ProgressView().controlSize(.small)
            if let toolName = panelState.currentToolName {
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

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Send a message...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...8)
                .focused($isInputFocused)
                .onSubmit { sendMessage() }
                .disabled(isBusy)
                .font(.body)

            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(canSend ? Color.accentColor : Color.secondary.opacity(0.3))
            }
            .buttonStyle(.borderless)
            .disabled(!canSend)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 40)
            Image(systemName: "brain.head.profile")
                .font(.system(size: 44))
                .foregroundStyle(.quaternary)
            Text("How can I help?")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            Text("Type a message below or hold the agent hotkey to speak.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            suggestionChips
        }
        .frame(maxWidth: .infinity)
    }

    private var suggestionChips: some View {
        HStack(spacing: 8) {
            chipButton("What's on my clipboard?")
            chipButton("Find files on Desktop")
            chipButton("Take a screenshot")
        }
        .padding(.top, 4)
    }

    // MARK: - Helpers

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isBusy
    }

    private var hasMessages: Bool {
        panelState.session?.displayMessages.isEmpty == false
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isBusy else { return }
        inputText = ""
        coordinator.sendTextMessage(text)
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        let target: String
        if panelState.isListening || panelState.isProcessing {
            target = "status"
        } else if panelState.isStreaming {
            target = "streaming"
        } else if let last = panelState.session?.displayMessages.last {
            target = last.id.uuidString
        } else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(target, anchor: .bottom)
        }
    }

    private func chipButton(_ text: String) -> some View {
        Button {
            inputText = ""
            coordinator.sendTextMessage(text)
        } label: {
            Text(text)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color(.controlBackgroundColor), in: Capsule())
        }
        .buttonStyle(.borderless)
        .disabled(isBusy)
    }

    private func statusRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 10) {
            agentAvatar
            HStack(spacing: 8) { content() }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            Spacer()
        }
    }

    private var agentAvatar: some View {
        Image(systemName: "brain.head.profile")
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 28)
            .background(Color(.controlBackgroundColor), in: Circle())
    }

    private func toolDisplayName(_ name: String) -> String {
        name.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}

// MARK: - Chat Bubble

private struct ChatBubble: View {
    let message: DisplayMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .user {
                Spacer(minLength: 60)
                userBubble
            } else {
                assistantBubble
                Spacer(minLength: 60)
            }
        }
    }

    private var userBubble: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(message.content)
                .font(.body)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)
            Text(timeString)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var assistantBubble: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(Color(.controlBackgroundColor), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(message.content)
                    .font(.body)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
                Text(timeString)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: message.timestamp)
    }
}
