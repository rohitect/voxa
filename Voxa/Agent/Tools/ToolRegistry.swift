import Foundation

// MARK: - Tool Confirmation

/// A pending tool confirmation request that the UI can observe and respond to.
struct ToolConfirmationRequest: Identifiable {
    let id = UUID()
    let toolName: String
    let arguments: String
    let timestamp = Date()
}

@Observable
final class ToolRegistry {
    private(set) var tools: [String: any AgentTool] = [:]
    let settings = ToolSettings()

    /// The currently pending confirmation request, if any. Observed by the UI.
    var pendingConfirmation: ToolConfirmationRequest?

    /// Continuation to resume after user responds to confirmation.
    private var confirmationContinuation: CheckedContinuation<Bool, Never>?

    func register(_ tool: any AgentTool) {
        tools[tool.name] = tool
    }

    func tool(named name: String) -> (any AgentTool)? {
        tools[name]
    }

    var allTools: [any AgentTool] {
        tools.values.sorted { $0.name < $1.name }
    }

    var enabledDefinitions: [ToolDefinition] {
        tools.values
            .filter { settings.isEnabled($0.name) }
            .map { $0.toDefinition() }
    }

    func execute(_ toolCall: ToolCall) async throws -> ToolResult {
        guard let tool = tools[toolCall.name] else {
            return .error("Unknown tool: \(toolCall.name)")
        }

        guard settings.isEnabled(tool.name) else {
            return .error("Tool '\(tool.name)' is disabled")
        }

        // If tool requires confirmation, suspend and wait for user response
        if tool.requiresConfirmation {
            let approved = await requestConfirmation(toolName: tool.name, arguments: toolCall.arguments)
            guard approved else {
                return .error("User denied execution of '\(tool.name)'")
            }
        }

        // Parse JSON arguments
        let arguments: [String: Any]
        if toolCall.arguments.isEmpty || toolCall.arguments == "{}" {
            arguments = [:]
        } else {
            guard let data = toolCall.arguments.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .error("Failed to parse arguments as JSON")
            }
            arguments = parsed
        }

        do {
            return try await tool.execute(arguments: arguments)
        } catch let error as ToolError {
            return .error(error.localizedDescription)
        } catch {
            return .error("Tool execution failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Confirmation Flow

    /// Suspend execution and wait for user to approve or deny.
    private func requestConfirmation(toolName: String, arguments: String) async -> Bool {
        let request = ToolConfirmationRequest(toolName: toolName, arguments: arguments)

        // Post the request on the main actor so the UI can observe it
        await MainActor.run {
            self.pendingConfirmation = request
        }

        // Suspend until user responds
        let approved = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            self.confirmationContinuation = continuation
        }

        // Clear the pending request
        await MainActor.run {
            self.pendingConfirmation = nil
        }

        return approved
    }

    /// Called by the UI when the user approves the pending tool execution.
    func approveConfirmation() {
        confirmationContinuation?.resume(returning: true)
        confirmationContinuation = nil
    }

    /// Called by the UI when the user denies the pending tool execution.
    func denyConfirmation() {
        confirmationContinuation?.resume(returning: false)
        confirmationContinuation = nil
    }

    func unregister(_ name: String) {
        tools.removeValue(forKey: name)
    }

    func unregisterAll(prefix: String) {
        let keysToRemove = tools.keys.filter { $0.hasPrefix(prefix) }
        for key in keysToRemove {
            tools.removeValue(forKey: key)
        }
    }

}
