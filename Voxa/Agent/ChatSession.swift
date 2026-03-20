import Foundation

/// Manages a multi-turn chat session with message history and context trimming.
@Observable
final class ChatSession: Identifiable, Codable {
    /// All messages in the session, including system, user, assistant, and tool messages.
    private(set) var messages: [ChatMessage] = []

    /// Traces keyed by the index of the assistant message that produced them.
    /// We use message array index (at time of storage) mapped to trace ID for persistence.
    private(set) var traces: [UUID: MessageTrace] = [:]

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
                    // Find a trace whose ID is stored for this assistant message position
                    let trace = traces.values.first { trace in
                        // Match by timestamp proximity — trace completedAt should be close to when message was added
                        guard let completedAt = trace.completedAt else { return false }
                        // Check if any entry content matches the assistant message
                        return trace.entries.contains { entry in
                            if case .llmResponse(let responseContent, _) = entry.kind {
                                return responseContent == content
                            }
                            return false
                        }
                    }
                    result.append(DisplayMessage(role: .assistant, content: content, trace: trace))
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

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case messages, id, createdAt, title, traces
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.title = try container.decode(String.self, forKey: .title)
        self.messages = try container.decode([ChatMessage].self, forKey: .messages)
        self.traces = (try? container.decode([UUID: MessageTrace].self, forKey: .traces)) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(title, forKey: .title)
        try container.encode(messages, forKey: .messages)
        try container.encode(traces, forKey: .traces)
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

    func addToolResult(content: String, toolCallId: String, toolName: String? = nil) {
        messages.append(ChatMessage(role: .tool, content: content, toolCallId: toolCallId, toolName: toolName))
    }

    /// Store a processing trace for an assistant response.
    func storeTrace(_ trace: MessageTrace) {
        traces[trace.id] = trace
    }

    func reset() {
        let systemPrompt = messages.first { $0.role == .system }
        messages.removeAll()
        traces.removeAll()
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
    let trace: MessageTrace?

    init(role: DisplayRole, content: String, trace: MessageTrace? = nil) {
        self.role = role
        self.content = content
        self.trace = trace
    }

    enum DisplayRole {
        case user
        case assistant
    }
}
