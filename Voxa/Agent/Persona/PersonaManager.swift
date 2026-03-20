import Foundation

/// Orchestrates the agent's identity, memory, and learning system.
/// Manages files at ~/.voxa/agent/ (soul.md, identity.md, memory/, logs/).
@Observable
final class PersonaManager {
    let memoryStore: SemanticMemoryStore
    let dailyLogger: DailyLogger
    let extractor: MemoryExtractor

    private let agentDirectory: URL

    /// Whether memory extraction runs automatically after each session.
    var autoExtract: Bool {
        get { UserDefaults.standard.bool(forKey: "persona.autoExtract") }
        set { UserDefaults.standard.set(newValue, forKey: "persona.autoExtract") }
    }

    init(providerManager: LLMProviderManager) {
        let dir = Constants.dataDirectory.appendingPathComponent("agent", isDirectory: true)
        self.agentDirectory = dir

        // Ensure directory structure
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        self.memoryStore = SemanticMemoryStore(agentDirectory: dir)
        self.dailyLogger = DailyLogger(agentDirectory: dir)
        self.extractor = MemoryExtractor(providerManager: providerManager)

        // Default autoExtract to true on first launch
        if UserDefaults.standard.object(forKey: "persona.autoExtract") == nil {
            UserDefaults.standard.set(true, forKey: "persona.autoExtract")
        }

        // Bootstrap default files if first launch
        bootstrapIfNeeded()
    }

    // MARK: - Identity Files (User-Editable)

    /// Read soul.md — the agent's personality and voice.
    var soul: String {
        readFile("soul.md") ?? Self.defaultSoul
    }

    /// Read identity.md — the agent's name and vibe.
    var identity: String {
        readFile("identity.md") ?? Self.defaultIdentity
    }

    /// The agent's display name, parsed from identity.md ("- Name: <value>").
    var agentName: String {
        for line in identity.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("- name:") {
                return String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            }
        }
        return "Voxa"
    }

    // MARK: - System Prompt Building

    /// Build the full system prompt with identity, memory, and context.
    func buildSystemPrompt(toolNames: [String], sessionContext: String) -> String {
        var sections: [String] = []

        // 1. Identity + Soul
        sections.append(identity)
        sections.append(soul)

        // 2. Relevant memories (retrieved by context relevance)
        let memories = memoryStore.relevantMemoriesFormatted(context: sessionContext)
        if !memories.isEmpty {
            sections.append(memories)
        }

        // 3. Today's log (recent context)
        let todayLog = dailyLogger.todayLog()
        if !todayLog.isEmpty {
            let truncated = String(todayLog.suffix(500))
            sections.append("## Today's Activity\n\(truncated)")
        }

        // 4. Tools
        if !toolNames.isEmpty {
            let toolList = toolNames.joined(separator: ", ")
            sections.append("""
            ## Tools
            You have access to: \(toolList). \
            Use tools proactively when the user's request requires action — don't just describe steps. \
            You can chain multiple tool calls to accomplish complex tasks. \
            If a tool fails, analyze the error and try an alternative approach.
            """)
        }

        // 5. Response guidelines
        sections.append("Keep responses concise — this is a voice interface. Be direct and actionable.")

        return sections.joined(separator: "\n\n")
    }

    // MARK: - Post-Session Learning

    /// Run after a session ends. Extracts memories and logs the session.
    func learnFromSession(_ session: ChatSession) async {
        // Log the session
        let userMessages = session.messages.filter { $0.role == .user }.compactMap(\.content)
        let assistantMessages = session.messages.filter { $0.role == .assistant }.compactMap(\.content)
        let toolMessages = session.messages.filter { $0.role == .tool }

        // Collect tool names from assistant messages that had tool calls
        let toolsUsed = session.messages
            .filter { $0.role == .assistant }
            .compactMap(\.toolCalls)
            .flatMap { $0 }
            .map(\.name)

        dailyLogger.logSession(
            title: session.title,
            userMessages: userMessages,
            assistantSummary: assistantMessages.last ?? "",
            toolsUsed: Array(Set(toolsUsed))
        )

        // Extract memories (if enabled and session is non-trivial)
        guard autoExtract else { return }

        let candidates = await extractor.extract(session: session)
        if !candidates.isEmpty {
            let source = "session:\(ISO8601DateFormatter().string(from: session.createdAt))"
            memoryStore.addCandidates(candidates, source: source)
            print("[PersonaManager] Extracted \(candidates.count) memories from session '\(session.title)'")
        }
    }

    // MARK: - User Commands

    /// "What do you know about me?" — returns formatted user profile.
    func whatDoYouKnow() -> String {
        let memories = memoryStore.formattedMemories()
        if memories.isEmpty {
            return "I don't have any memories about you yet. As we chat more, I'll learn your preferences and context."
        }
        return memories
    }

    /// "Forget that" — removes the most recent memory.
    func forgetLast() -> String {
        guard let last = memoryStore.entries.last else {
            return "Nothing to forget."
        }
        let content = last.content
        memoryStore.remove(last)
        return "Forgot: \(content)"
    }

    /// "Forget everything about [topic]" — removes matching memories.
    func forget(topic: String) -> String {
        let before = memoryStore.entries.count
        memoryStore.removeMatching(topic: topic)
        let removed = before - memoryStore.entries.count
        if removed == 0 {
            return "No memories found about '\(topic)'."
        }
        return "Removed \(removed) memory(s) about '\(topic)'."
    }

    // MARK: - Bootstrap

    private func bootstrapIfNeeded() {
        let soulPath = agentDirectory.appendingPathComponent("soul.md")
        let identityPath = agentDirectory.appendingPathComponent("identity.md")

        if !FileManager.default.fileExists(atPath: soulPath.path) {
            try? Self.defaultSoul.write(to: soulPath, atomically: true, encoding: .utf8)
        }
        if !FileManager.default.fileExists(atPath: identityPath.path) {
            try? Self.defaultIdentity.write(to: identityPath, atomically: true, encoding: .utf8)
        }
    }

    private func readFile(_ name: String) -> String? {
        let url = agentDirectory.appendingPathComponent(name)
        return try? String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Defaults

    static let defaultSoul = """
    # Soul

    ## Core
    - You are a personal voice assistant for a single user
    - You run entirely on their Mac — you are local, private, and fast
    - You learn from every interaction and get better over time

    ## Voice
    - Concise: this is a voice interface, not a blog post
    - Warm but not sycophantic — no "Great question!"
    - Direct: lead with the answer, then explain if needed
    - Match the user's energy — casual when they're casual, focused when they're focused

    ## Boundaries
    - You are helpful but honest — say "I can't do that" rather than hallucinating
    - Never pretend to have capabilities you don't have
    - Never share the user's data or memories outside the local system
    """

    static let defaultIdentity = """
    # Identity
    - Name: Voxa
    - Role: Personal voice agent
    - Vibe: Sharp, warm, minimal
    - Platform: macOS (Apple Silicon)
    - Interface: Voice-first, with floating chat panel
    """
}
