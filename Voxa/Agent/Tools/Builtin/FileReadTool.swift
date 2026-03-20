import Foundation

struct FileReadTool: AgentTool {
    let name = "file_read"
    let description = "Read the contents of a file. Returns the text content of the file."
    let parameters: [ToolParameter] = [
        ToolParameter(
            name: "path",
            type: "string",
            description: "Absolute path to the file to read."
        ),
        ToolParameter(
            name: "max_lines",
            type: "integer",
            description: "Maximum number of lines to return (default: all). Useful for large files.",
            required: false
        ),
        ToolParameter(
            name: "offset",
            type: "integer",
            description: "Line number to start reading from (0-based, default 0).",
            required: false
        ),
    ]

    func execute(arguments: [String: Any]) async throws -> ToolResult {
        guard let path = arguments["path"] as? String else {
            throw ToolError.invalidArguments("Missing required parameter 'path'")
        }

        let maxLines = (arguments["max_lines"] as? Int) ?? (arguments["max_lines"] as? Double).map { Int($0) }
        let offset = (arguments["offset"] as? Int) ?? (arguments["offset"] as? Double).map { Int($0) } ?? 0

        guard FileManager.default.fileExists(atPath: path) else {
            return .error("File not found: \(path)")
        }

        do {
            let content = try String(contentsOfFile: path, encoding: .utf8)

            if maxLines != nil || offset > 0 {
                var lines = content.components(separatedBy: .newlines)
                if offset > 0 {
                    lines = Array(lines.dropFirst(offset))
                }
                if let max = maxLines {
                    lines = Array(lines.prefix(max))
                }
                let result = lines.joined(separator: "\n")
                return .success(truncate(result))
            }

            return .success(truncate(content))
        } catch {
            return .error("Failed to read file: \(error.localizedDescription)")
        }
    }

    private func truncate(_ text: String, maxLength: Int = 4000) -> String {
        if text.count <= maxLength { return text }
        let truncated = String(text.prefix(maxLength))
        return truncated + "\n...(truncated)"
    }
}
