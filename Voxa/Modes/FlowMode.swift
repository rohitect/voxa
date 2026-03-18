import Foundation

/// Flow Mode: Toggle hotkey to start/stop continuous hands-free dictation.
/// Uses energy-based Voice Activity Detection (VAD) to segment speech into chunks,
/// transcribing and injecting each chunk as it completes.
final class FlowMode {
    private static var isFlowing = false
    private static var vadTimer: Timer?
    private static var silenceStart: Date?

    /// Energy threshold below which audio is considered silence.
    private static let silenceThreshold: Float = 0.01
    /// Duration of silence (seconds) required to trigger end-of-utterance.
    private static let silenceDuration: TimeInterval = 1.5

    /// Called on hotkey press — toggles flow mode on/off.
    static func onHotkeyDown(appState: AppState) {
        if isFlowing {
            stopFlow(appState: appState)
        } else {
            startFlow(appState: appState)
        }
    }

    /// No-op for flow mode (toggle is on keyDown only).
    static func onHotkeyUp(appState: AppState) {
        // Flow mode uses toggle, not hold — nothing to do on key up
    }

    // MARK: - Start/Stop

    private static func startFlow(appState: AppState) {
        guard appState.permissionManager.microphoneGranted else {
            print("[FlowMode] Cannot record — microphone not granted")
            return
        }
        guard appState.transcriptionEngine.isLoaded else {
            print("[FlowMode] Transcription model not loaded")
            return
        }

        isFlowing = true
        silenceStart = nil
        appState.status = .listening
        SoundManager.shared.playStartSound()
        FloatingIndicator.shared.showRecording()
        appState.audioEngine.startRecording()

        // Set up VAD: monitor audio levels to detect end of utterance
        appState.audioEngine.onAudioLevel = { level in
            handleVAD(level: level, appState: appState)
        }

        print("[FlowMode] Started continuous listening")
    }

    private static func stopFlow(appState: AppState) {
        isFlowing = false
        vadTimer?.invalidate()
        vadTimer = nil
        silenceStart = nil

        appState.audioEngine.stopRecording()
        SoundManager.shared.playStopSound()

        let buffer = appState.audioEngine.getBufferAndClear()
        if !buffer.isEmpty {
            // Process any remaining audio
            PushToTalkMode.processBuffer(buffer, appState: appState)
        } else {
            appState.status = .idle
            FloatingIndicator.shared.dismiss()
        }

        // Restore default audio level handler
        appState.audioEngine.onAudioLevel = { level in
            let bars = Int(level * 50)
            let meter = String(repeating: "|", count: min(bars, 50))
            print("[AudioLevel] \(String(format: "%.4f", level)) \(meter)")
        }

        print("[FlowMode] Stopped continuous listening")
    }

    // MARK: - VAD

    private static func handleVAD(level: Float, appState: AppState) {
        guard isFlowing else { return }

        if level < silenceThreshold {
            // Silence detected
            if silenceStart == nil {
                silenceStart = Date()
            } else if let start = silenceStart,
                      Date().timeIntervalSince(start) >= silenceDuration {
                // Enough silence — process the chunk
                silenceStart = nil
                processChunk(appState: appState)
            }
        } else {
            // Speech detected — reset silence timer
            silenceStart = nil
        }
    }

    private static func processChunk(appState: AppState) {
        guard isFlowing else { return }

        // Grab current buffer without stopping recording
        let buffer = appState.audioEngine.getBufferAndClear()
        guard !buffer.isEmpty else { return }

        print("[FlowMode] VAD triggered — processing \(buffer.count) samples")

        Task { @MainActor in
            guard appState.transcriptionEngine.isLoaded else { return }

            do {
                let result = try await appState.transcriptionEngine.transcribe(audioBuffer: buffer)
                let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }

                // Check shortcuts
                if let expansion = ShortcutManager.shared.matchShortcut(in: trimmed) {
                    TextInjector.inject(expansion)
                    appState.lastTranscription = expansion
                    return
                }

                var cleanedText = await appState.textCleanupEngine.cleanup(result.text)
                cleanedText = DictionaryManager.shared.apply(to: cleanedText)

                // Append a space after each chunk for natural separation
                TextInjector.inject(cleanedText + " ")
                appState.lastTranscription = cleanedText
                print("[FlowMode] Chunk injected: \"\(cleanedText)\"")
            } catch {
                print("[FlowMode] Chunk transcription failed: \(error)")
            }
        }
    }

    /// Whether flow mode is currently active.
    static var isActive: Bool { isFlowing }
}
