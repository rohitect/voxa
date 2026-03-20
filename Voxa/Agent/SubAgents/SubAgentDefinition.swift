import Foundation

/// Describes a sub-agent parsed from an agents.md file.
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

    /// The file path this definition was loaded from (nil for unsaved new agents).
    var filePath: String?

    init(
        id: String,
        name: String,
        description: String,
        systemPrompt: String,
        mcpServers: [String] = [],
        providerOverride: String? = nil,
        modelOverride: String? = nil,
        timeout: TimeInterval = 60,
        maxToolCalls: Int = 5,
        isEnabled: Bool = true,
        filePath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.systemPrompt = systemPrompt
        self.mcpServers = mcpServers
        self.providerOverride = providerOverride
        self.modelOverride = modelOverride
        self.timeout = timeout
        self.maxToolCalls = maxToolCalls
        self.isEnabled = isEnabled
        self.filePath = filePath
    }
}

// MARK: - agents.md Parser

extension SubAgentDefinition {

    /// Directory where agents.md files live: ~/.voxa/agent/agents/
    static var agentsDirectory: URL {
        Constants.dataDirectory
            .appendingPathComponent("agent", isDirectory: true)
            .appendingPathComponent("agents", isDirectory: true)
    }

    /// Load all sub-agent definitions from ~/.voxa/agent/agents/*.md
    static func loadAll() -> [SubAgentDefinition] {
        let dir = agentsDirectory

        // Ensure directory exists
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        )) ?? []

        let mdFiles = files.filter { $0.pathExtension == "md" }

        // Bootstrap defaults if no agents.md files exist yet
        if mdFiles.isEmpty {
            bootstrapDefaults(in: dir)
            // Re-read after bootstrap
            guard let bootstrapped = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil
            ) else { return [] }
            return bootstrapped.compactMap { url -> SubAgentDefinition? in
                guard url.pathExtension == "md" else { return nil }
                guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                return parse(markdown: content, filePath: url.path)
            }
        }

        return mdFiles.compactMap { url -> SubAgentDefinition? in
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return parse(markdown: content, filePath: url.path)
        }
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

        enum Section { case none, description, config, instructions }
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
            providerOverride: providerOverride,
            modelOverride: modelOverride,
            timeout: timeout,
            maxToolCalls: maxToolCalls,
            isEnabled: isEnabled,
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
        md += "- Timeout: \(Int(timeout))\n"
        md += "- Max tool calls: \(maxToolCalls)\n"
        if let provider = providerOverride {
            md += "- Provider: \(provider)\n"
        }
        if let model = modelOverride {
            md += "- Model: \(model)\n"
        }
        md += "- Enabled: \(isEnabled)\n"
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

    // MARK: - Default Agents (bootstrapped on first launch)

    private static func bootstrapDefaults(in directory: URL) {
        let computerAgent = SubAgentDefinition(
            id: "computer",
            name: "Computer",
            description: "Full computer control — launches apps, changes settings, searches files, captures screen, runs commands, automates UI.",
            systemPrompt: """
                You are a macOS computer control agent. You help users accomplish tasks on their Mac.

                Execute actions directly — don't describe steps, just do them. \
                Chain multiple tools when needed to accomplish complex tasks. \
                If something fails, try an alternative approach.

                Be concise in your responses since this is a voice interface.
                """,
            timeout: 120,
            maxToolCalls: 10
        )

        let writerAgent = SubAgentDefinition(
            id: "writer",
            name: "Writer",
            description: "Drafts and refines text, places results on the clipboard.",
            systemPrompt: """
                You are a writing assistant agent. You help users draft, edit, and refine text. \
                Place your final output on the clipboard so the user can paste it.

                Match the user's tone and style. Be concise unless asked for longer form content.
                """,
            timeout: 30,
            maxToolCalls: 2
        )

        for agent in [computerAgent, writerAgent] {
            let url = directory.appendingPathComponent("\(agent.id).md")
            try? agent.toMarkdown().write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
