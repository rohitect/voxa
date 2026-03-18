import Foundation

// MARK: - Tool Result

struct ToolResult: Sendable {
    let output: String
    let isError: Bool

    static func success(_ output: String) -> ToolResult {
        ToolResult(output: output, isError: false)
    }

    static func error(_ message: String) -> ToolResult {
        ToolResult(output: message, isError: true)
    }
}

// MARK: - Tool Error

enum ToolError: Error, LocalizedError {
    case invalidArguments(String)
    case executionFailed(String)
    case permissionDenied(String)
    case confirmationRequired
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let msg): return "Invalid arguments: \(msg)"
        case .executionFailed(let msg): return "Execution failed: \(msg)"
        case .permissionDenied(let msg): return "Permission denied: \(msg)"
        case .confirmationRequired: return "User confirmation required"
        case .timeout: return "Tool execution timed out"
        }
    }
}

// MARK: - Agent Tool Protocol

protocol AgentTool: Sendable {
    var name: String { get }
    var description: String { get }
    var parameters: [ToolParameter] { get }
    var requiresConfirmation: Bool { get }

    func execute(arguments: [String: Any]) async throws -> ToolResult
}

extension AgentTool {
    var requiresConfirmation: Bool { false }

    func toDefinition() -> ToolDefinition {
        ToolDefinition(name: name, description: description, parameters: parameters)
    }
}
