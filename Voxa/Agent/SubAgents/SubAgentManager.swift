import Foundation

/// Manages sub-agent definitions loaded from ~/.voxa/agent/agents/*.md,
/// active runners, and concurrency enforcement.
@Observable
final class SubAgentManager {
    /// All loaded definitions, keyed by id.
    private(set) var definitions: [String: SubAgentDefinition] = [:]

    /// Currently running sub-agent tasks.
    private(set) var activeRunners: [String: SubAgentRunner] = [:]

    private let configStore: MCPServerConfigStore
    private weak var providerManager: LLMProviderManager?

    private let maxConcurrent = 3

    init(configStore: MCPServerConfigStore, providerManager: LLMProviderManager) {
        self.configStore = configStore
        self.providerManager = providerManager
        loadDefinitions()
    }

    // MARK: - Definition Management

    /// Load all definitions from agents.md files on disk.
    func loadDefinitions() {
        definitions.removeAll()
        for def in SubAgentDefinition.loadAll() {
            definitions[def.id] = def
        }
    }

    /// Reload definitions from disk.
    func reload() {
        loadDefinitions()
    }

    /// Add or update a definition and save to disk.
    func save(_ definition: SubAgentDefinition) {
        var def = definition
        if def.filePath == nil {
            def.filePath = SubAgentDefinition.agentsDirectory
                .appendingPathComponent("\(def.id).md").path
        }
        def.save()
        definitions[def.id] = def
    }

    /// Delete a definition from memory and disk.
    func delete(_ definition: SubAgentDefinition) {
        definition.deleteFile()
        definitions.removeValue(forKey: definition.id)
    }

    // MARK: - Enable/Disable

    func isEnabled(_ agentId: String) -> Bool {
        let key = "agent.subagent.enabled.\(agentId)"
        if UserDefaults.standard.object(forKey: key) == nil {
            return definitions[agentId]?.isEnabled ?? false
        }
        return UserDefaults.standard.bool(forKey: key)
    }

    func setEnabled(_ agentId: String, enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "agent.subagent.enabled.\(agentId)")
    }

    /// All enabled definitions, sorted by name.
    var enabledDefinitions: [SubAgentDefinition] {
        definitions.values
            .filter { isEnabled($0.id) }
            .sorted { $0.name < $1.name }
    }

    /// All definitions sorted alphabetically.
    var sortedDefinitions: [SubAgentDefinition] {
        definitions.values.sorted { $0.name < $1.name }
    }

    // MARK: - Delegation

    /// Delegate a task to a sub-agent. Returns the sub-agent's final text response.
    func delegate(agentId: String, task: String, callbacks: AgentCallbacks) async throws -> String {
        guard let definition = definitions[agentId] else {
            throw SubAgentError.unknownAgent(agentId)
        }
        guard isEnabled(agentId) else {
            throw SubAgentError.agentDisabled(agentId)
        }
        guard activeRunners.count < maxConcurrent else {
            throw SubAgentError.concurrencyLimit
        }
        guard let providerManager else {
            throw SubAgentError.noProvider
        }

        // Resolve provider and model
        let provider: any LLMProvider
        let model: String

        if let overrideName = definition.providerOverride,
           let overrideProvider = providerManager.provider(named: overrideName) {
            provider = overrideProvider
            model = definition.modelOverride ?? overrideProvider.defaultModel
        } else {
            guard let activeProvider = providerManager.activeProvider else {
                throw SubAgentError.noProvider
            }
            provider = activeProvider
            model = definition.modelOverride ?? providerManager.activeModel
        }

        // Resolve MCP server configs for this agent
        let mcpConfigs = definition.mcpServers.compactMap { serverId in
            configStore.server(id: serverId)
        }

        let runner = SubAgentRunner(
            definition: definition,
            provider: provider,
            model: model,
            mcpConfigs: mcpConfigs
        )

        // Track active runner
        activeRunners[agentId] = runner
        defer { activeRunners.removeValue(forKey: agentId) }

        // Race runner against timeout
        let result: String = try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await runner.run(task: task, callbacks: callbacks)
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(definition.timeout * 1_000_000_000))
                throw SubAgentError.timeout(agentId)
            }

            guard let result = try await group.next() else {
                throw SubAgentError.timeout(agentId)
            }

            group.cancelAll()
            return result
        }

        return result
    }

    /// Cancel all active sub-agent runners.
    func cancelAll() {
        activeRunners.removeAll()
    }
}

// MARK: - Errors

enum SubAgentError: Error, LocalizedError {
    case unknownAgent(String)
    case agentDisabled(String)
    case concurrencyLimit
    case noProvider
    case timeout(String)

    var errorDescription: String? {
        switch self {
        case .unknownAgent(let id):
            return "Unknown sub-agent: '\(id)'"
        case .agentDisabled(let id):
            return "Sub-agent '\(id)' is disabled"
        case .concurrencyLimit:
            return "Maximum concurrent sub-agents reached (3)"
        case .noProvider:
            return "No LLM provider available for sub-agent"
        case .timeout(let id):
            return "Sub-agent '\(id)' timed out"
        }
    }
}
