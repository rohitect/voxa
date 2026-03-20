import Foundation

struct FileWriteTool: AgentTool {
    let name = "file_write"
    let description = "Write content to a file. Creates the file if it doesn't exist, or overwrites if it does. Creates intermediate directories as needed."
    let parameters: [ToolParameter] = [
        ToolParameter(
            name: "path",
            type: "string",
            description: "Absolute path to the file to write."
        ),
        ToolParameter(
            name: "content",
            type: "string",
            description: "The text content to write to the file."
        ),
        ToolParameter(
            name: "append",
            type: "boolean",
            description: "If true, append to the file instead of overwriting. Default false.",
            required: false
        ),
        ToolParameter(
            name: "make_executable",
            type: "boolean",
            description: "If true, set the file as executable (chmod +x). Default false.",
            required: false
        ),
    ]

    func execute(arguments: [String: Any]) async throws -> ToolResult {
        guard let path = arguments["path"] as? String else {
            throw ToolError.invalidArguments("Missing required parameter 'path'")
        }
        guard let content = arguments["content"] as? String else {
            throw ToolError.invalidArguments("Missing required parameter 'content'")
        }

        let append = arguments["append"] as? Bool ?? false
        let makeExecutable = arguments["make_executable"] as? Bool ?? false
        let fileURL = URL(fileURLWithPath: path)
        let fm = FileManager.default

        // Create parent directories if needed
        let parentDir = fileURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: parentDir.path) {
            do {
                try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
            } catch {
                return .error("Failed to create directory: \(error.localizedDescription)")
            }
        }

        do {
            if append, fm.fileExists(atPath: path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                handle.seekToEndOfFile()
                if let data = content.data(using: .utf8) {
                    handle.write(data)
                }
                handle.closeFile()
            } else {
                try content.write(to: fileURL, atomically: true, encoding: .utf8)
            }

            if makeExecutable {
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
            }

            let size = (try? fm.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
            return .success("Wrote \(size) bytes to \(path)")
        } catch {
            return .error("Failed to write file: \(error.localizedDescription)")
        }
    }
}
