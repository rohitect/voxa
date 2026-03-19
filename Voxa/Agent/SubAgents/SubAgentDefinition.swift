import Foundation

/// Describes a sub-agent that can be delegated to by the main agent.
struct SubAgentDefinition: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let description: String
    let systemPrompt: String
    let allowedTools: [String]
    let providerOverride: String?
    let modelOverride: String?
    let timeout: TimeInterval
    let maxToolCalls: Int
    var isEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case systemPrompt = "system_prompt"
        case allowedTools = "allowed_tools"
        case providerOverride = "provider_override"
        case modelOverride = "model_override"
        case timeout
        case maxToolCalls = "max_tool_calls"
        case isEnabled = "is_enabled"
    }

    init(
        id: String,
        name: String,
        description: String,
        systemPrompt: String,
        allowedTools: [String],
        providerOverride: String? = nil,
        modelOverride: String? = nil,
        timeout: TimeInterval = 60,
        maxToolCalls: Int = 5,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.systemPrompt = systemPrompt
        self.allowedTools = allowedTools
        self.providerOverride = providerOverride
        self.modelOverride = modelOverride
        self.timeout = timeout
        self.maxToolCalls = maxToolCalls
        self.isEnabled = isEnabled
    }
}

// MARK: - Source

enum SubAgentSource: Sendable {
    case builtin
    case custom(path: String)
}

// MARK: - Built-in Definitions

extension SubAgentDefinition {
    static let builtins: [SubAgentDefinition] = [
        SubAgentDefinition(
            id: "system",
            name: "System",
            description: "Controls system settings, launches apps, and manages the clipboard.",
            systemPrompt: """
                You are a macOS system control agent. You help users change system settings, \
                launch applications, and manage clipboard content. Be direct — execute the \
                requested action immediately without asking for confirmation.
                """,
            allowedTools: ["system_settings", "app_launcher", "clipboard"],
            timeout: 30,
            maxToolCalls: 3
        ),
        SubAgentDefinition(
            id: "research",
            name: "Research",
            description: "Captures screen content, searches files, and gathers information.",
            systemPrompt: """
                You are a research agent on macOS. You help users find information by \
                capturing screen content, searching files, and reading clipboard data. \
                Summarize findings concisely.
                """,
            allowedTools: ["screen_capture", "file_search", "clipboard"],
            timeout: 60,
            maxToolCalls: 5
        ),
        SubAgentDefinition(
            id: "code",
            name: "Code",
            description: "Searches codebases and runs shell commands for development tasks.",
            systemPrompt: """
                You are a coding assistant agent on macOS. You help users with development \
                tasks by searching files and running shell commands. Always explain what \
                commands you're about to run. Prefer safe, non-destructive operations.
                """,
            allowedTools: ["file_search", "shell_command"],
            timeout: 120,
            maxToolCalls: 8
        ),
        SubAgentDefinition(
            id: "writer",
            name: "Writer",
            description: "Drafts and refines text, placing results on the clipboard.",
            systemPrompt: """
                You are a writing assistant agent. You help users draft, edit, and refine \
                text. Place your final output on the clipboard so the user can paste it. \
                Be concise and match the user's tone.
                """,
            allowedTools: ["clipboard"],
            timeout: 30,
            maxToolCalls: 2
        ),
    ]

    /// Load custom sub-agent definitions from ~/.voxa/agent/subagents/*.json
    static func loadCustomDefinitions() -> [(SubAgentDefinition, SubAgentSource)] {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".voxa/agent/subagents")

        guard FileManager.default.fileExists(atPath: dir.path) else { return [] }

        let decoder = JSONDecoder()
        var results: [(SubAgentDefinition, SubAgentSource)] = []

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else { return [] }

        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  var definition = try? decoder.decode(SubAgentDefinition.self, from: data) else {
                print("[SubAgentDefinition] Failed to load: \(file.lastPathComponent)")
                continue
            }

            // Safety: strip delegate_to_agent to prevent nesting
            let filtered = definition.allowedTools.filter { $0 != "delegate_to_agent" }
            definition = SubAgentDefinition(
                id: definition.id,
                name: definition.name,
                description: definition.description,
                systemPrompt: definition.systemPrompt,
                allowedTools: filtered,
                providerOverride: definition.providerOverride,
                modelOverride: definition.modelOverride,
                timeout: definition.timeout,
                maxToolCalls: definition.maxToolCalls,
                isEnabled: definition.isEnabled
            )

            results.append((definition, .custom(path: file.path)))
        }

        return results
    }
}
