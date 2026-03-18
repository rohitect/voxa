import Foundation

/// A provider that can send chat messages to a language model and receive responses.
protocol LLMProvider: Sendable {
    /// Human-readable provider name (e.g. "Ollama", "OpenAI").
    var name: String { get }

    /// The default model ID for this provider.
    var defaultModel: String { get }

    /// Check if the provider is reachable and ready to serve requests.
    var isAvailable: Bool { get async }

    /// Send a chat completion request and return the full response.
    func chat(
        messages: [ChatMessage],
        model: String,
        tools: [ToolDefinition]?,
        timeout: TimeInterval
    ) async throws -> ChatResponse

    /// Send a streaming chat completion request.
    func chatStream(
        messages: [ChatMessage],
        model: String,
        tools: [ToolDefinition]?,
        timeout: TimeInterval
    ) -> AsyncThrowingStream<ChatStreamChunk, Error>
}

// Default timeout
extension LLMProvider {
    func chat(
        messages: [ChatMessage],
        model: String,
        tools: [ToolDefinition]? = nil,
        timeout: TimeInterval = 30
    ) async throws -> ChatResponse {
        try await chat(messages: messages, model: model, tools: tools, timeout: timeout)
    }

    func chatStream(
        messages: [ChatMessage],
        model: String,
        tools: [ToolDefinition]? = nil,
        timeout: TimeInterval = 30
    ) -> AsyncThrowingStream<ChatStreamChunk, Error> {
        chatStream(messages: messages, model: model, tools: tools, timeout: timeout)
    }
}
