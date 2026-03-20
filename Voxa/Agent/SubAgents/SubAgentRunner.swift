import Foundation
import MCP

/// Executes a single sub-agent task with isolated MCP connections and its own tool set.
final class SubAgentRunner {
    let definition: SubAgentDefinition
    private let provider: any LLMProvider
    private let model: String
    private let mcpConfigs: [MCPServerConfig]
    private let toolRegistry: ToolRegistry
    private let session: ChatSession

    /// Isolated MCP connections owned by this runner — disconnected on completion.
    private var connections: [MCPConnection] = []

    /// Called with each trace entry as it's created, for live trace streaming.
    var onTraceEntry: ((_ entry: TraceEntry) -> Void)?

    init(definition: SubAgentDefinition, provider: any LLMProvider, model: String, mcpConfigs: [MCPServerConfig]) {
        self.definition = definition
        self.provider = provider
        self.model = model
        self.mcpConfigs = mcpConfigs
        self.toolRegistry = ToolRegistry()
        self.session = ChatSession()
    }

    /// Result from a sub-agent run, including the response text and internal trace steps.
    struct RunResult {
        let response: String
        let traceEntries: [TraceEntry]
    }

    /// Run the sub-agent with the given task. Returns the final text response and trace.
    ///
    /// Stream deltas are suppressed so sub-agent LLM output doesn't leak into the main chat bubble.
    /// Tool start/end callbacks are preserved so the UI can show sub-agent tool activity.
    func run(task: String, callbacks: AgentCallbacks) async throws -> RunResult {
        let callbacks = AgentCallbacks(
            onStreamDelta: { _ in },
            onToolStart: callbacks.onToolStart,
            onToolEnd: callbacks.onToolEnd,
            onTraceUpdate: callbacks.onTraceUpdate
        )
        // Register builtin tools directly on this runner's tool registry
        // Sub-agent registries skip confirmation — their UI isn't wired up and would deadlock.
        toolRegistry.skipConfirmation = true
        toolRegistry.registerBuiltinTools(definition.builtinTools)

        // Connect to assigned MCP servers and discover tools
        await connectMCPServers()
        defer {
            Task { [connections] in
                for conn in connections {
                    await conn.disconnect()
                }
            }
        }

        // Set up the isolated session
        session.setSystemPrompt(definition.systemPrompt)
        session.addUserMessage(task)

        // Log the full system prompt for debugging
        if let systemMsg = session.llmMessages.first(where: { $0.role == .system }) {
            print("[SubAgentRunner:\(definition.id)] === SYSTEM PROMPT START ===")
            print(systemMsg.content ?? "(empty)")
            print("[SubAgentRunner:\(definition.id)] === SYSTEM PROMPT END ===")
        } else {
            print("[SubAgentRunner:\(definition.id)] WARNING: No system prompt in llmMessages!")
        }

        let toolDefs = toolRegistry.enabledDefinitions
        let hasTools = !toolDefs.isEmpty
        let builtinNames = Set(definition.builtinTools)
        var accumulatedResponse = ""
        var lastToolOutputs: [(name: String, output: String)] = []
        var traceEntries: [TraceEntry] = []

        // Helper to emit trace entries for live streaming
        func emitTrace(_ entry: TraceEntry) {
            traceEntries.append(entry)
            onTraceEntry?(entry)
        }

        for iteration in 0..<definition.maxToolCalls {
            try Task.checkCancellation()

            let messageCount = session.llmMessages.count
            let toolCount = hasTools ? toolDefs.count : 0
            emitTrace(TraceEntry(.llmRequest(messageCount: messageCount, toolCount: toolCount, iteration: iteration + 1)))

            // Stream LLM response
            let response: ChatResponse
            do {
                response = try await streamResponse(
                    messages: session.llmMessages,
                    tools: hasTools ? toolDefs : nil,
                    callbacks: callbacks
                )
            } catch {
                emitTrace(TraceEntry(.error("LLM error: \(error.localizedDescription)")))
                if !lastToolOutputs.isEmpty {
                    let summary = lastToolOutputs.map { "[\($0.name)]\n\($0.output)" }.joined(separator: "\n\n")
                    let fallback = "LLM error after tool execution: \(error.localizedDescription)\n\nTool results:\n\(summary)"
                    session.addAssistantMessage(ChatMessage(role: .assistant, content: fallback))
                    return RunResult(response: fallback, traceEntries: traceEntries)
                }
                throw error
            }

            // Trace the LLM response
            let toolCallSummaries: [ToolCallSummary]? = response.message.toolCalls?.map { call in
                ToolCallSummary(from: call, isMCP: !builtinNames.contains(call.name))
            }
            emitTrace(TraceEntry(.llmResponse(
                content: response.message.content,
                toolCalls: toolCallSummaries
            )))

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
            var iterationOutputs: [(name: String, output: String)] = []
            for call in toolCalls {
                try Task.checkCancellation()

                let prefixedName = "\(definition.id).\(call.name)"
                await callbacks.onToolStart(prefixedName)

                let start = Date()
                let result: ToolResult
                do {
                    result = try await toolRegistry.execute(call)
                } catch {
                    result = .error("Tool '\(call.name)' threw: \(error.localizedDescription)")
                }
                let durationMs = Int(Date().timeIntervalSince(start) * 1000)

                await callbacks.onToolEnd(prefixedName, result.isError)

                let truncated = Self.truncateOutput(result.output)
                session.addToolResult(content: truncated, toolCallId: call.id, toolName: call.name)
                iterationOutputs.append((name: call.name, output: result.output))

                // Trace the tool execution
                emitTrace(TraceEntry(.toolExecution(ToolCallSummary(
                    id: call.id,
                    name: call.name,
                    arguments: call.arguments,
                    output: result.output,
                    isError: result.isError,
                    durationMs: durationMs,
                    isMCP: !builtinNames.contains(call.name)
                ))))

                print("[SubAgentRunner:\(definition.id)] \(call.name): \(result.isError ? "ERROR" : "OK") (\(result.output.count) chars)")
            }
            lastToolOutputs = iterationOutputs
        }

        return RunResult(response: accumulatedResponse, traceEntries: traceEntries)
    }

    // MARK: - MCP Connection

    private func connectMCPServers() async {
        for config in mcpConfigs {
            let connection = MCPConnection(config: config)
            connections.append(connection)
            await connection.connect()

            if connection.status.isConnected {
                for mcpTool in connection.discoveredTools {
                    let adapter = MCPToolAdapter(
                        serverName: connection.config.name,
                        mcpTool: mcpTool,
                        connection: connection
                    )
                    toolRegistry.register(adapter)
                }
                print("[SubAgentRunner:\(definition.id)] Connected to MCP '\(config.name)' — \(connection.discoveredTools.count) tools")
            } else {
                print("[SubAgentRunner:\(definition.id)] Failed to connect to MCP '\(config.name)'")
            }
        }
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
