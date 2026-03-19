import Foundation

@Observable
final class ToolRegistry {
    private(set) var tools: [String: any AgentTool] = [:]
    let settings = ToolSettings()

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

        if tool.requiresConfirmation {
            return .error("Tool '\(tool.name)' requires user confirmation (not yet available)")
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

    func unregister(_ name: String) {
        tools.removeValue(forKey: name)
    }

    func unregisterAll(prefix: String) {
        let keysToRemove = tools.keys.filter { $0.hasPrefix(prefix) }
        for key in keysToRemove {
            tools.removeValue(forKey: key)
        }
    }

    func registerBuiltinTools() {
        register(SystemSettingsTool())
        register(ClipboardTool())
        register(AppLauncherTool())
        register(FileSearchTool())
        register(ScreenCaptureTool())
        register(UIAutomationTool())
        register(ShellCommandTool())
    }
}
