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

    init(definition: SubAgentDefinition, provider: any LLMProvider, model: String, mcpConfigs: [MCPServerConfig]) {
        self.definition = definition
        self.provider = provider
        self.model = model
        self.mcpConfigs = mcpConfigs
        self.toolRegistry = ToolRegistry()
        self.session = ChatSession()
    }

    /// Run the sub-agent with the given task. Returns the final text response.
    func run(task: String, callbacks: AgentCallbacks) async throws -> String {
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

        let toolDefs = toolRegistry.enabledDefinitions
        let hasTools = !toolDefs.isEmpty
        var accumulatedResponse = ""
        var lastToolOutputs: [(name: String, output: String)] = []

        for iteration in 0..<definition.maxToolCalls {
            try Task.checkCancellation()

            // Stream LLM response
            let response: ChatResponse
            do {
                response = try await streamResponse(
                    messages: session.llmMessages,
                    tools: hasTools ? toolDefs : nil,
                    callbacks: callbacks
                )
            } catch {
                if !lastToolOutputs.isEmpty {
                    let summary = lastToolOutputs.map { "[\($0.name)]\n\($0.output)" }.joined(separator: "\n\n")
                    let fallback = "LLM error after tool execution: \(error.localizedDescription)\n\nTool results:\n\(summary)"
                    session.addAssistantMessage(ChatMessage(role: .assistant, content: fallback))
                    return fallback
                }
                throw error
            }

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

                let result: ToolResult
                do {
                    result = try await toolRegistry.execute(call)
                } catch {
                    result = .error("Tool '\(call.name)' threw: \(error.localizedDescription)")
                }

                await callbacks.onToolEnd(prefixedName, result.isError)

                let truncated = Self.truncateOutput(result.output)
                session.addToolResult(content: truncated, toolCallId: call.id, toolName: call.name)
                iterationOutputs.append((name: call.name, output: result.output))

                print("[SubAgentRunner:\(definition.id)] \(call.name): \(result.isError ? "ERROR" : "OK") (\(result.output.count) chars)")
            }
            lastToolOutputs = iterationOutputs
        }

        return accumulatedResponse
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
