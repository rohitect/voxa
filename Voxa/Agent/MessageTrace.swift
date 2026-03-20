import Foundation

/// Captures the full processing trace for one assistant response turn.
/// Used to power the trace inspector UI ("i" button on chat bubbles).
struct MessageTrace: Codable, Sendable {
    let id: UUID
    let startedAt: Date
    var completedAt: Date?
    var agentName: String
    var provider: String
    var model: String
    var systemPromptLength: Int
    var entries: [TraceEntry]
    var totalUsage: TraceTokenUsage?

    init(agentName: String = "Voxa", provider: String, model: String, systemPromptLength: Int = 0) {
        self.id = UUID()
        self.startedAt = Date()
        self.agentName = agentName
        self.provider = provider
        self.model = model
        self.systemPromptLength = systemPromptLength
        self.entries = []
    }

    var durationMs: Int? {
        guard let end = completedAt else { return nil }
        return Int(end.timeIntervalSince(startedAt) * 1000)
    }

    mutating func append(_ entry: TraceEntry) {
        entries.append(entry)
    }

    mutating func finish(usage: TraceTokenUsage? = nil) {
        completedAt = Date()
        totalUsage = usage
    }
}

// MARK: - Trace Entry

/// A single event in the processing trace timeline.
struct TraceEntry: Identifiable, Codable, Sendable {
    let id: UUID
    let timestamp: Date
    let kind: TraceEntryKind

    init(_ kind: TraceEntryKind) {
        self.id = UUID()
        self.timestamp = Date()
        self.kind = kind
    }
}

enum TraceEntryKind: Codable, Sendable {
    /// LLM request sent with N messages and N tool definitions.
    case llmRequest(messageCount: Int, toolCount: Int, iteration: Int)
    /// LLM finished streaming — captured text and any tool call requests.
    case llmResponse(content: String?, toolCalls: [ToolCallSummary]?)
    /// A tool was executed.
    case toolExecution(ToolCallSummary)
    /// A sub-agent was delegated to.
    case subAgentDelegation(agentName: String, input: String, output: String, durationMs: Int)
    /// An error occurred during processing.
    case error(String)
}

// MARK: - Tool Call Summary (for trace display)

/// Lightweight summary of a tool call for trace storage.
struct ToolCallSummary: Identifiable, Codable, Sendable {
    let id: String
    let name: String
    let arguments: String
    var output: String?
    var isError: Bool
    var durationMs: Int?
    var isMCP: Bool

    init(from toolCall: ToolCall, isMCP: Bool = false) {
        self.id = toolCall.id
        self.name = toolCall.name
        self.arguments = toolCall.arguments
        self.isError = false
        self.isMCP = isMCP
    }

    init(id: String, name: String, arguments: String, output: String?, isError: Bool, durationMs: Int?, isMCP: Bool) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.output = output
        self.isError = isError
        self.durationMs = durationMs
        self.isMCP = isMCP
    }
}

// MARK: - Token Usage (trace-specific, Codable)

struct TraceTokenUsage: Codable, Sendable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int

    init(from usage: TokenUsage) {
        self.promptTokens = usage.promptTokens
        self.completionTokens = usage.completionTokens
        self.totalTokens = usage.totalTokens
    }

    init(promptTokens: Int, completionTokens: Int, totalTokens: Int) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
    }
}
