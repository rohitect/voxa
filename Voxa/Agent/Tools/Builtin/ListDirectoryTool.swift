import Foundation

struct ListDirectoryTool: AgentTool {
    let name = "list_directory"
    let description = "List files and directories at a given path. Shows names, sizes, and types."
    let parameters: [ToolParameter] = [
        ToolParameter(
            name: "path",
            type: "string",
            description: "Absolute path to the directory to list. Defaults to home directory.",
            required: false
        ),
        ToolParameter(
            name: "show_hidden",
            type: "boolean",
            description: "Include hidden files (starting with dot). Default false.",
            required: false
        ),
    ]

    func execute(arguments: [String: Any]) async throws -> ToolResult {
        let path = (arguments["path"] as? String) ?? NSHomeDirectory()
        let showHidden = arguments["show_hidden"] as? Bool ?? false

        let fm = FileManager.default

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return .error("Not a directory: \(path)")
        }

        do {
            let items = try fm.contentsOfDirectory(atPath: path)
            let filtered = showHidden ? items : items.filter { !$0.hasPrefix(".") }
            let sorted = filtered.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

            var lines: [String] = []
            for item in sorted {
                let fullPath = (path as NSString).appendingPathComponent(item)
                var itemIsDir: ObjCBool = false
                fm.fileExists(atPath: fullPath, isDirectory: &itemIsDir)

                if itemIsDir.boolValue {
                    lines.append("📁 \(item)/")
                } else {
                    let attrs = try? fm.attributesOfItem(atPath: fullPath)
                    let size = attrs?[.size] as? Int ?? 0
                    lines.append("   \(item)  (\(formatSize(size)))")
                }
            }

            if lines.isEmpty {
                return .success("(empty directory)")
            }

            let header = "\(path) — \(sorted.count) items"
            return .success(header + "\n" + lines.joined(separator: "\n"))
        } catch {
            return .error("Failed to list directory: \(error.localizedDescription)")
        }
    }

    private func formatSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }
}
