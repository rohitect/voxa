import Foundation

/// Manages registered LLM providers, active selection, and per-provider model choices.
@Observable
final class LLMProviderManager {
    /// All registered providers, keyed by name.
    private(set) var providers: [String: any LLMProvider] = [:]

    /// Name of the currently active provider (persisted).
    var activeProviderName: String {
        didSet { UserDefaults.standard.set(activeProviderName, forKey: "agent.activeProvider") }
    }

    /// Per-provider selected model (persisted).
    private(set) var modelSelections: [String: String] = [:]

    /// The currently active provider instance.
    var activeProvider: (any LLMProvider)? {
        providers[activeProviderName]
    }

    /// The model selected for the active provider.
    var activeModel: String {
        modelSelections[activeProviderName] ?? activeProvider?.defaultModel ?? ""
    }

    /// Ordered list of provider names for UI display.
    var availableProviderNames: [String] {
        providers.keys.sorted()
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: "agent.activeProvider") ?? "Ollama"
        self.activeProviderName = saved

        // Load persisted model selections
        if let dict = UserDefaults.standard.dictionary(forKey: "agent.modelSelections") as? [String: String] {
            self.modelSelections = dict
        }

        // Register built-in providers
        register(OllamaProvider())
        register(OpenAIProvider())
        register(GeminiProvider())
    }

    /// Register a provider. If a provider with the same name exists, it is replaced.
    func register(_ provider: any LLMProvider) {
        providers[provider.name] = provider
    }

    /// Switch the active provider.
    func setActiveProvider(_ name: String) {
        guard providers[name] != nil else { return }
        activeProviderName = name
    }

    /// Set the model for a specific provider (persisted).
    func setModel(_ model: String, for providerName: String) {
        modelSelections[providerName] = model
        UserDefaults.standard.set(modelSelections, forKey: "agent.modelSelections")
    }

    /// Get a provider by name.
    func provider(named name: String) -> (any LLMProvider)? {
        providers[name]
    }
}
