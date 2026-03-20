# Voxa Command Mode → Agentic Voice Assistant

## Context

Voxa's Command Mode currently does one thing: highlight text → speak instruction → LLM rewrites it. The goal is to expand this into a full **agentic voice assistant** inspired by [macpaw Eney](https://macpaw.com/eney) (native Mac AI companion with computer control) and [OpenClaw](https://openclaw.ai/) (open-source agent with MCP tools, skills marketplace, sub-agents). The end result: Voxa becomes a voice-driven agent that can control your Mac, use tools, hold multi-turn conversations, and connect to external MCP servers — supporting both **local models (Ollama) and cloud providers (OpenAI, Gemini, etc.)**.

### User Preferences
- **Start with:** Phase 7 (Foundation)
- **LLM:** Multi-provider — local Ollama + cloud APIs (OpenAI, Gemini, etc.) with provider selection in settings
- **Agent Panel:** Toggle between persistent panel (default) and pop-up per turn
- **Code separation:** Agent mode code must be as isolated as possible from existing dictation code. Minimal touching of original files. All agent logic lives under `Voxa/Agent/`.
- **ClawHub skills:** Support installing and using skills from OpenClaw's ClawHub marketplace (with security guardrails)

---

## Phase 7: Foundation — Agent Module Setup ✅

**Goal:** Set up the agent module as an isolated, self-contained layer. Minimize changes to existing dictation code.

### 7.0 Code Separation Principle

> **Rule: Agent mode is additive, not invasive.**
> All agent logic lives under `Voxa/Agent/`. Existing modes (`PushToTalkMode`, `FlowMode`, `CommandMode`), engines (`AudioEngine`, `TranscriptionEngine`, `TextCleanupEngine`), and utilities (`OllamaClient`) are **NOT modified**.

**Existing files we touch (minimal, additive-only):**

| File | Change | Why |
|------|--------|-----|
| `DictationModeType` enum | Add `.agent` case | Mode picker needs the option |
| `HotkeyManager.swift` | Add 4th hotkey binding (`onAgentDown`/`onAgentUp`) | Agent needs its own hotkey |
| `VoxaApp.swift` (AppState) | Add `agentCoordinator` property + wire agent hotkey callbacks | Entry point for agent mode |
| `SettingsView.swift` | Add "Agent" tab linking to `AgentSettingsView` | Settings entry point |
| `MenuBarView.swift` | Add agent mode option to mode picker | UI for selecting agent mode |

**That's it.** No changes to `PushToTalkMode`, `FlowMode`, `CommandMode`, `AudioEngine`, `TranscriptionEngine`, `TextCleanupEngine`, `OllamaClient`, `TextInjector`, or any existing UI.

### 7.1 AgentCoordinator — The Bridge

The sole bridge between existing Voxa and the agent module:

```swift
// Voxa/Agent/AgentCoordinator.swift
@Observable
final class AgentCoordinator {
    // References to existing engines (read-only, passed from AppState)
    private let audioEngine: AudioEngine
    private let transcriptionEngine: TranscriptionEngine

    // Agent's own systems (fully self-contained)
    let providerManager: LLMProviderManager
    let toolRegistry: ToolRegistry
    let agentPanel: AgentPanel

    // Hotkey handlers (called by AppState, same pattern as existing modes)
    func onHotkeyDown(appState: AppState) { ... }
    func onHotkeyUp(appState: AppState) { ... }
}
```

`AgentCoordinator` **borrows** `AudioEngine` and `TranscriptionEngine` (for mic + STT) but owns everything else. It does NOT use `TextCleanupEngine` or `OllamaClient` — it has its own `LLMProvider` stack.

### 7.2 LLM Provider Abstraction (All new files under `Voxa/Agent/LLM/`)

```swift
// Voxa/Agent/LLM/LLMProvider.swift
protocol LLMProvider {
    var name: String { get }
    var isAvailable: Bool { get async }
    func chat(messages: [ChatMessage], tools: [ToolDefinition]?, timeout: TimeInterval) async throws -> ChatResponse
    func chatStream(messages: [ChatMessage], tools: [ToolDefinition]?, timeout: TimeInterval) -> AsyncThrowingStream<ChatStreamChunk, Error>
}
```

- `Voxa/Agent/LLM/ChatTypes.swift` — shared types: `ChatMessage`, `ToolCall`, `ToolDefinition`, `ChatResponse`, `ChatStreamChunk`
- `Voxa/Agent/LLM/LLMProviderManager.swift` — manages providers, active selection, per-provider config

### 7.3 Provider Implementations

| Provider | File | API | Notes |
|----------|------|-----|-------|
| Ollama | `OllamaProvider.swift` | `/api/chat` (local) | **New HTTP client** for chat API — does NOT wrap or import existing `OllamaClient.swift` |
| OpenAI | `OpenAIProvider.swift` | `api.openai.com/v1/chat/completions` | GPT-4o, GPT-4-turbo, etc. |
| Gemini | `GeminiProvider.swift` | `generativelanguage.googleapis.com` | Gemini 2.0 Flash/Pro |

- `OllamaProvider` is a **completely separate client** using `/api/chat` — the existing `OllamaClient` (used by `TextCleanupEngine`) uses `/api/generate` and is untouched
- Cloud providers use `URLSession` directly, no SDKs
- API keys stored in macOS Keychain via `Voxa/Agent/Utilities/KeychainHelper.swift`

### 7.4 What Stays the Same

The existing dictation pipeline is completely untouched:

```
[UNCHANGED] Hotkey → AudioEngine → TranscriptionEngine → TextCleanupEngine → OllamaClient → TextInjector
                                                            ↑ uses /api/generate
```

The agent pipeline runs independently:

```
[NEW] Agent Hotkey → AudioEngine → TranscriptionEngine → AgentCoordinator → LLMProvider → AgentPanel
                     (borrowed)     (borrowed)            ↑ uses /api/chat (or OpenAI/Gemini)
```

Both pipelines share `AudioEngine` and `TranscriptionEngine` (read-only borrowing), but diverge completely after transcription.

**Files to modify (existing):** `DictationModeType` (1 line), `HotkeyManager.swift` (add binding), `VoxaApp.swift` (add property + callback), `SettingsView.swift` (add tab), `MenuBarView.swift` (add option)
**New files (all under `Voxa/Agent/`):** `AgentCoordinator.swift`, `LLMProvider.swift`, `ChatTypes.swift`, `LLMProviderManager.swift`, `OllamaProvider.swift`, `OpenAIProvider.swift`, `GeminiProvider.swift`, `KeychainHelper.swift`

---

## Phase 8: Tool System + Built-in Tools ✅

**Goal:** Tool protocol, registry, and 7 built-in tools.

### 8.1 Tool Infrastructure
- Create `Voxa/Agent/Tools/AgentTool.swift`:
  ```swift
  protocol AgentTool {
      var name: String { get }
      var description: String { get }
      var parameters: [ToolParameter] { get }
      var requiresConfirmation: Bool { get }
      func execute(arguments: [String: Any]) async throws -> ToolResult
      func toDefinition() -> ToolDefinition  // for LLM tool calling
  }
  ```
- Create `Voxa/Agent/Tools/ToolRegistry.swift` — register, lookup, list all tool definitions

### 8.2 Built-in Tools (`Voxa/Agent/Tools/Builtin/`)

| Tool | Implementation | macOS API |
|------|---------------|-----------|
| `AppLauncherTool` | Open/switch apps | `NSWorkspace.shared.open` |
| `ClipboardTool` | Read/write pasteboard | `NSPasteboard` (reuse from TextInjector) |
| `ScreenCaptureTool` | Capture screen + OCR | `CGWindowListCreateImage` + `VNRecognizeTextRequest` |
| `UIAutomationTool` | Click, type, read UI elements | `AXUIElement` (Accessibility API — already permitted) |
| `FileSearchTool` | Spotlight search | `NSMetadataQuery` |
| `SystemSettingsTool` | Open Settings panes | `x-apple.systempreferences:` URL scheme |

### 8.3 Tool Settings
- Add tool enable/disable toggles in Settings
- `ShellCommandTool` (optional, gated) — always requires confirmation

**New directory:** `Voxa/Agent/Tools/` with `AgentTool.swift`, `ToolRegistry.swift`, `Builtin/*.swift`

---

## Phase 9: Agent Core + Agent Mode ✅

**Goal:** Working voice agent with multi-turn chat and tool calling.

### 9.1 Intent Classification (`Voxa/Agent/IntentClassifier.swift`)
```
Tier 1 (fast, regex/keyword): "open X" → toolInvocation, "stop"/"cancel" → systemControl
Tier 2 (LLM fallback): ambiguous input → classify via structured output
```
Intents: `dictation`, `textRewrite`, `toolInvocation`, `agentChat`, `systemControl`

### 9.2 Chat Session (`Voxa/Agent/ChatSession.swift`)
- `@Observable` class with message history, system prompt (built from available tools), context trimming
- Session persists across multiple hotkey presses until explicitly reset

### 9.3 Agent Executor (`Voxa/Agent/AgentExecutor.swift`)
Core agentic loop:
1. Classify intent
2. If tool invocation → execute tool → add result to session → LLM summarizes
3. If chat → send session to active LLM provider with tool definitions
4. If LLM returns `tool_calls` → execute tools in loop (max 5 iterations)
5. Return response (text to display, text to inject, or both)

