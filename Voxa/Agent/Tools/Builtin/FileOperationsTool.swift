import Foundation

struct FileOperationsTool: AgentTool {
    let name = "file_operations"
    let description = "File operations: get file metadata, move, copy, or delete files and directories."
    let parameters: [ToolParameter] = [
        ToolParameter(
            name: "action",
            type: "string",
            description: "The file operation to perform.",
            enumValues: ["file_info", "move", "copy", "delete"]
        ),
        ToolParameter(
            name: "path",
            type: "string",
            description: "Path to the file or directory."
        ),
        ToolParameter(
            name: "destination",
            type: "string",
            description: "Destination path (for move and copy actions).",
            required: false
        ),
    ]

    var requiresConfirmation: Bool { true }

    func execute(arguments: [String: Any]) async throws -> ToolResult {
        guard let action = arguments["action"] as? String else {
            throw ToolError.invalidArguments("Missing required parameter 'action'")
        }
        guard let path = arguments["path"] as? String else {
            throw ToolError.invalidArguments("Missing required parameter 'path'")
        }

        let expandedPath = (path as NSString).expandingTildeInPath

        switch action {
        case "file_info":
            return fileInfo(path: expandedPath)
        case "move":
            return try moveFile(path: expandedPath, arguments: arguments)
        case "copy":
            return try copyFile(path: expandedPath, arguments: arguments)
        case "delete":
            return deleteFile(path: expandedPath)
        default:
            throw ToolError.invalidArguments("Unknown action: \(action)")
        }
    }

    // MARK: - File Info

    private func fileInfo(path: String) -> ToolResult {
        let fm = FileManager.default

        guard fm.fileExists(atPath: path) else {
            return .error("File not found: \(path)")
        }

        guard let attrs = try? fm.attributesOfItem(atPath: path) else {
            return .error("Failed to read attributes for: \(path)")
        }

        var output = "File: \(path)\n"

        if let type = attrs[.type] as? FileAttributeType {
            let typeStr: String = switch type {
            case .typeRegular: "Regular File"
            case .typeDirectory: "Directory"
            case .typeSymbolicLink: "Symbolic Link"
            default: "\(type)"
            }
            output += "Type: \(typeStr)\n"
        }

        if let size = attrs[.size] as? UInt64 {
            output += "Size: \(formatBytes(size))\n"
        }

        if let created = attrs[.creationDate] as? Date {
            output += "Created: \(formatDate(created))\n"
        }

        if let modified = attrs[.modificationDate] as? Date {
            output += "Modified: \(formatDate(modified))\n"
        }

        if let owner = attrs[.ownerAccountName] as? String {
            output += "Owner: \(owner)\n"
        }

        if let posix = attrs[.posixPermissions] as? Int {
            output += "Permissions: \(String(posix, radix: 8))\n"
        }

        // For directories, show item count
        if (attrs[.type] as? FileAttributeType) == .typeDirectory {
            if let contents = try? fm.contentsOfDirectory(atPath: path) {
                output += "Items: \(contents.count)\n"
            }
        }

        return .success(output)
    }

    // MARK: - Move

    private func moveFile(path: String, arguments: [String: Any]) throws -> ToolResult {
        guard let dest = arguments["destination"] as? String else {
            throw ToolError.invalidArguments("Missing required parameter 'destination' for move")
        }
        let expandedDest = (dest as NSString).expandingTildeInPath

        guard FileManager.default.fileExists(atPath: path) else {
            return .error("Source not found: \(path)")
        }

        do {
            try FileManager.default.moveItem(atPath: path, toPath: expandedDest)
            return .success("Moved \(path) → \(expandedDest)")
        } catch {
            return .error("Move failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Copy

    private func copyFile(path: String, arguments: [String: Any]) throws -> ToolResult {
        guard let dest = arguments["destination"] as? String else {
            throw ToolError.invalidArguments("Missing required parameter 'destination' for copy")
        }
        let expandedDest = (dest as NSString).expandingTildeInPath

        guard FileManager.default.fileExists(atPath: path) else {
            return .error("Source not found: \(path)")
        }

        do {
            try FileManager.default.copyItem(atPath: path, toPath: expandedDest)
            return .success("Copied \(path) → \(expandedDest)")
        } catch {
            return .error("Copy failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Delete

    private func deleteFile(path: String) -> ToolResult {
        guard FileManager.default.fileExists(atPath: path) else {
            return .error("File not found: \(path)")
        }

        do {
            try FileManager.default.removeItem(atPath: path)
            return .success("Deleted \(path)")
        } catch {
            return .error("Delete failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Formatting Helpers

    private func formatBytes(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unitIndex = 0
        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        if unitIndex == 0 {
            return "\(bytes) B"
        }
        return String(format: "%.1f %@ (%llu bytes)", value, units[unitIndex], bytes)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}
