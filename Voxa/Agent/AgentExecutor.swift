import Foundation

/// Callbacks for live UI updates during agent execution.
struct AgentCallbacks: Sendable {
    /// Called with each text delta from the LLM stream.
    let onStreamDelta: @Sendable (String) async -> Void
    /// Called when a tool starts executing.
    let onToolStart: @Sendable (String) async -> Void
    /// Called when a tool finishes executing.
    let onToolEnd: @Sendable (String, Bool) async -> Void

    static let none = AgentCallbacks(
        onStreamDelta: { _ in },
        onToolStart: { _ in },
        onToolEnd: { _, _ in }
    )
}

/// Core agentic loop: classify intent → stream LLM → execute tools → loop.
final class AgentExecutor {
    private let providerManager: LLMProviderManager
    private let toolRegistry: ToolRegistry
    private let personaManager: PersonaManager?
    private let maxToolIterations = 10

    init(providerManager: LLMProviderManager, toolRegistry: ToolRegistry, personaManager: PersonaManager? = nil) {
        self.providerManager = providerManager
        self.toolRegistry = toolRegistry
        self.personaManager = personaManager
    }

    /// Process a transcript through the agent pipeline.
    func process(
        transcript: String,
        session: ChatSession,
        callbacks: AgentCallbacks = .none
    ) async throws -> AgentResponse {
        let intent = IntentClassifier.classify(transcript)

        switch intent {
        case .systemControl(let action):
            return handleSystemControl(action, session: session)
        case .agentChat:
            return try await handleAgentChat(transcript: transcript, session: session, callbacks: callbacks)
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

    // MARK: - Agent Chat (streaming with tool loop)

    private func handleAgentChat(
        transcript: String,
        session: ChatSession,
        callbacks: AgentCallbacks
    ) async throws -> AgentResponse {
        guard let provider = providerManager.activeProvider else {
            return .chat("No LLM provider configured. Go to Settings > Agent to set one up.")
        }

        // Update system prompt with identity, memory, and tool info
        let toolDefs = toolRegistry.enabledDefinitions
        let hasTools = !toolDefs.isEmpty
        let toolNames = hasTools ? toolDefs.map(\.name) : []
        let sessionContext = session.messages.suffix(4).compactMap(\.content).joined(separator: " ")
        if let persona = personaManager {
            session.setSystemPrompt(persona.buildSystemPrompt(toolNames: toolNames, sessionContext: sessionContext))
        } else {
            session.setSystemPrompt(buildSystemPrompt(toolNames: toolNames))
        }

        // Add user message
        session.addUserMessage(transcript)

        let model = providerManager.activeModel
        var toolsUsed: [String] = []

        // Build trace
        let providerName = String(describing: type(of: provider)).replacingOccurrences(of: "Provider", with: "")
        let systemPromptLen = session.messages.first { $0.role == .system }?.content?.count ?? 0
        let agentName = personaManager?.agentName ?? "Voxa"
        var trace = MessageTrace(agentName: agentName, provider: providerName, model: model, systemPromptLength: systemPromptLen)

        // Agentic tool loop
        var lastToolOutputs: [(name: String, output: String)] = []

        for iteration in 0..<maxToolIterations {
            try Task.checkCancellation()

            let messageCount = session.llmMessages.count
            let toolCount = hasTools ? toolDefs.count : 0
            trace.append(TraceEntry(.llmRequest(messageCount: messageCount, toolCount: toolCount, iteration: iteration + 1)))

            // Stream LLM response
            let response: ChatResponse
            do {
                response = try await streamLLMResponse(
                    provider: provider,
                    messages: session.llmMessages,
                    model: model,
                    tools: hasTools ? toolDefs : nil,
                    callbacks: callbacks
                )
            } catch {
                trace.append(TraceEntry(.error("LLM stream failed: \(error.localizedDescription)")))
                trace.finish()

                // If LLM fails mid-tool-loop, return tool results instead of losing everything
                if !lastToolOutputs.isEmpty {
                    let summary = lastToolOutputs.map { "[\($0.name)]\n\($0.output)" }.joined(separator: "\n\n")
                    let errorNote = "LLM error after tool execution: \(error.localizedDescription)"
                    let fallbackText = "\(errorNote)\n\nTool results:\n\(summary)"
                    session.addAssistantMessage(ChatMessage(role: .assistant, content: fallbackText))
                    return .withTools(fallbackText, tools: toolsUsed, trace: trace)
                }
                throw error
            }

            // Record LLM response in trace
            let toolCallSummaries: [ToolCallSummary]? = response.message.toolCalls?.map { call in
                ToolCallSummary(from: call, isMCP: isMCPTool(call.name))
            }
            trace.append(TraceEntry(.llmResponse(
                content: response.message.content,
                toolCalls: toolCallSummaries
            )))

            // Add assistant message to session
            session.addAssistantMessage(response.message)

            // Check if LLM wants to call tools
            guard response.finishReason == .toolCalls,
                  let toolCalls = response.message.toolCalls,
                  !toolCalls.isEmpty else {
                // Final text response
                trace.finish(usage: response.usage.map { TraceTokenUsage(from: $0) })
                let content = response.message.content ?? ""
                if toolsUsed.isEmpty {
                    return .chat(content, trace: trace)
                } else {
                    return .withTools(content, tools: toolsUsed, trace: trace)
                }
            }

            print("[AgentExecutor] Iteration \(iteration + 1): \(toolCalls.count) tool call(s)")

            // Execute tools — parallel when multiple, sequential when single
            let results: [(ToolCall, ToolResult, Int)]  // added durationMs
            if toolCalls.count == 1 {
                let call = toolCalls[0]
                await callbacks.onToolStart(call.name)
                let start = Date()
                let result = await executeToolSafely(call)
                let durationMs = Int(Date().timeIntervalSince(start) * 1000)
                await callbacks.onToolEnd(call.name, result.isError)
                results = [(call, result, durationMs)]
            } else {
                results = await executeToolsInParallelTimed(toolCalls, callbacks: callbacks)
            }

            // Track tool outputs for fallback display
            lastToolOutputs = results.map { (name: $0.0.name, output: $0.1.output) }

            // Add results to session and trace
            for (call, result, durationMs) in results {
                let truncated = Self.truncateToolOutput(result.output)
                session.addToolResult(content: truncated, toolCallId: call.id, toolName: call.name)
                toolsUsed.append(call.name)

                trace.append(TraceEntry(.toolExecution(ToolCallSummary(
                    id: call.id,
                    name: call.name,
                    arguments: call.arguments,
                    output: result.output,
                    isError: result.isError,
                    durationMs: durationMs,
                    isMCP: isMCPTool(call.name)
                ))))

                print("[AgentExecutor] \(call.name): \(result.isError ? "ERROR" : "OK") (\(result.output.count) chars)")
            }
        }

        // Hit max iterations
        trace.append(TraceEntry(.error("Hit max tool iterations (\(maxToolIterations))")))
        trace.finish()
        let content = "I used several tools but couldn't complete the task within \(maxToolIterations) iterations."
        session.addAssistantMessage(ChatMessage(role: .assistant, content: content))
        return .withTools(content, tools: toolsUsed, trace: trace)
    }

    // MARK: - Streaming

    private func streamLLMResponse(
        provider: any LLMProvider,
        messages: [ChatMessage],
        model: String,
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
            timeout: 60
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

        // Determine finish reason
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

    // MARK: - Tool Execution

    /// Execute a single tool call, catching all errors.
    private func executeToolSafely(_ toolCall: ToolCall) async -> ToolResult {
        do {
            return try await toolRegistry.execute(toolCall)
        } catch {
            return .error("Tool '\(toolCall.name)' threw: \(error.localizedDescription)")
        }
    }

    /// Execute multiple tool calls in parallel using a TaskGroup.
    private func executeToolsInParallel(
        _ toolCalls: [ToolCall],
        callbacks: AgentCallbacks
    ) async -> [(ToolCall, ToolResult)] {
        let resultPairs = await withTaskGroup(
            of: (Int, ToolCall, ToolResult).self,
            returning: [(ToolCall, ToolResult)].self
        ) { group in
            for (index, call) in toolCalls.enumerated() {
                group.addTask {
                    await callbacks.onToolStart(call.name)
                    let result = await self.executeToolSafely(call)
                    await callbacks.onToolEnd(call.name, result.isError)
                    return (index, call, result)
                }
            }

            var collected: [(Int, ToolCall, ToolResult)] = []
            for await entry in group {
                collected.append(entry)
            }
            return collected.sorted { $0.0 < $1.0 }.map { ($0.1, $0.2) }
        }

        return resultPairs
    }

    /// Execute multiple tool calls in parallel, returning timing info for trace.
    private func executeToolsInParallelTimed(
        _ toolCalls: [ToolCall],
        callbacks: AgentCallbacks
    ) async -> [(ToolCall, ToolResult, Int)] {
        let resultPairs = await withTaskGroup(
            of: (Int, ToolCall, ToolResult, Int).self,
            returning: [(ToolCall, ToolResult, Int)].self
        ) { group in
            for (index, call) in toolCalls.enumerated() {
                group.addTask {
                    await callbacks.onToolStart(call.name)
                    let start = Date()
                    let result = await self.executeToolSafely(call)
                    let durationMs = Int(Date().timeIntervalSince(start) * 1000)
                    await callbacks.onToolEnd(call.name, result.isError)
                    return (index, call, result, durationMs)
                }
            }

            var collected: [(Int, ToolCall, ToolResult, Int)] = []
            for await entry in group {
                collected.append(entry)
            }
            return collected.sorted { $0.0 < $1.0 }.map { ($0.1, $0.2, $0.3) }
        }

        return resultPairs
    }

    /// Check if a tool name corresponds to an MCP tool (contains a dot separator).
    private func isMCPTool(_ name: String) -> Bool {
        name.contains(".")
    }

    // MARK: - Output Truncation

    /// Truncate tool output to avoid exceeding LLM context limits.
    private static let maxToolOutputChars = 4000

    private static func truncateToolOutput(_ output: String) -> String {
        guard output.count > maxToolOutputChars else { return output }
        let truncated = String(output.prefix(maxToolOutputChars))
        return truncated + "\n\n[Output truncated — \(output.count) total characters. First \(maxToolOutputChars) shown.]"
    }

    // MARK: - System Prompt

    private func buildSystemPrompt(toolNames: [String]) -> String {
        var prompt = """
        You are Voxa, a voice-controlled AI assistant running on macOS. \
        You help users accomplish tasks on their Mac through voice commands.
        """

        if !toolNames.isEmpty {
            let toolList = toolNames.joined(separator: ", ")
            prompt += """
             You have access to the following tools: \(toolList). \
            Use tools proactively when the user's request requires action — don't just describe steps. \
            You can chain multiple tool calls to accomplish complex tasks. \
            If a tool fails, analyze the error and try an alternative approach.
            """
        }

        prompt += " Keep responses concise — this is a voice interface. Be direct and actionable."
        return prompt
    }
}