### 9.4 Agent Mode (`Voxa/Modes/AgentMode.swift`)
- Implements `DictationMode` protocol
- Manages `ChatSession` lifecycle (create on first press, persist until reset)
- On hotkey up: transcribe → route through `AgentExecutor` → stream response to `AgentPanel`
- Uses `LLMProviderManager.activeProvider` — works with any configured provider (Ollama, OpenAI, Gemini)

### 9.5 Agent Panel (`Voxa/UI/AgentPanel.swift`) — Two Modes (Toggle)
- **Persistent mode (default):** Panel stays open across presses. Full chat history, scrollable. Dismiss via Esc or "stop" voice command. Cmd+N for new session.
- **Pop-up mode:** Panel appears per turn, shows current response only, auto-dismisses after 5s timeout. Less intrusive for quick commands.
- Toggle in Settings between modes
- Both modes share same `NSPanel` + `NSHostingView` pattern as `FloatingIndicator`
- Panel size: ~400x500 (persistent) or ~300x200 (pop-up)
- Shows: streaming response, tool execution status (spinner + tool name), quick actions

### 9.6 Agent Settings
- New "Agent" tab in `SettingsView`
- **LLM provider selection**: dropdown for Ollama / OpenAI / Gemini
- **Model selection**: per-provider model picker (e.g., `qwen2.5:7b` for Ollama, `gpt-4o` for OpenAI, `gemini-2.0-flash` for Gemini)
- **API key management**: secure input fields, stored in Keychain
- **Panel mode toggle**: persistent vs pop-up
- Agent timeout config (default 30s)

**New files:** `IntentClassifier.swift`, `ChatSession.swift`, `AgentExecutor.swift`, `AgentResponse.swift`, `AgentMode.swift`, `AgentPanel.swift`, `AgentPanelContent.swift`

---

## Phase 10: MCP Integration

**Goal:** Connect to external MCP servers for extensible tool access.

### 10.1 SPM Dependency
- Add `https://github.com/modelcontextprotocol/swift-sdk` (official MCP Swift SDK)

### 10.2 MCP Infrastructure (`Voxa/Agent/MCP/`)

| File | Purpose |
|------|---------|
| `MCPServerConfig.swift` | Config model (stdio command+args or HTTP URL) |
| `MCPConnection.swift` | Wraps SDK transport, handles init/reconnect |
| `MCPManager.swift` | Lifecycle: connect on launch, discover tools, reconnect on failure |
| `MCPToolAdapter.swift` | Bridges MCP tools → `AgentTool` protocol → registered in `ToolRegistry` |

### 10.3 Configuration
- Config stored at `~/.voxa/mcp-servers.json` (same pattern as Claude Desktop)
- `MCPSettingsView.swift` in Settings — add/remove/edit MCP servers

### 10.4 Transport Support
- `StdioTransport` — spawn local processes (filesystem server, etc.)
- `HTTPTransport` — connect to remote HTTP MCP servers
- Note: Must disable app sandboxing for process spawning (already the case for Voxa — needs Accessibility)

**New files:** `MCPServerConfig.swift`, `MCPConnection.swift`, `MCPManager.swift`, `MCPToolAdapter.swift`, `MCPSettingsView.swift`

---

## Phase 11: Sub-Agents (Inspired by OpenClaw)

**Goal:** Specialized child agents that the main agent can delegate tasks to — each with its own persona, tool subset, and optionally a different/cheaper LLM model.

### 11.1 Concepts

**Why sub-agents?** A single agent with all tools gets overwhelmed. Sub-agents let you:
- **Specialize**: A "code agent" knows about files and git; a "web agent" knows about search and URLs
- **Optimize cost**: Use a cheap/fast model (Haiku-level) for routine sub-tasks, expensive model (Opus-level) for the orchestrator
- **Isolate context**: Sub-agents don't inherit the full conversation — they get a focused task prompt, reducing noise
- **Parallelize**: Fan out independent tasks to multiple sub-agents simultaneously

### 11.2 Architecture

```
User speaks → Main Agent (orchestrator)
                ├── Handles directly (simple tasks)
                ├── Delegates to SubAgent: "system" (app control, settings)
                ├── Delegates to SubAgent: "research" (web search, screen reading)
                ├── Delegates to SubAgent: "code" (file ops, shell, git)
                └── Delegates to SubAgent: "custom" (user-defined)
```

**Key design:** Sub-agents are NOT separate processes. They are **isolated `ChatSession` instances** with their own system prompt, tool subset, and LLM provider — all managed within the same Voxa process.

### 11.3 SubAgent Definition (`Voxa/Agent/SubAgents/SubAgentDefinition.swift`)

```swift
struct SubAgentDefinition: Codable, Identifiable {
    let id: String                    // e.g., "system", "research", "code"
    let name: String                  // Display name
    let description: String           // What this agent specializes in
    let systemPrompt: String          // Agent-specific instructions
    let allowedTools: [String]        // Tool names this agent can use (subset of ToolRegistry)
    let provider: String?             // Override LLM provider (nil = use parent's)
    let model: String?                // Override model (nil = use parent's)
    let timeout: TimeInterval         // Max execution time (default: 30s)
    let maxToolCalls: Int             // Max tool iterations (default: 5)
}
```

### 11.4 Built-in Sub-Agents

| Agent | ID | Tools | Purpose |
|-------|----|-------|---------|
| **System** | `system` | AppLauncher, SystemSettings, UIAutomation | App control, settings, UI interaction |
| **Research** | `research` | ScreenCapture, WebSearch, Clipboard | Information gathering, screen reading |
| **Code** | `code` | FileSearch, ShellCommand, Clipboard | File operations, running commands |
| **Writer** | `writer` | Clipboard | Text generation, rewriting, formatting |

Each has a focused system prompt. For example, the `system` agent's prompt:
```
You are a macOS system control specialist. You can open apps, change settings,
and interact with UI elements. Be precise with click targets. Always confirm
before destructive actions. Report what you did concisely.
```

### 11.5 SubAgentManager (`Voxa/Agent/SubAgents/SubAgentManager.swift`)

```swift
@Observable
final class SubAgentManager {
    private var definitions: [String: SubAgentDefinition] = [:]
    private var activeSessions: [String: ChatSession] = [:]

    // Registry
    func register(_ definition: SubAgentDefinition)
    func definitions(matching task: String) -> [SubAgentDefinition]  // LLM picks best match

    // Execution
    func spawn(
        agentId: String,
        task: String,
        context: String?,         // Optional parent context snippet
        toolRegistry: ToolRegistry,
        providerManager: LLMProviderManager
    ) async throws -> SubAgentResult

    // Lifecycle
    func activeAgents() -> [String]
    func cancel(agentId: String)
    func cancelAll()
}
```

### 11.6 How Delegation Works in AgentExecutor

The `AgentExecutor` agentic loop (Phase 9) gets a new intent and delegation path:

```swift
enum Intent {
    case dictation
    case textRewrite(text: String, command: String)
    case toolInvocation
    case agentChat
    case systemControl
    case delegation(agentId: String, task: String)  // NEW
}
```

**Delegation flow:**
1. User speaks a complex request (e.g., "find the latest sales report PDF and email a summary")
2. IntentClassifier Tier 2 (LLM) recognizes this needs multiple specialists
3. Main agent decomposes into sub-tasks:
   - Sub-agent "research": find and read the PDF
   - Sub-agent "writer": summarize it
4. `SubAgentManager.spawn()` creates isolated sessions for each
5. Sub-agents execute with their tool subsets
6. Results flow back to main agent's session
7. Main agent synthesizes and responds to user

**Alternatively**, the LLM itself can request delegation via a special built-in tool:

```swift
// Built-in tool available to the main agent
struct DelegateToAgentTool: AgentTool {
    let name = "delegate_to_agent"
    let description = "Delegate a task to a specialized sub-agent"
    let parameters = [
        ToolParameter(name: "agent_id", type: .string, description: "Which sub-agent: system, research, code, writer"),
        ToolParameter(name: "task", type: .string, description: "Clear task description for the sub-agent"),
        ToolParameter(name: "context", type: .string, description: "Relevant context from current conversation", required: false)
    ]
}
```

This is cleaner than hardcoding delegation logic — the LLM decides when to delegate.

### 11.7 Context Isolation (OpenClaw Pattern)

