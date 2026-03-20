import Foundation

/// The bridge between the existing Voxa dictation pipeline and the agent module.
/// Manages ChatSession lifecycle, routes through AgentExecutor, and updates AgentPanel.
@Observable
final class AgentCoordinator {
    let providerManager: LLMProviderManager
    let toolRegistry: ToolRegistry
    let mcpManager: MCPManager
    let conversationStore: ConversationStore
    let subAgentManager: SubAgentManager
    let personaManager: PersonaManager

    private let audioEngine: AudioEngine
    private let transcriptionEngine: TranscriptionEngine
    private let executor: AgentExecutor
    private let delegateTool: DelegateToAgentTool

    /// The active chat session (persists across hotkey presses until reset).
    var session: ChatSession {
        get { conversationStore.activeConversation }
        set { conversationStore.activeConversation = newValue }
    }

    /// Whether agent mode is currently active (recording).
    private(set) var isActive = false

    /// The current processing task — stored for cancellation support.
    private var processingTask: Task<Void, Never>?

    init(audioEngine: AudioEngine, transcriptionEngine: TranscriptionEngine) {
        self.audioEngine = audioEngine
        self.transcriptionEngine = transcriptionEngine
        self.providerManager = LLMProviderManager()
        self.toolRegistry = ToolRegistry()
        self.mcpManager = MCPManager(toolRegistry: toolRegistry)
        self.subAgentManager = SubAgentManager(configStore: mcpManager.configStore, providerManager: providerManager)
        let delegateTool = DelegateToAgentTool(subAgentManager: subAgentManager)
        self.delegateTool = delegateTool
        self.toolRegistry.register(delegateTool)

        // Register builtin tools
        self.toolRegistry.register(ClipboardTool())
        self.toolRegistry.register(AppLauncherTool())
        self.toolRegistry.register(FileSearchTool())
        self.toolRegistry.register(ScreenCaptureTool())
        self.toolRegistry.register(SystemSettingsTool())
        self.toolRegistry.register(UIAutomationTool())
        self.toolRegistry.register(ShellCommandTool())
        self.toolRegistry.register(AppleScriptTool())
        self.toolRegistry.register(FileWriteTool())
        self.toolRegistry.register(FileReadTool())
        self.toolRegistry.register(ListDirectoryTool())

        self.conversationStore = ConversationStore()
        self.personaManager = PersonaManager(providerManager: providerManager)
        self.executor = AgentExecutor(providerManager: providerManager, toolRegistry: toolRegistry, personaManager: personaManager)

        // Connect all enabled MCP servers on launch
        Task { await mcpManager.connectAll() }

        // Wire up panel UI callbacks
        AgentPanel.shared.state.toolRegistry = toolRegistry
        AgentPanel.shared.state.requestNewSession = { [weak self] in
            self?.resetSession()
        }
        AgentPanel.shared.state.sendMessage = { [weak self] text in
            self?.sendTextMessage(text)
        }
    }

    // MARK: - Session Management

    func resetSession() {
        conversationStore.newConversation()
        AgentPanel.shared.state.session = session
        AgentPanel.shared.showStatus("New session started. How can I help?")
        CompanionState.shared.phase = .idle
    }

    /// Switch to an existing conversation.
    func switchConversation(_ conversation: ChatSession) {
        cancelProcessing()
        conversationStore.select(conversation)
        AgentPanel.shared.state.session = session
    }

    /// Cancel any in-progress agent processing.
    func cancelProcessing() {
        processingTask?.cancel()
        processingTask = nil
    }

    // MARK: - Hotkey Handlers

    /// Called when the agent hotkey is pressed down — start recording.
    func onHotkeyDown(appState: AppState) {
        guard !isActive else { return }

        // Cancel any in-progress processing from a previous turn
        if processingTask != nil {
            cancelProcessing()
        }

        isActive = true
        appState.status = .listening
        print("[AgentCoordinator] Hotkey down — recording")

        AgentPanel.shared.showListening()
        CompanionState.shared.phase = .listening
        audioEngine.startRecording()
    }

