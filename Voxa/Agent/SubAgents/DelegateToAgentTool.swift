import Foundation

/// Built-in tool that allows the main agent to delegate tasks to specialized sub-agents.
final class DelegateToAgentTool: AgentTool, @unchecked Sendable {
    let name = "delegate_to_agent"
    let parameters: [ToolParameter] = [
        ToolParameter(
            name: "agent",
            type: "string",
            description: "The sub-agent ID to delegate to."
        ),
        ToolParameter(
            name: "task",
            type: "string",
            description: "A clear description of the task for the sub-agent to perform."
        ),
    ]

    weak var subAgentManager: SubAgentManager?

    /// Set before each processing cycle so sub-agent activity shows in the UI.
    var activeCallbacks: AgentCallbacks = .none

    /// Trace entries from the last sub-agent delegation, read by AgentExecutor after execution.
    private(set) var lastDelegationTrace: [TraceEntry] = []

    /// Called with each sub-agent trace entry as it happens, for live trace display.
    var onSubAgentTraceEntry: ((_ agentId: String, _ entry: TraceEntry) -> Void)?

    /// Dynamic description listing available agents from loaded definitions.
    var description: String {
        guard let manager = subAgentManager else {
            return "Delegate a task to a specialized sub-agent."
        }
        let agentList = manager.enabledDefinitions
            .map { agent -> String in
                let mcpInfo = agent.mcpServers.isEmpty ? "no MCPs" : "\(agent.mcpServers.count) MCP(s)"
                return "'\(agent.id)' — \(agent.description) [\(mcpInfo)]"
            }
            .joined(separator: "; ")
        if agentList.isEmpty {
            return "Delegate a task to a specialized sub-agent. No agents currently enabled."
        }
        return "Delegate a task to a specialized sub-agent. Available: \(agentList)"
    }

    init(subAgentManager: SubAgentManager? = nil) {
        self.subAgentManager = subAgentManager
    }

    func execute(arguments: [String: Any]) async throws -> ToolResult {
        guard let agentId = arguments["agent"] as? String else {
            throw ToolError.invalidArguments("Missing required parameter 'agent'")
        }
        guard let task = arguments["task"] as? String else {
            throw ToolError.invalidArguments("Missing required parameter 'task'")
        }
        guard let manager = subAgentManager else {
            return .error("Sub-agent system not available")
        }

        do {
            let delegation = try await manager.delegate(
                agentId: agentId,
                task: task,
                callbacks: activeCallbacks,
                onTraceEntry: { [weak self] entry in
                    self?.onSubAgentTraceEntry?(agentId, entry)
                }
            )
            lastDelegationTrace = delegation.traceEntries
            return .success(delegation.response.isEmpty ? "(sub-agent completed with no output)" : delegation.response)
        } catch let error as SubAgentError {
            return .error(error.localizedDescription)
        } catch is CancellationError {
            return .error("Sub-agent task was cancelled")
        } catch {
            return .error("Sub-agent error: \(error.localizedDescription)")
        }
    }
}
