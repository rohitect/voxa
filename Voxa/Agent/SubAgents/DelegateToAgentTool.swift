import Foundation

/// Built-in tool that allows the main agent to delegate tasks to specialized sub-agents.
final class DelegateToAgentTool: AgentTool, @unchecked Sendable {
    let name = "delegate_to_agent"
    let description: String
    let parameters: [ToolParameter] = [
        ToolParameter(
            name: "agent",
            type: "string",
            description: "The sub-agent ID to delegate to (e.g. 'system', 'research', 'code', 'writer')."
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

    init(subAgentManager: SubAgentManager? = nil) {
        self.subAgentManager = subAgentManager

        // Build description listing available agents
        let agentList = SubAgentDefinition.builtins
            .map { "'\($0.id)' (\($0.description))" }
            .joined(separator: ", ")
        self.description = "Delegate a task to a specialized sub-agent. Available agents: \(agentList). Custom agents may also be available."
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
            let result = try await manager.delegate(
                agentId: agentId,
                task: task,
                callbacks: activeCallbacks
            )
            return .success(result.isEmpty ? "(sub-agent completed with no output)" : result)
        } catch let error as SubAgentError {
            return .error(error.localizedDescription)
        } catch is CancellationError {
            return .error("Sub-agent task was cancelled")
        } catch {
            return .error("Sub-agent error: \(error.localizedDescription)")
        }
    }
}