    /// Called when the agent hotkey is released — stop recording, transcribe, send to agent.
    func onHotkeyUp(appState: AppState) {
        guard isActive else { return }
        isActive = false
        appState.status = .processing
        print("[AgentCoordinator] Hotkey up — processing")

        let buffer = audioEngine.getBufferAndClear()
        audioEngine.stopRecording()

        AgentPanel.shared.showProcessing()
        CompanionState.shared.phase = .processing

        processingTask = Task {
            await processVoiceInput(buffer: buffer, appState: appState)
        }
    }

    // MARK: - Text Message Input

    /// Send a typed text message through the agent pipeline.
    func sendTextMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Cancel any in-progress processing
        cancelProcessing()

        // Update state (shared between floating panel and in-window chat)
        AgentPanel.shared.state.session = session
        AgentPanel.shared.showProcessing()
        CompanionState.shared.phase = .processing

        processingTask = Task {
            await processTextInput(trimmed)
        }
    }

    // MARK: - Processing

    private func processTextInput(_ transcript: String) async {
        do {
            // Check for system control intents
            let intent = IntentClassifier.classify(transcript)
            if case .systemControl(let action) = intent {
                await MainActor.run {
                    switch action {
                    case .stop, .cancel:
                        AgentPanel.shared.showStatus("Cancelled.")
                        CompanionState.shared.phase = .idle
                    case .reset, .newSession:
                        resetSession()
                    }
                }
                return
            }

            let callbacks = makeCallbacks()
            delegateTool.activeCallbacks = callbacks

            let response = try await executor.process(
                transcript: transcript,
                session: session,
                callbacks: callbacks
            )

            await MainActor.run {
                if let trace = response.trace {
                    self.session.storeTrace(trace)
                }
                AgentPanel.shared.finalizeResponse(response, session: self.session)
                CompanionState.shared.phase = .idle
                self.conversationStore.saveActive()
            }

            // Learn from the session in the background
            await personaManager.learnFromSession(session)

            print("[AgentCoordinator] Text response: \(response.displayText.prefix(200))")

        } catch is CancellationError {
            print("[AgentCoordinator] Text processing cancelled")
            await MainActor.run {
                AgentPanel.shared.showStatus("Cancelled.")
                CompanionState.shared.phase = .idle
            }
        } catch {
            print("[AgentCoordinator] Text error: \(error)")
            let userMessage = Self.formatErrorForUser(error)
            await MainActor.run {
                // Add error as an assistant message so it's visible in conversation
                session.addAssistantMessage(ChatMessage(role: .assistant, content: userMessage))
                AgentPanel.shared.finalizeResponse(.chat(userMessage), session: self.session)
                CompanionState.shared.phase = .idle
                self.conversationStore.saveActive()
            }
        }
    }

    private func processVoiceInput(buffer: [Float], appState: AppState) async {
        guard !buffer.isEmpty else {
            print("[AgentCoordinator] Empty audio buffer")
            await MainActor.run {
                appState.status = .idle
                AgentPanel.shared.dismiss()
                CompanionState.shared.phase = .idle
            }
            return
        }

        do {
            let result = try await transcriptionEngine.transcribe(audioBuffer: buffer)
            let transcript = result.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            print("[AgentCoordinator] Transcript: \(transcript)")

            guard !transcript.isEmpty else {
                await MainActor.run {
                    appState.status = .idle
                    AgentPanel.shared.dismiss()
                    CompanionState.shared.phase = .idle
                }
                return
            }

            // Check for system control intents before full processing
            let intent = IntentClassifier.classify(transcript)
            if case .systemControl(let action) = intent {
                handleSystemControl(action, appState: appState)
                return
            }

            let callbacks = makeCallbacks()
            delegateTool.activeCallbacks = callbacks

            // Process through the agent executor
            let response = try await executor.process(
                transcript: transcript,
                session: session,
                callbacks: callbacks
            )

            await MainActor.run {
                // Store trace before finalizing
                if let trace = response.trace {
                    self.session.storeTrace(trace)
                }
                // Finalize the response in the panel
                AgentPanel.shared.finalizeResponse(response, session: self.session)
                CompanionState.shared.phase = .idle
                self.conversationStore.saveActive()

                // Inject text if needed
                if let injectText = response.injectText {
                    TextInjector.inject(injectText)
                }

                appState.lastTranscription = transcript
                appState.status = .idle
            }

            // Learn from the session in the background
            await personaManager.learnFromSession(session)

            print("[AgentCoordinator] Response: \(response.displayText.prefix(200))")

        } catch is CancellationError {
            print("[AgentCoordinator] Processing cancelled")
            await MainActor.run {
                appState.status = .idle
                AgentPanel.shared.showStatus("Cancelled.")
                CompanionState.shared.phase = .idle
            }
        } catch {
            print("[AgentCoordinator] Error: \(error)")
            let userMessage = Self.formatErrorForUser(error)
            await MainActor.run {
                appState.status = .idle
                session.addAssistantMessage(ChatMessage(role: .assistant, content: userMessage))
                AgentPanel.shared.finalizeResponse(.chat(userMessage), session: self.session)
                CompanionState.shared.phase = .idle
                self.conversationStore.saveActive()
            }
        }
    }

    // MARK: - Callbacks

    private func makeCallbacks() -> AgentCallbacks {
        AgentCallbacks(
            onStreamDelta: { @Sendable delta in
                await MainActor.run {
                    AgentPanel.shared.appendStreamingText(delta)
                    CompanionState.shared.phase = .responding
                    CompanionState.shared.tokenPulseCounter += 1
                }
            },
            onToolStart: { @Sendable toolName in
                await MainActor.run {
                    AgentPanel.shared.showToolExecution(toolName)
                    CompanionState.shared.phase = .toolExecution(toolName)
                }
            },
            onToolEnd: { @Sendable toolName, isError in
                await MainActor.run {
                    AgentPanel.shared.clearToolExecution()
                    CompanionState.shared.phase = .responding
                }
            }
        )
    }

    // MARK: - System Control

    // MARK: - Error Formatting

    private static func formatErrorForUser(_ error: Error) -> String {
        if let llmError = error as? LLMError {
            switch llmError {
            case .httpError(let code, let message):
                let detail = message ?? "No details"
                switch code {
                case 400:
                    return "The LLM rejected the request (HTTP 400). This often happens when too many tools are registered or the conversation is too long. Try starting a new session.\n\nDetails: \(detail)"
                case 401, 403:
                    return "Authentication failed (HTTP \(code)). Check your API key in Settings > Agent."
                case 429:
                    return "Rate limited (HTTP 429). Wait a moment and try again."
                case 500...599:
                    return "The LLM service returned a server error (HTTP \(code)). Try again shortly."
                default:
                    return "LLM request failed (HTTP \(code)): \(detail)"
                }
            case .timeout:
                return "The LLM request timed out. The server may be overloaded — try again."
            case .invalidAPIKey:
                return "Invalid API key. Check your settings in Settings > Agent."
            case .providerUnavailable(let name):
                return "LLM provider '\(name)' is not available. Check that it's running and configured correctly."
            default:
                return "LLM error: \(llmError.localizedDescription)"
            }
        }
        return "Error: \(error.localizedDescription)"
    }

    // MARK: - System Control

    private func handleSystemControl(_ action: Intent.SystemControlAction, appState: AppState) {
        Task { @MainActor in
            switch action {
            case .stop, .cancel:
                cancelProcessing()
                AgentPanel.shared.dismiss()
            case .reset, .newSession:
                cancelProcessing()
                resetSession()
            }
            appState.status = .idle
            CompanionState.shared.phase = .idle
        }
    }
}
