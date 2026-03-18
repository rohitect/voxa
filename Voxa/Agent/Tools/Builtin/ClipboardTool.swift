import AppKit
import Foundation

struct ClipboardTool: AgentTool {
    let name = "clipboard"
    let description = "Read from or write to the system clipboard."
    let parameters: [ToolParameter] = [
        ToolParameter(
            name: "action",
            type: "string",
            description: "The action to perform.",
            enumValues: ["read", "write"]
        ),
        ToolParameter(
            name: "text",
            type: "string",
            description: "The text to write to clipboard (required for write action).",
            required: false
        ),
    ]

    func execute(arguments: [String: Any]) async throws -> ToolResult {
        guard let action = arguments["action"] as? String else {
            throw ToolError.invalidArguments("Missing required parameter 'action'")
        }

        switch action {
        case "read":
            let text = await MainActor.run {
                NSPasteboard.general.string(forType: .string)
            }
            return .success(text ?? "(clipboard is empty or contains non-text content)")

        case "write":
            guard let text = arguments["text"] as? String else {
                throw ToolError.invalidArguments("Missing required parameter 'text' for write action")
            }
            await MainActor.run {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
            return .success("Wrote \(text.count) characters to clipboard")

        default:
            throw ToolError.invalidArguments("Unknown action: \(action). Use 'read' or 'write'.")
        }
    }
}
