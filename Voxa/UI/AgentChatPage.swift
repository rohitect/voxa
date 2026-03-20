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
            .frame(width: 240)

            Divider()

            ChatMainArea(
                coordinator: coordinator,
                panelState: panelState,
                onDelete: {
                    store.delete(coordinator.session)
                    panelState.session = coordinator.session
                }
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

    @State private var searchText = ""

    private var filteredGroups: [(title: String, sessions: [ChatSession])] {
        let groups = store.groupedConversations
        guard !searchText.isEmpty else { return groups }
        return groups.compactMap { group in
            let filtered = group.sessions.filter {
                $0.title.localizedCaseInsensitiveContains(searchText)
            }
            return filtered.isEmpty ? nil : (title: group.title, sessions: filtered)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            newChatButton
            searchField
            Divider().padding(.horizontal, 12)
            conversationList
            Spacer(minLength: 0)
            clearAllButton
        }
        .background(Color.primary.opacity(0.04))
    }

    private var newChatButton: some View {
        Button(action: onNew) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                Text("New Chat")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("⌘N")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            TextField("Search chats...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.subheadline)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var conversationList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(filteredGroups.indices, id: \.self) { index in
                    let group = filteredGroups[index]
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
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .tracking(0.5)
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var clearAllButton: some View {
        VStack(spacing: 0) {
            Divider().padding(.horizontal, 12)
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
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "bubble.left.fill" : "bubble.left")
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .accentColor : .gray)
                    .frame(width: 16)

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
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 20, height: 20)
                            .background(Color.primary.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.borderless)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.borderless)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }

    private var rowBackground: Color {
        if isSelected { return Color.accentColor.opacity(0.12) }
        if isHovered { return Color.primary.opacity(0.04) }
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
    let onDelete: () -> Void

    @State private var inputText = ""
    @State private var showDeleteConfirmation = false
    @FocusState private var isInputFocused: Bool

    private var isBusy: Bool {
        panelState.isListening || panelState.isProcessing || panelState.isStreaming
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            chatArea
            inputBar
        }
        .background(Color.clear)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Text(coordinator.session.title)
                .font(.headline)
                .lineLimit(1)

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
                Text(coordinator.providerManager.activeProviderName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.quaternary)
                Text(coordinator.providerManager.activeModel)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.06), in: Capsule())

            Button {
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Delete conversation")
            .alert("Delete conversation?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive, action: onDelete)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This conversation will be permanently deleted.")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: - Chat Area

    private var chatArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                chatMessages
                    .padding(.vertical, 16)
            }
            .scrollContentBackground(.hidden)
            .onAppear {
                // Scroll without animation on initial load to avoid layout loop
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    proxy.scrollTo("bottomAnchor", anchor: .bottom)
                }
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
        VStack(alignment: .leading, spacing: 0) {
            if let session = panelState.session {
                let messages = session.displayMessages
                ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                    ChatBubble(
                        message: message,
                        isFirstInGroup: isFirstInGroup(index, messages: messages)
                    )
                    .id(message.id)
                }
            }

            if panelState.isStreaming, !panelState.streamingText.isEmpty {
                streamingBubble.id("streaming")
            }

            // Tool confirmation banner
            if let confirmation = coordinator.toolRegistry.pendingConfirmation {
                ToolConfirmationBanner(
                    request: confirmation,
                    onApprove: { coordinator.toolRegistry.approveConfirmation() },
                    onDeny: { coordinator.toolRegistry.denyConfirmation() }
                )
                .id("confirmation")
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if panelState.isListening {
                listeningIndicator.id("status")
            } else if panelState.isProcessing {
                processingIndicator.id("status")
            }

            if !hasMessages && !isBusy {
                emptyState.id("empty")
            }

            // Stable anchor at the bottom for reliable scrolling
            Color.clear.frame(height: 1).id("bottomAnchor")
        }
    }

    private func isFirstInGroup(_ index: Int, messages: [DisplayMessage]) -> Bool {
        guard index > 0 else { return true }
        return messages[index].role != messages[index - 1].role
    }

    private var streamingBubble: some View {
        HStack(alignment: .top, spacing: 10) {
            agentAvatar
            VStack(alignment: .leading, spacing: 6) {
                MarkdownView(panelState.streamingText, fontSize: 13, isUser: false)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                TypingDotsView()
                    .padding(.leading, 14)
            }
            Spacer(minLength: 60)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 8)
    }

    private var listeningIndicator: some View {
        statusRow {
            HStack(spacing: 8) {
                ListeningWaveView()
                    .frame(width: 24, height: 16)
                Text("Listening...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var processingIndicator: some View {
        statusRow {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                if let toolName = panelState.currentToolName {
                    Label(toolDisplayName(toolName), systemImage: "gearshape.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                } else {
                    Text("Thinking...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.5)
            HStack(alignment: .center, spacing: 12) {
                TextField("Message Voxa...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...8)
                    .focused($isInputFocused)
                    .onSubmit { sendMessage() }
                    .disabled(isBusy)
                    .font(.body)

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(canSend ? Color.accentColor : Color.secondary.opacity(0.2))
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.borderless)
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.primary.opacity(isInputFocused ? 0.15 : 0.08), lineWidth: 1)
            )
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .contentShape(Rectangle())
        .onTapGesture { isInputFocused = true }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 60)

            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.08))
                    .frame(width: 80, height: 80)
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.accentColor.opacity(0.6))
            }

            VStack(spacing: 8) {
                Text("How can I help?")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("Type a message below or hold the agent hotkey to speak.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }

            suggestionChips
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private var suggestionChips: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                chipButton("What's on my clipboard?", icon: "doc.on.clipboard")
                chipButton("Take a screenshot", icon: "camera.viewfinder")
            }
            HStack(spacing: 8) {
                chipButton("Find files on Desktop", icon: "folder.badge.magnifyingglass")
                chipButton("Summarize selected text", icon: "text.quote")
            }
        }
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
        isInputFocused = true
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo("bottomAnchor", anchor: .bottom)
        }
    }

    private func chipButton(_ text: String, icon: String) -> some View {
        Button {
            inputText = ""
            coordinator.sendTextMessage(text)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(text)
                    .font(.caption)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
        }
        .buttonStyle(.borderless)
        .disabled(isBusy)
    }

    private func statusRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            agentAvatar
            content()
            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
    }

    private var agentAvatar: some View {
        Image(systemName: "brain.head.profile")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 30, height: 30)
            .background(Color.primary.opacity(0.06), in: Circle())
    }

    private func toolDisplayName(_ name: String) -> String {
        name.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}

