import Foundation

/// Manages sub-agent definitions, active runners, and concurrency enforcement.
@Observable
final class SubAgentManager {
    /// All loaded definitions (builtin + custom), keyed by id.
    private(set) var definitions: [String: SubAgentDefinition] = [:]

    /// Sources for each definition.
    private(set) var sources: [String: SubAgentSource] = [:]

    /// Currently running sub-agent tasks.
    private(set) var activeRunners: [String: SubAgentRunner] = [:]

    private weak var parentRegistry: ToolRegistry?
    private weak var providerManager: LLMProviderManager?

    private let maxConcurrent = 3

    init(parentRegistry: ToolRegistry, providerManager: LLMProviderManager) {
        self.parentRegistry = parentRegistry
        self.providerManager = providerManager
        loadDefinitions()
    }

    // MARK: - Definition Management

    func loadDefinitions() {
        // Load builtins
        for def in SubAgentDefinition.builtins {
            definitions[def.id] = def
            sources[def.id] = .builtin
        }

        // Load custom
        for (def, source) in SubAgentDefinition.loadCustomDefinitions() {
            definitions[def.id] = def
            sources[def.id] = source
        }
    }

    /// Reload only custom definitions from disk.
    func reloadCustom() {
        // Remove existing custom definitions
        let customIds = sources.filter {
            if case .custom = $0.value { return true }
            return false
        }.map(\.key)

        for id in customIds {
            definitions.removeValue(forKey: id)
            sources.removeValue(forKey: id)
        }

        // Reload
        for (def, source) in SubAgentDefinition.loadCustomDefinitions() {
            definitions[def.id] = def
            sources[def.id] = source
        }
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

    /// All definitions sorted: builtins first, then custom, each alphabetical.
    var sortedDefinitions: [SubAgentDefinition] {
        let builtins = definitions.values
            .filter { sources[$0.id] == .builtin }
            .sorted { $0.name < $1.name }
        let custom = definitions.values
            .filter {
                if case .custom = sources[$0.id] { return true }
                return false
            }
            .sorted { $0.name < $1.name }
        return builtins + custom
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
        guard let parentRegistry, let providerManager else {
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

        let runner = SubAgentRunner(
            definition: definition,
            provider: provider,
            model: model,
            parentRegistry: parentRegistry
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

            // First to complete wins
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

// MARK: - Sub-Agent Source Equatable

extension SubAgentSource: Equatable {
    static func == (lhs: SubAgentSource, rhs: SubAgentSource) -> Bool {
        switch (lhs, rhs) {
        case (.builtin, .builtin): return true
        case (.custom(let a), .custom(let b)): return a == b
        default: return false
        }
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
