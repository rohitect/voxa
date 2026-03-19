import Foundation
import MCP

/// Bridges an MCP server tool into the AgentTool protocol so it can be
/// registered in ToolRegistry alongside built-in tools.
struct MCPToolAdapter: AgentTool, @unchecked Sendable {
    let name: String
    let description: String
    let parameters: [ToolParameter]

    private let serverName: String
    private let mcpToolName: String
    private let connection: MCPConnection

    init(serverName: String, mcpTool: MCP.Tool, connection: MCPConnection) {
        self.serverName = serverName
        self.mcpToolName = mcpTool.name
        self.name = "\(serverName).\(mcpTool.name)"
        self.description = mcpTool.description ?? "MCP tool from \(serverName)"
        self.parameters = MCPTypes.toolParameters(from: mcpTool)
        self.connection = connection
    }

    func execute(arguments: [String: Any]) async throws -> ToolResult {
        do {
            let output = try await connection.callTool(name: mcpToolName, arguments: arguments)
            return .success(output)
        } catch let error as ToolError {
            throw error
        } catch {
            return .error("MCP tool '\(name)' failed: \(error.localizedDescription)")
        }
    }
}
