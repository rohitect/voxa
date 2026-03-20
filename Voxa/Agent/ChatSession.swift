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
    ///
    /// Enforces API ordering rules:
    /// - Tool-result messages must immediately follow their parent assistant tool-call message
    /// - Assistant messages with tool calls must come after a user or tool message
    /// - No consecutive assistant messages
    /// - No orphaned tool results or tool calls without results
    var llmMessages: [ChatMessage] {
        // Pass 1: Group messages into valid sequences.
        // A valid sequence is either:
        //   [user]
        //   [assistant(text only)]
        //   [assistant(tool_calls), tool, tool, ...]  (complete tool round-trip)
        // We walk the messages and build groups, dropping any broken ones.

        struct MessageGroup {
            var messages: [ChatMessage]
        }

        var groups: [MessageGroup] = []
        var i = 0

        while i < messages.count {
            let msg = messages[i]

            switch msg.role {
            case .system:
                groups.append(MessageGroup(messages: [msg]))
                i += 1

            case .user:
                groups.append(MessageGroup(messages: [msg]))
                i += 1

            case .assistant:
                if let calls = msg.toolCalls, !calls.isEmpty {
                    // Collect the following tool result messages
                    var group: [ChatMessage] = [msg]
                    let expectedIDs = Set(calls.map(\.id))
                    var foundIDs: Set<String> = []
                    var j = i + 1
                    while j < messages.count && messages[j].role == .tool {
                        if let callId = messages[j].toolCallId, expectedIDs.contains(callId) {
                            group.append(messages[j])
                            foundIDs.insert(callId)
                        }
                        j += 1
                    }

                    if foundIDs == expectedIDs {
                        // Complete tool round-trip — keep it
                        groups.append(MessageGroup(messages: group))
                    } else {
                        // Incomplete — keep only the text content as a plain assistant message
                        if let content = msg.content, !content.isEmpty {
                            groups.append(MessageGroup(messages: [
                                ChatMessage(role: .assistant, content: content)
                            ]))
                        }
                    }
                    i = j  // skip past the tool results we consumed

                } else {
                    // Plain text assistant message
                    groups.append(MessageGroup(messages: [msg]))
                    i += 1
                }

            case .tool:
                // Orphaned tool result (not preceded by its assistant) — skip
                i += 1
            }
        }

        // Pass 2: Flatten groups, merging consecutive assistant-only groups
        var result: [ChatMessage] = []
        for group in groups {
            let first = group.messages[0]

            if first.role == .assistant && first.toolCalls == nil {
                // Text-only assistant — merge with previous if also text-only assistant
                if let lastIdx = result.indices.last,
                   result[lastIdx].role == .assistant,
                   result[lastIdx].toolCalls == nil {
                    let merged = (result[lastIdx].content ?? "") + "\n" + (first.content ?? "")
                    result[lastIdx] = ChatMessage(role: .assistant, content: merged)
                } else {
                    result.append(contentsOf: group.messages)
                }
            } else {
                result.append(contentsOf: group.messages)
            }
        }

        return result
    }

    // MARK: - Context Trimming

    private func trimIfNeeded() {
        guard messages.count > maxMessages else { return }

        // Keep system prompt (first message if system) + last N messages
        let systemPrompt = messages.first?.role == .system ? messages.first : nil
        let keepCount = maxMessages - (systemPrompt != nil ? 1 : 0)
        let nonSystem = systemPrompt != nil ? Array(messages.dropFirst()) : messages
        var startIndex = max(0, nonSystem.count - keepCount)

        // Ensure we don't start on a tool-result message (which would be orphaned
        // from its preceding assistant tool-call message). Walk forward until we
        // land on a user or assistant message — never a bare tool result.
        while startIndex < nonSystem.count && nonSystem[startIndex].role == .tool {
            startIndex += 1
        }

        // Also check: if the first kept message is an assistant with toolCalls,
        // but some/all of its tool results were trimmed, drop it too so the
        // conversation starts cleanly on a user message.
        if startIndex < nonSystem.count,
           nonSystem[startIndex].role == .assistant,
           let calls = nonSystem[startIndex].toolCalls, !calls.isEmpty {
            // Skip past this assistant message and any following tool results
            startIndex += 1
            while startIndex < nonSystem.count && nonSystem[startIndex].role == .tool {
                startIndex += 1
            }
        }

        let recentMessages = Array(nonSystem.suffix(from: startIndex))

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