Sub-agents receive **reduced context** (mirroring OpenClaw's AGENTS.md + TOOLS.md only):

| Context | Main Agent | Sub-Agent |
|---------|-----------|-----------|
| soul.md | Yes | No |
| user.md | Yes | No |
| identity.md | Yes | No |
| tools.md | Yes | Yes (environment reference needed) |
| memory.md | Yes | No |
| Daily logs | Yes (today + yesterday) | No |
| Sub-agent system prompt | No | Yes (agent-specific instructions) |
| Parent task prompt | No | Yes (the delegated task) |
| Available tools | All | Subset (per definition) |

**Rationale:** Sub-agents don't need personality or user history — they need focus. Less context = cheaper tokens + better task adherence.

### 11.8 Concurrency & Safety

- **Max concurrent sub-agents:** 3 (configurable)
- **Max spawn depth:** 1 (sub-agents cannot spawn their own sub-agents — keeps things simple)
- **Timeout:** Per-agent, default 30s, configurable in definition
- **Tool confirmation:** Sub-agents inherit `requiresConfirmation` from tools — destructive ops still prompt user
- **Cancellation:** Parent can cancel any/all active sub-agents (voice: "cancel", "stop")

### 11.9 Custom Sub-Agents

Users can define custom sub-agents via YAML files at `~/.voxa/agent/subagents/`:

```yaml
# ~/.voxa/agent/subagents/devops.yaml
id: devops
name: DevOps Agent
description: Handles deployment, Docker, and infrastructure tasks
systemPrompt: |
  You are a DevOps specialist. You help with deployments,
  Docker commands, CI/CD pipelines, and infrastructure.
  Always show commands before running them.
allowedTools:
  - shell_command
  - file_search
  - clipboard
provider: ollama        # Use local model for sensitive ops
model: qwen2.5:7b
timeout: 60
maxToolCalls: 10
```

**Sub-agent settings UI** in Settings → Agent → Sub-Agents:
- List built-in + custom sub-agents
- Enable/disable individual agents
- Edit custom agent YAML
- Create new custom agents

**New files:** `SubAgentDefinition.swift`, `SubAgentManager.swift`, `SubAgentResult.swift`, `DelegateToAgentTool.swift`
**New directory:** `Voxa/Agent/SubAgents/`

---

## Phase 12: Skills System (Inspired by OpenClaw)

**Goal:** Reusable instruction sets that teach the agent *how* to combine tools for specific workflows — without granting new permissions.

### 12.1 Key Concept: Tools vs Skills vs Sub-Agents

| | Tools | Skills | Sub-Agents |
|--|-------|--------|------------|
| **What** | Atomic capabilities | Workflow instructions | Specialized brains |
| **Format** | Swift protocol | Markdown (SKILL.md) | YAML definition + ChatSession |
| **Example** | "read clipboard" | "how to format code for a PR" | "code specialist agent" |
| **Grants permissions?** | Yes (it IS the permission) | No (teaches how to use existing tools) | No (uses tool subset) |
| **Runs code?** | Yes | No (injected into prompt) | Yes (via allowed tools) |

### 12.2 Skill Format (`SKILL.md`)

Following the AgentSkills specification (adopted by both OpenAI and Anthropic):

```markdown
---
name: git-commit
description: Create well-formatted git commits with conventional commit messages
version: 1.0.0
emoji: 📝
requires:
  tools: [shell_command, file_search]
triggers:
  - "commit"
  - "save changes"
  - "git commit"
---

# Git Commit Skill

When the user asks to commit changes:

1. Run `git status` to see what's changed
2. Run `git diff --staged` to review staged changes (if any)
3. If nothing is staged, ask the user what to stage
4. Generate a conventional commit message:
   - Format: `type(scope): description`
   - Types: feat, fix, refactor, docs, test, chore
   - Keep description under 72 characters
5. Show the proposed commit message and ask for confirmation
6. Run `git commit -m "message"`
7. Report success with the commit hash
```

### 12.3 Skill Loading & Discovery (`Voxa/Agent/Skills/SkillManager.swift`)

```swift
@Observable
final class SkillManager {
    // Skill sources (priority order):
    // 1. User skills: ~/.voxa/agent/skills/
    // 2. Bundled skills: Voxa.app/Contents/Resources/Skills/

    var loadedSkills: [Skill] = []

    func loadSkills()                                    // Scan directories, parse SKILL.md files
    func skill(named: String) -> Skill?
    func skills(matching transcript: String) -> [Skill]  // Trigger word matching
    func skillPromptText(for skills: [Skill]) -> String  // Format for system prompt injection
}
```

**Loading flow:**
1. At agent session start, `SkillManager.loadSkills()` scans skill directories
2. Skills are parsed: YAML frontmatter → metadata, markdown body → instructions
3. `requires.tools` checked against `ToolRegistry` — skill disabled if required tools missing
4. Active skills' instructions injected into system prompt under a `## Skills` section

### 12.4 Skill Activation

Skills activate in two ways:

**1. Always-active skills** — injected into every agent session's system prompt:
```yaml
---
name: voice-style
always: true
---
When responding to voice queries, keep answers under 3 sentences.
Lead with the answer, explain after. Use natural speech patterns.
```

**2. Trigger-activated skills** — loaded when transcript matches trigger words:
```yaml
triggers:
  - "commit"
  - "git commit"
```
When the user says "commit my changes", the IntentClassifier matches the trigger and injects this skill's instructions into the current turn's prompt.

### 12.5 Built-in Skills (shipped with Voxa)

| Skill | Triggers | Tools Used | What It Teaches |
|-------|----------|------------|-----------------|
| `voice-style` | (always) | — | How to format responses for voice output |
| `git-commit` | "commit", "save changes" | ShellCommand, FileSearch | Conventional commit workflow |
| `screenshot-describe` | "what's on screen", "describe screen" | ScreenCapture | How to capture and describe screen content |
| `app-workflow` | "open and do X in Y" | AppLauncher, UIAutomation | Multi-step app automation |
| `file-finder` | "find file", "where is" | FileSearch, ShellCommand | Smart file search with Spotlight + fallback |
| `summarize-text` | "summarize", "tldr" | Clipboard, ScreenCapture | Read text and produce concise summary |

### 12.6 Custom Skills (Local)

Users create custom skills at `~/.voxa/agent/skills/`:

```
~/.voxa/agent/skills/
├── git-commit/
│   └── SKILL.md
├── deploy/
│   └── SKILL.md
├── meeting-notes/
│   └── SKILL.md
└── my-workflow/
    └── SKILL.md
```

Each skill is a folder with a `SKILL.md` file. Users can create these manually or via voice: "create a new skill called deploy that runs my deploy script".

### 12.7 ClawHub Integration — Install Skills from the Marketplace

Voxa can install and use skills from [ClawHub](https://clawhub.ai/), OpenClaw's public skill registry (3,286+ verified skills).

#### How It Works

ClawHub skills use the same `SKILL.md` format we already support. Integration is straightforward:

```swift
// Voxa/Agent/Skills/ClawHubClient.swift
final class ClawHubClient {
    let baseURL = URL(string: "https://api.clawhub.ai")!

    func search(query: String) async throws -> [ClawHubSkill]     // Vector-powered semantic search
    func details(slug: String) async throws -> ClawHubSkill        // Full skill metadata
    func download(slug: String, version: String?) async throws -> URL  // Download skill bundle
    func checkSecurity(slug: String) async throws -> SecurityReport    // VirusTotal + audit
}
```

#### Skill Sources & Priority (highest → lowest)

| Priority | Source | Path | Notes |
|----------|--------|------|-------|
| 1 | User skills | `~/.voxa/agent/skills/` | User-created, always trusted |
| 2 | ClawHub installed | `~/.voxa/agent/skills-clawhub/` | Downloaded from marketplace |
| 3 | Bundled skills | `Voxa.app/Contents/Resources/Skills/` | Shipped with app |

ClawHub skills install to a **separate directory** (`skills-clawhub/`) so they're clearly distinguished from user-created skills.

#### Install Flow

1. User says "install a skill for docker" (or uses Settings UI)
2. `ClawHubClient.search("docker")` → returns matching skills with ratings/downloads
3. Agent shows top results in AgentPanel, user picks one
4. **Security check** before install:
   - Fetch VirusTotal report for the skill bundle
   - Check `requires.tools` — warn if skill needs dangerous tools (e.g., `shell_command`)
   - Show permission audit: "This skill uses: shell_command, file_search. Allow?"
5. Download and extract to `~/.voxa/agent/skills-clawhub/<slug>/`
6. `SkillManager` picks it up on next load

#### Voice Commands for ClawHub

- "Install a skill for [topic]" → search + install flow
- "Find skills for [topic]" → search and list results
- "Update my skills" → check for newer versions of installed ClawHub skills
- "Remove [skill name]" → delete from skills-clawhub directory

#### Security Guardrails

ClawHub had a malicious skills incident (230+ malicious skills, ClawHavoc campaign). Voxa mitigates this:

| Threat | Mitigation |
|--------|-----------|
| Malicious SKILL.md instructions | Skills are markdown instructions, not executable code — they can't run anything the agent's tools don't already allow |
| Prompt injection in skill text | Skill content sandboxed under a `## Skill: <name>` section in prompt, agent instructed to treat skill instructions as task guidance, not system commands |
| Overly broad tool requests | `requires.tools` audited at install time — user must explicitly approve each tool |
| Data exfiltration via tool chaining | Tools with network access (`shell_command`) always require confirmation — skill can't silently call `curl` |
| Stale/vulnerable skills | Version tracking + "update my skills" command; warn if installed skill has known issues |
| VirusTotal flagged bundles | Block install entirely if VirusTotal reports malicious signatures |

**Key principle:** Skills can't do anything the user hasn't already authorized via tool permissions. A malicious skill can only instruct the LLM to use existing tools — and destructive tools require confirmation.

### 12.8 Skills + Sub-Agents Composition

Skills and sub-agents compose naturally:

```
User: "commit my changes"

1. IntentClassifier matches trigger "commit" → loads `git-commit` skill
2. Skill instructions injected into prompt
3. AgentExecutor sees skill requires shell_command → delegates to "code" sub-agent
4. Code sub-agent executes the git workflow per skill instructions
5. Result flows back to main agent → responds to user
```

The main agent acts as **orchestrator**: skills tell it *what to do*, sub-agents tell it *who does it*, tools tell it *how*.

### 12.9 Skill Settings UI

Settings → Agent → Skills:
- **Installed tab**: List all skills (built-in + custom + ClawHub), enable/disable, view/edit SKILL.md
- **ClawHub tab**: Search marketplace, browse categories, install/update/remove
- **Create tab**: New custom skill from template
- Skill trigger testing ("type a phrase, see which skill matches")
- Per-skill tool permission review

**New files:** `Skill.swift`, `SkillManager.swift`, `SkillParser.swift`, `ClawHubClient.swift`, `ClawHubSkill.swift`
**New directory:** `Voxa/Agent/Skills/`, `Voxa/Resources/Skills/` (bundled defaults)

---

## Phase 13: Heartbeat & Scheduled Tasks (Inspired by OpenClaw)

**Goal:** Give Voxa proactive awareness — periodic background checks and time-based automated tasks, all running locally from the menu bar app.

### 13.1 Concepts: Heartbeat vs Cron

| | Heartbeat | Cron Jobs |
|--|-----------|-----------|
| **What** | Periodic awareness loop | Precise time-based tasks |
| **When** | Every N minutes (default: 30m) | Exact schedule (cron expression or interval) |
| **Purpose** | "Check if anything needs attention" | "Do this at exactly 9 AM" |
| **Context** | Reads HEARTBEAT.md checklist | Isolated per-job (fresh context each run) |
| **Cost** | Cheap (skip if nothing to do) | Per-job token cost |
| **Example** | "Any pending dictations? Model updates available?" | "Send daily transcription stats at 6 PM" |

### 13.2 Heartbeat System

#### `HEARTBEAT.md` — The Proactive Checklist

Lives at `~/.voxa/agent/heartbeat.md`:

```markdown
# Voxa Heartbeat

## Always Check
- [ ] If Ollama is running, verify model is loaded and responsive
- [ ] Check disk space for model storage (warn if < 5GB free)

## Morning (8-9 AM weekdays)
- [ ] Summarize yesterday's transcription activity (word count, sessions)

## Every 4 Hours
- [ ] Check if WhisperKit model has updates available
- [ ] Check if any ClawHub skill updates are pending

## Evening (6 PM)
- [ ] Log daily transcription stats to memory
```

#### How It Works in Voxa

Since Voxa is a **menu bar app** (not a daemon), the heartbeat runs as an **in-process timer** using `DispatchSourceTimer` or `Timer`:

```swift
// Voxa/Agent/Heartbeat/HeartbeatScheduler.swift
@Observable
final class HeartbeatScheduler {
    private var timer: DispatchSourceTimer?
    private let agentCoordinator: AgentCoordinator

    var interval: TimeInterval = 30 * 60  // 30 minutes default
    var activeHours: ActiveHoursConfig?     // Optional time window
    var isRunning: Bool = false

    func start() { ... }   // Create repeating timer
    func stop() { ... }
    func runNow() { ... }  // Manual trigger ("check now" voice command)

    private func tick() async {
        // 1. Check active hours — skip if outside window
        // 2. Read heartbeat.md
        // 3. If empty/whitespace → skip (save tokens)
        // 4. Run cheap checks first (no LLM):
        //    - Ollama reachability (HTTP ping)
        //    - Disk space (FileManager)
        //    - Time-based task matching
        // 5. If anything needs attention → invoke LLM for decision/action
        // 6. If nothing → log HEARTBEAT_OK, skip LLM entirely
    }
}
```

**Key design: "Cheap checks first"** — Most heartbeat tasks can be resolved with simple system calls (HTTP ping, disk check, file exists). Only escalate to LLM when something actually needs attention. This keeps cost near-zero during quiet periods.

#### Heartbeat → macOS Integration

Since Voxa is always running in the menu bar:
- Timer runs in-process (no launchd/systemd needed)
- **System sleep handling**: Use `NSWorkspace.willSleepNotification` / `didWakeNotification` to pause/resume timer and recalculate next tick based on wall clock time (avoids the OpenClaw sleep bug)
- **App quit**: Heartbeat stops naturally when app quits
- **Launch at login**: Already supported via `SMAppService` — heartbeat resumes on reboot

#### Heartbeat Notifications

When the heartbeat finds something actionable:

| Priority | Delivery | Example |
|----------|----------|---------|
| **Info** | Daily log entry only | "Model cache: 2.3GB used, 47GB free" |
| **Notice** | macOS notification (banner) | "WhisperKit model update available" |
| **Alert** | Notification + AgentPanel popup | "Ollama is not running — transcription cleanup disabled" |

Uses `UNUserNotificationCenter` for native macOS notifications.

### 13.3 Cron Jobs — Precise Scheduling

For tasks that need exact timing (not just periodic checks):

```swift
// Voxa/Agent/Heartbeat/CronJob.swift
struct CronJob: Codable, Identifiable {
    let id: UUID
    let name: String
    let schedule: CronSchedule
    let task: String               // Natural language task for the agent
    let enabled: Bool
    let model: String?             // Override LLM model for this job
    let timeout: TimeInterval      // Max execution time
    let notify: Bool               // Send macOS notification on completion
    let createdAt: Date
}

enum CronSchedule: Codable {
    case at(Date)                  // One-shot: run once at this time
    case every(TimeInterval)       // Repeating: every N seconds
    case cron(String, timezone: String?)  // Standard cron expression
}
```

```swift
// Voxa/Agent/Heartbeat/CronScheduler.swift
@Observable
final class CronScheduler {
    var jobs: [CronJob] = []
    private var timers: [UUID: DispatchSourceTimer] = [:]

    func addJob(_ job: CronJob)
    func removeJob(id: UUID)
    func enableJob(id: UUID, enabled: Bool)
    func nextFireDate(for job: CronJob) -> Date?

    // Persistence
    func save()   // Write to ~/.voxa/agent/cron-jobs.json
    func load()   // Read on launch
}
```

#### Cron Job Execution

Each cron job runs in an **isolated ChatSession** (not the main agent session):
- Fresh context per run (cheap, no history pollution)
- Uses heartbeat.md context (optional) + job-specific task prompt
- Results logged to daily log + optional macOS notification
- Agent can use tools during cron execution (same tool registry)

#### Voice Commands for Cron

- "Remind me to check email every 2 hours" → creates cron job
- "Every morning at 9, summarize my dictation stats" → creates cron job
- "Show my scheduled tasks" → lists active cron jobs
- "Cancel the email reminder" → removes cron job
- "Run all my checks now" → manual heartbeat trigger

#### Built-in Cron-Aware Tool

```swift
// Voxa/Agent/Tools/Builtin/CronTool.swift
struct CronTool: AgentTool {
    let name = "manage_cron"
    let description = "Create, list, or remove scheduled tasks"
    let parameters = [
        ToolParameter(name: "action", type: .string, description: "create, list, remove, or trigger"),
        ToolParameter(name: "name", type: .string, description: "Job name", required: false),
        ToolParameter(name: "schedule", type: .string, description: "Cron expression, interval, or timestamp", required: false),
        ToolParameter(name: "task", type: .string, description: "What the agent should do", required: false),
    ]
}
```

This lets the LLM create/manage cron jobs via tool calling — the user says it in natural language, the agent translates to a cron job.

### 13.4 Token Cost Management

| Scenario | Tokens | Cost/month (Ollama) | Cost/month (GPT-4o) |
|----------|--------|--------------------|--------------------|
| Heartbeat (cheap checks only, no LLM) | 0 | $0 | $0 |
| Heartbeat (LLM needed, isolated) | ~2-5K | $0 (local) | ~$0.05 |
| Heartbeat (full context, every 30m) | ~100K | $0 (local) | ~$4.30 |
| Single cron job (isolated) | ~5-15K | $0 (local) | ~$0.20 |

**Voxa advantage over OpenClaw:** With Ollama as primary provider, heartbeat and cron jobs cost **$0** in API fees. Only cloud providers (OpenAI/Gemini) incur costs.

**Optimization strategies:**
- Use Ollama (free, local) for heartbeat and routine cron jobs
- Reserve cloud models for user-facing interactions
- Skip LLM entirely when cheap checks find nothing actionable
- Keep `heartbeat.md` under 500 tokens

### 13.5 Settings UI

Settings → Agent → Automation:

**Heartbeat section:**
- Enable/disable toggle
- Interval picker (15m, 30m, 1h, 2h, custom)
- Active hours (start/end time + "all day" option)
- Edit HEARTBEAT.md (inline editor)
- LLM model override for heartbeat (default: use agent model)

**Cron jobs section:**
- List all jobs (name, schedule, next fire date, enabled toggle)
- Add new job (name, schedule, task description)
- Remove/edit existing jobs
- Manual "Run now" button per job
- Job execution history (last 10 runs with status)

**New files:** `HeartbeatScheduler.swift`, `CronJob.swift`, `CronScheduler.swift`, `CronParser.swift`, `CronTool.swift`
**New directory:** `Voxa/Agent/Heartbeat/`

---

## Phase 14: Personal Agent — Identity, Memory & Learning

**Goal:** Make Voxa a **personal agent** that deeply knows its user and gets smarter over time. Not a generic assistant with static config files — a living system that learns who you are, how you work, and what you need.

Inspired by: Mem0 (memory extraction + consolidation), Stanford Generative Agents (reflections), OpenClaw (persona files), Letta/MemGPT (tiered memory), Dot (emotional intelligence).

### 14.1 Core Principle: The Agent Learns, Not Just Stores

```
Week 1:  "User's name is Rohit. He's a software engineer."
Week 4:  "Rohit works on Swift/macOS apps. Prefers terse responses.
          Dictates most between 9-11 AM and 2-4 PM. Usually works on Voxa."
Month 3: "Rohit starts mornings with planning dictation, afternoons with code.
          Gets frustrated when explanations are too long. Prefers Gemini for
          quick tasks, Ollama for private work. His deployment workflow involves
          running tests first, then tagging, then pushing."
```

The agent **actively extracts, consolidates, and reflects** — it doesn't wait for the user to manually update a profile.

### 14.2 Three-Tier Memory Architecture

Drawing from cognitive science (Mem0, Stanford Generative Agents, Letta):

| Tier | Type | What It Stores | Persistence | Token Cost |
|------|------|---------------|-------------|-----------|
| **1. Working** | Current session | Active conversation, tools in use | Session only (RAM) | Included in chat |
| **2. Episodic** | Daily logs | Timestamped events, interactions, observations | `logs/YYYY-MM-DD.md` | Load today + yesterday |
| **3. Semantic** | Long-term knowledge | Facts, preferences, routines, relationships, reflections | `memory/` directory | Selectively retrieved |

#### Tier 1: Working Memory (Current Session)

The active `ChatSession` — messages, tool results, in-flight context. Dies when session ends. Nothing new here (already in Phase 9).

#### Tier 2: Episodic Memory (Daily Logs)

Append-only journal capturing **what happened**:

```markdown
## 2026-03-18

- 09:15 | session_start | Agent mode activated
- 09:15 | user_request | "Open Xcode and find the TranscriptionEngine file"
- 09:16 | tool_use | AppLauncher → opened Xcode | ScreenCapture → found TranscriptionEngine.swift
- 09:17 | user_request | "Rewrite the function header to be more descriptive"
- 09:18 | delegation | code sub-agent | used OpenAI GPT-4o | 3.2s
- 09:20 | user_feedback | accepted rewrite without edits ← [signal: output quality good]
- 09:25 | session_end | duration: 10m | tools: 3 | turns: 5 | provider: openai
- 14:30 | session_start | Agent mode activated
- 14:30 | user_request | "What's wrong with the OllamaClient timeout?"
- 14:31 | tool_use | FileSearch → Constants.swift | ScreenCapture → error in console
- 14:35 | user_feedback | "no, check the session config not constants" ← [signal: correction, learn search preference]
```

**Key difference from OpenClaw:** Episodic logs capture **signals**, not just events. Each entry notes implicit feedback (accepted output, corrections, edits, tone).

#### Tier 3: Semantic Memory (Long-Term Knowledge)

Structured knowledge extracted and consolidated from episodic memory. Lives in `~/.voxa/agent/memory/`:

```
~/.voxa/agent/memory/
├── user-profile.md       # Who the user is (auto-maintained)
├── preferences.md        # Learned preferences (auto-maintained)
├── routines.md           # Detected behavioral patterns
├── relationships.md      # People the user mentions
├── projects.md           # Active projects and context
└── reflections.md        # Higher-order insights (weekly synthesis)
```

Each file is **agent-maintained** — the agent writes to these, not the user (though the user can edit/override).

### 14.3 Memory Extraction — Learning From Every Interaction

After each agent session ends, a **memory extraction pass** runs:

```swift
// Voxa/Agent/Persona/MemoryExtractor.swift
final class MemoryExtractor {
    /// Runs after each session. Extracts salient facts from the conversation.
    func extract(session: ChatSession) async -> [MemoryCandidate] {
        // 1. Send session transcript to LLM with extraction prompt
        // 2. LLM returns structured facts:
        //    - type: preference | fact | routine | person | project | correction
        //    - content: "User prefers Gemini for quick tasks"
        //    - importance: 1-10 (1 = mundane, 10 = life event)
        //    - source: which message triggered this
    }
}
```

**Extraction prompt** (sent to LLM after session):
```
You are analyzing a voice assistant session to learn about the user.
Extract any new facts, preferences, corrections, or patterns you observed.
Focus on what would help you serve this user better in future sessions.

For each observation, classify:
- type: preference | fact | routine | person | project | correction
- importance: 1 (routine small talk) to 10 (major life/work event)
- content: concise statement of what you learned

Only extract genuinely new or updated information. Skip trivial task details.
```

**What gets extracted:**
- Explicit preferences: "I prefer concise answers" → preference
- Implicit preferences: user accepted output without edits → preference (inferred quality bar)
- Corrections: "no, check the session config" → correction (update search behavior)
- People mentioned: "send this to Alex on the team" → person
- Project context: "we're deploying v2.0 next week" → project
- Routines: morning planning dictation detected across 5+ days → routine

### 14.4 Memory Consolidation — From Observations to Understanding

Raw extractions are **deduplicated and merged** into semantic memory files:

```swift
// Voxa/Agent/Persona/MemoryConsolidator.swift
final class MemoryConsolidator {
    /// Merge new candidates into existing semantic memory.
    /// Uses vector similarity to find duplicates/updates.
    func consolidate(candidates: [MemoryCandidate], existing: SemanticMemory) async -> [MemoryUpdate] {
        // For each candidate:
        // 1. Embed candidate text
        // 2. Find similar existing memories (cosine similarity > 0.85)
        // 3. If match found:
        //    - UPDATE if new info refines existing (e.g., "prefers Gemini" → "prefers Gemini for quick tasks, Ollama for private work")
        //    - NOOP if duplicate
        // 4. If no match: ADD new memory
        // 5. Check for contradictions → resolve (newest wins, or flag for user)
    }
}
```

**Consolidation runs:**
- After every agent session (lightweight — just new extractions)
- During heartbeat idle time (heavier — cross-reference recent logs)
- Uses local Ollama model (free) to avoid cloud API costs

### 14.5 Reflections — Weekly Synthesis

Inspired by Stanford Generative Agents: when cumulative importance of recent memories exceeds a threshold, the agent generates **higher-order insights**.

```swift
// Voxa/Agent/Persona/ReflectionEngine.swift
final class ReflectionEngine {
    /// Generate reflections from recent memories.
    /// Triggered weekly or when importance accumulates past threshold.
    func reflect(recentMemories: [SemanticMemoryEntry]) async -> [Reflection] {
        // 1. Take last 7 days of memories
        // 2. Ask LLM: "What are the 3 most important patterns or insights
        //    about this user based on these observations?"
        // 3. Store reflections in reflections.md with citations to source memories
    }
}
```

**Example reflections after 1 month:**
```markdown
# Reflections

## 2026-04-15 — Weekly Reflection
- Rohit's productivity peaks in morning (9-11 AM). Most complex dictation
  and coding tasks happen then. Afternoon sessions are shorter, more tactical.
  [Sources: routines.md#morning-pattern, 15 daily logs]
- When Rohit says "check" or "look at" he means search files, not take a screenshot.
  Early sessions had me using ScreenCapture when he meant FileSearch.
  [Sources: corrections from 2026-03-20, 2026-03-22, 2026-03-25]
- Voxa deployment workflow is always: test → tag → push. Never skip tests.
  [Sources: projects.md#voxa, 8 observed deployments]
```

Reflections feed back into the system prompt as high-signal context.

### 14.6 Behavioral Pattern Detection

The agent passively detects patterns from interaction data:

```swift
// Voxa/Agent/Persona/PatternDetector.swift
final class PatternDetector {
    /// Analyze episodic logs to detect behavioral patterns.
    func detectPatterns(logs: [DailyLog]) -> [BehavioralPattern] { ... }
}

struct BehavioralPattern {
    let type: PatternType   // .schedule, .topic, .style, .routine, .tool_preference
    let description: String
    let confidence: Float   // 0.0–1.0 (needs N occurrences to reach high confidence)
    let firstSeen: Date
    let occurrences: Int
}
```

**Patterns detected:**

| Pattern | Signal | Threshold | Example |
|---------|--------|-----------|---------|
| **Work schedule** | Session start/end timestamps | 5+ days | "Active 9-11 AM, 2-5 PM on weekdays" |
| **Topic clusters** | Transcription content keywords | 10+ mentions | "Frequently works on: Voxa, SwiftUI, Ollama" |
| **Communication style** | Response acceptance, corrections | 10+ sessions | "Prefers terse responses; corrects when too verbose" |
| **Tool preferences** | Tool usage frequency, corrections | 5+ uses | "Prefers FileSearch over ScreenCapture for code lookup" |
| **Provider preferences** | Which LLM used for which tasks | 5+ sessions | "Uses Gemini for quick Q&A, Ollama for code rewrites" |
| **Routines** | Repeated sequences at similar times | 3+ occurrences | "Morning: open Xcode → check git status → review PRs" |

Patterns below confidence threshold are tracked but not surfaced. High-confidence patterns get written to `routines.md`.

### 14.7 The User Profile — A Living Document

`user-profile.md` is **not manually maintained** — it's auto-generated from semantic memory:

```markdown
# Rohit — Personal Profile
Last updated: 2026-04-15

## Identity
- Name: Rohit Ranjan
- Role: Software Engineer / Indie Developer
- Expertise: Swift, macOS, SwiftUI, AI agents (learning)
- Machine: MacBook Pro M3, macOS Sonoma

## Communication
- Style: Direct, technical, concise
- Dislikes: Verbose explanations, "happy to help" filler, unnecessary confirmations
- Voice: Prefers short spoken responses (< 10 seconds)
- When frustrated: Uses shorter sentences, repeats the request differently

## Work Patterns
- Peak hours: 9–11 AM (deep work), 2–5 PM (tactical tasks)
- Morning routine: Open Xcode, check git status, plan tasks
- Typical session: 5–15 minutes, 3–8 voice interactions
- Most active days: Monday–Friday

## Preferences
- LLM: Gemini for quick tasks, Ollama for private/sensitive work
- Search: Prefers file search over screen capture for code
- Commits: Bundled PRs over many small ones
- Deployment: Always test → tag → push (never skip tests)

## Current Focus
- Building Voxa agent mode (Phases 7–15)
- Exploring AI agent patterns (MCP, sub-agents, skills)
- Personal productivity through voice automation

## People
- Alex: team collaborator, mentioned in code review context
```

The agent **proposes updates** after each session. In auto-approve mode, they're written silently. In manual mode, the agent says "I noticed you prefer X — should I remember that?"

### 14.8 Agent Identity Files (User-Editable)

These remain manually editable (the user defines the agent's personality, not the agent itself):

#### `soul.md` — Personality & Voice

```markdown
# Soul

## Core
- You are a personal voice assistant for a single user
- You know them well and get better over time
- Be concise — voice responses should be speakable in under 10 seconds
- Be direct — no filler, no preamble, no "Sure, I'd be happy to help!"
- Be proactive — suggest next steps based on what you know about their patterns

## Relationship
- You're a trusted personal tool, not a friend or therapist
- Reference what you know naturally: "Like your usual morning routine..." not "According to my records..."
- If you notice something off-pattern, mention it: "You don't usually work this late — everything okay?"
- Never be sycophantic. Never be obsequious. Be warm but efficient.

## Boundaries
- Never read out API keys, passwords, or sensitive data aloud
- Ask before destructive actions (deleting files, closing apps)
- If unsure, say so — don't hallucinate
- Health/emotional topics: acknowledge, redirect to humans
- Never pretend to be more than a tool
```

#### `identity.md` — Agent Identity

```markdown
# Identity
- Name: Voxa
- Role: Personal voice agent
- Vibe: Sharp, warm, minimal
```

#### `tools.md` — Environment Reference (User-Editable)

```markdown
# Environment

## Apps
- Xcode — primary IDE
- iTerm2 — terminal
- Arc — browser

## Paths
- Projects: ~/my/projects/
- Downloads: ~/Downloads/

## Custom Commands
- "deploy" → ./scripts/deploy.sh
- "test" → xcodebuild test
```

### 14.9 System Prompt Assembly

The system prompt is **dynamically built** from all tiers:

```swift
func buildSystemPrompt(session: ChatSession, tools: [ToolDefinition]) -> String {
    var sections: [String] = []

    // 1. Identity + Soul (who am I, how do I behave) — static, user-editable
    sections.append(contentsOf: [identity, soul])

    // 2. User Profile (who am I helping) — auto-maintained, living document
    sections.append(userProfile)

    // 3. Relevant Memories (what do I remember that's relevant NOW)
    //    — retrieved by relevance to current session context, not dumped wholesale
    let relevantMemories = memoryRetriever.retrieve(
        query: session.recentContext,
        maxTokens: 800,
        scoring: .weighted(recency: 0.3, importance: 0.3, relevance: 0.4)
    )
    sections.append(formatMemories(relevantMemories))

    // 4. Recent Reflections (high-order insights)
    sections.append(latestReflections)

    // 5. Today's patterns + recent log (continuity)
    sections.append(todayLog)

    // 6. Environment reference — static, user-editable
    sections.append(toolsReference)

    // 7. Available tools + skills
    sections.append(formatToolDefinitions(tools))

    return sections.joined(separator: "\n\n---\n\n")
}
```

**Key difference from OpenClaw:** Memories are **retrieved by relevance**, not all dumped into prompt. If the user is working on deployment, deployment-related memories surface. If they're doing morning planning, routine memories surface. This keeps the prompt focused and token-efficient.

### 14.10 Memory Retrieval — Weighted Scoring

Following Stanford Generative Agents' retrieval formula:

```
score = α × recency + β × importance + γ × relevance

where:
  recency    = exponential decay based on last access time (0.0–1.0)
  importance = LLM-assigned at extraction time (1–10, normalized to 0.0–1.0)
  relevance  = cosine similarity between query embedding and memory embedding (0.0–1.0)

  α = 0.3, β = 0.3, γ = 0.4 (defaults, tunable)
```

For embedding, use a lightweight local model — no cloud API needed:
- Apple's `NLEmbedding` (built into macOS, no dependency)
- Or a small SentenceTransformers model via CoreML

### 14.11 Workspace Directory

```
~/.voxa/agent/
├── soul.md                    # Agent personality (user-editable)
├── identity.md                # Agent name/vibe (user-editable)
├── tools.md                   # Environment reference (user-editable)
├── memory/                    # Semantic memory (agent-maintained)
│   ├── user-profile.md        # Auto-generated user profile
│   ├── preferences.md         # Learned preferences
│   ├── routines.md            # Detected behavioral patterns
│   ├── relationships.md       # People the user mentions
│   ├── projects.md            # Active projects and context
│   └── reflections.md         # Weekly synthesized insights
├── logs/                      # Episodic memory (append-only daily logs)
│   ├── 2026-03-18.md
│   └── ...
├── heartbeat.md               # Proactive checklist
├── cron-jobs.json             # Scheduled tasks
├── subagents/                 # Custom sub-agent definitions
├── skills/                    # Custom user skills
├── skills-clawhub/            # Installed ClawHub skills
└── sessions/                  # Saved chat sessions
```

### 14.12 Progressive Profiling Timeline

| Timeframe | What the Agent Knows | How It Learned |
|-----------|---------------------|----------------|
| **Day 1** | Name, role, stated preferences | First-run onboarding + first session extraction |
| **Week 1** | Communication style, tool preferences, active projects | Extraction from 5-10 sessions |
| **Week 2-4** | Work schedule, topic clusters, routine sequences | Pattern detection across daily logs |
| **Month 2-3** | Deep preferences (inferred, not stated), people/relationships, deployment workflows | Consolidation + reflections |
| **Month 6+** | Seasonal patterns, long-term project arcs, evolved preferences | Reflection-on-reflections, pattern trends |

### 14.13 Privacy & User Control

The agent knows a lot. The user must stay in control:

- **"What do you know about me?"** — voice command that reads back the user profile
- **"Forget that"** — removes the most recent memory extraction
- **"Forget everything about [topic]"** — searches and removes related memories
- **"Show me my memory"** — opens memory directory in Finder
- **Memory browser** in Settings — view, edit, delete any memory entry
- **Export/Import** — backup/restore entire `~/.voxa/agent/` directory
- **Memory auto-approve toggle** — when off, agent asks before writing memories
- **Log retention** — configurable days to keep (default: 90)
- **Nuclear option** — "Reset everything" deletes all memory, starts fresh

### 14.14 Swift Implementation

```swift
// Voxa/Agent/Persona/PersonaManager.swift
@Observable
final class PersonaManager {
    let workspace: URL  // ~/.voxa/agent/

    // Static files (user-editable)
    var soul: String { get }
    var identity: String { get }
    var toolsReference: String { get }

    // Dynamic memory (agent-maintained)
    let memoryStore: SemanticMemoryStore
    let extractor: MemoryExtractor
    let consolidator: MemoryConsolidator
    let reflectionEngine: ReflectionEngine
    let patternDetector: PatternDetector
    let dailyLogger: DailyLogger

    // Build system prompt with relevant memories
    func buildSystemPrompt(session: ChatSession, tools: [ToolDefinition]) -> String

    // Post-session learning
    func learnFromSession(_ session: ChatSession) async

    // User commands
    func whatDoYouKnow() -> String            // Read back profile
    func forget(topic: String) async           // Remove memories about topic
    func forgetLast() async                    // Remove last extraction
}
```

```swift
// Voxa/Agent/Persona/SemanticMemoryStore.swift
@Observable
final class SemanticMemoryStore {
    // Read/write semantic memory files
    func userProfile() -> String
    func preferences() -> [MemoryEntry]
    func routines() -> [BehavioralPattern]
    func reflections() -> [Reflection]

    // Retrieval
    func retrieve(query: String, maxTokens: Int, scoring: ScoringWeights) -> [MemoryEntry]

    // Modification
    func add(_ entry: MemoryEntry) async
    func update(_ entry: MemoryEntry) async
    func remove(_ entry: MemoryEntry) async
    func removeMatching(topic: String) async
}
```

**New files:** `PersonaManager.swift`, `MemoryExtractor.swift`, `MemoryConsolidator.swift`, `ReflectionEngine.swift`, `PatternDetector.swift`, `SemanticMemoryStore.swift`, `MemoryEntry.swift`, `DailyLogger.swift`, `PersonaBootstrap.swift`, `PersonaSettingsView.swift`, `MemoryBrowserView.swift`
**New directory:** `Voxa/Agent/Persona/`

---

## Phase 15: TTS — Voice Responses

**Goal:** The agent speaks back. Voxa becomes a two-way voice assistant.

### 15.1 TTS Engine Selection

| Option | TTFA | Quality | Size | Integration |
|--------|------|---------|------|-------------|
| **FluidAudio (Kokoro)** | ~80ms | 8/10 | ~200MB | Native SPM, CoreML/ANE |
| Speech-Swift (Qwen3-TTS) | ~97ms | 9/10 | ~1.7GB | SPM, MLX |
| AVSpeechSynthesizer | ~50ms | 6/10 | 0 | System API |

**Primary: FluidAudio with Kokoro** — native Swift SPM, ~80ms time-to-first-audio, runs on Apple Neural Engine (same as WhisperKit), 48 voices, 9 languages, MIT license. Production-proven (BoltAI, Enconvo).

**Streaming path: FluidAudio PocketTTS** — when LLM streams tokens, start speaking before the full response is generated. ~80ms TTFA, autoregressive streaming, voice cloning from short audio samples.

**Fallback: AVSpeechSynthesizer (Enhanced voices)** — zero dependency, works immediately while Kokoro model downloads.

**Upgrade path: Speech-Swift with Qwen3-TTS** — 9/10 quality, 97ms TTFA, ~1.7GB model. Best voice quality available locally. Add as optional "high quality" voice in settings if user has disk space.

### 15.2 SPM Dependency

```swift
.package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.4")
```

Kokoro model (~200MB) auto-downloads from HuggingFace on first use. First-run CoreML compilation takes ~15 seconds (cached after).

### 15.3 Implementation

```swift
// Voxa/Agent/TTS/TTSEngine.swift
protocol TTSEngine {
    var isReady: Bool { get }
    func speak(_ text: String) async
    func speakStream(_ tokens: AsyncStream<String>) async  // Start speaking as tokens arrive
    func stop()
    var availableVoices: [VoiceOption] { get }
}
```

```swift
// Voxa/Agent/TTS/KokoroTTSEngine.swift — primary
// Voxa/Agent/TTS/SystemTTSEngine.swift  — AVSpeechSynthesizer fallback
// Voxa/Agent/TTS/TTSManager.swift       — selects engine, manages voice settings
```

### 15.4 When to Speak

Not every response should be spoken. Rules:

| Scenario | Speak? | Why |
|----------|--------|-----|
| Agent answers a question | Yes | Core voice assistant behavior |
| Tool execution status | No | Visual indicator is enough |
| Error/failure | Short spoken alert | "That didn't work" + visual detail |
| Text injection (dictation result) | No | Text was pasted, no need to read it |
| Long response (> 30 seconds spoken) | First sentence + "see panel for details" | Don't trap user in long audio |

### 15.5 TTS Settings

Settings → Agent → Voice:
- **Enable/disable TTS** toggle (default: enabled)
- **Voice selection** dropdown (48 Kokoro voices)
- **Speed** slider (0.5x–2.0x)
- **Engine selection**: Kokoro (recommended) / System voices / Qwen3-TTS (high quality)
- **Auto-speak** toggle: speak all responses vs only when asked ("read that out")
- **Preview** button: hear selected voice say a sample sentence

**New files:** `TTSEngine.swift`, `KokoroTTSEngine.swift`, `SystemTTSEngine.swift`, `TTSManager.swift`
**New directory:** `Voxa/Agent/TTS/`
**New SPM dependency:** `FluidAudio`

---

## Phase 16: Polish + Advanced Features

**Goal:** Production-quality agent experience.

- **Visual feedback**: Tool execution spinner + name in AgentPanel
- **Session persistence**: Save/load past conversations to `~/.voxa/agent/sessions/`
- **Safety**: Confirmation prompt for destructive tools (shell, file delete, UI clicks)
- **Error recovery**: Graceful fallback if tool fails, LLM times out, MCP disconnects
- **Rate limiting**: Max 5 tool iterations per turn, max 10 tool calls per session
- **Onboarding update**: Add agent mode intro step with voice selection
- **Memory search**: Semantic search over logs and memory for older context recall

---

## New Directory Structure

```
Voxa/
├── Agent/
│   ├── AgentExecutor.swift
│   ├── AgentResponse.swift
│   ├── ChatSession.swift
│   ├── IntentClassifier.swift
│   ├── LLM/                             (new)
│   │   ├── LLMProvider.swift            # Protocol
│   │   ├── ChatTypes.swift              # Shared types
│   │   ├── LLMProviderManager.swift     # Provider selection + config
│   │   ├── OllamaProvider.swift         # Wraps OllamaClient for /api/chat
│   │   ├── OpenAIProvider.swift         # OpenAI REST API
│   │   └── GeminiProvider.swift         # Gemini REST API
│   ├── Persona/                          (new)
│   │   ├── PersonaManager.swift         # Orchestrates identity + memory
│   │   ├── PersonaBootstrap.swift       # First-run onboarding
│   │   ├── DailyLogger.swift            # Append-only episodic log writer
│   │   ├── MemoryExtractor.swift        # Extract facts from sessions
│   │   ├── MemoryConsolidator.swift     # Deduplicate + merge into semantic memory
│   │   ├── ReflectionEngine.swift       # Weekly synthesis of insights
│   │   ├── PatternDetector.swift        # Behavioral pattern detection
│   │   ├── SemanticMemoryStore.swift    # Read/write/retrieve semantic memory
│   │   └── MemoryEntry.swift            # Memory data models
│   ├── SubAgents/                        (new)
│   │   ├── SubAgentDefinition.swift     # Agent definition model
│   │   ├── SubAgentManager.swift        # Spawn, manage, cancel sub-agents
│   │   ├── SubAgentResult.swift         # Result type from sub-agent execution
│   │   └── DelegateToAgentTool.swift    # Built-in tool for LLM-driven delegation
│   ├── Skills/                           (new)
│   │   ├── Skill.swift                  # Skill model (parsed from SKILL.md)
│   │   ├── SkillManager.swift           # Load, discover, activate skills
│   │   ├── SkillParser.swift            # Parse YAML frontmatter + markdown
│   │   └── ClawHubClient.swift          # ClawHub marketplace API client
│   ├── Heartbeat/                        (new)
│   │   ├── HeartbeatScheduler.swift     # Periodic awareness loop
│   │   ├── CronJob.swift                # Cron job model
│   │   ├── CronScheduler.swift          # Schedule and execute cron jobs
│   │   └── CronParser.swift             # Parse cron expressions
│   ├── TTS/                              (new)
│   │   ├── TTSEngine.swift              # Protocol
│   │   ├── KokoroTTSEngine.swift        # FluidAudio/Kokoro (primary)
│   │   ├── SystemTTSEngine.swift        # AVSpeechSynthesizer (fallback)
│   │   └── TTSManager.swift             # Engine selection + voice settings
│   ├── Tools/
│   │   ├── AgentTool.swift
│   │   ├── ToolRegistry.swift
│   │   └── Builtin/
│   │       ├── AppLauncherTool.swift
│   │       ├── ClipboardTool.swift
│   │       ├── FileSearchTool.swift
│   │       ├── ScreenCaptureTool.swift
│   │       ├── UIAutomationTool.swift
│   │       ├── SystemSettingsTool.swift
│   │       ├── ShellCommandTool.swift
│   │       └── CronTool.swift           # Create/list/remove scheduled tasks
│   └── MCP/
│       ├── MCPManager.swift
│       ├── MCPConnection.swift
│       ├── MCPServerConfig.swift
│       └── MCPToolAdapter.swift
├── Modes/
│   ├── DictationModeProtocol.swift  (new)
│   ├── ModeRegistry.swift           (new)
│   ├── AgentMode.swift              (new)
│   └── ... (existing modes wrapped)
├── Core/
│   ├── TranscriptionPipeline.swift  (new)
│   └── ... (existing)
├── UI/
│   ├── AgentPanel.swift             (new)
│   ├── AgentPanelContent.swift      (new)
│   ├── MCPSettingsView.swift        (new)
│   ├── PersonaSettingsView.swift    (new)
│   ├── SubAgentSettingsView.swift   (new)
│   ├── SkillSettingsView.swift      (new)
│   └── ... (existing)
├── Utilities/
│   ├── KeychainHelper.swift         (new — secure API key storage)
│   └── ... (existing)

# Runtime data directory (created at first agent launch):
~/.voxa/agent/
├── soul.md              # Agent personality & voice style (user-editable)
├── identity.md          # Agent name, vibe (user-editable)
├── tools.md             # Environment reference (user-editable)
├── memory/              # Semantic memory (agent-maintained, living)
│   ├── user-profile.md  # Auto-generated user profile
│   ├── preferences.md   # Learned preferences
│   ├── routines.md      # Detected behavioral patterns
│   ├── relationships.md # People the user mentions
│   ├── projects.md      # Active projects and context
│   └── reflections.md   # Weekly synthesized insights
├── subagents/           # Custom sub-agent definitions
│   └── devops.yaml
├── skills/              # Custom user skills (highest priority)
│   └── my-workflow/
│       └── SKILL.md
├── skills-clawhub/      # Installed from ClawHub marketplace
│   └── docker-deploy/
│       └── SKILL.md
├── heartbeat.md         # Proactive checklist (read by heartbeat)
├── cron-jobs.json       # Persisted cron job definitions
├── logs/                # Episodic memory (append-only daily logs)
│   └── YYYY-MM-DD.md
└── sessions/            # Saved chat sessions

# Bundled resources (shipped with app):
Voxa.app/Contents/Resources/
├── SubAgents/           # Built-in sub-agent definitions
│   ├── system.yaml
│   ├── research.yaml
│   ├── code.yaml
│   └── writer.yaml
└── Skills/              # Built-in skills
    ├── voice-style/SKILL.md
    ├── git-commit/SKILL.md
    ├── screenshot-describe/SKILL.md
    ├── app-workflow/SKILL.md
    ├── file-finder/SKILL.md
    └── summarize-text/SKILL.md
```

---

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Agent code fully isolated under `Voxa/Agent/` | Existing dictation pipeline untouched. Only 5 existing files get minimal additive changes. |
| `AgentCoordinator` as sole bridge | Borrows AudioEngine + TranscriptionEngine (read-only), owns everything else. Clean boundary. |
| Separate `OllamaProvider` (not wrapping `OllamaClient`) | Complete independence from existing LLM code. Uses `/api/chat` vs existing `/api/generate`. |
| `LLMProvider` protocol with pluggable backends | User wants Ollama + OpenAI + Gemini; protocol makes adding providers trivial |
| API keys in Keychain, not UserDefaults | Security — API keys are sensitive credentials |
| Separate agent model from cleanup model | Agent needs reasoning + tool selection; cleanup just fixes grammar. Different providers possible. |
| Cloud providers use raw URLSession, no SDKs | Keeps dependencies minimal; OpenAI/Gemini chat APIs are simple REST |
| MCP tools bridged to same `AgentTool` protocol | Agent executor doesn't care if a tool is built-in or MCP |
| Two-tier intent classifier | Fast path for obvious commands, LLM only for ambiguous cases |
| `requiresConfirmation` on tools | Safety for destructive operations (shell, clicks, file ops) |
| Persistent + pop-up panel toggle | Persistent for power users, pop-up for quick commands. User preference. |
| Three-tier memory (working → episodic → semantic) | Cognitive science model. Working = session, episodic = daily events, semantic = consolidated facts/patterns. |
| Agent actively learns, not just stores | Extraction + consolidation + reflection pipeline. Agent gets smarter over weeks/months without manual user input. |
| Memory retrieved by relevance, not dumped wholesale | Weighted scoring (recency + importance + relevance). Keeps system prompt focused and token-efficient. |
| User profile is auto-generated, not manually maintained | Agent writes user-profile.md from extracted observations. User can override but shouldn't need to. |
| Weekly reflections synthesize higher-order insights | Stanford Generative Agents pattern. "Rohit deploys with test→tag→push" is more useful than individual log entries. |
| Behavioral pattern detection from interaction data | Work schedule, topic clusters, tool preferences, routines detected passively over time. |
| `NLEmbedding` for local vector similarity | Built into macOS, no external dependency. Used for memory retrieval scoring and deduplication. |
| Privacy controls: "what do you know?", "forget that" | User must stay in control of what a personal agent remembers. |
| soul.md + identity.md are user-editable, memory is agent-managed | User controls personality; agent controls knowledge. Clear separation. |
| Sub-agents as isolated ChatSessions, not processes | Same process = fast, no IPC overhead. Isolation via separate system prompts + tool subsets. |
| LLM decides when to delegate (via `delegate_to_agent` tool) | Cleaner than hardcoded routing. LLM evaluates task complexity and picks the right specialist. |
| Sub-agents get reduced context (no soul/user/memory) | Focus + token efficiency. Sub-agents need task instructions, not personality. |
| ClawHub marketplace + local skills, with security layer | User wants ClawHub access. Security via VirusTotal check + tool permission audit + confirmation on destructive tools. |
| Skills = instructions, not executable code | Skills teach the LLM how to combine tools. They can't grant permissions or run code directly. |
| Tools vs Skills vs Sub-Agents distinction | Clear separation of concerns: tools = capabilities, skills = workflows, sub-agents = specialists. |
| Heartbeat: cheap checks first, LLM only when needed | Most checks are system calls (HTTP ping, disk space). Skip LLM if nothing actionable. Near-zero cost with Ollama. |
| In-process timer for heartbeat (not launchd) | Voxa is a menu bar app, always running. Simpler than external daemon. Sleep/wake handled via NSWorkspace notifications. |
| Cron jobs in isolated sessions | Fresh context per run = cheap. No history pollution in main agent session. |
| FluidAudio/Kokoro for TTS (not AVSpeechSynthesizer) | 8/10 quality vs 6/10, ~80ms TTFA, runs on Neural Engine (same as WhisperKit). Native SPM. |
| TTSEngine protocol with pluggable backends | Kokoro primary, AVSpeechSynthesizer fallback, Qwen3-TTS upgrade path. Same pattern as LLMProvider. |
| Not all responses spoken | Dictation results → paste only. Tool status → visual only. Questions → speak. Avoids audio fatigue. |
| No external agent framework | No mature Swift option exists; agentic loop is ~100 lines |

---

## Inspiration & References

### macpaw Eney
- Native macOS "Computerbeing" — performs tasks, not just answers questions
- ELIX local engine for on-device reasoning + context search
- Task automation: app switching, file uploads, PDF manipulation, settings adjustments
- Voice-first with Respeecher TTS integration (launching 2026)
- Hybrid: local processing + cloud APIs (GPT-4, Gemini) for complex tasks

### OpenClaw
- Open-source autonomous agent with persistent daemon (Gateway)
- 50+ built-in integrations (messaging, productivity, smart home)
- ClawHub skills marketplace (3,286+ verified skills, YAML-based)
- Self-extension: agent can write its own tools
- Full computer control: file system, shell, browser automation
- **Persona system**: soul.md (personality), user.md (user profile), identity.md (agent identity), tools.md (environment), memory.md (long-term), daily logs (session journal), heartbeat.md (periodic tasks), agents.md (operating rules)
- All persona files are plain Markdown, injected into system prompt at session start
- Two-layer memory: curated long-term (memory.md) + ephemeral daily (logs/YYYY-MM-DD.md)
- **Sub-agents**: Spawned via `sessions_spawn`, isolated context (only AGENTS.md + TOOLS.md), max depth 2, announce pattern for results, per-spawn model override for cost optimization
- **Skills**: SKILL.md format (YAML frontmatter + markdown instructions), tools ≠ skills (tools = capabilities, skills = workflows), local + ClawHub marketplace, AgentSkills specification
- **Security lesson**: 230+ malicious skills found on ClawHub (ClawHavoc incident) — Voxa integrates ClawHub with VirusTotal checks, tool permission audits, and confirmation gates on destructive tools

### MCP (Model Context Protocol)
- Official Swift SDK: `github.com/modelcontextprotocol/swift-sdk`
- MacPaw Swift SDK: `github.com/MacPaw/mcp-swift-sdk`
- Standardized tool discovery and invocation across servers
- StdioTransport (process spawning) and HTTPTransport supported

### macOS Computer Control
- `AXUIElement` APIs for UI automation (already permitted via Accessibility)
- `CGWindowListCreateImage` + Vision `VNRecognizeTextRequest` for screen OCR
- `NSWorkspace` for app launching
- `NSMetadataQuery` for Spotlight search

---

## Verification

### Phase 7
- All existing modes work identically (no regressions)
- Unit tests for LLM provider chat/streaming methods (mock HTTP)
- Provider switching works in settings

### Phase 8
- Each tool instantiates and executes programmatically in unit tests
- ScreenCaptureTool returns OCR text from a test image

### Phase 9
- Press agent hotkey → speak "open Safari" → Safari opens
- Speak "what's on my screen?" → OCR result displayed in AgentPanel
- Multi-turn: "summarize that" (referring to previous screen capture) works
- Panel mode toggle switches between persistent and pop-up correctly

### Phase 10
- Configure MCP filesystem server → speak "list files on desktop" → file list in panel
- MCP server disconnect/reconnect handled gracefully

### Phase 11 — Sub-Agents
- "Open Safari and search for weather" → main agent delegates to `system` sub-agent → Safari opens + search performed
- Sub-agent uses only its allowed tool subset (verify `code` agent can't use AppLauncher)
- Max 3 concurrent sub-agents enforced
- Sub-agent timeout fires correctly (cancels after configured seconds)
- Custom sub-agent YAML loaded from `~/.voxa/agent/subagents/`
- `delegate_to_agent` tool appears in main agent's tool definitions

### Phase 12 — Skills & ClawHub
- "Commit my changes" triggers `git-commit` skill → correct workflow followed
- Always-active skills (e.g., `voice-style`) present in every session's system prompt
- Custom skill at `~/.voxa/agent/skills/my-skill/SKILL.md` loads and activates
- Skill with missing required tools is disabled (verify via settings UI)
- Skills + sub-agents compose: skill instructions flow to delegated sub-agent
- "Install a skill for docker" → ClawHub search → results shown → install + security check
- ClawHub skill installs to `skills-clawhub/` (separate from user skills)
- Skill with VirusTotal flag is blocked from installation
- Tool permission audit shown before install ("This skill uses: shell_command. Allow?")

### Phase 13 — Heartbeat & Cron
- Heartbeat fires every 30m (verify timer accuracy)
- Cheap checks run without LLM (Ollama ping, disk space check)
- LLM only invoked when cheap checks find something actionable
- System sleep/wake pauses and resumes timer correctly
- Active hours window respected (no heartbeat outside configured hours)
- "Remind me to check X every 2 hours" → cron job created via voice
- Cron jobs persist to `cron-jobs.json` and survive app restart
- macOS notification delivered on heartbeat alert
- "Show my scheduled tasks" → lists all cron jobs

### Phase 14 — Personal Agent Memory
- First launch creates default persona files + empty memory directory
- After 3+ sessions: user-profile.md contains name, role, preferences (auto-extracted)
- Memory extraction runs post-session: new facts appear in semantic memory
- Consolidation deduplicates: same preference stated twice → single entry
- After 7+ days: routines.md detects work schedule pattern
- After 2+ weeks: reflections.md contains first weekly synthesis
- "What do you know about me?" → reads back user profile
- "Forget everything about [topic]" → removes matching memories
- Relevant memories surface in system prompt based on current context (not all dumped)
- Memory browser in Settings shows all entries with edit/delete

### Phase 15 — TTS
- Kokoro model downloads and compiles on first use
- Agent speaks response aloud with < 100ms time-to-first-audio
- Streaming TTS: audio starts while LLM is still generating tokens
- Fallback to AVSpeechSynthesizer when Kokoro model not yet downloaded
- Voice selection works across 48 Kokoro voices
- Long responses truncated: "See panel for full details"
- TTS toggle on/off works correctly

### Phase 16 — Polish
- Destructive tool (shell command) shows confirmation before executing
- Memory search finds relevant entries from older daily logs
- Session persistence: save/load past conversations
