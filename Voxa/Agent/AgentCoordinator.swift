import Foundation

/// The bridge between the existing Voxa dictation pipeline and the agent module.
/// Borrows references to AudioEngine and TranscriptionEngine from AppState.
@Observable
final class AgentCoordinator {
    let providerManager: LLMProviderManager
    let toolRegistry: ToolRegistry

    private let audioEngine: AudioEngine
    private let transcriptionEngine: TranscriptionEngine

    /// Whether agent mode is currently active (recording).
    private(set) var isActive = false

    /// Maximum number of tool call iterations before forcing a stop.
    private let maxToolIterations = 5

    init(audioEngine: AudioEngine, transcriptionEngine: TranscriptionEngine) {
        self.audioEngine = audioEngine
        self.transcriptionEngine = transcriptionEngine
        self.providerManager = LLMProviderManager()
        self.toolRegistry = ToolRegistry()
        self.toolRegistry.registerBuiltinTools()
    }

    // MARK: - Hotkey Handlers

    /// Called when the agent hotkey is pressed down — start recording.
    func onHotkeyDown(appState: AppState) {
        guard !isActive else { return }
        isActive = true
        appState.status = .listening
        print("[AgentCoordinator] Hotkey down — recording")

        do {
            try audioEngine.startRecording()
        } catch {
            print("[AgentCoordinator] Failed to start recording: \(error)")
            isActive = false
            appState.status = .idle
        }
    }

    /// Called when the agent hotkey is released — stop recording, transcribe, send to LLM.
    func onHotkeyUp(appState: AppState) {
        guard isActive else { return }
        isActive = false
        appState.status = .processing
        print("[AgentCoordinator] Hotkey up — processing")

        let buffer = audioEngine.getBufferAndClear()
        audioEngine.stopRecording()

        Task {
            await processVoiceInput(buffer: buffer, appState: appState)
        }
    }

    // MARK: - Processing

    private func processVoiceInput(buffer: [Float], appState: AppState) async {
        guard !buffer.isEmpty else {
            print("[AgentCoordinator] Empty audio buffer")
            await MainActor.run { appState.status = .idle }
            return
        }

        do {
            let result = try await transcriptionEngine.transcribe(audioBuffer: buffer)
            let transcript = result.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            print("[AgentCoordinator] Transcript: \(transcript)")

            guard !transcript.isEmpty else {
                await MainActor.run { appState.status = .idle }
                return
            }

            guard let provider = providerManager.activeProvider else {
                print("[AgentCoordinator] No active LLM provider")
                await MainActor.run { appState.status = .idle }
                return
            }

            let toolDefinitions = toolRegistry.enabledDefinitions
            let hasTools = !toolDefinitions.isEmpty

            var messages: [ChatMessage] = [
                ChatMessage(role: .system, content: buildSystemPrompt(hasTools: hasTools)),
                ChatMessage(role: .user, content: transcript),
            ]

            let model = providerManager.activeModel

            // Tool execution loop
            for iteration in 0..<maxToolIterations {
                let response = try await provider.chat(
                    messages: messages,
                    model: model,
                    tools: hasTools ? toolDefinitions : nil,
                    timeout: 30
                )

                // Check if LLM wants to call tools
                guard response.finishReason == .toolCalls,
                      let toolCalls = response.message.toolCalls,
                      !toolCalls.isEmpty else {
                    // No tool calls — we have the final response
                    if let content = response.message.content {
                        print("[AgentCoordinator] LLM response: \(content)")
                    }
                    break
                }

                print("[AgentCoordinator] Tool loop iteration \(iteration + 1): \(toolCalls.count) tool call(s)")

                // Append assistant message with tool calls
                messages.append(response.message)

                // Execute each tool call and append results
                for toolCall in toolCalls {
                    print("[AgentCoordinator] Executing tool: \(toolCall.name)")
                    let toolResult = try await toolRegistry.execute(toolCall)
                    print("[AgentCoordinator] Tool result (\(toolCall.name)): \(toolResult.isError ? "ERROR" : "OK") — \(String(toolResult.output.prefix(200)))")

                    messages.append(ChatMessage(
                        role: .tool,
                        content: toolResult.output,
                        toolCallId: toolCall.id
                    ))
                }
            }

            await MainActor.run { appState.status = .idle }
        } catch {
            print("[AgentCoordinator] Error: \(error)")
            await MainActor.run { appState.status = .idle }
        }
    }

    // MARK: - Helpers

    private func buildSystemPrompt(hasTools: Bool) -> String {
        var prompt = "You are a helpful voice assistant running on macOS. Respond concisely."
        if hasTools {
            prompt += " You have access to tools that can interact with the user's Mac. Use them when the user's request requires taking action on their computer. If a task can be done with a tool, use it rather than just describing the steps."
        }
        return prompt
    }
}
