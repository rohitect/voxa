import Foundation

/// The bridge between the existing Voxa dictation pipeline and the agent module.
/// Manages ChatSession lifecycle, routes through AgentExecutor, and updates AgentPanel.
@Observable
final class AgentCoordinator {
    let providerManager: LLMProviderManager
    let toolRegistry: ToolRegistry

    private let audioEngine: AudioEngine
    private let transcriptionEngine: TranscriptionEngine
    private let executor: AgentExecutor

    /// The active chat session (persists across hotkey presses until reset).
    private(set) var session: ChatSession

    /// Whether agent mode is currently active (recording).
    private(set) var isActive = false

    init(audioEngine: AudioEngine, transcriptionEngine: TranscriptionEngine) {
        self.audioEngine = audioEngine
        self.transcriptionEngine = transcriptionEngine
        self.providerManager = LLMProviderManager()
        self.toolRegistry = ToolRegistry()
        self.toolRegistry.registerBuiltinTools()
        self.session = ChatSession()
        self.executor = AgentExecutor(providerManager: providerManager, toolRegistry: toolRegistry)

        // Wire up new session request from panel UI
        AgentPanel.shared.state.requestNewSession = { [weak self] in
            self?.resetSession()
        }
    }

    // MARK: - Session Management

    func resetSession() {
        session = ChatSession()
        AgentPanel.shared.showStatus("New session started. How can I help?")
    }

    // MARK: - Hotkey Handlers

    /// Called when the agent hotkey is pressed down — start recording.
    func onHotkeyDown(appState: AppState) {
        guard !isActive else { return }
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

        Task {
            await processVoiceInput(buffer: buffer, appState: appState)
        }
    }

    // MARK: - Processing

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

            // Process through the agent executor
            let response = try await executor.process(transcript: transcript, session: session)

            await MainActor.run {
                // Show response in panel
                AgentPanel.shared.showResponse(response, session: self.session)
                AgentPanel.shared.clearToolExecution()

                // Inject text if needed
                if let injectText = response.injectText {
                    TextInjector.inject(injectText)
                }

                appState.lastTranscription = transcript
                appState.status = .idle
            }

            print("[AgentCoordinator] Response: \(response.displayText.prefix(200))")

        } catch {
            print("[AgentCoordinator] Error: \(error)")
            await MainActor.run {
                appState.status = .idle
                AgentPanel.shared.showStatus("Error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - System Control

    private func handleSystemControl(_ action: Intent.SystemControlAction, appState: AppState) {
        Task { @MainActor in
            switch action {
            case .stop, .cancel:
                AgentPanel.shared.dismiss()
            case .reset, .newSession:
                resetSession()
            }
            appState.status = .idle
        }
    }
}
