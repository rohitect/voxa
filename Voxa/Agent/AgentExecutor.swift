import Foundation

/// Core agentic loop: classify intent → execute tools → LLM response.
final class AgentExecutor {
    private let providerManager: LLMProviderManager
    private let toolRegistry: ToolRegistry
    private let maxToolIterations = 5

    init(providerManager: LLMProviderManager, toolRegistry: ToolRegistry) {
        self.providerManager = providerManager
        self.toolRegistry = toolRegistry
    }

    /// Process a transcript through the agent pipeline.
    func process(transcript: String, session: ChatSession) async throws -> AgentResponse {
        let intent = IntentClassifier.classify(transcript)

        switch intent {
        case .systemControl(let action):
            return handleSystemControl(action, session: session)

        case .dictation:
            return .injection(transcript, display: "Dictated: \(transcript)")

        case .textRewrite(let text, let command):
            return try await handleRewrite(text: text, command: command, session: session)

        case .toolInvocation, .agentChat:
            return try await handleAgentChat(transcript: transcript, session: session)
        }
    }

    // MARK: - System Control

    private func handleSystemControl(_ action: Intent.SystemControlAction, session: ChatSession) -> AgentResponse {
        switch action {
        case .stop, .cancel:
            return .chat("Cancelled.")
        case .reset, .newSession:
            session.reset()
            return .chat("Session reset. How can I help?")
        }
    }

    // MARK: - Text Rewrite

    private func handleRewrite(text: String, command: String, session: ChatSession) async throws -> AgentResponse {
        guard let provider = providerManager.activeProvider else {
            return .chat("No LLM provider configured.")
        }

        let rewriteMessages = [
            ChatMessage(role: .system, content: "Rewrite the given text according to the user's instruction. Output ONLY the rewritten text."),
            ChatMessage(role: .user, content: "Text: \(text)\n\nInstruction: \(command)"),
        ]

        let model = providerManager.activeModel
        let response = try await provider.chat(messages: rewriteMessages, model: model, timeout: 10)

        if let content = response.message.content {
            return .injection(content, display: "Rewrote text")
        }

        return .chat("Failed to rewrite text.")
    }

    // MARK: - Agent Chat (with tool loop)

    private func handleAgentChat(transcript: String, session: ChatSession) async throws -> AgentResponse {
        guard let provider = providerManager.activeProvider else {
            return .chat("No LLM provider configured. Go to Settings > Agent to set one up.")
        }

        // Update system prompt with current tool definitions
        let toolDefs = toolRegistry.enabledDefinitions
        let hasTools = !toolDefs.isEmpty
        session.setSystemPrompt(buildSystemPrompt(hasTools: hasTools))

        // Add user message
        session.addUserMessage(transcript)

        let model = providerManager.activeModel
        var toolsUsed: [String] = []

        // Tool execution loop
        for iteration in 0..<maxToolIterations {
            let response = try await provider.chat(
                messages: session.llmMessages,
                model: model,
                tools: hasTools ? toolDefs : nil,
                timeout: 30
            )

            // Check if LLM wants to call tools
            guard response.finishReason == .toolCalls,
                  let toolCalls = response.message.toolCalls,
                  !toolCalls.isEmpty else {
                // No tool calls — we have the final response
                session.addAssistantMessage(response.message)
                let content = response.message.content ?? ""
                if toolsUsed.isEmpty {
                    return .chat(content)
                } else {
                    return .withTools(content, tools: toolsUsed)
                }
            }

            print("[AgentExecutor] Iteration \(iteration + 1): \(toolCalls.count) tool call(s)")

            // Append assistant message with tool calls
            session.addAssistantMessage(response.message)

            // Execute each tool call
            for toolCall in toolCalls {
                print("[AgentExecutor] Executing: \(toolCall.name)")
                let result = try await toolRegistry.execute(toolCall)
                session.addToolResult(content: result.output, toolCallId: toolCall.id)
                toolsUsed.append(toolCall.name)
                print("[AgentExecutor] Result: \(result.isError ? "ERROR" : "OK")")
            }
        }

        // If we hit max iterations, return what we have
        let lastAssistant = session.messages.last { $0.role == .assistant }
        let content = lastAssistant?.content ?? "I used several tools but couldn't complete the task within the iteration limit."
        return .withTools(content, tools: toolsUsed)
    }

    // MARK: - System Prompt

    private func buildSystemPrompt(hasTools: Bool) -> String {
        var prompt = "You are a helpful voice assistant running on macOS. Respond concisely and naturally."
        if hasTools {
            prompt += " You have access to tools that can interact with the user's Mac. Use them when the user's request requires taking action on their computer. If a task can be done with a tool, use it rather than just describing the steps."
        }
        prompt += " Keep responses brief — this is a voice interface."
        return prompt
    }
}
