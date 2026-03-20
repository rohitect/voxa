import Foundation

/// Manages sub-agent definitions (built-in + custom from ~/.voxa/agent/agents/*.md),
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

    /// Load all definitions: built-in agents + custom agents from disk.
    func loadDefinitions() {
        definitions.removeAll()
        for def in SubAgentDefinition.loadAll() {
            definitions[def.id] = def
        }
    }

    /// Reload all definitions (built-in + custom from disk).
    func reload() {
        loadDefinitions()
    }

    /// Add or update a custom agent definition and save to disk.
    /// Built-in agents cannot be overwritten — only their enable/disable state can change.
    func save(_ definition: SubAgentDefinition) {
        guard !definition.isBuiltIn else {
            print("[SubAgentManager] Cannot save over built-in agent '\(definition.id)'")
            return
        }
        guard !SubAgentDefinition.builtInAgentIds.contains(definition.id) else {
            print("[SubAgentManager] Cannot save agent with reserved built-in ID '\(definition.id)'")
            return
        }
        var def = definition
        if def.filePath == nil {
            def.filePath = SubAgentDefinition.agentsDirectory
                .appendingPathComponent("\(def.id).md").path
        }
        def.save()
        definitions[def.id] = def
    }

    /// Delete a custom agent definition from memory and disk.
    /// Built-in agents cannot be deleted.
    func delete(_ definition: SubAgentDefinition) {
        guard !definition.isBuiltIn else {
            print("[SubAgentManager] Cannot delete built-in agent '\(definition.id)'")
            return
        }
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

    /// Built-in agents only, sorted by name.
    var builtInDefinitions: [SubAgentDefinition] {
        definitions.values.filter(\.isBuiltIn).sorted { $0.name < $1.name }
    }

    /// Custom (user-defined) agents only, sorted by name.
    var customDefinitions: [SubAgentDefinition] {
        definitions.values.filter { !$0.isBuiltIn }.sorted { $0.name < $1.name }
    }

    // MARK: - Delegation

    /// Result from a sub-agent delegation, including response and internal trace.
    struct DelegationResult {
        let response: String
        let traceEntries: [TraceEntry]
    }

    /// Delegate a task to a sub-agent. Returns the sub-agent's response and trace.
    /// - Parameter onTraceEntry: Called with each trace entry as it's created, for live trace display.
    func delegate(agentId: String, task: String, callbacks: AgentCallbacks, onTraceEntry: ((_ entry: TraceEntry) -> Void)? = nil) async throws -> DelegationResult {
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
        runner.onTraceEntry = onTraceEntry

        // Track active runner
        activeRunners[agentId] = runner
        defer { activeRunners.removeValue(forKey: agentId) }

        // Race runner against timeout
        let runResult: SubAgentRunner.RunResult = try await withThrowingTaskGroup(of: SubAgentRunner.RunResult.self) { group in
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

        return DelegationResult(response: runResult.response, traceEntries: runResult.traceEntries)
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
