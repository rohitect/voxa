import Foundation

/// A named category of tools with an SF Symbol icon, used for grouping tools in the UI.
struct ToolCategory: Sendable, Equatable {
    let name: String
    let icon: String
    let tools: [String]
}

/// Describes a sub-agent — either a built-in (hardcoded) or a custom agent loaded from an agents.md file.
struct SubAgentDefinition: Identifiable, Sendable {
    let id: String
    var name: String
    var description: String
    var systemPrompt: String
    var mcpServers: [String]
    var providerOverride: String?
    var modelOverride: String?
    var timeout: TimeInterval
    var maxToolCalls: Int
    var isEnabled: Bool

    /// Whether this is a built-in agent (cannot be deleted).
    var isBuiltIn: Bool

    /// The file path this definition was loaded from (nil for unsaved new agents).
    var filePath: String?

    /// Names of builtin tools to attach directly (not via MCP).
    var builtinTools: [String]

    /// Optional tool categories for grouping tools in the UI.
    /// When non-empty, tools are displayed grouped by category instead of a flat list.
    var toolCategories: [ToolCategory]

    init(
        id: String,
        name: String,
        description: String,
        systemPrompt: String,
        mcpServers: [String] = [],
        builtinTools: [String] = [],
        toolCategories: [ToolCategory] = [],
        providerOverride: String? = nil,
        modelOverride: String? = nil,
        timeout: TimeInterval = 60,
        maxToolCalls: Int = 5,
        isEnabled: Bool = true,
        isBuiltIn: Bool = false,
        filePath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.systemPrompt = systemPrompt
        self.mcpServers = mcpServers
        self.builtinTools = builtinTools
        self.toolCategories = toolCategories
        self.providerOverride = providerOverride
        self.modelOverride = modelOverride
        self.timeout = timeout
        self.maxToolCalls = maxToolCalls
        self.isEnabled = isEnabled
        self.isBuiltIn = isBuiltIn
        self.filePath = filePath
    }
}

// MARK: - agents.md Parser

extension SubAgentDefinition {

    /// IDs of built-in agents. Must be kept in sync with `builtInAgents`.
    /// This is a static constant (not derived) to avoid infinite recursion,
    /// since `computerUseAgent` → `parse()` → `builtInAgentIds` would otherwise
    /// trigger `builtInAgents` → `computerUseAgent` again.
    static let builtInAgentIds: Set<String> = ["computer_use_agent"]

    /// Directory where agents.md files live: ~/.voxa/agent/agents/
    static var agentsDirectory: URL {
        Constants.dataDirectory
            .appendingPathComponent("agent", isDirectory: true)
            .appendingPathComponent("agents", isDirectory: true)
    }

