import Foundation

/// Executes a single sub-agent task in an isolated session with a filtered tool set.
final class SubAgentRunner {
    let definition: SubAgentDefinition
    private let provider: any LLMProvider
    private let model: String
    private let filteredRegistry: ToolRegistry
    private let session: ChatSession

    init(definition: SubAgentDefinition, provider: any LLMProvider, model: String, parentRegistry: ToolRegistry) {
        self.definition = definition
        self.provider = provider
        self.model = model
        self.filteredRegistry = ToolRegistry()
        self.session = ChatSession()

        // Copy only allowed tools from parent registry
        for toolName in definition.allowedTools {
            if let tool = parentRegistry.tool(named: toolName) {
                filteredRegistry.register(tool)
                // Ensure the tool is enabled in the filtered registry
                filteredRegistry.settings.setEnabled(toolName, enabled: true)
            }
        }
    }

    /// Run the sub-agent with the given task. Returns the final text response.
    func run(task: String, callbacks: AgentCallbacks) async throws -> String {
        // Set up the isolated session
        session.setSystemPrompt(definition.systemPrompt)
        session.addUserMessage(task)

        let toolDefs = filteredRegistry.enabledDefinitions
        let hasTools = !toolDefs.isEmpty
        var accumulatedResponse = ""

        for iteration in 0..<definition.maxToolCalls {
            try Task.checkCancellation()

            // Stream LLM response
            let response = try await streamResponse(
                messages: session.llmMessages,
                tools: hasTools ? toolDefs : nil,
                callbacks: callbacks
            )

            session.addAssistantMessage(response.message)

            // Check if LLM wants to call tools
            guard response.finishReason == .toolCalls,
                  let toolCalls = response.message.toolCalls,
                  !toolCalls.isEmpty else {
                accumulatedResponse = response.message.content ?? ""
                break
            }

            print("[SubAgentRunner:\(definition.id)] Iteration \(iteration + 1): \(toolCalls.count) tool call(s)")

            // Execute tools
            for call in toolCalls {
                try Task.checkCancellation()

                let prefixedName = "\(definition.id).\(call.name)"
                await callbacks.onToolStart(prefixedName)

                let result: ToolResult
                do {
                    result = try await filteredRegistry.execute(call)
                } catch {
                    result = .error("Tool '\(call.name)' threw: \(error.localizedDescription)")
                }

                await callbacks.onToolEnd(prefixedName, result.isError)

                let truncated = Self.truncateOutput(result.output)
                session.addToolResult(content: truncated, toolCallId: call.id)

                print("[SubAgentRunner:\(definition.id)] \(call.name): \(result.isError ? "ERROR" : "OK") (\(result.output.count) chars)")
            }
        }

        return accumulatedResponse
    }

    // MARK: - Streaming

    private func streamResponse(
        messages: [ChatMessage],
        tools: [ToolDefinition]?,
        callbacks: AgentCallbacks
    ) async throws -> ChatResponse {
        var accumulatedContent = ""
        var accumulatedToolCalls: [ToolCall] = []
        var lastFinishReason: ChatResponse.FinishReason?

        let stream = provider.chatStream(
            messages: messages,
            model: model,
            tools: tools,
            timeout: definition.timeout
        )

        for try await chunk in stream {
            try Task.checkCancellation()

            if let delta = chunk.deltaContent, !delta.isEmpty {
                accumulatedContent += delta
                await callbacks.onStreamDelta(delta)
            }
            if let toolCalls = chunk.deltaToolCalls {
                accumulatedToolCalls.append(contentsOf: toolCalls)
            }
            if let reason = chunk.finishReason {
                lastFinishReason = reason
            }
        }

        let finishReason: ChatResponse.FinishReason
        if !accumulatedToolCalls.isEmpty {
            finishReason = .toolCalls
        } else {
            finishReason = lastFinishReason ?? .stop
        }

        let message = ChatMessage(
            role: .assistant,
            content: accumulatedContent.isEmpty ? nil : accumulatedContent,
            toolCalls: accumulatedToolCalls.isEmpty ? nil : accumulatedToolCalls
        )

        return ChatResponse(message: message, finishReason: finishReason, usage: nil)
    }

    // MARK: - Output Truncation

    private static let maxOutputChars = 4000

    private static func truncateOutput(_ output: String) -> String {
        guard output.count > maxOutputChars else { return output }
        let truncated = String(output.prefix(maxOutputChars))
        return truncated + "\n\n[Output truncated — \(output.count) total characters. First \(maxOutputChars) shown.]"
    }
}
