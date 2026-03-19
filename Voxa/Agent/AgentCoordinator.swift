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
        self.toolRegistry.registerBuiltinTools()
        self.subAgentManager = SubAgentManager(parentRegistry: toolRegistry, providerManager: providerManager)
        let delegateTool = DelegateToAgentTool(subAgentManager: subAgentManager)
        self.delegateTool = delegateTool
        self.toolRegistry.register(delegateTool)
        self.mcpManager = MCPManager(toolRegistry: toolRegistry)
        self.conversationStore = ConversationStore()
        self.executor = AgentExecutor(providerManager: providerManager, toolRegistry: toolRegistry)

        // Connect all enabled MCP servers on launch
        Task { await mcpManager.connectAll() }

        // Wire up panel UI callbacks
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
                AgentPanel.shared.finalizeResponse(response, session: self.session)
            }

            print("[AgentCoordinator] Text response: \(response.displayText.prefix(200))")

        } catch is CancellationError {
            print("[AgentCoordinator] Text processing cancelled")
            await MainActor.run {
                AgentPanel.shared.showStatus("Cancelled.")
            }
        } catch {
            print("[AgentCoordinator] Text error: \(error)")
            await MainActor.run {
                AgentPanel.shared.showStatus("Error: \(error.localizedDescription)")
            }
        }
    }

    private func processVoiceInput(buffer: [Float], appState: AppState) async {
        guard !buffer.isEmpty else {
            print("[AgentCoordinator] Empty audio buffer")
            await MainActor.run {
                appState.status = .idle
                AgentPanel.shared.dismiss()
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
                // Finalize the response in the panel
                AgentPanel.shared.finalizeResponse(response, session: self.session)

                // Inject text if needed
                if let injectText = response.injectText {
                    TextInjector.inject(injectText)
                }

                appState.lastTranscription = transcript
                appState.status = .idle
            }

            print("[AgentCoordinator] Response: \(response.displayText.prefix(200))")

        } catch is CancellationError {
            print("[AgentCoordinator] Processing cancelled")
            await MainActor.run {
                appState.status = .idle
                AgentPanel.shared.showStatus("Cancelled.")
            }
        } catch {
            print("[AgentCoordinator] Error: \(error)")
            await MainActor.run {
                appState.status = .idle
                AgentPanel.shared.showStatus("Error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Callbacks

    private func makeCallbacks() -> AgentCallbacks {
        AgentCallbacks(
            onStreamDelta: { @Sendable delta in
                await MainActor.run {
                    AgentPanel.shared.appendStreamingText(delta)
                }
            },
            onToolStart: { @Sendable toolName in
                await MainActor.run {
                    AgentPanel.shared.showToolExecution(toolName)
                }
            },
            onToolEnd: { @Sendable toolName, isError in
                await MainActor.run {
                    AgentPanel.shared.clearToolExecution()
                }
            }
        )
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
        }
    }
}