// MARK: - Chat Bubble

private struct ChatBubble: View {
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

    // MARK: User Bubble — right-aligned with accent background

    private var userBubble: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Spacer(minLength: 80)
            VStack(alignment: .trailing, spacing: 4) {
                Text(message.content)
                    .font(.body)
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.accentColor, in: BubbleShape(isUser: true))
                    .foregroundStyle(.white)

                messageActions(alignment: .trailing)
            }
        }
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .padding(.horizontal, 28)
        .padding(.top, isFirstInGroup ? 16 : 4)
        .padding(.bottom, 4)
    }

    // MARK: Assistant Bubble — left-aligned with background

    private var assistantBubble: some View {
        HStack(alignment: .top, spacing: 10) {
            if isFirstInGroup {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Color.primary.opacity(0.06), in: Circle())
            } else {
                Spacer().frame(width: 30)
            }

            VStack(alignment: .leading, spacing: 4) {
                MarkdownView(message.content, fontSize: 13, isUser: false)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.primary.opacity(0.06), in: BubbleShape(isUser: false))

                messageActions(alignment: .leading)
            }

            Spacer(minLength: 60)
        }
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .padding(.horizontal, 28)
        .padding(.top, isFirstInGroup ? 16 : 4)
        .padding(.bottom, 4)
    }

    // MARK: Message Actions (hover only)

    private func messageActions(alignment: HorizontalAlignment) -> some View {
        HStack(spacing: 2) {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.content, forType: .string)
                showCopied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showCopied = false }
            } label: {
                Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundStyle(showCopied ? .green : .secondary)
                    .frame(width: 26, height: 26)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("Copy")

            if message.trace != nil {
                Button {
                    showTrace = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("View trace")
            }

            Text(timeString)
                .font(.caption2)
                .foregroundStyle(.quaternary)
                .padding(.horizontal, 6)
        }
        .padding(.top, 2)
    }

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: message.timestamp)
    }
}

// MARK: - Bubble Shape (with tail)

private struct BubbleShape: Shape {
    let isUser: Bool

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 16
        return Path(
            roundedRect: rect,
            cornerRadii: RectangleCornerRadii(
                topLeading: radius,
                bottomLeading: radius,
                bottomTrailing: isUser ? 4 : radius,
                topTrailing: radius
            )
        )
    }
}

// MARK: - Typing Dots (streaming indicator)

private struct TypingDotsView: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 5, height: 5)
                    .offset(y: animating ? -3 : 0)
                    .animation(
                        .easeInOut(duration: 0.4)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.15),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}

// MARK: - Tool Confirmation Banner

private struct ToolConfirmationBanner: View {
    let request: ToolConfirmationRequest
    let onApprove: () -> Void
    let onDeny: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 20))
                .foregroundStyle(.orange)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 8) {
                Text("Tool requires confirmation")
                    .font(.subheadline.weight(.semibold))

                VStack(alignment: .leading, spacing: 4) {
                    Text(request.toolName)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)

                    if !request.arguments.isEmpty && request.arguments != "{}" {
                        Text(formattedArguments)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                    }
                }

                HStack(spacing: 10) {
                    Button(action: onApprove) {
                        Label("Allow", systemImage: "checkmark")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)

                    Button(action: onDeny) {
                        Label("Deny", systemImage: "xmark")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 40)
        }
        .padding(16)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.orange.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, 28)
        .padding(.vertical, 8)
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

// MARK: - Listening Wave

private struct ListeningWaveView: View {
    @State private var animating = false
    private let barHeights: [CGFloat] = [10, 16, 8, 14]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<4) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.red.opacity(0.7))
                    .frame(width: 3, height: animating ? barHeights[index] : 4)
                    .animation(
                        .easeInOut(duration: 0.3 + Double(index) * 0.1)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.08),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}
