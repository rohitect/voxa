import Foundation

/// Manages a multi-turn chat session with message history and context trimming.
@Observable
final class ChatSession: Identifiable {
    /// All messages in the session, including system, user, assistant, and tool messages.
    private(set) var messages: [ChatMessage] = []

    /// Display messages for the UI (excludes system and tool messages).
    var displayMessages: [DisplayMessage] {
        var result: [DisplayMessage] = []
        for msg in messages {
            switch msg.role {
            case .user:
                if let content = msg.content {
                    result.append(DisplayMessage(role: .user, content: content))
                }
            case .assistant:
                if let content = msg.content, !content.isEmpty {
                    result.append(DisplayMessage(role: .assistant, content: content))
                }
            case .system, .tool:
                break
            }
        }
        return result
    }

    /// Maximum number of messages to keep before trimming (keeps system prompt + recent messages).
    private let maxMessages = 40

    /// Unique session identifier.
    let id: UUID

    /// When this session was created.
    let createdAt: Date

    /// Conversation title (auto-generated from first user message).
    var title: String = "New Chat"

    init(id: UUID = UUID(), createdAt: Date = Date()) {
        self.id = id
        self.createdAt = createdAt
    }

    /// Whether the session has any user/assistant exchanges.
    var hasHistory: Bool {
        messages.contains { $0.role == .user || $0.role == .assistant }
    }

    // MARK: - Message Management

    func setSystemPrompt(_ prompt: String) {
        // Remove existing system prompt if any
        messages.removeAll { $0.role == .system }
        messages.insert(ChatMessage(role: .system, content: prompt), at: 0)
    }

    func addUserMessage(_ content: String) {
        // Auto-title from first user message
        if title == "New Chat" {
            let truncated = content.prefix(50)
            title = truncated.count < content.count ? "\(truncated)..." : String(truncated)
        }
        messages.append(ChatMessage(role: .user, content: content))
        trimIfNeeded()
    }

    func addAssistantMessage(_ message: ChatMessage) {
        messages.append(message)
    }

    func addToolResult(content: String, toolCallId: String) {
        messages.append(ChatMessage(role: .tool, content: content, toolCallId: toolCallId))
    }

    func reset() {
        let systemPrompt = messages.first { $0.role == .system }
        messages.removeAll()
        if let systemPrompt {
            messages.append(systemPrompt)
        }
    }

    /// Returns all messages suitable for sending to the LLM.
    var llmMessages: [ChatMessage] {
        messages
    }

    // MARK: - Context Trimming

    private func trimIfNeeded() {
        guard messages.count > maxMessages else { return }

        // Keep system prompt (first message if system) + last N messages
        let systemPrompt = messages.first?.role == .system ? messages.first : nil
        let keepCount = maxMessages - (systemPrompt != nil ? 1 : 0)
        let recentMessages = Array(messages.suffix(keepCount))

        messages.removeAll()
        if let systemPrompt {
            messages.append(systemPrompt)
        }
        messages.append(contentsOf: recentMessages)
    }
}

// MARK: - Display Message

struct DisplayMessage: Identifiable {
    let id = UUID()
    let role: DisplayRole
    let content: String
    let timestamp = Date()

    enum DisplayRole {
        case user
        case assistant
    }
}
