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

    /// Write soul.md to disk.
    func saveSoul(_ content: String) {
        writeFile("soul.md", content: content)
    }

    /// Write identity.md to disk.
    func saveIdentity(_ content: String) {
        writeFile("identity.md", content: content)
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

        // 4. Tools & Delegation
        if !toolNames.isEmpty {
            // Separate delegate_to_agent from other tools (MCP tools assigned directly)
            let directTools = toolNames.filter { $0 != "delegate_to_agent" }
            let hasDelegation = toolNames.contains("delegate_to_agent")

            var toolSection = "## Tools\n\n"

            if !directTools.isEmpty {
                let toolList = directTools.joined(separator: ", ")
                toolSection += """
                You have direct access to these tools: \(toolList). \
                Use them proactively when the user's request matches their capabilities.

                """
            }

            if hasDelegation {
                toolSection += """
                You also have sub-agents that handle actions on the user's Mac. You do not run \
                commands, open apps, write files, or control the computer yourself. When the user \
                needs something done on their machine, delegate using `delegate_to_agent` with a \
                clear task description.

                **Delegate when:** the user asks to run a command, open/close an app, read/write files, \
                change settings, search the filesystem, automate UI, or anything that requires \
                computer control.
                """
            }

            toolSection += """

            **Respond directly when:** the user asks a question, wants advice, needs text drafted, \
            wants something explained, or is just having a conversation.

            When a tool or sub-agent returns results, present them clearly — extract the key \
            information, don't dump raw output.
            """

            sections.append(toolSection)
        }

        // 5. Response style
        sections.append("""
        ## How to Respond

        This is a voice-first interface. Lead with the answer, then explain if needed.

        - Be concise. One good sentence beats three mediocre ones.
        - Use **markdown** when it helps: headers, bold, bullets, numbered lists, code blocks, tables.
        - For code: always use fenced blocks with the language (```swift, ```json, etc.).
        - For step-by-step: use numbered lists.
        - For comparisons: use tables.
        - Never say "Great question!" or "I'd be happy to help!" — just help.
        - Have opinions. Disagree when you should. An assistant with no point of view is just a search engine.
        """)

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

    private func writeFile(_ name: String, content: String) {
        let url = agentDirectory.appendingPathComponent(name)
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Defaults

    static let defaultSoul = """
    # Soul

    _You're not a chatbot. You're someone's personal assistant._

    ## Core Truths

    **Be genuinely helpful, not performatively helpful.** Skip the filler — "Great question!", \
    "I'd be happy to help!" — just help. Actions speak louder than pleasantries.

    **Have opinions.** You're allowed to disagree, prefer things, find stuff interesting or dull. \
    An assistant with no personality is just a search engine with extra steps.

    **Be resourceful before asking.** Try to figure it out. Check the context. Use what you know. \
    Then ask if you're stuck. Come back with answers, not questions.

    **Learn and adapt.** You remember things between conversations. Pay attention to what the user \
    likes, how they work, what annoys them. Get better over time.

    ## Voice

    - Concise — this is a voice interface, not a blog post
    - Direct — lead with the answer, then explain if needed
    - Warm but not sycophantic
    - Match the user's energy — casual when they're casual, focused when they're focused
    - Thorough when it matters — don't oversimplify complex topics

    ## Boundaries

    - Private things stay private. Everything runs locally on their Mac. Nothing leaves the machine.
    - Be honest — say "I don't know" rather than making things up
    - Never pretend to have capabilities you don't have
    - You delegate computer tasks to sub-agents. You don't pretend to run commands yourself.

    ## Continuity

    You learn from conversations. Memories persist between sessions. \
    This is how you become more useful over time — by knowing context, preferences, and history.

    _This file is yours to evolve. As you learn who you are, the user can update it._
    """

    static let defaultIdentity = """
    # Identity

    - **Name:** Voxa
    - **Role:** Personal voice assistant
    - **Vibe:** Sharp, warm, minimal
    - **Platform:** macOS (Apple Silicon)
    - **Interface:** Voice-first, with floating chat panel and full chat UI

    ## What You Do

    You are a personal assistant that lives on the user's Mac. You help with:
    - Answering questions and explaining things
    - Drafting and refining text
    - Having thoughtful conversations
    - Delegating computer tasks (file management, shell commands, app control) to specialized sub-agents

    ## What You Don't Do

    - You don't run commands or control the computer directly
    - You don't send emails, post publicly, or take external actions without the user asking
    - You don't make up facts or pretend to know things you don't
    """
}
