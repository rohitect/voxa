import SwiftUI

struct AgentPanelContent: View {
    let state: AgentPanelState
    let onDismiss: () -> Void
    let onNewSession: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbar

            Divider()

            // Content area
            if state.isListening {
                listeningView
            } else if state.isProcessing {
                processingView
            } else if let session = state.session {
                chatView(session: session)
            } else if let status = state.statusMessage {
                statusView(status)
            } else {
                emptyView
            }
        }
        .frame(minWidth: 280, minHeight: 180)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            Image(systemName: "brain.head.profile")
                .foregroundStyle(.secondary)

            Text("Agent")
                .font(.headline)

            Spacer()

            if state.panelMode == .persistent {
                Button(action: onNewSession) {
                    Image(systemName: "plus.message")
                        .font(.system(size: 13))
                }
                .buttonStyle(.borderless)
                .help("New Session")
            }

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

    // MARK: - States

    private var listeningView: some View {
        VStack(spacing: 12) {
            Spacer()
            Circle()
                .fill(.red)
                .frame(width: 16, height: 16)
                .modifier(PulseModifier())
            Text("Listening...")
                .font(.title3)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var processingView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .controlSize(.regular)
            if let toolName = state.currentToolName {
                Label(toolDisplayName(toolName), systemImage: "gearshape.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Text("Thinking...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func chatView(session: ChatSession) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(session.displayMessages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding(14)
            }
            .onChange(of: session.displayMessages.count) { _, _ in
                if let last = session.displayMessages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func statusView(_ status: String) -> some View {
        VStack {
            Spacer()
            Text(status)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "waveform")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("Press Ctrl+Space and speak")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

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