    /// Load all sub-agent definitions: hardcoded built-ins + user-defined from ~/.voxa/agent/agents/*.md
    static func loadAll() -> [SubAgentDefinition] {
        // Start with hardcoded built-in agents
        var agents = builtInAgents

        // Load user-defined agents from disk
        let dir = agentsDirectory
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        )) ?? []

        let builtInIds = Set(builtInAgents.map(\.id))

        for url in files where url.pathExtension == "md" {
            guard let content = try? String(contentsOf: url, encoding: .utf8),
                  let parsed = parse(markdown: content, filePath: url.path) else { continue }
            // Skip any user file that collides with a built-in agent ID
            if builtInIds.contains(parsed.id) { continue }
            agents.append(parsed)
        }

        return agents
    }

    /// Parse a single agents.md file into a SubAgentDefinition.
    ///
    /// Expected format (following agents.md standard — plain markdown):
    /// ```markdown
    /// # Agent Name
    ///
    /// One-line description of what this agent does.
    ///
    /// ## Config
    /// - ID: computer
    /// - MCP Servers: server-id-1, server-id-2
    /// - Timeout: 120
    /// - Max tool calls: 10
    /// - Provider: ollama
    /// - Model: llama3.2
    ///
    /// ## Instructions
    ///
    /// You are a macOS computer control agent. You help users...
    /// (free-form markdown — this becomes the system prompt)
    /// ```
    static func parse(markdown: String, filePath: String? = nil) -> SubAgentDefinition? {
        let lines = markdown.components(separatedBy: "\n")
        guard !lines.isEmpty else { return nil }

        // Parse # Title
        var name = ""
        var description = ""
        var configLines: [String] = []
        var instructionLines: [String] = []
        var categoryLines: [String] = []

        enum Section { case none, description, config, instructions, toolCategories }
        var currentSection: Section = .none

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // # Title
            if trimmed.hasPrefix("# ") && !trimmed.hasPrefix("## ") {
                name = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                currentSection = .description
                continue
            }

            // ## Config
            if trimmed.lowercased().hasPrefix("## config") {
                currentSection = .config
                continue
            }

            // ## Tool Categories
            if trimmed.lowercased().hasPrefix("## tool categories") {
                currentSection = .toolCategories
                continue
            }

            // ## Instructions (or ## System Prompt, ## Prompt)
            let lower = trimmed.lowercased()
            if lower.hasPrefix("## instructions") || lower.hasPrefix("## system prompt") || lower.hasPrefix("## prompt") {
                currentSection = .instructions
                continue
            }

            // Any other ## heading resets to none
            if trimmed.hasPrefix("## ") {
                currentSection = .none
                continue
            }

            switch currentSection {
            case .description:
                if !trimmed.isEmpty && description.isEmpty {
                    description = trimmed
                }
            case .config:
                if trimmed.hasPrefix("- ") {
                    configLines.append(String(trimmed.dropFirst(2)))
                }
            case .toolCategories:
                if trimmed.hasPrefix("- ") {
                    categoryLines.append(String(trimmed.dropFirst(2)))
                }
            case .instructions:
                instructionLines.append(line)
            case .none:
                break
            }
        }

        guard !name.isEmpty else { return nil }

        // Parse config key-value pairs
        var id = name.lowercased().replacingOccurrences(of: " ", with: "_")
        var mcpServerIds: [String] = []
        var timeout: TimeInterval = 60
        var maxToolCalls = 5
        var providerOverride: String?
        var modelOverride: String?
        var isEnabled = true
        var builtinToolNames: [String] = []

        for configLine in configLines {
            let parts = configLine.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespaces)

            switch key {
            case "id":
                id = value.lowercased().replacingOccurrences(of: " ", with: "_")
            case "mcp servers", "mcp_servers":
                mcpServerIds = value.split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
            case "builtin tools", "builtin_tools":
                builtinToolNames = value.split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
            case "timeout":
                timeout = TimeInterval(value) ?? 60
            case "max tool calls", "max_tool_calls":
                maxToolCalls = Int(value) ?? 5
            case "provider":
                providerOverride = value.isEmpty ? nil : value
            case "model":
                modelOverride = value.isEmpty ? nil : value
            case "enabled":
                isEnabled = value.lowercased() != "false"
            default:
                break
            }
        }

        // Parse tool categories
        // Format: "Category Name [sf.symbol]: tool1, tool2, tool3"
        var toolCategories: [ToolCategory] = []
        for catLine in categoryLines {
            // Split on ":" to get name+icon and tools
            let catParts = catLine.split(separator: ":", maxSplits: 1)
            guard catParts.count == 2 else { continue }

            let nameAndIcon = catParts[0].trimmingCharacters(in: .whitespaces)
            let toolsStr = catParts[1].trimmingCharacters(in: .whitespaces)

            // Extract icon from [brackets] if present
            var categoryName = nameAndIcon
            var icon = "wrench"
            if let bracketStart = nameAndIcon.firstIndex(of: "["),
               let bracketEnd = nameAndIcon.firstIndex(of: "]"),
               bracketStart < bracketEnd {
                icon = String(nameAndIcon[nameAndIcon.index(after: bracketStart)..<bracketEnd])
                categoryName = String(nameAndIcon[..<bracketStart]).trimmingCharacters(in: .whitespaces)
            }

            let tools = toolsStr.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
            }

            if !tools.isEmpty {
                toolCategories.append(ToolCategory(name: categoryName, icon: icon, tools: tools))
            }
        }

        // Build system prompt from instructions section
        let systemPrompt = instructionLines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return SubAgentDefinition(
            id: id,
            name: name,
            description: description,
            systemPrompt: systemPrompt,
            mcpServers: mcpServerIds,
            builtinTools: builtinToolNames,
            toolCategories: toolCategories,
            providerOverride: providerOverride,
            modelOverride: modelOverride,
            timeout: timeout,
            maxToolCalls: maxToolCalls,
            isEnabled: isEnabled,
            isBuiltIn: builtInAgentIds.contains(id),
            filePath: filePath
        )
    }

    /// Serialize this definition back to agents.md markdown format.
    func toMarkdown() -> String {
        var md = "# \(name)\n\n"
        md += "\(description)\n\n"
        md += "## Config\n"
        md += "- ID: \(id)\n"
        if !mcpServers.isEmpty {
            md += "- MCP Servers: \(mcpServers.joined(separator: ", "))\n"
        }
        if !builtinTools.isEmpty {
            md += "- Builtin Tools: \(builtinTools.joined(separator: ", "))\n"
        }
        md += "- Timeout: \(Int(timeout))\n"
        md += "- Max tool calls: \(maxToolCalls)\n"
        if let provider = providerOverride {
            md += "- Provider: \(provider)\n"
        }
        if let model = modelOverride {
            md += "- Model: \(model)\n"
        }
        md += "- Enabled: \(isEnabled)\n"
        if !toolCategories.isEmpty {
            md += "\n## Tool Categories\n"
            for cat in toolCategories {
                md += "- \(cat.name) [\(cat.icon)]: \(cat.tools.joined(separator: ", "))\n"
            }
        }
        md += "\n## Instructions\n\n"
        md += systemPrompt + "\n"
        return md
    }

    /// Save this definition to its file (or create a new file).
    func save() {
        let dir = Self.agentsDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let url: URL
        if let path = filePath {
            url = URL(fileURLWithPath: path)
        } else {
            url = dir.appendingPathComponent("\(id).md")
        }

        try? toMarkdown().write(to: url, atomically: true, encoding: .utf8)
    }

    /// Delete this definition's file from disk.
    func deleteFile() {
        guard let path = filePath else { return }
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - Built-in Agents

    /// Load the Computer Use Agent from the bundled `computer_use_agent.md` resource.
    /// Falls back to a minimal hardcoded definition if the resource is missing or unparseable.
    static var computerUseAgent: SubAgentDefinition {
        if let url = Bundle.main.url(forResource: "computer_use_agent", withExtension: "md"),
           let content = try? String(contentsOf: url, encoding: .utf8),
           var parsed = parse(markdown: content, filePath: url.path) {
            parsed.isBuiltIn = true
            return parsed
        }

        // Fallback — should never happen in a properly bundled app
        return SubAgentDefinition(
            id: "computer_use_agent",
            name: "Computer Use Agent",
            description: "Full computer control — launches apps, changes settings, searches files, captures screen, runs commands, automates UI.",
            systemPrompt: "You are a macOS computer control agent. You help users accomplish tasks on their Mac by directly interacting with the system using your tools.",
            builtinTools: [
                "screen_capture", "ui_automation", "mouse", "keyboard", "clipboard",
                "file_read", "file_write", "list_directory", "file_search", "file_operations",
                "app_launcher", "window_management", "system_settings",
                "shell_command", "applescript", "shortcuts", "system_info", "notification"
            ],
            timeout: 120,
            maxToolCalls: 15,
            isEnabled: true,
            isBuiltIn: true
        )
    }

    /// All built-in agents.
    static var builtInAgents: [SubAgentDefinition] {
        [computerUseAgent]
    }
}
